#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Universal APM Telemetry Agent
#
# Supports:
#   - Ubuntu host
#   - Docker
#   - K3s
#   - Kubernetes/containerd
#   - NGINX
#   - Frappe/ERPNext
#
# Sends:
#   Metrics -> Prometheus remote_write
#   Logs   -> Loki
#   Traces -> Central OpenTelemetry Collector
#
# Usage:
#
# sudo ./install-telemetry.sh \
#   --central-ip 10.0.0.10 \
#   --environment prod \
#   --service frappe
#
# ============================================================

VERSION="2.0.0"

NODE_EXPORTER_VERSION="1.7.0"
PROMTAIL_IMAGE="grafana/promtail:2.9.6"
OTEL_IMAGE="otel/opentelemetry-collector-contrib:0.97.0"

CENTRAL_IP=""
ENVIRONMENT=""
SERVICE=""

PROMETHEUS_REMOTE_WRITE=""
LOKI_URL=""
OTEL_TRACES_ENDPOINT=""

HOSTNAME="$(hostname)"

INSTALL_DIR="/opt/apm-agent"

NODE_EXPORTER_BIN="/usr/local/bin/node_exporter"
NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"

PROMTAIL_CONFIG="/etc/promtail/config.yml"
PROMTAIL_CONTAINER="apm-promtail"

OTEL_CONFIG="${INSTALL_DIR}/otel-config.yml"
OTEL_CONTAINER="apm-otel"

# ============================================================
# HELP
# ============================================================

usage() {
cat <<EOF

Universal APM Telemetry Agent v${VERSION}

Usage:

  sudo $0 \\
    --central-ip <IP/DNS> \\
    --environment <dev|qa|stage|prod> \\
    --service <service-name>

Optional:

    --prometheus-port <port>
    --loki-port <port>
    --otel-grpc-port <port>

Example:

  sudo $0 \\
    --central-ip 10.10.10.20 \\
    --environment prod \\
    --service frappe

EOF
}

# ============================================================
# ARGUMENT PARSING
# ============================================================

PROMETHEUS_PORT="9090"
LOKI_PORT="3100"
OTEL_GRPC_PORT="4317"

while [[ $# -gt 0 ]]; do

    case "$1" in

        --central-ip)
            CENTRAL_IP="$2"
            shift 2
            ;;

        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;

        --service)
            SERVICE="$2"
            shift 2
            ;;

        --prometheus-port)
            PROMETHEUS_PORT="$2"
            shift 2
            ;;

        --loki-port)
            LOKI_PORT="$2"
            shift 2
            ;;

        --otel-grpc-port)
            OTEL_GRPC_PORT="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            exit 1
            ;;

    esac

done

# ============================================================
# VALIDATION
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root."
    echo
    echo "sudo $0 ..."
    exit 1
fi

if [[ -z "$CENTRAL_IP" ]]; then
    echo "[ERROR] --central-ip is required."
    exit 1
fi

if [[ -z "$ENVIRONMENT" ]]; then
    echo "[ERROR] --environment is required."
    exit 1
fi

if [[ -z "$SERVICE" ]]; then
    SERVICE="$(hostname)"
fi

case "$ENVIRONMENT" in
    dev|qa|stage|prod)
        ;;
    *)
        echo "[ERROR] Environment must be dev, qa, stage or prod."
        exit 1
        ;;
esac

PROMETHEUS_REMOTE_WRITE="http://${CENTRAL_IP}:${PROMETHEUS_PORT}/api/v1/write"
LOKI_URL="http://${CENTRAL_IP}:${LOKI_PORT}/loki/api/v1/push"
OTEL_TRACES_ENDPOINT="${CENTRAL_IP}:${OTEL_GRPC_PORT}"

# ============================================================
# DETECTION
# ============================================================

detect_platform() {

    PLATFORM="ubuntu"

    if command -v k3s >/dev/null 2>&1; then
        PLATFORM="k3s"

    elif command -v kubectl >/dev/null 2>&1 &&
         kubectl version --client >/dev/null 2>&1; then
        PLATFORM="kubernetes"

    elif command -v docker >/dev/null 2>&1 &&
         docker info >/dev/null 2>&1; then
        PLATFORM="docker"

    else
        PLATFORM="host"
    fi

    echo "[INFO] Platform detected: ${PLATFORM}"
}

detect_components() {

    HAS_NGINX=false
    HAS_FRAPPE=false
    HAS_DOCKER=false
    HAS_CONTAINERD=false

    if command -v nginx >/dev/null 2>&1 ||
       systemctl list-unit-files 2>/dev/null | grep -q '^nginx'; then
        HAS_NGINX=true
    fi

    if [[ -d "/home/frappe" ]] ||
       [[ -d "/opt/frappe" ]] ||
       [[ -d "/home/frappe-bench" ]] ||
       find /home /opt -maxdepth 4 \
          -type d \
          \( -name "sites" -o -name "apps" \) \
          2>/dev/null | grep -q .; then
        HAS_FRAPPE=true
    fi

    if command -v docker >/dev/null 2>&1; then
        HAS_DOCKER=true
    fi

    if command -v containerd >/dev/null 2>&1 ||
       systemctl is-active --quiet containerd 2>/dev/null; then
        HAS_CONTAINERD=true
    fi

    echo "[INFO] NGINX detected: ${HAS_NGINX}"
    echo "[INFO] Frappe detected: ${HAS_FRAPPE}"
    echo "[INFO] Docker detected: ${HAS_DOCKER}"
    echo "[INFO] containerd detected: ${HAS_CONTAINERD}"
}

# ============================================================
# DIRECTORY
# ============================================================

prepare_directories() {

    mkdir -p "$INSTALL_DIR"
    mkdir -p /etc/promtail

}

# ============================================================
# NODE EXPORTER
# ============================================================

install_node_exporter() {

    echo
    echo "============================================================"
    echo " Installing Node Exporter"
    echo "============================================================"

    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        echo "[OK] Node Exporter already running."
        return
    fi

    TMP="/tmp/node_exporter.tar.gz"

    wget -q \
      "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" \
      -O "$TMP"

    tar -xzf "$TMP" -C /tmp

    install \
      -m 0755 \
      "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" \
      "$NODE_EXPORTER_BIN"

    rm -rf \
      "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" \
      "$TMP"

    if ! id node_exporter >/dev/null 2>&1; then
        useradd \
          --system \
          --no-create-home \
          --shell /usr/sbin/nologin \
          node_exporter
    fi

    cat > "$NODE_EXPORTER_SERVICE" <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=${NODE_EXPORTER_BIN}

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now node_exporter

    echo "[OK] Node Exporter running on :9100"
}

# ============================================================
# PROMTAIL CONFIG
# ============================================================

configure_promtail() {

    echo
    echo "============================================================"
    echo " Configuring Promtail"
    echo "============================================================"

    local SCRAPES=""

    # --------------------------------------------------------
    # System logs
    # --------------------------------------------------------

    SCRAPES+="
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: \"${HOSTNAME}\"
          environment: \"${ENVIRONMENT}\"
          service: \"${SERVICE}\"
          __path__: /var/log/*.log
"

    # --------------------------------------------------------
    # NGINX
    # --------------------------------------------------------

    if [[ "$HAS_NGINX" == "true" ]]; then

        SCRAPES+="
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: \"${HOSTNAME}\"
          environment: \"${ENVIRONMENT}\"
          service: \"${SERVICE}\"
          __path__: /var/log/nginx/*.log
"

    fi

    # --------------------------------------------------------
    # Docker
    # --------------------------------------------------------

    if [[ "$HAS_DOCKER" == "true" ]]; then

        SCRAPES+="
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          host: \"${HOSTNAME}\"
          environment: \"${ENVIRONMENT}\"
          service: \"${SERVICE}\"
          __path__: /var/lib/docker/containers/*/*.log
"

    fi

    # --------------------------------------------------------
    # Kubernetes / K3s
    # --------------------------------------------------------

    if [[ "$PLATFORM" == "k3s" ||
          "$PLATFORM" == "kubernetes" ]]; then

        SCRAPES+="
  - job_name: kubernetes-pods
    static_configs:
      - targets:
          - localhost
        labels:
          job: kubernetes-pods
          host: \"${HOSTNAME}\"
          environment: \"${ENVIRONMENT}\"
          service: \"${SERVICE}\"
          __path__: /var/log/pods/*/*/*.log
"

    fi

    # --------------------------------------------------------
    # Frappe
    # --------------------------------------------------------

    if [[ "$HAS_FRAPPE" == "true" ]]; then

        SCRAPES+="
  - job_name: frappe
    static_configs:
      - targets:
          - localhost
        labels:
          job: frappe
          host: \"${HOSTNAME}\"
          environment: \"${ENVIRONMENT}\"
          service: \"${SERVICE}\"
          __path__: /home/*/frappe-bench/logs/*.log
"

    fi

    cat > "$PROMTAIL_CONFIG" <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${LOKI_URL}

scrape_configs:
${SCRAPES}
EOF

    echo "[OK] Promtail configuration written."
}

# ============================================================
# PROMTAIL CONTAINER
# ============================================================

install_promtail() {

    echo
    echo "============================================================"
    echo " Installing Promtail"
    echo "============================================================"

    docker rm -f "$PROMTAIL_CONTAINER" >/dev/null 2>&1 || true

    docker run -d \
      --name "$PROMTAIL_CONTAINER" \
      --restart unless-stopped \
      --network host \
      -v /var/log:/var/log:ro \
      -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
      -v /var/log/pods:/var/log/pods:ro \
      -v /etc/promtail/config.yml:/etc/promtail/config.yml:ro \
      "$PROMTAIL_IMAGE" \
      -config.file=/etc/promtail/config.yml

    echo "[OK] Promtail running."
}

# ============================================================
# OTEL CONFIGURATION
# ============================================================

configure_otel() {

    echo
    echo "============================================================"
    echo " Configuring OpenTelemetry Collector"
    echo "============================================================"

    cat > "$OTEL_CONFIG" <<EOF
extensions:

  health_check:
    endpoint: 0.0.0.0:13133

receivers:

  otlp:

    protocols:

      grpc:
        endpoint: 0.0.0.0:4317

      http:
        endpoint: 0.0.0.0:4318

  hostmetrics:

    collection_interval: 15s

    scrapers:
      cpu:
      disk:
      filesystem:
      load:
      memory:
      network:
      paging:
      processes:

processors:

  memory_limiter:
    check_interval: 5s
    limit_mib: 512
    spike_limit_mib: 128

  batch:
    timeout: 5s
    send_batch_size: 1024

  resource:

    attributes:

      - key: deployment.environment
        value: ${ENVIRONMENT}
        action: upsert

      - key: service.name
        value: ${SERVICE}
        action: upsert

      - key: host.name
        value: ${HOSTNAME}
        action: upsert

exporters:

  otlp:

    endpoint: ${OTEL_TRACES_ENDPOINT}

    tls:
      insecure: true

  prometheusremotewrite:

    endpoint: ${PROMETHEUS_REMOTE_WRITE}

    resource_to_telemetry_conversion:
      enabled: true

service:

  extensions:
    - health_check

  pipelines:

    traces:

      receivers:
        - otlp

      processors:
        - memory_limiter
        - resource
        - batch

      exporters:
        - otlp

    metrics:

      receivers:
        - otlp
        - hostmetrics

      processors:
        - memory_limiter
        - resource
        - batch

      exporters:
        - prometheusremotewrite
EOF

    echo "[OK] OTel configuration written."
}

# ============================================================
# OTEL CONTAINER
# ============================================================

install_otel() {

    echo
    echo "============================================================"
    echo " Installing OpenTelemetry Collector"
    echo "============================================================"

    docker rm -f "$OTEL_CONTAINER" >/dev/null 2>&1 || true

    docker run -d \
      --name "$OTEL_CONTAINER" \
      --restart unless-stopped \
      --network host \
      --pid host \
      -v "$OTEL_CONFIG:/etc/otelcol-contrib/config.yml:ro" \
      -v /:/hostfs:ro \
      "$OTEL_IMAGE" \
      --config=/etc/otelcol-contrib/config.yml

    echo "[OK] OpenTelemetry Collector running."
}

# ============================================================
# APPLICATION ENVIRONMENT
# ============================================================

write_environment_file() {

    cat > "${INSTALL_DIR}/environment" <<EOF
APM_HOST=${HOSTNAME}
APM_ENVIRONMENT=${ENVIRONMENT}
APM_SERVICE=${SERVICE}

OTEL_EXPORTER_OTLP_ENDPOINT=http://${CENTRAL_IP}:${OTEL_GRPC_PORT}
OTEL_EXPORTER_OTLP_PROTOCOL=grpc

OTEL_SERVICE_NAME=${SERVICE}
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=${ENVIRONMENT},host.name=${HOSTNAME},service.name=${SERVICE}
EOF

    chmod 600 "${INSTALL_DIR}/environment"

    echo "[OK] Application telemetry environment written:"
    echo "     ${INSTALL_DIR}/environment"
}

# ============================================================
# CONNECTIVITY TEST
# ============================================================

test_connectivity() {

    echo
    echo "============================================================"
    echo " Testing Central APM Connectivity"
    echo "============================================================"

    test_port() {

        local NAME="$1"
        local HOST="$2"
        local PORT="$3"

        if timeout 3 bash -c \
            "</dev/tcp/${HOST}/${PORT}" \
            >/dev/null 2>&1; then

            echo "[OK] ${NAME}: ${HOST}:${PORT}"

        else

            echo "[WARN] ${NAME}: ${HOST}:${PORT} unreachable"

        fi
    }

    test_port "Prometheus" "$CENTRAL_IP" "$PROMETHEUS_PORT"
    test_port "Loki" "$CENTRAL_IP" "$LOKI_PORT"
    test_port "OTel" "$CENTRAL_IP" "$OTEL_GRPC_PORT"
}

# ============================================================
# STATUS
# ============================================================

show_status() {

    echo
    echo "============================================================"
    echo " APM TELEMETRY AGENT INSTALLED"
    echo "============================================================"

    echo
    echo "Host:"
    echo "  ${HOSTNAME}"

    echo
    echo "Environment:"
    echo "  ${ENVIRONMENT}"

    echo
    echo "Service:"
    echo "  ${SERVICE}"

    echo
    echo "Platform:"
    echo "  ${PLATFORM}"

    echo
    echo "Components:"
    echo "  Node Exporter : :9100"
    echo "  Promtail      : Docker"
    echo "  OTel          : Docker"

    echo
    echo "Central:"
    echo "  Prometheus: ${PROMETHEUS_REMOTE_WRITE}"
    echo "  Loki:       ${LOKI_URL}"
    echo "  OTel:       ${OTEL_TRACES_ENDPOINT}"

    echo
    echo "Detected:"
    echo "  NGINX:       ${HAS_NGINX}"
    echo "  Frappe:      ${HAS_FRAPPE}"
    echo "  Docker:      ${HAS_DOCKER}"
    echo "  containerd:  ${HAS_CONTAINERD}"

    echo
    echo "============================================================"
}

# ============================================================
# MAIN
# ============================================================

echo
echo "============================================================"
echo " Universal APM Telemetry Agent v${VERSION}"
echo "============================================================"
echo

detect_platform
detect_components
prepare_directories

test_connectivity

install_node_exporter

configure_promtail
install_promtail

configure_otel
install_otel

write_environment_file

show_status

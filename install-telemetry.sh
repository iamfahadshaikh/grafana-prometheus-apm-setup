#!/usr/bin/env bash

set -euo pipefail

# --------------------------------------------------
# CONFIGURATION & CONSTANTS
# --------------------------------------------------
DEFAULT_NODE_EXPORTER_VERSION="1.7.0"
DEFAULT_PROMTAIL_IMAGE="grafana/promtail:2.9.6"
PROMTAIL_CONFIG_PATH="/etc/promtail/config.yml"
FORCE_REINSTALL=false
HOSTNAME=$(hostname)
INPUT_IP="${1:-}"

echo "=================================================="
echo "    TELEMETRY AGENT INSTALLER & LOG FORWARDER    "
echo "=================================================="

# --------------------------------------------------
# STEP 0: AUTOMATED DUAL-NETWORKING RESOLUTION
# --------------------------------------------------
if [[ -z "$INPUT_IP" ]]; then
  read -p "Enter Central Loki IP (Public or Private): " INPUT_IP
fi

if [[ -z "$INPUT_IP" ]]; then
  echo "[ERROR] Loki Server IP is required. Exiting."
  exit 1
fi

# Strip protocols, ports, and trailing paths
CLEAN_IP=$(echo "$INPUT_IP" | sed -e 's|^http://||' -e 's|^https://||' -e 's|:.*||' -e 's|/.*||')

echo "[INFO] Testing connectivity to Central Loki Server ($CLEAN_IP)..."

# Test connection on Loki ingestion port 3100
if nc -z -w 3 "$CLEAN_IP" 3100 2>/dev/null; then
    TARGET_IP="$CLEAN_IP"
    echo "[OK] Reachable via $TARGET_IP:3100"
else
    echo "[WARN] Port 3100 not reachable on $CLEAN_IP."
    echo "[WARN] If on a different VNet, ensure Azure NSG on APM server allows Inbound TCP 3100!"
    TARGET_IP="$CLEAN_IP"
fi

CENTRAL_LOKI_URL="http://${TARGET_IP}:3100/loki/api/v1/push"

echo "Central Loki Endpoint: $CENTRAL_LOKI_URL"
echo "Host Identifier:       $HOSTNAME"
echo "=================================================="
echo ""

# --------------------------------------------------
# STEP 1: NODE EXPORTER INSTALLATION (IDEMPOTENT)
# --------------------------------------------------
echo "--- [1/3] Node Exporter Setup ---"

if command -v node_exporter &>/dev/null && systemctl is-active --quiet node_exporter && [ "$FORCE_REINSTALL" = false ]; then
  echo "[SKIP] Node Exporter service is already installed and active."
else
  echo "[INFO] Installing Node Exporter v${DEFAULT_NODE_EXPORTER_VERSION}..."

  wget -q "https://github.com/prometheus/node_exporter/releases/download/v${DEFAULT_NODE_EXPORTER_VERSION}/node_exporter-${DEFAULT_NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  tar -xzf "node_exporter-${DEFAULT_NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  sudo mv "node_exporter-${DEFAULT_NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf "node_exporter-${DEFAULT_NODE_EXPORTER_VERSION}.linux-amd64*"

  if ! id -u node_usr &>/dev/null; then
    sudo useradd -r -s /bin/false node_usr
  fi

  cat <<EOF | sudo tee /etc/systemd/system/node_exporter.service > /dev/null
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_usr
Group=node_usr
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|etc)(\$|/)

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now node_exporter
  echo "[OK] Node Exporter service active on port :9100"
fi
echo ""

# --------------------------------------------------
# STEP 2: PROMTAIL CONFIGURATION CHECK & DETECTION
# --------------------------------------------------
echo "--- [2/3] Promtail Configuration Setup ---"

SHOULD_CONFIGURE=true

if [ -f "$PROMTAIL_CONFIG_PATH" ]; then
  echo "=================================================="
  echo "[DETECTED] Existing Promtail configuration found at $PROMTAIL_CONFIG_PATH:"
  echo "--------------------------------------------------"
  sudo cat "$PROMTAIL_CONFIG_PATH"
  echo "--------------------------------------------------"
  echo "=================================================="
  echo ""

  echo "Options:"
  echo "  1) Keep existing configuration and exit setup"
  echo "  2) Overwrite with a fresh new configuration"
  read -p "Select choice [1/2] (Default: 1): " CONFIG_CHOICE
  CONFIG_CHOICE=${CONFIG_CHOICE:-1}

  if [ "$CONFIG_CHOICE" = "1" ]; then
    echo "[INFO] Preserving existing configuration."
    SHOULD_CONFIGURE=false
  else
    echo "[INFO] Proceeding with fresh configuration setup..."
  fi
else
  echo "[INFO] No existing Promtail configuration found. Proceeding with fresh setup."
fi

if [ "$SHOULD_CONFIGURE" = true ]; then
  SCRAPE_CONFIGS=""

  # Preset 1: System / Var logs
  read -p "Forward System Logs (/var/log/*.log)? [Y/n]: " INC_SYS
  INC_SYS=${INC_SYS:-Y}
  if [[ "$INC_SYS" =~ ^[Yy]$ ]]; then
    SCRAPE_CONFIGS+="
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          host: \"$HOSTNAME\"
          job: \"syslog\"
          __path__: /var/log/*.log"
  fi

  # Preset 2: Nginx Access & Error logs
  read -p "Forward Nginx Logs (/var/log/nginx/*.log)? [Y/n]: " INC_NGINX
  INC_NGINX=${INC_NGINX:-Y}
  if [[ "$INC_NGINX" =~ ^[Yy]$ ]]; then
    SCRAPE_CONFIGS+="
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          host: \"$HOSTNAME\"
          job: \"nginx\"
          __path__: /var/log/nginx/*.log"
  fi

  # Preset 3: Docker Container Logs
  read -p "Forward Docker Container Logs (/var/lib/docker/containers/*/*.log)? [Y/n]: " INC_DOCKER
  INC_DOCKER=${INC_DOCKER:-Y}
  if [[ "$INC_DOCKER" =~ ^[Yy]$ ]]; then
    SCRAPE_CONFIGS+="
  - job_name: docker
    static_configs:
      - targets: [localhost]
        labels:
          host: \"$HOSTNAME\"
          job: \"docker\"
          __path__: /var/lib/docker/containers/*/*.log"
  fi

  # Custom Log Path Loop
  while true; do
    read -p "Do you want to add a CUSTOM log path? [y/N]: " INC_CUSTOM
    INC_CUSTOM=${INC_CUSTOM:-N}
    if [[ "$INC_CUSTOM" =~ ^[Yy]$ ]]; then
      read -p "Enter job name (e.g., app-backend): " CUST_JOB
      read -p "Enter full log file path/glob (e.g., /var/log/modsec_audit.log): " CUST_PATH

      if [[ -n "$CUST_JOB" && -n "$CUST_PATH" ]]; then
        SCRAPE_CONFIGS+="
  - job_name: $CUST_JOB
    static_configs:
      - targets: [localhost]
        labels:
          host: \"$HOSTNAME\"
          job: \"$CUST_JOB\"
          __path__: $CUST_PATH"
        echo "[OK] Added custom target: $CUST_JOB -> $CUST_PATH"
      else
        echo "[WARN] Empty job name or path provided. Skipping..."
      fi
    else
      break
    fi
  done

  # Write configuration
  sudo mkdir -p /etc/promtail
  cat <<EOF | sudo tee "$PROMTAIL_CONFIG_PATH" > /dev/null
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: $CENTRAL_LOKI_URL

scrape_configs:$SCRAPE_CONFIGS
EOF
  echo "[INFO] Generated new configuration at $PROMTAIL_CONFIG_PATH"
fi

# --------------------------------------------------
# STEP 3: CONTAINER LAUNCH
# --------------------------------------------------
echo "--- [3/3] Deploying Promtail Container ---"

sudo docker rm -f promtail 2>/dev/null || true

sudo docker run -d \
  --name=promtail \
  --restart=unless-stopped \
  -v /var/log:/var/log:ro \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  -v /etc/promtail/config.yml:/etc/promtail/config.yml:ro \
  "$DEFAULT_PROMTAIL_IMAGE" -config.file=/etc/promtail/config.yml > /dev/null

echo ""
echo "=================================================="
echo "    TELEMETRY AGENT SETUP COMPLETE               "
echo "=================================================="
echo "1. Node Exporter: Active on port :9100"
echo "2. Promtail:      Forwarding to $CENTRAL_LOKI_URL"
echo "=================================================="
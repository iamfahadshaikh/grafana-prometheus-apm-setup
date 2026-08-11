#!/usr/bin/env bash

set -e

CENTRAL_LOKI_URL="http://4.240.15.105:3100/loki/api/v1/push"
HOSTNAME=$(hostname)

echo "=================================================="
echo "    TELEMETRY AGENT INSTALLER & LOG FORWARDER    "
echo "=================================================="
echo "Central Loki Server: $CENTRAL_LOKI_URL"
echo "Host Identifier:    $HOSTNAME"
echo "=================================================="
echo ""

# --------------------------------------------------
# STEP 1: INSTALL NODE EXPORTER
# --------------------------------------------------
echo "[INFO] Installing Node Exporter..."
NODE_EXPORTER_VERSION="1.7.0"

wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

sudo useradd -r -s /bin/false node_usr || true

cat <<'EOF' | sudo tee /etc/systemd/system/node_exporter.service > /dev/null
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_usr
Group=node_usr
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|etc)($|/)

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
echo "[OK] Node Exporter service active and listening on port :9100"
echo ""

# --------------------------------------------------
# STEP 2: INTERACTIVE LOG SELECTION
# --------------------------------------------------
echo "--------------------------------------------------"
echo " Configure Promtail Log Forwarding Targets"
echo "--------------------------------------------------"

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

# Custom Log Path Prompt Loop
while true; do
  read -p "Do you want to add a CUSTOM log path? [y/N]: " INC_CUSTOM
  INC_CUSTOM=${INC_CUSTOM:-N}
  if [[ "$INC_CUSTOM" =~ ^[Yy]$ ]]; then
    read -p "Enter job name (e.g., app-backend): " CUST_JOB
    read -p "Enter full log file path/glob (e.g., /home/user/app/logs/*.log): " CUST_PATH

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
      echo "[WARN] Job name or path was empty. Skipping..."
    fi
  else
    break
  fi
done

# --------------------------------------------------
# STEP 3: GENERATE PROMTAIL CONFIG & DEPLOY CONTAINER
# --------------------------------------------------
sudo mkdir -p /etc/promtail

cat <<EOF | sudo tee /etc/promtail/config.yml > /dev/null
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/log/promtail-positions.yaml

clients:
  - url: $CENTRAL_LOKI_URL

scrape_configs:$SCRAPE_CONFIGS
EOF

echo ""
echo "[INFO] Generated Promtail Configuration at /etc/promtail/config.yml"

# Restart Promtail container
sudo docker rm -f promtail 2>/dev/null || true

echo "[INFO] Launching Promtail via Docker..."
sudo docker run -d \
  --name=promtail \
  --restart=unless-stopped \
  -v /var/log:/var/log:ro \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  -v /etc/promtail/config.yml:/etc/promtail/config.yml:ro \
  grafana/promtail:2.9.6 -config.file=/etc/promtail/config.yml

echo ""
echo "=================================================="
echo "    TELEMETRY AGENTS INSTALLED SUCCESSFULLY    "
echo "=================================================="
echo "1. Node Exporter is active on port :9100"
echo "2. Promtail container is shipping logs to $CENTRAL_LOKI_URL"
echo "=================================================="
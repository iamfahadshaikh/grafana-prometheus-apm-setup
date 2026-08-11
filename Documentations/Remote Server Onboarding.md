# Remote Instance Onboarding & Telemetry Forwarding Guide

This operational guide provides step-by-step instructions for connecting remote instances (Development, QA, or Remote Production hosts) to the Central Observability Hub.

---

## 1. Port Exposure & Firewall Matrix

### Central Observability Server Ports

| Port | Direction | Allowed Source | Functional Purpose |
| :--- | :--- | :--- | :--- |
| **`80`** | Inbound | Public / VPN Users | HTTP to HTTPS automatic redirection |
| **`443`** | Inbound | Public / VPN Users | Secure HTTPS access to Grafana Web UI |
| **`3100`** | Inbound | Remote Agents (Dev/QA/Prod IPs) | Loki Log Ingestion endpoint (Promtail push) |
| **`4317`** | Inbound | Remote Apps (Dev/QA/Prod IPs) | OpenTelemetry gRPC Trace Ingestion endpoint |
| **`4318`** | Inbound | Remote Apps (Dev/QA/Prod IPs) | OpenTelemetry HTTP Trace Ingestion endpoint |

### Remote Agent Machine Ports

| Port | Direction | Allowed Source | Functional Purpose |
| :--- | :--- | :--- | :--- |
| **`9100`** | Inbound | Central Server IP Only | Node Exporter system metrics scrape target |

---

## 2. Granular Onboarding Steps

Follow these 4 steps on any remote target machine (e.g., `dev-server-01`, `qa-server-01`).

---

### Step 1: Install Node Exporter on the Remote Machine (Metrics Gatherer)

1. SSH into the target remote machine:
   ```bash
   ssh user@<REMOTE_INSTANCE_IP>
   ```

2. Execute the following commands to download, configure, and register Node Exporter as a `systemd` service:
   ```bash
   # Download and extract Node Exporter binary
   wget [https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz](https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz)
   tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
   sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
   rm -rf node_exporter-1.7.0.linux-amd64*

   # Create system user for execution
   sudo useradd --rs /bin/false node_usr || true

   # Create systemd unit file
   cat <<'EOF' | sudo tee /etc/systemd/system/node_exporter.service
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

   # Start service
   sudo systemctl daemon-reload
   sudo systemctl enable --now node_exporter
   sudo systemctl status node_exporter
   ```

---

### Step 2: Deploy Promtail on the Remote Server (Log Forwarder)

1. Create a dedicated directory and configuration file at `/etc/promtail/config.yml` (replace `<CENTRAL_OBSERVABILITY_SERVER_IP>` with your central server's IP address):
   ```bash
   sudo mkdir -p /etc/promtail
   ```

   ```yaml
   server:
     http_listen_port: 9080
     grpc_listen_port: 0

   positions:
     filename: /var/log/promtail-positions.yaml

   clients:
     - url: http://<CENTRAL_OBSERVABILITY_SERVER_IP>:3100/loki/api/v1/push

   scrape_configs:
     - job_name: remote-system-logs
       static_configs:
         - targets: [localhost]
           labels:
             host: "qa-app-01"            # Unique host label
             environment: "qa"             # Environment tag (dev/qa/production)
             job: "syslog"
             __path__: /var/log/*.log
   ```

2. Launch Promtail via Docker on the remote server:
   ```bash
   docker run -d \
     --name=promtail \
     --restart=unless-stopped \
     -v /var/log:/var/log:ro \
     -v /etc/promtail/config.yml:/etc/promtail/config.yml:ro \
     grafana/promtail:2.9.6 -config.file=/etc/promtail/config.yml
   ```

---

### Step 3: Register Remote Target in Central Prometheus

1. On your **Central Observability Server**, edit `prometheus/prometheus.yml` and add the new remote targets under `scrape_configs`:
   ```yaml
     # Remote QA Server Scrape Target
     - job_name: 'qa-environment'
       static_configs:
         - targets: ['<REMOTE_QA_SERVER_IP>:9100']
           labels:
             host: 'qa-app-01'
             environment: 'qa'

     # Remote Dev Server Scrape Target
     - job_name: 'dev-environment'
       static_configs:
         - targets: ['<REMOTE_DEV_SERVER_IP>:9100']
           labels:
             host: 'dev-app-01'
             environment: 'dev'
   ```

2. Reload Prometheus configuration dynamically without downtime:
   ```bash
   curl -X POST http://localhost:9090/-/reload
   ```

3. Verify firewall connectivity:
   * **On Remote Target:** Ensure port `9100` allows incoming connections from Central Server IP.
   * **On Central Server:** Ensure ports `3100`, `4317`, and `4318` allow incoming connections from Remote Target IPs.

---

### Step 4: Configure APM Tracing in Application Code

In the application codebase running on the remote Dev, QA, or Production server, configure the OpenTelemetry exporter environment variables:

```bash
# Set OTLP gRPC or HTTP ingestion endpoint pointing to Central Server
export OTEL_EXPORTER_OTLP_ENDPOINT="http://<CENTRAL_OBSERVABILITY_SERVER_IP>:4317"

# Define Service and Environment metadata
export OTEL_SERVICE_NAME="payment-service-qa"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=qa,host.name=qa-app-01"
```

---

## 3. Visual Verification in Grafana GUI

After onboarding a remote host:

1. **Access Web Portal:** Navigate to `https://<CENTRAL_SERVER_IP>` and log in.
2. **Metrics Dashboard:** Open **Dashboard `1860` (Node Exporter Full)**. Click the **Host** filter dropdown at the top-left to select and switch views between `localhost`, `qa-app-01`, and `dev-app-01`.
3. **Log Stream Verification:** Navigate to **Explore** $\rightarrow$ **Loki**. Use the Label Browser to filter by `environment = qa` or `host = qa-app-01`.
4. **Distributed Tracing Verification:** Navigate to **Explore** $\rightarrow$ **Tempo**. Query traces originating from service `payment-service-qa`.
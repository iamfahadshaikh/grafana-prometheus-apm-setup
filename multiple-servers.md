                  ┌─────────────────────────────────────────┐
                  │          GRAFANA (Central UI)           │
                  └────────────────────┬────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
   PROMETHEUS                       LOKI                           TEMPO
(Metrics & Stats)             (Central Logs)                  (APM & Traces)
 ── Host Hardware              ── System Syslogs               ── End-to-End Traces
 ── Container Resources        ── NGINX Access/Errors          ── Slow Functions
 ── Throughput & Errors        ── Application Logs             ── Service Bottlenecks
 ── Uptime & Availability      ── DB / Cache Logs              ── DB Query Timing


Architecture Summary Matrix
Component,Telemetry Type,Role in Platform,Primary Access / Endpoint
Grafana,Visualization,Unified UI for Dashboards & Exploration,http://localhost:3000
Prometheus,Metrics,Time-series Database & Scrape Engine,http://localhost:9090
Loki,Logs,High-efficiency Log Storage Engine,http://localhost:3100
Tempo,Traces,Distributed APM Trace Storage,http://localhost:3200
OTEL Collector,Ingestion Proxy,OpenTelemetry Protocol (OTLP) Pipeline,Ports 4317 (gRPC) / 4318 (HTTP)
Alertmanager,Alerting,Notification Router & Silence Engine,http://localhost:9093
Node Exporter,Host Metrics,Linux System Hardware Daemon,http://localhost:9100/metrics
cAdvisor,Container Metrics,Docker Runtime Usage Analyzer,http://localhost:8080
Promtail,Log Agent,Log Collector & Forwarder for Loki,Ships to Loki (:3100)

Look at that output—**100% clean across the board!**

Every core service is running without errors or health probe failures:

* **`prometheus`**: `Up (healthy)`
* **`grafana`**: `Up (healthy)`
* **`loki`**: `Up (healthy)`
* **`tempo`**: `Up (healthy)`
* **`alertmanager`**: `Up (healthy)`
* **`cadvisor`**: `Up (healthy)`
* **`otel-collector`**: `Up` (Running cleanly without container health check interference)
* **`node-exporter`**: `Up`
* **`promtail`**: `Up`

---

## Phase Execution Summary

* **Phase 1 (Container Orchestration):** Complete — All core services online, network configuration aligned.
* **Phase 2 (Ingestion Engines Verification):** Complete — All 7 Prometheus targets reporting `health: "up"`, Loki ready, Tempo ready, OTEL listening.
* **Phase 3 (Datasource Provisioning):** Complete — Grafana automatically connected to Prometheus (`:9090`), Loki (`:3100`), and Tempo (`:3200`).

---

## PHASE 4: Remote Production Server Onboarding

Now we transition to **Phase 4: Remote Production Server Onboarding**.

The objective of Phase 4 is to configure target production servers (`Server 1`, `Server 2`, etc.) to forward telemetry directly to this central observability server.

### Central Observability Node Ingestion Endpoints

Ensure these ports are reachable over your network from remote servers:

* **Metrics (Prometheus Scrape):** Remote Exporters listening on `:9100` (Node Exporter), `:9113` (NGINX Exporter).
* **Logs (Loki Ingestion):** `http://<OBSERVABILITY_SERVER_IP>:3100/loki/api/v1/push`
* **Traces & APM (OpenTelemetry Collector):**
* **gRPC OTLP:** `<OBSERVABILITY_SERVER_IP>:4317`
* **HTTP OTLP:** `http://<OBSERVABILITY_SERVER_IP>:4318/v1/traces`



---

### Step 1: Remote Server Exporter Setup (Node Exporter)

On every remote Linux server, run Node Exporter to expose system hardware metrics.

#### Automated Install Script for Remote Servers (`setup-remote-node-exporter.sh`):

```bash
#!/usr/bin/env bash

set -Eeuo pipefail

NODE_EXPORTER_VERSION="1.7.0"

echo "[INFO] Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

echo "[INFO] Extracting binary..."
tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

echo "[INFO] Creating system user..."
sudo useradd --rs /bin/false node_usr || true

echo "[INFO] Creating systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_usr
Group=node_usr
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|etc)($$|/)

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] Reloading systemd and starting Node Exporter..."
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

echo "[OK] Node Exporter active and listening on port 9100."

```

---

### Step 2: Configure Central Prometheus Scrape Target

Once Node Exporter is running on your remote production server, edit `prometheus/prometheus.yml` on your central observability server to scrape it.

#### Updated `prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    origin: central-observability
    environment: production

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - alert.rules.yml

scrape_configs:
  # Central Server Self-Monitoring
  - job_name: prometheus
    static_configs:
      - targets:
          - prometheus:9090

  - job_name: central-node-exporter
    static_configs:
      - targets:
          - host.docker.internal:9100

  - job_name: cadvisor
    static_configs:
      - targets:
          - cadvisor:8080

  - job_name: otel-collector
    static_configs:
      - targets:
          - otel-collector:8888

  - job_name: alertmanager
    static_configs:
      - targets:
          - alertmanager:9093

  - job_name: loki
    static_configs:
      - targets:
          - loki:3100

  - job_name: tempo
    static_configs:
      - targets:
          - tempo:3200

  # -----------------------------------------------------------------------
  # REMOTE PRODUCTION SERVERS
  # -----------------------------------------------------------------------
  - job_name: production-server-1
    static_configs:
      - targets:
          - "<REMOTE_SERVER_1_IP>:9100"
        labels:
          server_name: "prod-server-01"
          environment: "production"

  # Add future servers here:
  # - job_name: production-server-2
  #   static_configs:
  #     - targets:
  #         - "<REMOTE_SERVER_2_IP>:9100"
  #       labels:
  #         server_name: "prod-server-02"
  #         environment: "production"

```

---

### Step 3: Remote Promtail Configuration (Log Forwarding)

On the remote server, deploy Promtail to forward system and application logs directly to central Loki.

#### Remote `promtail-config.yml`:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/log/promtail-positions.yaml

clients:
  - url: http://<CENTRAL_OBSERVABILITY_SERVER_IP>:3100/loki/api/v1/push

scrape_configs:
  - job_name: remote-syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: prod-server-01
          environment: production
          __path__: /var/log/*.log

  - job_name: remote-nginx-access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          log_type: access
          host: prod-server-01
          environment: production
          __path__: /var/log/nginx/access.log

  - job_name: remote-nginx-error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          log_type: error
          host: prod-server-01
          environment: production
          __path__: /var/log/nginx/error.log

```

---

### Next Action

1. Do you have a specific IP or hostname for `Production Server 1` to onboard first?
2. Once you add the remote server IP to `prometheus/prometheus.yml`, reload Prometheus without downtime using:
```bash
curl -X POST http://localhost:9090/-/reload

```


Got it! No command line or config files for the remote servers—you want to onboard and manage everything visually through a **GUI**.

The Grafana Observability Stack provides full GUI-based workflows for configuration, ingestion monitoring, log querying, and dashboard setup.

---

## How to Configure and Onboard Remote Servers via GUI

### 1. Prometheus Remote Target Management (GUI)

Instead of editing `prometheus.yml` via CLI every time you add a server, you can manage and inspect your remote targets directly from the Grafana or Prometheus web interfaces.

* **Prometheus Targets Dashboard (`http://<OBSERVABILITY_SERVER_IP>:9090/targets`):**
* Displays every remote exporter endpoint visually.
* Shows real-time target status (`UP` / `DOWN`), last scrape duration, scrape error messages, and assigned labels without touching the host terminal.


* **Grafana Service Discovery View (`http://<OBSERVABILITY_SERVER_IP>:3000`):**
1. Go to **Connections** $\rightarrow$ **Data Sources** $\rightarrow$ **Prometheus**.
2. Click **Build a Query** or use **Explore** to select metric namespaces (`node_*`, `container_*`) using visual dropdown menus—no PromQL typing required.



---

### 2. Log Exploration & Streaming via Grafana Explore GUI

Once Promtail or a log forwarder is running on the remote machine, you do not need to check remote log files over SSH.

1. Open Grafana (`http://<OBSERVABILITY_SERVER_IP>:3000`).
2. Navigate to **Explore** (compass icon on the left menu).
3. Select **Loki** from the top-left data source dropdown.
4. Click **Label Browser**:
* Select `host` $\rightarrow$ Choose your remote server name (e.g., `prod-server-01`).
* Select `job` $\rightarrow$ Choose `syslog` or `nginx`.


5. Click **Show Logs** to stream live logs, filter by log level (`ERROR`, `WARN`), or search text visually.

---

### 3. Visual Dashboard Import (No Manual Panel Building)

You can instantly visualize remote server metrics using pre-built community dashboards via the Grafana GUI:

1. In Grafana, click **Dashboards** $\rightarrow$ **New** $\rightarrow$ **Import**.
2. Enter official Grafana Dashboard IDs:
* **Node Exporter Full (Linux Hardware):** Enter ID `1860`
* **cAdvisor (Docker Containers):** Enter ID `14282`
* **NGINX High Performance:** Enter ID `12708`


3. Click **Load**, select your provisioned **Prometheus** datasource from the dropdown, and click **Import**.
4. Use the top-left **Host / Server** drop-down filter in the dashboard to switch between `Server 1`, `Server 2`, and `Server 3` visually.

---

### 4. Alerting Configuration via Grafana Unified Alerting GUI

Instead of maintaining `alert.rules.yml` or `alertmanager.yml`, you can build, route, and test alerts visually:

1. Go to **Alerting** $\rightarrow$ **Alert Rules** $\rightarrow$ **Create Alert Rule**.
2. Pick a metric visually using the query builder (e.g., CPU usage $> 80\%$).
3. Set evaluation intervals and threshold conditions.
4. Go to **Contact Points** to visually configure Slack webhooks, Email (SMTP), Discord, or Teams integration.
5. Go to **Notification Policies** to route specific server tags to target notification channels using drag-and-drop rule matching.
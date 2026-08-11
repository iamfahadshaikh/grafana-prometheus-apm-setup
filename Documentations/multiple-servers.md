# Multi-Node Fleet Observability Strategy Guide

## Fleet Architecture Diagram

```
                  ┌─────────────────────────────────────────┐
                  │          GRAFANA (Central UI)           │
                  └────────────────────┬────────────────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          ▼                            ▼                            ▼
    PROMETHEUS                       LOKI                         TEMPO
 (Metrics & Stats)              (Central Logs)                (APM & Traces)
  ── Host Hardware               ── System Syslogs             ── End-to-End Traces
  ── Container Resources        ── NGINX Access/Errors        ── Slow Functions
  ── Throughput & Errors        ── Application Logs            ── Service Bottlenecks
  ── Uptime & Availability      ── DB / Cache Logs            ── DB Query Timing
```

---

## Multi-Server Standardization Rules

When scaling observability across multiple servers (`prod-server-01`, `prod-server-02`, `staging-server-01`), follow strict naming and labeling conventions to maintain dashboard usability.

### Mandatory External Labels
Every metric target and log-stream must include three metadata labels:

1. `environment`: (`production` | `staging` | `development`)
2. `host`: (`prod-app-01`, `db-node-02`, etc.)
3. `region`: (`us-east-1`, `ap-south-1`, `on-prem`, etc.)

---

## Ingestion Endpoints Directory

Configure remote shippers using these central server endpoints:

* **Metrics Scrape Endpoint:** Central Prometheus pulls from remote `:9100`.
* **Loki Log Ingestion:** `http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push`
* **OTEL Traces (gRPC):** `<CENTRAL_SERVER_IP>:4317`
* **OTEL Traces (HTTP):** `http://<CENTRAL_SERVER_IP>:4318/v1/traces`

---

## Visual Verification in Grafana GUI

Once remote servers are onboarded:

1. **Dashboard 1860 (Node Exporter Full):** Use the **Host** dropdown menu at the top-left to select and switch between hosts visually.
2. **Grafana Explore (Loki):** Open the Label Browser, select `host` $\rightarrow$ `prod-server-01` to filter logs by host.
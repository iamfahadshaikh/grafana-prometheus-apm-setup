# Observability Implementation Status Guide

## 1. Active & Verified Capabilities

The central observability platform is fully operational, hardened, and actively gathering telemetry across all categories:

| Observability Category | Underlying Tooling | Ingestion Target | Dashboard ID / Interface |
| :--- | :--- | :--- | :--- |
| **Host System OS & Hardware** | Node Exporter | Prometheus | Dashboard `1860` |
| **Container Metrics & Workloads** | cAdvisor | Prometheus | Dashboard `14282` |
| **Centralized System & Web Logs** | Promtail + Nginx | Loki | Grafana Explore (`/explore`) |
| **Distributed APM & Traces** | OTEL Collector | Tempo | Dashboard `23242` |
| **Throughput & Error Rates** | Prometheus + OTEL | Prometheus | App Dashboards |
| **Alert Routing & Silencing** | Prometheus Rules | Alertmanager | Alertmanager UI (`:9093`) |
| **Redis Cache Metrics** | Redis Exporter | Prometheus | Dashboard `763` |
| **PostgreSQL Database Metrics** | Postgres Exporter | Prometheus | Dashboard `9628` |
| **Synthetic Uptime & SSL Probes** | Blackbox Exporter | Prometheus | Custom Synthetic Panel |

---

## 2. Maintenance Tasks

The following operational tasks remain for production deployment maintenance:

1. **Production TLS Certificates:** Replace the temporary self-signed certificates in `nginx/certs/` with CA-signed certificates (e.g., Let's Encrypt).
2. **Alertmanager Webhooks:** Replace placeholder webhook URLs in `alertmanager/alertmanager.yml` with active Slack, PagerDuty, or Email SMTP configurations.
3. **Remote Node Fleet Scaling:** Onboard additional remote production hosts using the procedure in `connect-remote-server.md`.
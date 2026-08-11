# Functional Component Reporting Guide

## Platform Component Inventory

The central observability stack consists of **13 active containerized services**, **1 bridge network**, and **5 persistent volumes**.

| # | Service Component | Functional Category | Primary Role in Platform |
| :-: | :--- | :--- | :--- |
| 1 | **Nginx** | Edge Gateway | TLS/SSL termination, HTTP-to-HTTPS redirect, rate limiting |
| 2 | **Grafana** | Visualization | Unified UI for dashboards, exploration, and alerting |
| 3 | **Prometheus** | Metrics Engine | Time-series DB, metric scraper, and rule evaluator |
| 4 | **Alertmanager** | Alerting | Notification router, alert deduplication, and silence engine |
| 5 | **Loki** | Log Storage | Indexless chunked log storage engine |
| 6 | **Promtail** | Log Collection | Local/remote log tailer and shipper targeting Loki |
| 7 | **Tempo** | Trace Storage | High-scale distributed tracing storage backend |
| 8 | **OTEL Collector** | Telemetry Hub | OpenTelemetry protocol (OTLP) receiver and processor |
| 9 | **Node Exporter** | Host Metrics | Linux hardware exporter (CPU, RAM, Disk, Network) |
| 10 | **cAdvisor** | Container Metrics | Docker container resource and runtime usage analyzer |
| 11 | **Blackbox Exporter**| Availability | External synthetic HTTP, TCP, ICMP, and SSL certificate probes |
| 12 | **Redis Exporter** | Cache Metrics | Redis memory limits, client counts, and hit/miss ratios |
| 13 | **Postgres Exporter**| DB Metrics | PostgreSQL active connections, slow queries, and locks |

---

## Infrastructure Resources

* **Bridge Network:** `observability`
* **Persistent Volumes:**
  * `grafana-data` (Dashboards, user accounts, and SQLite DB)
  * `prometheus-data` (TSDB metrics storage)
  * `alertmanager-data` (Alert notification state and silences)
  * `loki-data` (Log chunks and compaction state)
  * `tempo-data` (Distributed trace blocks)

---

## Functional Category Mapping

```
                               CENTRAL OBSERVABILITY
                                        │
     ┌──────────────┬───────────────────┼───────────────────┬──────────────┐
     ▼              ▼                   ▼                   ▼              ▼
VISUALIZATION    METRICS             LOGGING             TRACING        ALERTING
  Grafana      Prometheus            Promtail             Tempo       Alertmanager
              Node Exporter           Loki            OTEL Collector
                cAdvisor
             Redis Exporter
            Postgres Exporter
           Blackbox Exporter
```
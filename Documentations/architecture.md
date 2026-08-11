# Central Observability Platform Architecture Guide

## Overview & System Flow Architecture

This central observability platform acts as a unified telemetry hub collecting **Metrics**, **Logs**, and **Traces** across local host containers and remote production nodes. 

Access to all visual dashboards, search portals, and administrative APIs is protected behind **Nginx** acting as a TLS/SSL terminating reverse proxy.

```
                                USER / BROWSER
                                      |
                           https://<SERVER_IP>:443
                                      |
                                      v
                             +-----------------+
                             |  NGINX GATEWAY  | (SSL / Rate Limiting / WAF)
                             +--------+--------+
                                      |
                                      | Internal Proxy Pass
                                      v
                                   GRAFANA
                         (Central Visual Dashboard)
                              [http://127.0.0.1:3000](http://127.0.0.1:3000)
                                      |
             +------------------------+------------------------+
             |                        |                        |
             v                        v                        v
        PROMETHEUS                   LOKI                    TEMPO
 (Time-Series Metrics Engine)    (Log Engine)         (Distributed Traces DB)
    [http://127.0.0.1:9090](http://127.0.0.1:9090)     [http://127.0.0.1:3100](http://127.0.0.1:3100)   [http://127.0.0.1:3200](http://127.0.0.1:3200)
             ^                        ^                        ^
             | (Scrapes)              | (Push Stream)          | (OTLP Export)
             |                        |                        |
      PROMETHEUS SERVER            PROMTAIL              OTEL COLLECTOR
     (Scrape Scheduler)        (Log Collector)      (Ingestion Gateway)
             ^                        ^                 Ports 4317 / 4318
             |                        |                        ^
             |                        |                        |
+------------+------------+ +---------+------------+ +---------+------------+
| METRICS SOURCES         | | LOG SOURCES          | | TRACE SOURCES          |
|                         | |                      | |                        |
| Node Exporter (:9100)   | | NGINX Access/Error   | | OpenTelemetry SDKs     |
| cAdvisor (:8080)        | | ModSecurity / WAF    | | Microservice Traces    |
| Blackbox Exp (:9115)    | | Container Logs       | | Python / Node / Go Apps |
| Redis Exp (:9121)       | | System Syslogs       | | API Gateways           |
| Postgres Exp (:9187)    | | Application Logs     | |                        |
+-------------------------+ +----------------------+ +------------------------+

                                 PROMETHEUS
                                      |
                                      v (Alert Trigger)
                                 ALERTMANAGER
                            [http://127.0.0.1:9093](http://127.0.0.1:9093)
                                      |
                           +----------+----------+
                           |          |          |
                           v          v          v
                         Slack      Email     Teams
```

---

## Service & Network Architecture Matrix

| Service | Protocol / Port | Internal Bind | Role in Platform | Access Path |
| :--- | :--- | :--- | :--- | :--- |
| **Nginx** | `80`, `443` | `0.0.0.0` | SSL/TLS Termination, Rate-limiting Gateway | `https://<SERVER_IP>` |
| **Grafana** | `3000` | `127.0.0.1` | Unified Visualization Dashboard UI | Proxied via Nginx |
| **Prometheus** | `9090` | `127.0.0.1` | Time-Series Metrics Engine & Scraper | `http://127.0.0.1:9090` |
| **Alertmanager** | `9093` | `127.0.0.1` | Alert Routing, Deduplication & Notification | `http://127.0.0.1:9093` |
| **Loki** | `3100` | `127.0.0.1` | High-efficiency Log Aggregation Engine | `http://127.0.0.1:3100` |
| **Promtail** | N/A | Internal | Host & Container Log Collector | Ships directly to Loki |
| **Tempo** | `3200` | `127.0.0.1` | Distributed Tracing & APM Storage | `http://127.0.0.1:3200` |
| **OTEL Collector**| `4317`, `4318` | `127.0.0.1` | OpenTelemetry Ingestion Gateway (gRPC/HTTP) | Ingests from SDKs |
| **Node Exporter**| `9100` | Host Net | Linux Host Hardware & OS Metrics | Scraped by Prometheus |
| **cAdvisor** | `8080` | `127.0.0.1` | Docker Container Resource Usage | Scraped by Prometheus |
| **Blackbox Exp** | `9115` | `127.0.0.1` | External Synthetic Endpoint & SSL Probes | Scraped by Prometheus |
| **Redis Exporter**| `9121` | `127.0.0.1` | Cache Hit/Miss Ratios & Memory Limits | Scraped by Prometheus |
| **Postgres Exp** | `9187` | `127.0.0.1` | DB Query Performance & Pool Connections | Scraped by Prometheus |
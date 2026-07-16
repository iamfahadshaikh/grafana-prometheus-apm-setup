Your Docker Compose file contains **12 services (components)**.

| #  | Component                   | Purpose                                       |
| -- | --------------------------- | --------------------------------------------- |
| 1  | **Grafana**                 | Dashboards and visualization                  |
| 2  | **Prometheus**              | Metrics collection and storage                |
| 3  | **Alertmanager**            | Alert routing and notifications               |
| 4  | **Loki**                    | Log aggregation and storage                   |
| 5  | **Promtail**                | Log collection agent (sends logs to Loki)     |
| 6  | **Tempo**                   | Distributed tracing backend                   |
| 7  | **OpenTelemetry Collector** | Receives, processes, and forwards telemetry   |
| 8  | **Node Exporter**           | Host/server metrics (CPU, RAM, Disk, Network) |
| 9  | **cAdvisor**                | Docker container metrics                      |
| 10 | **Blackbox Exporter**       | Uptime, HTTP, TCP, ICMP, SSL monitoring       |
| 11 | **Redis Exporter**          | Redis metrics                                 |
| 12 | **Postgres Exporter**       | PostgreSQL metrics                            |

### Other infrastructure defined

Besides the 12 services, the compose file also defines:

* **1 Network**

  * `observability`

* **5 Named Volumes**

  * `grafana-data`
  * `prometheus-data`
  * `alertmanager-data`
  * `loki-data`
  * `tempo-data`

### Functional grouping

You can think of the stack as:

* **Visualization**

  * Grafana

* **Metrics**

  * Prometheus
  * Node Exporter
  * cAdvisor
  * Redis Exporter
  * Postgres Exporter

* **Logging**

  * Promtail
  * Loki

* **Tracing**

  * Tempo
  * OpenTelemetry Collector

* **Alerting**

  * Alertmanager

* **Availability Monitoring**

  * Blackbox Exporter

So the stack consists of **12 Docker services**, organized into **6 functional observability categories**.

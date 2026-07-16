Spot on! Right now, everything you are seeing in Grafana is coming from **Host 01 (your local machine where Docker is running)**.

To monitor an external **EC2 instance**, **Azure VM**, or **bare-metal server**, you **do not** install Grafana, Loki, or Prometheus on those remote machines. Your central server stays the single source of truth. You only install small **agents/exporters** on the remote server that send data back to your central host over the network.

---

## The Remote Server Architecture

```
  ┌─────────────────────────────────────────────────────────────┐
  │              REMOTE SERVER (AWS EC2 / Azure VM)             │
  │                                                             │
  │   ┌──────────────────┐                ┌─────────────────┐   │
  │   │  Node Exporter   │                │    Promtail     │   │
  │   │  (Port 9100)     │                │   (Log Agent)   │   │
  │   └────────┬─────────┘                └────────┬────────┘   │
  └────────────┼───────────────────────────────────┼────────────┘
               │ (Metrics Scrape)                  │ (Pushes Logs over HTTP)
               │                                   │
               ▼                                   ▼
  ┌─────────────────────────┐         ┌─────────────────────────┐
  │   Prometheus (:9090)    │         │       Loki (:3100)      │
  └─────────────────────────┘         └─────────────────────────┘
  ┌─────────────────────────────────────────────────────────────┐
  │               CENTRAL OBSERVABILITY SERVER                  │
  └─────────────────────────────────────────────────────────────┘

```

---

## How to Connect a Remote Server (3 Simple Steps)

### Step 1: Install Exporters on the Remote Server (AWS EC2 / Azure VM)

SSH into your remote server and install the light metric & log collectors:

1. **System Metrics (Node Exporter):**
Run Node Exporter as a container or system service listening on port `:9100`:
```bash
docker run -d --name=node-exporter --net=host prom/node-exporter:v1.7.0

```


2. **System & Web Logs (Promtail):**
Create a small `promtail-config.yml` on the remote server pointing back to your Central Server IP:
```yaml
server:
  http_listen_port: 9080

positions:
  filename: /var/log/positions.yaml

clients:
  - url: http://<CENTRAL_SERVER_PUBLIC_IP>:3100/loki/api/v1/push

scrape_configs:
  - job_name: remote-system-logs
    static_configs:
      - targets: [localhost]
        labels:
          host: "aws-ec2-prod-01"   # <--- Label your remote server name
          job: "syslog"
          path: /var/log/*.log

```


Start Promtail on the remote machine:
```bash
docker run -d --name=promtail -v /var/log:/var/log:ro -v $(pwd)/promtail-config.yml:/etc/promtail/config.yml grafana/promtail:2.9.6 -config.file=/etc/promtail/config.yml

```



---

### Step 2: Update Prometheus Config on Your Central Server

On your central machine, edit `prometheus/prometheus.yml` so Prometheus pulls metrics from the remote server's IP address:

```yaml
  - job_name: 'remote-ec2-server'
    static_configs:
      - targets: ['<REMOTE_EC2_PUBLIC_OR_PRIVATE_IP>:9100']
        labels:
          host: 'aws-ec2-prod-01'
          environment: 'production'

```

Reload Prometheus instantly:

```bash
curl -X POST http://localhost:9090/-/reload

```

---

### Step 3: Firewall / Security Group Settings

Ensure network connectivity between your machines:

* **AWS Security Group / Azure NSG on Remote Server:** Allow Inbound Port `9100` from your Central Server IP (for metric scraping).
* **AWS Security Group / Azure NSG on Central Server:** Allow Inbound Port `3100` (Loki) & `4317/4318` (OTEL) from your Remote Server IP (for log and trace ingestion).

---

## How it Looks in Grafana GUI

Once connected:

1. **In Dashboard `1860` (Node Exporter Full):**
At the top-left of the screen, a new drop-down menu labeled **Host** or **Instance** will automatically appear! You can click it to switch between `localhost`, `aws-ec2-prod-01`, and `azure-vm-02`.
2. **In Grafana Explore (Loki):**
Under **Label filters**, click `host` $\rightarrow$ you will now see `aws-ec2-prod-01` alongside `localhost`. You can view logs across all your servers in one unified place!
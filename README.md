# Central Observability Platform

A production-oriented, containerized observability platform for collecting and visualizing **Metrics** and **Logs** from a central server and remote application servers.

The platform uses:

* **Grafana** for visualization
* **Prometheus** for metrics collection and storage
* **Loki** for centralized log storage
* **Promtail** for remote log collection
* **Node Exporter** for Linux host metrics
* **Nginx** as the HTTPS reverse proxy
* **Docker Compose** for running the central observability stack
* **Alertmanager** for alert routing
* **Tempo / OpenTelemetry Collector** for distributed tracing

The setup was implemented across **two Linux servers**:

1. **Central APM / Observability Server**
2. **Remote Test Application Server**

---

# 1. Architecture

The overall architecture is:

```text
                         USER / BROWSER
                               |
                               |
                     HTTPS :443 / HTTP :80
                               |
                               v
                    +---------------------+
                    |        NGINX        |
                    |  Reverse Proxy /    |
                    |  TLS Termination    |
                    +----------+----------+
                               |
                               v
                    +---------------------+
                    |       GRAFANA       |
                    | Visualization / UI  |
                    +----------+----------+
                               |
              +----------------+----------------+
              |                |                |
              v                v                v
       +-------------+   +-------------+   +-------------+
       | PROMETHEUS  |   |    LOKI     |   |    TEMPO    |
       |   Metrics   |   |    Logs     |   |   Traces    |
       +------+------+   +------+------+   +------+------+
              ^                 ^                 ^
              |                 |                 |
              |                 |                 |
       Node Exporter        Promtail          OTEL Collector
              |                 |                 |
              |                 |                 |
              +-----------------+-----------------+
                                |
                         REMOTE SERVERS
                                |
               +----------------+----------------+
               |                                 |
               v                                 v
        +--------------+                  +---------------+
        | Node Exporter|                  |   Promtail   |
        |    :9100     |                  | Docker Agent  |
        +--------------+                  +-------+-------+
                                                |
                              +-----------------+----------------+
                              |                 |                |
                              v                 v                v
                         /var/log/*.log   Nginx Logs     Docker Logs
```

The central server acts as the observability hub.

Remote servers do not need the complete Grafana/Prometheus/Loki stack. They only need telemetry agents such as **Node Exporter** and **Promtail**.

---

# 2. Server Roles

## Central APM Server

The central server hosts the main observability platform.

The central server is responsible for:

* Grafana
* Prometheus
* Loki
* Tempo
* Alertmanager
* OpenTelemetry Collector
* Nginx
* Exporter services
* Persistent Docker volumes
* Centralized dashboards
* Centralized logs
* Remote metrics scraping

---

## Remote Test Application Server

The remote server is used to simulate an application workload and provide telemetry to the central observability server.

The remote server runs:

* Node Exporter
* Promtail
* Test application / workload
* Docker containers
* Stress workload for generating CPU/memory activity

---

# 3. Central Server Setup - The APM

## Step 1 — Update the Server

Start by updating the operating system packages.

```bash
sudo apt update
```

---

# 4. Clone the Repository

Clone the observability platform repository:

```bash
git clone https://github.com/iamfahadshaikh/grafana-prometheus-apm-setup.git
```

Move into the project directory:

```bash
cd grafana-prometheus-apm-setup/
```

Verify the repository contents:

```bash
ls
```

---

# 5. Install Docker

Docker is required to run the observability services.

The setup process initially attempted several Docker installation commands:

```bash
sudo apt install docker
```
or 
```bash
sudo apt install docker.io
```

Verify Docker:

```bash
docker --version
```

If required, verify that Docker is running:

```bash
sudo systemctl status docker
```

---

# 6. Install Docker Compose

The deployment uses Docker Compose.

The setup attempted several package names before installing the Compose V2 package:

```bash
sudo apt install docker-compose
```

The Compose V2 package used during the setup was:

```bash
sudo apt install docker-compose-v2
```

Verify Compose:

```bash
docker compose version
```

---

# 7. Make the Deployment Script Executable

Give the deployment script execute permissions:

```bash
sudo chmod +x deploy.sh
```

Run the deployment:

```bash
./deploy.sh
```

If permissions require root privileges:

```bash
sudo bash deploy.sh
```

The deployment script is responsible for bringing up the central observability stack.

---

# 8. Verify Docker Containers

After deployment, check the running containers:

```bash
docker ps
```

If Docker requires elevated permissions:

```bash
sudo docker ps
```

All expected observability services should be running.

---

# 9. Determine the Server Public IP

The public IP was checked during the actual setup using:

```bash
curl -k ifconfig.me
```

This IP is important because remote servers need to communicate with the central Loki and Prometheus endpoints.

For example:

```text
CENTRAL_SERVER_IP=<CENTRAL_SERVER_PUBLIC_IP>
```

---

# 10. Central Prometheus Configuration

The Prometheus configuration is located inside:

```text
prometheus/
```

Move into the Prometheus directory:

```bash
cd prometheus/
```

Check the files:

```bash
ls
```

The main configuration file is:

```text
prometheus.yml
```

Open the configuration:

```bash
sudo nano prometheus.yml
```

---

# 11. Configure the Remote Test Application as a Prometheus Target

The remote test application server runs Node Exporter on:

```text
:9100
```

Prometheus on the central server needs to scrape that endpoint.

A target can be configured in `prometheus.yml` similar to:

```yaml
scrape_configs:
  - job_name: test-app-vm
    static_configs:
      - targets:
          - "<TEST_APP_SERVER_IP>:9100"
```

Replace:

```text
<TEST_APP_SERVER_IP>
```

with the public/private IP address that the central Prometheus server can reach.


---

# 12. Reload Prometheus

After modifying `prometheus.yml`, Prometheus can be reloaded without completely rebuilding the stack.

The setup used:

```bash
curl -X POST http://localhost:9090/-/reload
```

Then verify the configuration:

```bash
cat prometheus.yml
```

---

# 13. Verify Prometheus Targets

The Prometheus API can be used to verify that the remote server is being discovered and scraped.

The setup used:

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="test-app-vm") | {instance: .discoveredLabels.address, health: .health, lastError: .lastError}'
```

A healthy target should report:

```json
{
  "instance": "TEST_APP_SERVER_IP:9100",
  "health": "up",
  "lastError": ""
}
```

If the target is:

```text
down
```

check:

* Node Exporter is running on the remote server
* Port `9100` is reachable
* Azure/network security rules allow the connection
* The IP address is correct
* Prometheus configuration is correct

---

# 14. Remote Test Application Server Setup

Now configure the second server, The Application server.

---

# 15. Update the Remote Server

Run:

```bash
sudo apt update
```

---

# 16. Create the Test Application Script

The setup created a test application script:

```bash
sudo nano test-app.sh
```

Make it executable:

```bash
sudo chmod +x test-app.sh
```

Run it:

```bash
./test-app.sh
```

The exact contents of the application script can be customized according to the workload or application being monitored.

---

# 17. Install Telemetry Agents

Create the telemetry installation script:

```bash
sudo nano install-telemetry.sh
```

Make it executable:

```bash
sudo chmod +x install-telemetry.sh
```

Run the installer:

```bash
./install-telemetry.sh
```

The installer performs two major tasks:

1. Installs **Node Exporter**
2. Configures and launches **Promtail**

---

# 18. Configure the Central Loki Server

At the beginning of `install-telemetry.sh`, define the central Loki endpoint:

```bash
CENTRAL_LOKI_URL="http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push"
```

For example:

```bash
CENTRAL_LOKI_URL="http://4.240.15.105:3100/loki/api/v1/push"
```

For production deployments, replace the IP with the actual central server address and preferably protect the endpoint using TLS and appropriate network controls.

The script also determines the hostname automatically:

```bash
HOSTNAME=$(hostname)
```

This hostname is attached to the logs so that logs from multiple servers can be distinguished in Loki.

---

# 19. Install Node Exporter

The telemetry script installs Node Exporter version:

```text
1.7.0
```

The script downloads:

```bash
NODE_EXPORTER_VERSION="1.7.0"

wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

Extract it:

```bash
tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

Install the binary:

```bash
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```

Clean up the extracted files:

```bash
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
```

---

# 20. Create the Node Exporter System User

The script creates a dedicated system user:

```bash
sudo useradd -r -s /bin/false node_usr || true
```

This avoids running Node Exporter as the root user.

---

# 21. Create the Node Exporter Systemd Service

The installer creates:

```text
/etc/systemd/system/node_exporter.service
```

The service configuration is:

```ini
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
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable and start Node Exporter:

```bash
sudo systemctl enable --now node_exporter
```

Node Exporter listens on:

```text
9100
```

---

# 22. Verify Node Exporter

Check the service:

```bash
sudo systemctl status node_exporter
```

Test the metrics endpoint locally:

```bash
curl http://localhost:9100/metrics | head -n 5
```

You should receive Prometheus-formatted metrics.

You can also check listening ports:

```bash
sudo ss -lntp | grep 9100
```

---

# 23. Configure Promtail

Promtail is used to collect logs from the remote server and forward them to the central Loki instance.

The installer creates:

```text
/etc/promtail/
```

and generates:

```text
/etc/promtail/config.yml
```

The configuration uses:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/log/promtail-positions.yaml

clients:
  - url: http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push
```

---

# 24. Select Logs to Forward

The installation script interactively asks which log sources should be forwarded.

## System Logs

The first prompt is:

```text
Forward System Logs (/var/log/*.log)? [Y/n]:
```

If enabled, Promtail collects:

```text
/var/log/*.log
```

with labels similar to:

```yaml
job: syslog
host: "<HOSTNAME>"
```

---

## Nginx Logs

The installer asks:

```text
Forward Nginx Logs (/var/log/nginx/*.log)? [Y/n]:
```

If enabled, Promtail collects:

```text
/var/log/nginx/*.log
```

with:

```yaml
job: nginx
```

---

## Docker Container Logs

The installer asks:

```text
Forward Docker Container Logs (/var/lib/docker/containers/*/*.log)? [Y/n]:
```

If enabled, Promtail collects Docker container logs from:

```text
/var/lib/docker/containers/*/*.log
```

with:

```yaml
job: docker
```

---

# 25. Add Custom Application Logs

The installer also supports custom log paths.

It asks:

```text
Do you want to add a CUSTOM log path? [y/N]:
```

If enabled, provide a job name:

```text
Enter job name (e.g., app-backend):
```

Then provide the log path:

```text
Enter full log file path/glob (e.g., /home/user/app/logs/*.log):
```

For example:

```text
Job name:
app-backend

Log path:
/home/azureuser/app/logs/*.log
```

This makes it possible to forward application-specific logs to Loki.

---

# 26. Promtail Docker Deployment

The installer removes an existing Promtail container if one exists:

```bash
sudo docker rm -f promtail 2>/dev/null || true
```

Then it starts Promtail using Docker:

```bash
sudo docker run -d \
  --name=promtail \
  --restart=unless-stopped \
  -v /var/log:/var/log:ro \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  -v /etc/promtail/config.yml:/etc/promtail/config.yml:ro \
  grafana/promtail:2.9.6 \
  -config.file=/etc/promtail/config.yml
```

The container is configured to restart automatically:

```text
--restart=unless-stopped
```

---

# 27. Verify Promtail

Check the Promtail container:

```bash
docker ps | grep promtail
```

If required:

```bash
sudo docker ps | grep promtail
```

Check all running containers:

```bash
sudo docker ps
```

View Promtail logs:

```bash
sudo docker logs promtail
```

If Promtail is working correctly, it should be able to communicate with the central Loki endpoint.

---

# 28. Generate Test System Load

To verify that the monitoring system is actually receiving changing metrics, the remote server can generate CPU and memory activity.

Install `stress`:

```bash
sudo apt install stress
```

Run the continuous workload:

```bash
for ((;;)); do
    echo "=== [STRESS ACTIVE] Running 15s load ==="
    stress --cpu 2 --vm 1 --vm-bytes 1G --timeout 15s

    echo "=== [REST ACTIVE] Cooling down for 10s ==="
    sleep 10
done
```

This produces a repeating workload:

```text
15 seconds  -> CPU / memory stress
10 seconds  -> cooling down
15 seconds  -> CPU / memory stress
10 seconds  -> cooling down
...
```

This makes CPU and memory graphs in Grafana visibly change.

Stop the workload with:

```text
Ctrl+C
```

---

# 29. Central Server Verification

Return to the central APM server:

Check the running containers:

```bash
sudo docker ps
```

Verify that the observability stack is running.

---

# 30. Verify Prometheus

Prometheus is available internally on:

```text
http://localhost:9090
```

You can test the Prometheus API:

```bash
curl http://localhost:9090/api/v1/targets
```

For the remote test application:

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="test-app-vm") | {instance: .discoveredLabels.address, health: .health, lastError: .lastError}'
```

Expected state:

```text
health: up
```

---

# 31. Verify Loki

The remote Promtail instance sends logs to:

```text
http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push
```

Loki receives the logs and stores them centrally.

From Grafana, logs can then be explored through:

```text
Explore → Loki
```

Useful labels include:

```text
job
host
```

Example queries can include:

```logql
{job="syslog"}
```

```logql
{job="nginx"}
```

```logql
{job="docker"}
```

---

# 32. Verify Grafana

Open the Grafana web interface through the central Nginx endpoint:

```text
https://<CENTRAL_SERVER_IP>
```

Log in using the Grafana credentials configured by the deployment.

---

# 33. Verify Metrics in Grafana

Navigate to:

```text
Dashboards
```

Then open:

```text
Node Exporter Full
```

Dashboard ID:

```text
1860
```

The dashboard should display metrics from the central and remote servers, including:

* CPU utilization
* Memory utilization
* Disk usage
* Filesystem usage
* Network traffic
* System load
* Host availability

When the `stress` workload is running on the Test App server, CPU and memory graphs should visibly increase.

---

# 34. Verify Logs in Grafana

Navigate to:

```text
Explore
```

Select:

```text
Loki
```

You can query logs using LogQL.

For system logs:

```logql
{job="syslog"}
```

For Nginx logs:

```logql
{job="nginx"}
```

For Docker logs:

```logql
{job="docker"}
```

For a specific remote server:

```logql
{host="<HOSTNAME>"}
```

This allows logs from multiple remote servers to be centralized in one Grafana interface.

---

# 35. Verify Traces

If OpenTelemetry tracing is configured, navigate to:

```text
Explore
```

and select:

```text
Tempo
```

Tempo is used as the distributed tracing backend.

Applications can send telemetry through the OpenTelemetry Collector using:

```text
OTLP gRPC  -> 4317
OTLP HTTP  -> 4318
```

This enables tracing across:

* Python applications
* Node.js applications
* Go services
* APIs
* Microservices
* Application gateways

---


# 36. Network and Port Requirements

The following ports are used by the platform:

|   Port | Protocol | Purpose                      |
| -----: | :------: | ---------------------------- |
|   `80` |   HTTP   | HTTP → HTTPS redirect        |
|  `443` |   HTTPS  | Grafana / central web access |
| `3100` |   HTTP   | Loki log ingestion           |
| `4317` |   gRPC   | OpenTelemetry OTLP           |
| `4318` |   HTTP   | OpenTelemetry OTLP           |
| `9090` |   HTTP   | Prometheus                   |
| `9093` |   HTTP   | Alertmanager                 |
| `9100` |   HTTP   | Node Exporter                |

For remote servers, the central server must be reachable on the required telemetry ports.

The remote Test App server must expose:

```text
9100/tcp
```

to the central Prometheus server.

The central server must allow:

```text
3100/tcp
```

from remote Promtail agents.

For production environments, restrict these ports to trusted source IP addresses instead of exposing them publicly.

---

# 37. Persistent Storage

The central stack uses persistent Docker volumes for important observability data.

| Volume              | Purpose                                                |
| ------------------- | ------------------------------------------------------ |
| `grafana-data`      | Grafana configuration, dashboards, users, and database |
| `prometheus-data`   | Prometheus time-series data                            |
| `alertmanager-data` | Alert state and silences                               |
| `loki-data`         | Loki log storage                                       |
| `tempo-data`        | Tempo trace storage                                    |

Persistent volumes ensure that restarting or recreating containers does not automatically remove stored observability data.

---

# 38. Complete Setup Flow

The actual installation flow can be summarized as:

```text
CENTRAL APM SERVER
        |
        |-- apt update
        |
        |-- Clone Git repository
        |
        |-- Install Docker
        |
        |-- Install Docker Compose V2
        |
        |-- chmod +x deploy.sh
        |
        |-- ./deploy.sh
        |
        |-- docker ps
        |
        |-- Configure prometheus.yml
        |
        |-- Add test-app-vm target
        |
        |-- Reload Prometheus
        |
        |-- Verify Prometheus target
        |
        |
        v
REMOTE TEST-APP SERVER
        |
        |-- apt update
        |
        |-- Create test-app.sh
        |
        |-- Run test application
        |
        |-- Create install-telemetry.sh
        |
        |-- Install Node Exporter
        |
        |-- Create systemd service
        |
        |-- Start Node Exporter :9100
        |
        |-- Configure Promtail
        |
        |-- Select log sources
        |
        |-- Start Promtail container
        |
        |-- Verify docker ps
        |
        |-- Install stress
        |
        |-- Generate CPU/memory workload
        |
        v
CENTRAL GRAFANA
        |
        |-- Verify Metrics
        |
        |-- Verify Logs
        |
        |-- Verify Traces
        |
        v
      OBSERVABILITY
```

---

# 39. Troubleshooting

## Docker is not installed

Check:

```bash
docker --version
```

Install Docker:

```bash
sudo apt update
sudo apt install docker.io
```

---

## Docker Compose is not available

Check:

```bash
docker compose version
```

Install:

```bash
sudo apt install docker-compose-v2
```

---

## `deploy.sh` Permission Denied

Run:

```bash
sudo chmod +x deploy.sh
```

Then:

```bash
./deploy.sh
```

Or:

```bash
sudo bash deploy.sh
```

---

## Prometheus Target is Down

Check the remote server:

```bash
sudo systemctl status node_exporter
```

Test locally:

```bash
curl http://localhost:9100/metrics
```

Check port:

```bash
sudo ss -lntp | grep 9100
```

Then check the central Prometheus configuration:

```bash
cat prometheus.yml
```

Reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

Check the target:

```bash
curl -s http://localhost:9090/api/v1/targets
```

---

## Promtail is Not Running

Check:

```bash
sudo docker ps | grep promtail
```

If the container is missing:

```bash
sudo docker logs promtail
```

Check the configuration:

```bash
sudo cat /etc/promtail/config.yml
```

Verify that the Loki URL is correct.

---

## Logs Are Not Appearing in Loki

Check Promtail:

```bash
sudo docker logs promtail
```

Verify the central Loki endpoint:

```text
http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push
```

Check network connectivity from the remote server:

```bash
curl http://<CENTRAL_SERVER_IP>:3100/ready
```

Also verify that port `3100` is permitted by the server's firewall/security group.

---

## Grafana Shows No Metrics

First verify Prometheus:

```bash
curl http://localhost:9090/api/v1/targets
```

Then verify the remote Node Exporter:

```bash
curl http://<TEST_APP_SERVER_IP>:9100/metrics
```

If Prometheus reports the target as:

```text
up
```

the metrics should be available to Grafana.

---

# 40. Useful Commands

### Central server

Check containers:

```bash
sudo docker ps
```

Check Prometheus:

```bash
curl http://localhost:9090/api/v1/targets
```

Reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

Check public IP:

```bash
curl -k ifconfig.me
```

---

### Remote server

Check Node Exporter:

```bash
sudo systemctl status node_exporter
```

Check Node Exporter metrics:

```bash
curl http://localhost:9100/metrics | head -n 5
```

Check Promtail:

```bash
sudo docker ps | grep promtail
```

Check Promtail logs:

```bash
sudo docker logs promtail
```

Check all containers:

```bash
sudo docker ps
```

---

# 41. Final Verification Checklist

Before considering the deployment complete, verify the following.

## Central Server

* [ ] Repository cloned
* [ ] Docker installed
* [ ] Docker Compose V2 installed
* [ ] `deploy.sh` executable
* [ ] `deploy.sh` completed successfully
* [ ] Containers are running
* [ ] Prometheus is accessible
* [ ] Loki is running
* [ ] Grafana is accessible
* [ ] Nginx is serving HTTPS
* [ ] Prometheus configuration contains the remote target

## Remote Test Server

* [ ] Test application installed
* [ ] Node Exporter installed
* [ ] Node Exporter systemd service running
* [ ] Port `9100` accessible from the central server
* [ ] Promtail configuration generated
* [ ] Promtail container running
* [ ] Loki URL points to the central server
* [ ] System logs configured
* [ ] Nginx logs configured if required
* [ ] Docker logs configured if required
* [ ] Custom application logs configured if required

## Observability Validation

* [ ] Prometheus target shows `up`
* [ ] Node Exporter metrics visible in Grafana
* [ ] Node Exporter Full dashboard (`1860`) working
* [ ] Loki logs visible in Grafana Explore
* [ ] Remote host can be identified using the `host` label
* [ ] Test workload causes CPU/memory graphs to change
* [ ] Tempo is available for configured trace sources
* [ ] Alertmanager is available for configured alerts

---

# 42. Result

After completing the setup, the environment provides a centralized observability workflow:


The final result is a centralized platform where:

**Metrics → Prometheus → Grafana**

**Logs → Promtail → Loki → Grafana**

**Traces → OpenTelemetry → Tempo → Grafana**

This allows infrastructure, application, container, log, and tracing data to be viewed from a single observability platform.

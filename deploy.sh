#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT="Grafana Observability Stack"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

REQUIRED_DIRS=(
  prometheus
  alertmanager
  grafana
  loki
  promtail
  tempo
  otel
  logs
  nginx
  nginx/certs
  grafana/provisioning
  grafana/provisioning/datasources
  grafana/provisioning/dashboards
  grafana/dashboards
)

GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo
echo "==============================================="
echo "      GRAFANA OBSERVABILITY PLATFORM"
echo "==============================================="
echo

command -v docker >/dev/null 2>&1 || error "Docker not installed."
docker compose version >/dev/null 2>&1 || error "Docker Compose not installed."
success "Docker environment verified"

info "Creating core directories..."
for dir in "${REQUIRED_DIRS[@]}"; do
  mkdir -p "$ROOT_DIR/$dir"
done
success "Directories ready"

chmod -R 755 "$ROOT_DIR/logs" "$ROOT_DIR/grafana"
success "Directory permissions set"

# Check SSL certificates for Nginx
if [ ! -f "$ROOT_DIR/nginx/certs/fullchain.pem" ] || [ ! -f "$ROOT_DIR/nginx/certs/privkey.pem" ]; then
  warn "SSL certificates missing in ./nginx/certs/."
  warn "Generating self-signed certificate for temporary testing..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$ROOT_DIR/nginx/certs/privkey.pem" \
    -out "$ROOT_DIR/nginx/certs/fullchain.pem" \
    -subj "/CN=localhost" >/dev/null 2>&1
  success "Self-signed SSL certificate created"
fi

FILES=(
  docker-compose.yml
  prometheus/prometheus.yml
  prometheus/alert.rules.yml
  alertmanager/alertmanager.yml
  grafana/provisioning/datasources/datasource.yml
  grafana/provisioning/dashboards/dashboard.yml
  loki/config.yml
  promtail/config.yml
  tempo/tempo.yml
  otel/config.yml
  nginx/nginx.conf
  nginx/default.conf
)

info "Validating configuration files..."
MISSING=0
for f in "${FILES[@]}"; do
  if [ ! -f "$ROOT_DIR/$f" ]; then
    echo "Missing required file: $f"
    MISSING=1
  fi
done

if [ "$MISSING" -eq 1 ]; then
  error "Configuration validation failed. Missing files."
fi
success "Configuration files verified"

info "Testing Docker Compose syntax..."
docker compose -f "$COMPOSE_FILE" config >/dev/null || error "Docker Compose file failed syntax check."
success "Docker Compose syntax valid"

info "Pulling official container images..."
docker compose -f "$COMPOSE_FILE" pull
success "Container images pulled"

info "Starting observability stack..."
docker compose -f "$COMPOSE_FILE" up -d

echo
info "Checking container health status..."
sleep 10
docker compose -f "$COMPOSE_FILE" ps

echo
success "Deployment execution complete."
echo "Public Gateway (Nginx) : https://localhost (or your server domain)"
echo "Grafana Internal       : http://127.0.0.1:3000"
echo "Prometheus Internal    : http://127.0.0.1:9090"
echo "Alertmanager Internal  : http://127.0.0.1:9093"
echo "Loki Internal          : http://127.0.0.1:3100"
echo "Tempo Internal         : http://127.0.0.1:3200"
echo
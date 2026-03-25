#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export CHARTS_DIR="${CHARTS_DIR:-${SCRIPT_DIR}}"
export CLUSTER_NAME="${CLUSTER_NAME:-rancher-monitoring-dev}"
export RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-adminadmin}"
export RANCHER_REPLICAS="${RANCHER_REPLICAS:-1}"
export DASHBOARD_BRANCH="${DASHBOARD_BRANCH:-configurable-monitoring-urls}"

if [[ -z "${DASHBOARD_DIR:-}" ]]; then
  if sibling_dashboard_dir="$(realpath "${SCRIPT_DIR}/../dashboard" 2>/dev/null)"; then
    DASHBOARD_DIR="${sibling_dashboard_dir}"
  else
    DASHBOARD_DIR=""
  fi
fi
export DASHBOARD_DIR

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command '$1' was not found in PATH"
    exit 1
  fi
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    echo "ERROR: environment variable '$1' must be set"
    exit 1
  fi
}

require_command k3d
require_command helm
require_command kubectl

require_env RANCHER_HOST
require_env DASHBOARD_HOST

if [[ -z "${DASHBOARD_DIR}" || ! -d "${DASHBOARD_DIR}" ]]; then
  echo "ERROR: DASHBOARD_DIR must point to your local dashboard checkout"
  exit 1
fi

k3d cluster delete "${CLUSTER_NAME}" >/dev/null 2>&1 || true
k3d cluster create "${CLUSTER_NAME}" \
  --servers 1 \
  --agents 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"

helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace cert-manager >/dev/null 2>&1 || true
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deploy/cert-manager
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector

kubectl create namespace cattle-system >/dev/null 2>&1 || true
helm upgrade --install rancher rancher-latest/rancher \
  -n cattle-system \
  --set hostname="${RANCHER_HOST}" \
  --set bootstrapPassword="${RANCHER_BOOTSTRAP_PASSWORD}" \
  --set replicas="${RANCHER_REPLICAS}"

kubectl -n cattle-system rollout status deploy/rancher

cat <<EOF

Rancher should now be reachable at:
  https://${RANCHER_HOST}

Before continuing, start the Dashboard in another terminal.

Option A — dev server (same host, simple):
  cd "${DASHBOARD_DIR}"
  git checkout "${DASHBOARD_BRANCH}"
  yarn install
  API=https://${RANCHER_HOST} yarn dev

Option B — static build served by Python (different hosts/URLs, e.g. ngrok):
  cd "${DASHBOARD_DIR}"
  git checkout "${DASHBOARD_BRANCH}"
  yarn install
  API=https://${RANCHER_HOST} \\
    RESOURCE_BASE=https://${DASHBOARD_HOST}/ \\
    ROUTER_BASE=/dashboard/ \\
    yarn build
  # Then serve dist/ with the Python CORS server — see docs/monitoring-prototype/README.md

Then open https://${DASHBOARD_HOST} once in your browser and accept the certificate warning.
Press Enter here when the Dashboard is running and accessible.

EOF
read -r

kubectl patch settings.management.cattle.io ui-dashboard-index \
  --type merge \
  -p '{"value":"https://'"${DASHBOARD_HOST}"'/index.html"}'

kubectl patch settings.management.cattle.io ui-offline-preferred \
  --type merge \
  -p '{"value":"false"}'

kubectl create namespace monitoring >/dev/null 2>&1 || true
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-nginx-proxy-config
  namespace: monitoring
data:
  nginx.conf: |-
    worker_processes      auto;
    error_log             /dev/stdout warn;
    pid                   /var/cache/nginx/nginx.pid;

    events {
       worker_connections 1024;
    }

    http {
      include       /etc/nginx/mime.types;
      log_format    main '[$time_local - $status] $remote_addr - $remote_user $request ($http_referer)';

      proxy_connect_timeout       10;
      proxy_read_timeout          180;
      proxy_send_timeout          5;
      proxy_buffering             off;
      proxy_cache_path            /var/cache/nginx/cache levels=1:2 keys_zone=my_zone:100m inactive=1d max_size=10g;

      map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
      }

      server {
        listen          8080;
        listen     [::]:8080;
        access_log      off;

        gzip            on;
        gzip_min_length 1k;
        gzip_comp_level 2;
        gzip_types      text/plain application/javascript application/x-javascript text/css application/xml text/javascript image/jpeg image/gif image/png;
        gzip_vary       on;
        gzip_disable    "MSIE [1-6]\.";

        proxy_set_header Host $host;

        location /api/dashboards {
          proxy_pass     http://localhost:3000;
        }

        location /api/search {
          proxy_pass     http://localhost:3000;

          sub_filter_types application/json;
          sub_filter_once off;
        }

        location /api/live/ {
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $http_host;
          proxy_pass http://localhost:3000;
        }

        location / {
          proxy_cache         my_zone;
          proxy_cache_valid   200 302 1d;
          proxy_cache_valid   301 30d;
          proxy_cache_valid   any 5m;
          proxy_cache_bypass  $http_cache_control;
          add_header          X-Proxy-Cache $upstream_cache_status;
          add_header          Cache-Control "public";

          proxy_pass     http://localhost:3000/;

          sub_filter_once off;
          sub_filter '"appSubUrl":""' '"appSubUrl":"/api/v1/namespaces/monitoring/services/http:ext-monitoring-grafana:80/proxy"';
          sub_filter ':"/avatar/' ':"avatar/';

          rewrite ^/api/v1/namespaces/monitoring/services/http:ext-monitoring-grafana:80/proxy(.*)$ /$1 break;
          rewrite ^/k8s/clusters/.*/api/v1/namespaces/monitoring/services/http:ext-monitoring-grafana:80/proxy(.*)$ /$1 break;

          if ($request_filename ~ .*\.(?:js|css|jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm)$) {
            expires             90d;
          }
        }
      }
    }
EOF

cat > /tmp/ext-monitoring-values.yaml <<'EOF'
grafana:
  adminPassword: admin
  grafana.ini:
    auth:
      disable_login_form: true
    auth.anonymous:
      enabled: true
      org_role: Viewer
    security:
      allow_embedding: true
  service:
    portName: nginx-http
    targetPort: 8080
  extraContainers: |
    - name: grafana-proxy
      args:
      - nginx
      - -g
      - daemon off;
      - -c
      - /nginx/nginx.conf
      image: rancher/mirrored-library-nginx:1.29.1-alpine
      ports:
      - containerPort: 8080
        name: nginx-http
        protocol: TCP
      volumeMounts:
      - mountPath: /nginx
        name: grafana-nginx
      - mountPath: /var/cache/nginx
        name: nginx-home
      securityContext:
        runAsUser: 101
        runAsGroup: 101
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
          - ALL
  extraContainerVolumes:
  - name: nginx-home
    emptyDir: {}
  - name: grafana-nginx
    configMap:
      name: grafana-nginx-proxy-config
      items:
      - key: nginx.conf
        mode: 438
        path: nginx.conf
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
      label: grafana_dashboard
      labelValue: "1"
EOF

helm upgrade --install ext-monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f /tmp/ext-monitoring-values.yaml

cat > /tmp/rancher-monitoring-dashboard-only-values.yaml <<'EOF'
dashboardIntegration:
  grafanaURL: /api/v1/namespaces/monitoring/services/http:ext-monitoring-grafana:80/proxy/
  prometheusURL: ""

dashboardArtifacts:
  namespace: cattle-dashboards
  groups:
    rancherCore: true
    fleet: true
    performance: true
    ingressNginx: false
    logging:
      fluentd: false
      fluentbit: false
    backupRestore: false
EOF

helm upgrade --install rancher-monitoring \
  "${CHARTS_DIR}/charts/rancher-monitoring/80.9.1-rancher.5" \
  -n cattle-monitoring-system \
  --create-namespace \
  -f /tmp/rancher-monitoring-dashboard-only-values.yaml

cat <<EOF

kubectl get configmap -n cattle-monitoring-system rancher-monitoring-dashboard-values -o jsonpath='{.data.values\.json}'
kubectl get configmaps -n cattle-dashboards -l grafana_dashboard=1

# Optional PushProx for K3s control-plane metrics:
#   helm upgrade --install rancher-pushprox \
#     "${CHARTS_DIR}/charts/rancher-pushprox/0.1.9-rancher.1" \
#     -n cattle-monitoring-system \
#     --create-namespace \
#     --set targets.k3sServer.enabled=true
EOF

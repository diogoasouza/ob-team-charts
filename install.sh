#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export CHARTS_DIR="${CHARTS_DIR:-${SCRIPT_DIR}}"
export CLUSTER_NAME="${CLUSTER_NAME:-rancher-monitoring-dev}"
export RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-adminadmin}"
export RANCHER_REPLICAS="${RANCHER_REPLICAS:-1}"
export DASHBOARD_BRANCH="${DASHBOARD_BRANCH:-poc/minimal-monitoring-detection}"

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

kubectl create namespace cattle-monitoring-system >/dev/null 2>&1 || true

# NOTE: Ideally kube-prometheus-stack would be installed into its own namespace (e.g. "monitoring")
# with a stub ExternalName Service in cattle-monitoring-system pointing at it. However, the
# Kubernetes API server proxy does not support ExternalName services — it requires selector-managed
# endpoints. Until a clean cross-namespace solution is found, the workaround is to install the
# external stack directly into cattle-monitoring-system so the rancher-monitoring-grafana Service
# can use a pod selector and get real endpoints. This is tracked for follow-up investigation.

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
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
      label: grafana_dashboard
      labelValue: "1"
EOF

helm upgrade --install ext-monitoring prometheus-community/kube-prometheus-stack \
  -n cattle-monitoring-system \
  --create-namespace \
  -f /tmp/ext-monitoring-values.yaml

kubectl -n cattle-monitoring-system rollout status deploy/ext-monitoring-grafana

cat > /tmp/rancher-monitoring-dashboard-only-values.yaml <<'EOF'
dashboardIntegration:
  grafanaURL: /api/v1/namespaces/cattle-monitoring-system/services/http:rancher-monitoring-grafana:80/proxy/
  grafana:
    selector: {}  # Not used when grafanaProxy.enabled=true
    port: 8181    # Not used when grafanaProxy.enabled=true
  prometheus:
    selector: {}
    port: 9090
  alertmanager:
    selector: {}
    port: 9093

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

# Enable the nginx proxy deployment that handles Rancher's Kubernetes API proxy URL rewriting
grafanaProxy:
  enabled: true
  upstreamService: ext-monitoring-grafana
  upstreamPort: 80
  proxyPath: /api/v1/namespaces/cattle-monitoring-system/services/http:rancher-monitoring-grafana:80/proxy
EOF

helm upgrade --install rancher-monitoring \
  "${CHARTS_DIR}/charts/rancher-monitoring/80.9.1-rancher.6" \
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

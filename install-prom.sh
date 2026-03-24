#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PROMETHEUS_FEDERATOR_DIR="${PROMETHEUS_FEDERATOR_DIR:-$(realpath "${SCRIPT_DIR}/../prometheus-federator")}"
export PROMETHEUS_FEDERATOR_CHART_DIR="${PROMETHEUS_FEDERATOR_CHART_DIR:-${PROMETHEUS_FEDERATOR_DIR}/charts/prometheus-federator}"
export PROMETHEUS_FEDERATOR_DOCKERFILE="${PROMETHEUS_FEDERATOR_DOCKERFILE:-${PROMETHEUS_FEDERATOR_DIR}/package/Dockerfile-prometheus-federator}"

export RANCHER_CLUSTER_ID="${RANCHER_CLUSTER_ID:-local}"
export KUBECTL_WAIT_TIMEOUT="${KUBECTL_WAIT_TIMEOUT:-10m}"
CLUSTER_NAME="${CLUSTER_NAME:-}"

export PROMETHEUS_FEDERATOR_IMAGE_REPO="${PROMETHEUS_FEDERATOR_IMAGE_REPO:-local}"
export PROMETHEUS_FEDERATOR_IMAGE_TAG="${PROMETHEUS_FEDERATOR_IMAGE_TAG:-dev}"

if [[ -z "${PROJECT_MONITORING_VERSION:-}" ]] && [[ -f "${PROMETHEUS_FEDERATOR_DIR}/build.yaml" ]]; then
  PROJECT_MONITORING_VERSION="$(awk -F: '/^rancherProjectMonitoringVersion:/ {gsub(/ /, "", $2); print $2; exit}' "${PROMETHEUS_FEDERATOR_DIR}/build.yaml")"
fi
export PROJECT_MONITORING_VERSION="${PROJECT_MONITORING_VERSION:-0.6.6}"
export PROJECT_MONITORING_CHART_REPO_URL="${PROJECT_MONITORING_CHART_REPO_URL:-https://raw.githubusercontent.com/rancher/ob-team-charts/refs/heads/main}"

# The upstream Prometheus that project Prometheuses federate from.
# Matches the 'ext-monitoring' release installed by install.sh in the 'monitoring' namespace.
export FEDERATE_PROMETHEUS_URL="${FEDERATE_PROMETHEUS_URL:-ext-monitoring-kube-promet-prometheus.monitoring.svc:9090}"

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

wait_for_rollout() {
  local namespace="$1"
  local resource="$2"
  kubectl -n "${namespace}" rollout status "${resource}" --timeout="${KUBECTL_WAIT_TIMEOUT}"
}

wait_for_namespace() {
  local namespace="$1"
  local attempts="${2:-60}"

  for ((i = 1; i <= attempts; i++)); do
    if kubectl get namespace "${namespace}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "ERROR: namespace '${namespace}' was not created in time"
  exit 1
}

detect_cluster_name() {
  local current_context
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${current_context}" == k3d-* ]]; then
    echo "${current_context#k3d-}"
    return 0
  fi
  return 1
}

build_and_import_prometheus_federator_image() {
  local image="${PROMETHEUS_FEDERATOR_IMAGE_REPO}/prometheus-federator:${PROMETHEUS_FEDERATOR_IMAGE_TAG}"

  echo "Building local prometheus-federator image:"
  echo "  ${image}"
  docker build \
    -f "${PROMETHEUS_FEDERATOR_DOCKERFILE}" \
    --build-arg RANCHER_PROJECT_MONITORING="${PROJECT_MONITORING_VERSION}" \
    --build-arg TAG="${PROMETHEUS_FEDERATOR_IMAGE_TAG}" \
    --build-arg REPO="${PROMETHEUS_FEDERATOR_IMAGE_REPO}" \
    -t "${image}" \
    "${PROMETHEUS_FEDERATOR_DIR}"

  echo "Importing image into k3d cluster:"
  echo "  ${CLUSTER_NAME}"
  k3d image import "${image}" -c "${CLUSTER_NAME}"
}

require_command helm
require_command kubectl
require_command docker
require_command k3d

require_env RANCHER_HOST

if [[ ! -d "${PROMETHEUS_FEDERATOR_DIR}" ]]; then
  echo "ERROR: prometheus-federator repo not found at '${PROMETHEUS_FEDERATOR_DIR}'"
  exit 1
fi

if [[ ! -d "${PROMETHEUS_FEDERATOR_CHART_DIR}" ]]; then
  echo "ERROR: prometheus-federator chart directory not found at '${PROMETHEUS_FEDERATOR_CHART_DIR}'"
  exit 1
fi

if [[ ! -f "${PROMETHEUS_FEDERATOR_DOCKERFILE}" ]]; then
  echo "ERROR: prometheus-federator Dockerfile not found at '${PROMETHEUS_FEDERATOR_DOCKERFILE}'"
  exit 1
fi

if [[ -z "${CLUSTER_NAME}" ]]; then
  if detected_cluster_name="$(detect_cluster_name || true)" && [[ -n "${detected_cluster_name}" ]]; then
    CLUSTER_NAME="${detected_cluster_name}"
  else
    CLUSTER_NAME="rancher-monitoring-dev"
  fi
fi
export CLUSTER_NAME

if ! kubectl get namespace cattle-system >/dev/null 2>&1; then
  cat <<'EOF'
ERROR: Rancher does not appear to be installed yet.

Run ./install.sh first, wait for Rancher/dashboard-only monitoring to be up,
then rerun ./install-prom.sh.
EOF
  exit 1
fi

if ! kubectl get namespace cattle-monitoring-system >/dev/null 2>&1; then
  cat <<'EOF'
ERROR: cattle-monitoring-system is missing.

Run ./install.sh first so the dashboard-only monitoring prerequisites exist.
EOF
  exit 1
fi

cat <<EOF
Installing local prometheus-federator chart from:
  ${PROMETHEUS_FEDERATOR_CHART_DIR}

Using image:
  ${PROMETHEUS_FEDERATOR_IMAGE_REPO}/prometheus-federator:${PROMETHEUS_FEDERATOR_IMAGE_TAG}

Using k3d cluster:
  ${CLUSTER_NAME}

Using managed project chart source:
  ${PROJECT_MONITORING_CHART_REPO_URL}
  rancher-project-monitoring ${PROJECT_MONITORING_VERSION}

Federating from upstream Prometheus:
  ${FEDERATE_PROMETHEUS_URL}
EOF

build_and_import_prometheus_federator_image

helm upgrade --install prometheus-federator \
  "${PROMETHEUS_FEDERATOR_CHART_DIR}" \
  -n cattle-monitoring-system \
  --create-namespace \
  --set global.cattle.url="https://${RANCHER_HOST}" \
  --set global.cattle.clusterId="${RANCHER_CLUSTER_ID}" \
  --set helmProjectOperator.image.repository="${PROMETHEUS_FEDERATOR_IMAGE_REPO}/prometheus-federator" \
  --set helmProjectOperator.image.tag="${PROMETHEUS_FEDERATOR_IMAGE_TAG}" \
  --set helmProjectOperator.image.pullPolicy=IfNotPresent \
  --set helmProjectOperator.chartSource.name="rancher-project-monitoring" \
  --set helmProjectOperator.chartSource.repo="${PROJECT_MONITORING_CHART_REPO_URL}" \
  --set helmProjectOperator.chartSource.version="${PROJECT_MONITORING_VERSION}" \
  --set helmProjectOperator.valuesOverride.global.cattle.url="https://${RANCHER_HOST}" \
  --set helmProjectOperator.valuesOverride.global.cattle.clusterId="${RANCHER_CLUSTER_ID}" \
  --set "helmProjectOperator.valuesOverride.federate.targets[0]=${FEDERATE_PROMETHEUS_URL}"

wait_for_rollout cattle-monitoring-system deployment/prometheus-federator

kubectl apply -f - <<'EOF'
apiVersion: management.cattle.io/v3
kind: Project
metadata:
  name: p-example
  namespace: local
spec:
  clusterName: local
  displayName: PromFed Example
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    field.cattle.io/projectId: local:p-example
  labels:
    field.cattle.io/projectId: p-example
  name: e2e-prometheus-federator
EOF

wait_for_namespace cattle-project-p-example

kubectl apply -f - <<'EOF'
apiVersion: helm.cattle.io/v1alpha1
kind: ProjectHelmChart
metadata:
  name: project-monitoring
  namespace: cattle-project-p-example
spec:
  helmApiVersion: monitoring.cattle.io/v1alpha1
  values:
    alertmanager:
      alertmanagerSpec:
        image:
          repository: quay.io/prometheus/alertmanager
          tag: v0.28.1
        resources: null
    grafana:
      image:
        repository: grafana/grafana
        tag: 11.5.5
      proxy:
        image:
          repository: nginx
          tag: 1.27.2-alpine
      initChownData:
        image:
          repository: busybox
          tag: "1.31.1"
      downloadDashboardsImage:
        repository: curlimages/curl
        tag: 8.9.1
      sidecar:
        image:
          repository: quay.io/kiwigrid/k8s-sidecar
          tag: 1.30.0
      imageRenderer:
        image:
          repository: grafana/grafana-image-renderer
          tag: v4.0.5
      resources: null
    prometheus:
      prometheusSpec:
        image:
          repository: quay.io/prometheus/prometheus
          tag: v3.2.1
        proxy:
          image:
            repository: nginx
            tag: 1.27.2-alpine
        resources: null
EOF

kubectl wait \
  --for=condition=complete \
  --timeout="${KUBECTL_WAIT_TIMEOUT}" \
  -n cattle-monitoring-system \
  job/helm-install-cattle-project-p-example-monitoring

kubectl logs -n cattle-monitoring-system job/helm-install-cattle-project-p-example-monitoring

wait_for_rollout cattle-project-p-example statefulset/alertmanager-cattle-project-p-example-m-alertmanager
wait_for_rollout cattle-project-p-example statefulset/prometheus-cattle-project-p-example-m-prometheus
wait_for_rollout cattle-project-p-example deployment/cattle-project-p-example-monitoring-grafana

cat <<EOF

Project monitoring test environment is ready.

Useful checks:
  kubectl get projecthelmcharts -A
  kubectl get jobs -n cattle-monitoring-system
  kubectl get all -n cattle-project-p-example
  kubectl get configmaps -n cattle-project-p-example -l helm.cattle.io/dashboard-values-configmap
  kubectl get configmaps -n cattle-project-p-example -l grafana_dashboard=1

Direct endpoints:
  Grafana: https://${RANCHER_HOST}/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-monitoring-grafana:80/proxy
  Prometheus: https://${RANCHER_HOST}/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-m-prometheus:9090/proxy
  Alertmanager: https://${RANCHER_HOST}/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-m-alertmanager:9093/proxy

Note:
  prometheus-federator now requires an approved project chart reference.
  Override PROJECT_MONITORING_CHART_REPO_URL / PROJECT_MONITORING_VERSION if you want a different source.
EOF

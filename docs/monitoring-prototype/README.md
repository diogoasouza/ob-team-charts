# Monitoring prototype README

This prototype uses two repo-root scripts:

- `./install.sh` bootstraps a fresh k3d cluster, installs Rancher, starts the dashboard-only cluster-monitoring prototype, and points Rancher at a local Dashboard dev server.
- `./install-prom.sh` builds a local `prometheus-federator` image from `../prometheus-federator`, imports it into the active k3d cluster, installs the local `prometheus-federator` chart, and creates a sample project monitor.

## Current prototype status

- Cluster monitoring is tested in a dashboard-only mode.
- Project monitoring is **not** dashboard-only yet. The sample project monitor still deploys the current project monitoring runtime stack.

## Required local setup

- Local checkout of this repo
- Local checkout of `../dashboard`
- Local checkout of `../prometheus-federator`
- `k3d`, `kubectl`, `helm`, and `docker`

## Suggested `.envrc`

Add the personal values you do not want in git to your local `.envrc`:

```bash
export RANCHER_HOST="your-rancher-host.example.com"
export DASHBOARD_HOST="your-dashboard-host.example.com"

# Optional overrides
export DASHBOARD_DIR="/path/to/dashboard"
export CLUSTER_NAME="rancher-monitoring-dev"
export DASHBOARD_BRANCH="configurable-monitoring-urls"
export RANCHER_BOOTSTRAP_PASSWORD="adminadmin"
export RANCHER_REPLICAS="1"

export RANCHER_CLUSTER_ID="local"
export PROMETHEUS_FEDERATOR_DIR="/path/to/prometheus-federator"
export PROMETHEUS_FEDERATOR_IMAGE_REPO="local"
export PROMETHEUS_FEDERATOR_IMAGE_TAG="dev"
export PROJECT_MONITORING_CHART_REPO_URL="https://raw.githubusercontent.com/rancher/ob-team-charts/refs/heads/main"
export PROJECT_MONITORING_VERSION="0.6.6"

# The cluster Prometheus that project Prometheuses federate from.
# Defaults to the 'ext-monitoring' release installed by install.sh.
export FEDERATE_PROMETHEUS_URL="ext-monitoring-kube-promet-prometheus.monitoring.svc:9090"
```

Then run:

```bash
direnv allow
```

## Prototype flow

From `ob-team-charts`:

```bash
./install.sh
./install-prom.sh
```

`install.sh` will pause after Rancher comes up and ask you to start the local Dashboard dev server. It expects:

```bash
cd "$DASHBOARD_DIR"
git checkout "$DASHBOARD_BRANCH"
yarn install
API="https://$RANCHER_HOST" yarn dev
```

## What gets installed

After `./install.sh`:

- Rancher in `cattle-system`
- external monitoring stack in `monitoring`
- dashboard-only `rancher-monitoring` in `cattle-monitoring-system`

After `./install-prom.sh`:

- `prometheus-federator` in `cattle-monitoring-system`
- sample Rancher project `PromFed Example`
- sample namespace `e2e-prometheus-federator`
- generated project registration namespace `cattle-project-p-example`
- sample `ProjectHelmChart` named `project-monitoring`
- project monitoring stack in `cattle-project-p-example`
- sample `ProjectHelmChart` overrides long-running project monitoring images to upstream repositories instead of Rancher mirrors

## Where to look

Project monitoring objects:

```bash
kubectl get projecthelmcharts -A
kubectl get all -n cattle-project-p-example
kubectl get configmaps -n cattle-project-p-example -l helm.cattle.io/dashboard-values-configmap
kubectl get configmaps -n cattle-project-p-example -l grafana_dashboard=1
```

Direct endpoints:

- Grafana: `https://$RANCHER_HOST/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-monitoring-grafana:80/proxy`
- Prometheus: `https://$RANCHER_HOST/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-m-prometheus:9090/proxy`
- Alertmanager: `https://$RANCHER_HOST/api/v1/namespaces/cattle-project-p-example/services/http:cattle-project-p-example-m-alertmanager:9093/proxy`

## How to change the installed charts

Per-project chart values go through the `ProjectHelmChart`:

```bash
kubectl edit projecthelmchart -n cattle-project-p-example project-monitoring
```

The YAML under `spec.values` is passed to `rancher-project-monitoring`.

In this prototype, `install-prom.sh` pre-populates `spec.values` with upstream image repositories for Grafana, Prometheus, Alertmanager, and the running nginx/sidecar helpers.

Operator-wide defaults are controlled by the `prometheus-federator` install in `install-prom.sh`, especially:

- `helmProjectOperator.chartSource.*`
- `helmProjectOperator.valuesOverride.*`

If you want to point the prototype at a different approved project chart source, change:

- `PROJECT_MONITORING_CHART_REPO_URL`
- `PROJECT_MONITORING_VERSION`

If you want project Prometheuses to federate from a different upstream Prometheus (e.g. a different release name or namespace), change:

- `FEDERATE_PROMETHEUS_URL` — defaults to `ext-monitoring-kube-promet-prometheus.monitoring.svc:9090`, matching the `ext-monitoring` release deployed by `install.sh`

If you want to rebuild the federator image under a different name/tag, change:

- `PROMETHEUS_FEDERATOR_IMAGE_REPO`
- `PROMETHEUS_FEDERATOR_IMAGE_TAG`

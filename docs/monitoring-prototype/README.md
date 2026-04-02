# Monitoring prototype README

This prototype uses two repo-root scripts:

- `./install.sh` bootstraps a fresh k3d cluster, installs Rancher, starts the dashboard-only cluster-monitoring prototype, and points Rancher at a local Dashboard dev server.
- `./install-prom.sh` builds a local `prometheus-federator` image from `../prometheus-federator`, imports it into the active k3d cluster, installs the local `prometheus-federator` chart, and creates a sample project monitor.

## Current prototype status

"Dashboard-only" means the Rancher chart ships only dashboard artifacts and integration metadata; Grafana and Prometheus are installed separately from upstream rather than being shipped by Rancher.

- Cluster monitoring is tested in dashboard-only mode: `rancher-monitoring` ships only dashboard artifacts; an upstream kube-prometheus-stack (`ext-monitoring`) provides the Grafana and Prometheus runtime.
- Project monitoring has been preliminarily tested via `install-prom.sh`. The project monitor runs Grafana and Prometheus from upstream public registries rather than Rancher-shipped images, which aligns with the dashboard-only direction.

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
export DASHBOARD_BRANCH="poc/minimal-monitoring-detection"
export RANCHER_BOOTSTRAP_PASSWORD="adminadmin"
export RANCHER_REPLICAS="1"

# Dashboard build vars (used when building for a static Python server on a different host)
# RESOURCE_BASE is the full URL where the built dashboard assets are served from.
# ROUTER_BASE is the path prefix the Vue router uses (e.g. /dashboard/).
export RESOURCE_BASE="https://${DASHBOARD_HOST}/"
export ROUTER_BASE="/dashboard/"

export RANCHER_CLUSTER_ID="local"
export PROMETHEUS_FEDERATOR_DIR="/path/to/prometheus-federator"
export PROMETHEUS_FEDERATOR_IMAGE_REPO="local"
export PROMETHEUS_FEDERATOR_IMAGE_TAG="dev"
export PROJECT_MONITORING_CHART_REPO_URL="https://raw.githubusercontent.com/rancher/ob-team-charts/refs/heads/main"
export PROJECT_MONITORING_VERSION="0.6.6"

# The cluster Prometheus that project Prometheuses federate from.
# Defaults to the 'ext-monitoring' release installed by install.sh.
export FEDERATE_PROMETHEUS_URL="ext-monitoring-kube-promet-prometheus.cattle-monitoring-system.svc:9090"
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

`install.sh` will pause after Rancher comes up and ask you to start the Dashboard.

**Option A – dev server (same host, simple):**

```bash
cd "$DASHBOARD_DIR"
git checkout "$DASHBOARD_BRANCH"
yarn install
API="https://$RANCHER_HOST" yarn dev
```

**Option B – static build served by Python (different hosts/URLs):**

Use this when the dashboard is accessed via a different URL than where `yarn dev` listens, e.g. via an ngrok tunnel or a reverse proxy. The extra env vars tell the build where assets are hosted and what router base path to use.

```bash
cd "$DASHBOARD_DIR"
git checkout "$DASHBOARD_BRANCH"
yarn install
API="https://$RANCHER_HOST" \
  RESOURCE_BASE="https://$DASHBOARD_HOST/" \
  ROUTER_BASE="/dashboard/" \
  yarn build

# Serve dist/ with CORS headers (needed for cross-origin dashboard assets)
python3 - <<'PYEOF'
import functools, http.server, os, socketserver

PORT = int(os.environ.get("PORT", "8006"))
DIRECTORY = os.environ.get("DIRECTORY", "dist")

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        super().end_headers()
    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

handler = functools.partial(CORSRequestHandler, directory=DIRECTORY)
with socketserver.TCPServer(("0.0.0.0", PORT), handler) as httpd:
    print(f"Serving {DIRECTORY} on http://0.0.0.0:{PORT}")
    httpd.serve_forever()
PYEOF
```

> **Note:** `RESOURCE_BASE` and `ROUTER_BASE` must match whatever URL and path Rancher resolves when it loads `ui-dashboard-index`.  The values in your `.envrc` are passed through automatically if you run `install.sh` under `direnv`.

## What gets installed

After `./install.sh`:

- Rancher in `cattle-system`
- external monitoring stack (`ext-monitoring`) in `cattle-monitoring-system`
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

- `FEDERATE_PROMETHEUS_URL` — defaults to `ext-monitoring-kube-promet-prometheus.cattle-monitoring-system.svc:9090`, matching the `ext-monitoring` release deployed by `install.sh`

If you want to rebuild the federator image under a different name/tag, change:

- `PROMETHEUS_FEDERATOR_IMAGE_REPO`
- `PROMETHEUS_FEDERATOR_IMAGE_TAG`

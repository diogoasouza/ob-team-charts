# rancher-monitoring dashboard artifact prototype

This chart keeps the `rancher-monitoring` release identity, but renders only dashboard delivery artifacts and integration metadata.

## What this prototype does

- Ships the Rancher dashboard JSON artifacts under `files/rancher/**`
- Ships the ingress-nginx addon dashboards under `files/ingress-nginx/**`
- Renders dashboard ConfigMaps into a dashboard namespace independent of `grafana.enabled`
- Publishes a `*-dashboard-values` ConfigMap with external integration metadata for Rancher consumers
- Leaves Grafana, Prometheus, Alertmanager, exporters, PushProx, datasources, and operator-managed runtime resources out of the rendered chart

## What this prototype does not do

- It does not deploy Grafana, Prometheus, Alertmanager, exporters, or PushProx
- It does not wire datasources into an external Grafana instance for you
- It does not update Rancher Dashboard UI logic that still assumes an in-cluster Grafana service proxy for cluster monitoring

## Values

### Dashboard artifact delivery

```yaml
dashboardArtifacts:
  enabled: true
  namespace: cattle-dashboards
  useExistingNamespace: false
  cleanupOnUninstall: false
  label: grafana_dashboard
  labelValue: "1"
  annotations: {}
  groups:
    rancherCore: true
    fleet: true
    ingressNginx: true
    performance: true
    logging:
      fluentd: true
      fluentbit: true
    backupRestore: true
```

### External integration metadata

```yaml
dashboardIntegration:
  grafanaURL: https://grafana.example.com
  prometheusURL: https://prometheus.example.com
```

The chart writes these values into the release-scoped `rancher-monitoring` dashboard-values ConfigMap as `values.json`, alongside dashboard UID/title inventory, chart metadata, and dashboard namespace/label information.

## Rendered resources

By default this prototype renders:

- one namespace for dashboard ConfigMaps, unless `dashboardArtifacts.useExistingNamespace=true`
- one metadata ConfigMap in the release namespace
- three RBAC Roles for metadata ConfigMaps in the release namespace
- three RBAC Roles for dashboard artifact ConfigMaps in the dashboard namespace
- twelve dashboard ConfigMaps covering the current Rancher and addon dashboard artifact set

The current artifact inventory contains 26 dashboard JSON files:

- Rancher core: home, cluster, nodes, kubernetes, workloads, pods
- Fleet dashboards
- Performance debugging dashboard
- Logging dashboards for Fluent Bit and Fluentd
- Backup and restore dashboard
- ingress-nginx dashboards

## Operational notes

- `dashboardIntegration.grafanaURL` should point at the external Grafana base URL Rancher will eventually use for cluster dashboards.
- `dashboardIntegration.prometheusURL` is optional and is included for future consumers that need a Prometheus endpoint hint.
- Backup/restore and logging dashboards are delivered as artifacts only. They require external datasource wiring and metric collection to become functional.
- PushProx replacement and equivalent external collection paths are intentionally deferred in this prototype.

## Rancher Dashboard follow-up

This chart-side contract is prepared for Rancher Dashboard changes, but cluster-level Rancher UI currently still hardcodes in-cluster Grafana proxy URLs and endpoint checks. A follow-up Rancher Dashboard change is still required to consume `status.dashboardValues.grafanaURL`-style metadata for cluster monitoring, similar to project monitoring.

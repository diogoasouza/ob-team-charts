# rancher-project-monitoring

This proof-of-concept chart keeps the `rancher-project-monitoring` release identity, but now ships only the minimal Rancher-owned compatibility payload for project monitoring.

By default it publishes dashboard ConfigMaps, dashboard inventory metadata, and project-scoped RBAC aggregation roles without embedding or linking Rancher-managed Grafana, Prometheus, or Alertmanager runtimes.

## What this PoC does

- Publishes project dashboard metadata through the existing `dashboard-values` ConfigMap contract
- Preserves project-scoped dashboard inventory and RBAC aggregation roles Rancher expects
- Ships dashboard ConfigMaps without embedding the Grafana subchart
- Leaves Grafana, Prometheus, and Alertmanager runtime ownership external to this chart

## What this PoC does not do

- It does not make `prometheus-federator` consume an external chart source by itself
- It does not provision or validate an external Grafana, Prometheus, or Alertmanager for you
- It does not keep any Rancher-owned Grafana or Prometheus runtime images in the chart payload

## External integration metadata

Set these values to publish externally managed endpoints for Rancher consumers:

```yaml
dashboardIntegration:
  grafanaURL: https://grafana.example.com
  prometheusURL: https://prometheus.example.com
  alertmanagerURL: https://alertmanager.example.com
```

These values are written into the release-scoped `*-dashboard-values` ConfigMap as `values.json`, alongside the Rancher dashboard UID/title inventory.

## Dependencies

This chart is still intended to be deployed via [Prometheus Federator](https://github.com/rancher/prometheus-federator). In this repository, the chart-side PoC is ready first; the operator still needs complementary work to stop assuming the legacy embedded runtime path by default.

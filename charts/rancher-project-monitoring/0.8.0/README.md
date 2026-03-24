# rancher-project-monitoring

This proof-of-concept chart keeps the `rancher-project-monitoring` release identity, but switches the Rancher-owned path to an external-URL-first model. By default it publishes Rancher dashboard artifacts, project RBAC metadata, and a `*-dashboard-values` ConfigMap for Rancher consumers without deploying Grafana, Prometheus, or Alertmanager runtimes.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+

## Install Chart

This chart is not intended for standalone use; it's intended to be deployed via [Prometheus Federator](https://github.com/rancher/prometheus-federator). For a Prometheus Stack intended to be deployed standalone, please use [rancher-monitoring](https://rancher.com/docs/rancher/v2.6/en/monitoring-alerting/) or the upstream [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) project.

## Dependencies

This chart is designed to be deployed alongside an existing Prometheus Operator deployment in a cluster that has already installed the Prometheus Operator CRDs. Specifically, it is intended to be deployed alongside [`rancher-monitoring`](https://rancher.com/docs/rancher/v2.6/en/monitoring-alerting/), which provides the cluster-scoped Prometheus Operator and, when you re-enable the project Prometheus runtime, can also provide the default federation target.

### Configuration

Since this chart installs a project-scoped version of [`rancher-monitoring`](https://rancher.com/docs/rancher/v2.6/en/monitoring-alerting/), a Helm chart based off of [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), most of the options that apply to either of those charts will apply to this chart (e.g. support for configuring persistent volumes, ingresses, etc.) and can be passed in as part of the `spec.values` of the ProjectHelmChart that deploys this chart; however, certain advanced functionality (such as Thanos support) and options that pose security risks in Project environments (e.g. ability to `ignoreNamespaceSelectors` or modify the existing namepaceSelectors of the Cluster Prometheus, ability to mount additional scrape configs, etc.) have been removed from the `values.yaml` of the chart. For more information on how to configure values and what they mean, please see the comments and options provided on the `values.yaml` packaged with this chart.

## Further Information

For more in-depth documentation of configuration options meanings, please see

- [`rancher-monitoring`](https://rancher.com/docs/rancher/v2.6/en/monitoring-alerting/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [Prometheus](https://prometheus.io/docs/introduction/overview/)
- [Grafana](https://github.com/grafana/helm-charts/tree/main/charts/grafana#grafana-helm-chart)

## What this PoC does

- Publishes project dashboard metadata through the existing `dashboard-values` ConfigMap contract
- Preserves project-scoped dashboard inventory and RBAC aggregation roles Rancher expects
- Renders dashboard ConfigMaps even when the Grafana subchart is disabled
- Leaves project Grafana, Prometheus, and Alertmanager disabled by default

## What this PoC does not do

- It does not make `prometheus-federator` consume an external chart source by itself
- It does not provision or validate an external Grafana, Prometheus, or Alertmanager for you
- It does not remove the need for Rancher Dashboard / Manager follow-up where UI assumptions still exist

## External integration metadata

Set these values to publish externally managed endpoints for Rancher consumers:

```yaml
dashboardIntegration:
  grafanaURL: https://grafana.example.com
  prometheusURL: https://prometheus.example.com
  alertmanagerURL: https://alertmanager.example.com
```

If a runtime component is re-enabled and the corresponding `dashboardIntegration` value is left empty, the chart falls back to the legacy in-cluster URL behavior for that component.

## Dependencies

This chart is still intended to be deployed via [Prometheus Federator](https://github.com/rancher/prometheus-federator). In this repository, the chart-side PoC is ready first; the operator still needs complementary work to stop assuming the legacy embedded runtime path by default.

# rancher-monitoring-dashboards

Dashboard artifact delivery for Rancher Monitoring with BYO Grafana and Prometheus integration. It is designed to be deployed alongside an existing Prometheus stack, which aims to provide Rancher's curated dashboards without installing the full `rancher-monitoring` suite.

## Overview

The `rancher-monitoring-dashboards` chart installs a dashboard-only version of `rancher-monitoring`. This means preserving all the monitoring dashboards' functionality without depending on Rancher-shipped `kube-prometheus-stack` runtime images or components. Instead, this chart presupposes that a Prometheus stack infrastructure is already in place for it to work.

## Prerequisites

- Kubernetes 1.19+
- Helm 3+
- Prometheus Stack

## Key difference from `rancher-monitoring`

`rancher-monitoring-dashboards` does not ship Grafana, Prometheus, and other runtime components. It will install only dashboard artifacts and integration metadata. Here are the major differences between `rancher-monitoring` and `rancher-monitoring-dashboards`:

|                                       |              `rancher-monitoring`               |                          `rancher-monitoring-dashboards`                          |
|---------------------------------------|-------------------------------------------------|-----------------------------------------------------------------------------------|
| **What it installs**                  | Full observability stack                        | Dashboards only                                                                   |
| **Grafana**                           | Bundled in chart                                | External / BYO                                                                    |
| **Prometheus**                        | Bundled in chart                                | External / BYO                                                                    |
| **Alertmanager**                      | Bundled in chart                                | External / BYO                                                                    |
| **Node/kube-state-metrics exporters** | Bundled in chart                                | External / BYO                                                                    |
| **Use case**                          | Greenfield clusters with no existing monitoring | Clusters already running a monitoring stack that want Rancher-specific dashboards |

## Usage

Install `rancher-monitoring` when you need Rancher to manage the full monitoring stack. Install `rancher-monitoring-dashboards` when you already have the Prometheus stack running and just want Rancher's dashboards.

## Dependencies

`rancher-monitoring-dashboards` relies on an existing Prometheus stack that is already deployed and running on the cluster. The easiest way to do this is to pre-install the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart.

## Install Chart

Follow the [integration guide](/INTEGRATION-GUIDE.md) to install the chart.

## Uninstall Chart

The chart can be uninstalled in the Rancher UI or through `helm`:

```console
helm uninstall [RELEASE_NAME]
```

This removes all the Kubernetes components associated with the chart and deletes the release.

_See [helm uninstall](https://helm.sh/docs/helm/helm_uninstall/) for command documentation._


### Configuration

The following table lists the configurable parameters of the `rancher-monitoring-dashboards` chart and their default values:

|                   Parameter                   |                                              Default                                              |
|-----------------------------------------------|---------------------------------------------------------------------------------------------------|
| commonLabels                                  | `{}`                                                                                              |
| extraManifests                                | `{}`                                                                                              |
| global.disableProxyIPv6                       | `false`                                                                                           |
| global.cattle.systemDefaultRegistry           | `""`                                                                                              |
| global.cattle.clusterId                       | `""`                                                                                              |
| global.cattle.clusterName                     | `""`                                                                                              |
| global.kubectl.repository                     | `"rancher/kuberlr-kubectl"`                                                                       |
| global.kubectl.tag                            | `"v71"`                                                                                           |
| global.kubectl.pullPolicy                     | `"IfNotPresent"`                                                                                  |
| global.rbac.create                            | `true`                                                                                            |
| global.rbac.userRoles.create                  | `true`                                                                                            |
| global.rbac.userRoles.aggregateToDefaultRoles | `true`                                                                                            |
| dashboardArtifacts.enabled                    | `true`                                                                                            |
| dashboardArtifacts.namespace                  | `"cattle-dashboards"`                                                                             |
| dashboardArtifacts.useExistingNamespace       | `false`                                                                                           |
| dashboardArtifacts.cleanupOnUninstall         | `false`                                                                                           |
| dashboardArtifacts.label                      | `"grafana_dashboard"`                                                                             |
| dashboardArtifacts.labelValue                 | `"1"`                                                                                             |
| dashboardArtifacts.annotations                | `{}`                                                                                              |
| dashboardArtifacts.groups.rancherCore         | `true`                                                                                            |
| dashboardArtifacts.groups.fleet               | `true`                                                                                            |
| dashboardArtifacts.groups.ingressNginx        | `true`                                                                                            |
| dashboardArtifacts.groups.performance         | `true`                                                                                            |
| dashboardArtifacts.groups.logging.fluentd     | `true`                                                                                            |
| dashboardArtifacts.groups.logging.fluentbit   | `true`                                                                                            |
| dashboardArtifacts.groups.backupRestore       | `true`                                                                                            |
| dashboardIntegration.grafanaURL               | `""`                                                                                              |
| dashboardIntegration.prometheusURL            | `""`                                                                                              |
| grafanaProxy.enabled                          | `true`                                                                                            |
| grafanaProxy.upstreamService                  | `"kube-prometheus-stack-grafana"`                                                                 |
| grafanaProxy.upstreamPort                     | `80`                                                                                              |
| grafanaProxy.proxyPath                        | `"/api/v1/namespaces/cattle-monitoring-system/services/http:rancher-monitoring-grafana:80/proxy"` |
| prometheusProxy.enabled                       | `true`                                                                                            |
| prometheusProxy.upstreamService               | `"kube-prometheus-stack-prometheus"`                                                              |
| prometheusProxy.upstreamPort                  | `9090`                                                                                            |
| alertmanagerProxy.enabled                     | `true`                                                                                            |
| alertmanagerProxy.upstreamService             | `"kube-prometheus-stack-alertmanager"`                                                            |
| alertmanagerProxy.upstreamPort                | `9093`                                                                                            |
| monitoringProxy.replicas                      | `1`                                                                                               |
| monitoringProxy.image.repository              | `"library/nginx"`                                                                                 |
| monitoringProxy.image.tag                     | `"1.31.2-alpine"`                                                                                 |
| monitoringProxy.image.pullPolicy              | `"IfNotPresent"`                                                                                  |
| monitoringProxy.resources.limits.cpu          | `"200m"`                                                                                          |
| monitoringProxy.resources.limits.memory       | `"256Mi"`                                                                                         |
| monitoringProxy.resources.requests.cpu        | `"50m"`                                                                                           |
| monitoringProxy.resources.requests.memory     | `"64Mi"`                                                                                          |
| monitoringProxy.nodeSelector                  | `{}`                                                                                              |
| monitoringProxy.tolerations                   | `{}`                                                                                              |
| monitoringProxy.affinity                      | `{}`                                                                                              |
| kubeTargetVersionOverride                     | `""`                                                                                              |
| rancherMonitoring.enabled                     | `true`                                                                                            |
| rancherMonitoring.selector                    | `{}`                                                                                              |
| rancherMonitoring.prometheusServiceAccount    | `"kube-prometheus-stack-prometheus"`                                                              |
| hardenedNodeExporter.enabled                  | `false`                                                                                           |
| kubeStateMetrics.enabled                      | `false`                                                                                           |
| nodeExporter.enabled                          | `false`                                                                                           |
| hardened.enabled                              | `false`                                                                                           |
| hardened.k3s.networkPolicy.enabled            | `false`                                                                                           |
| defaultRules.create                           | `false`                                                                                           |
| etcd.enabled                                  | `false`                                                                                           |
| k3sServer.enabled                             | `true`                                                                                            |
| grafana.enabled                               | `false`                                                                                           |
| grafana.forceDeployDashboards                 | `false`                                                                                           |
| grafana.defaultDashboardsEnabled              | `true`                                                                                            |
| grafana.defaultDashboards.namespace           | `"cattle-dashboards"`                                                                             |
| grafana.sidecar.dashboards.label              | `"grafana_dashboard"`                                                                             |
| grafana.sidecar.dashboards.labelValue         | `"1"`                                                                                             |
| grafana.sidecar.dashboards.annotations        | `{}`                                                                                              |

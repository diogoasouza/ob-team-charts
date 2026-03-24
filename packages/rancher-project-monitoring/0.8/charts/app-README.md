# Rancher Project Monitoring and Alerting

This proof-of-concept keeps the `rancher-project-monitoring` release identity, but limits the Rancher-owned payload to dashboard artifacts, dashboard-values metadata, and project-scoped RBAC roles.

The chart no longer embeds the Grafana subchart or carries Rancher-managed Grafana, Prometheus, or Alertmanager runtime images.

Note: This chart is not intended for standalone use; it's intended to be deployed via [Prometheus Federator](https://github.com/rancher/prometheus-federator). Complementary operator work is still needed before this becomes the default end-to-end deployment path.

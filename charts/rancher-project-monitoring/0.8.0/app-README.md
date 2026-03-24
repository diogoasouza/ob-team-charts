# Rancher Project Monitoring and Alerting

This proof-of-concept keeps the `rancher-project-monitoring` release identity, but disables the Rancher-owned Grafana, Prometheus, and Alertmanager runtimes by default.

The chart now focuses on:
- Dashboard ConfigMaps and dashboard inventory metadata for Rancher consumers
- Project-scoped RBAC aggregation roles and dashboard-values metadata
- Optional re-enablement of project Prometheus, Alertmanager, and Grafana runtimes when explicitly requested

Note: This chart is not intended for standalone use; it's intended to be deployed via [Prometheus Federator](https://github.com/rancher/prometheus-federator). Complementary operator work is still needed before this becomes the default end-to-end deployment path.

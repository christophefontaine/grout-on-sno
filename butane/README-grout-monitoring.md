# Grout Telemetry Monitoring Deployment

## Overview
This configuration enables Prometheus to scrape metrics from the grout telemetry service running on the host at port 9876.

## Files
- `40-grout-monitoring-namespace.yaml` - Creates the grout-monitoring namespace with cluster-monitoring label
- `50-cluster-monitoring-config.yaml` - Enables user workload monitoring in the cluster
- `50-grout-telemetry-monitoring.yaml` - Main monitoring configuration including:
  - ServiceAccount for the telemetry exporter
  - RoleBinding to grant Prometheus access to the namespace
  - DaemonSet running socat to proxy host:9876 → pod:9877
  - Service to expose the DaemonSet pods
  - ServiceMonitor to configure Prometheus scraping

## Deployment Steps

1. Apply the namespace configuration:
```bash
oc apply -f openshift/40-grout-monitoring-namespace.yaml
```

2. Apply the cluster monitoring configuration:
```bash
oc apply -f openshift/50-cluster-monitoring-config.yaml
```

3. Apply the grout telemetry monitoring configuration:
```bash
oc apply -f openshift/50-grout-telemetry-monitoring.yaml
```

4. **IMPORTANT** - Grant hostnetwork SCC to the telemetry exporter ServiceAccount:
```bash
oc adm policy add-scc-to-user hostnetwork -z grout-telemetry-exporter -n grout-monitoring
```

This step is required because the DaemonSet uses `hostNetwork: true` to access the grout telemetry service running on localhost:9876 of the host.

## Verification

Check that metrics are being scraped:
```bash
# Check the DaemonSet is running
oc get daemonset -n grout-monitoring

# Check the pods are running
oc get pods -n grout-monitoring

# Query metrics from Prometheus
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=dpdk_counters_rx_packets'
```

## Available Metrics

The grout telemetry service exposes the following metrics:
- `dpdk_counters_rx_packets` - Number of received packets per port
- `dpdk_counters_rx_bytes` - Number of received bytes per port
- `dpdk_counters_rx_missed` - Number of dropped packets
- `dpdk_counters_rx_nombuf` - Rx mbuf allocation failures
- `dpdk_counters_rx_errors` - Number of erroneous received packets
- `dpdk_counters_tx_packets` - Number of transmitted packets per port
- `dpdk_counters_tx_bytes` - Number of transmitted bytes per port
- `dpdk_counters_tx_errors` - Packet transmission failures
- `dpdk_cpu_total_cycles` - Total CPU cycles per core
- `dpdk_cpu_busy_cycles` - Busy CPU cycles per core
- `dpdk_memory_total_bytes` - Total reserved memory
- `dpdk_memory_used_bytes` - Currently used memory

## Architecture

```
Host (node)
  └─ grout-telemetry service: localhost:9876

DaemonSet Pod (hostNetwork=true)
  └─ socat: proxies localhost:9876 → 0.0.0.0:9877

Service (ClusterIP: None)
  └─ Exposes pod IP:9877

Prometheus
  └─ Scrapes via ServiceMonitor every 30s
```

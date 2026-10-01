#!/bin/bash
set -e

# Generate custom enterprise metadata metric for Prometheus/Grafana textfile collector
mkdir -p /var/lib/node_exporter/textfile_collector
cat <<EOF > /var/lib/node_exporter/textfile_collector/node_meta.prom
# HELP cluster_node_info Metadata about the simulated cluster VM node
# TYPE cluster_node_info gauge
cluster_node_info{cluster="${CLUSTER_ID:-cluster-unknown}",node_name="${NODE_NAME:-node-unknown}",datacenter="${DATACENTER:-dc-unknown}",role="${NODE_ROLE:-worker}"} 1
EOF

echo "[$(date -u +%FT%TZ)] Starting simulated enterprise node ${NODE_NAME:-unknown} in ${CLUSTER_ID:-unknown}..."
echo "[$(date -u +%FT%TZ)] Local network configuration:"
ip -o addr show | awk '{print "  " $2, $3, $4}'

exec /bin/node_exporter \
  --collector.textfile.directory=/var/lib/node_exporter/textfile_collector \
  --web.listen-address=":9100" \
  "$@"

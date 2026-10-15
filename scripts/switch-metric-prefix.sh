#!/usr/bin/env bash
# Switch the metric prefix used by the alert rules (valkey_ <-> redis_).
# The Grafana dashboard does not need this: it has a "Metric prefix" variable.
#   switch-metric-prefix.sh redis
#   switch-metric-prefix.sh valkey
set -euo pipefail
to="${1:?usage: switch-metric-prefix.sh valkey|redis}"
case "$to" in valkey) from=redis ;; redis) from=valkey ;; *) echo "use valkey or redis"; exit 1 ;; esac
f="${WORKSHOP_HOME:?source env.sh first}/manifests/07-monitoring/03-prometheusrule.yaml"
sed -i.bak -E "s/(^|[^a-zA-Z_])${from}_/\1${to}_/g" "$f" && rm -f "$f.bak"
echo "Alert rules now use the '${to}_' prefix. Re-apply them:"
echo "  render $f | kubectl apply -f -"

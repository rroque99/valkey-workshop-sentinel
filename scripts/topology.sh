#!/usr/bin/env bash
# Where is the writer? Where are the replicas? Which nodes / zones do they run on?
#   topology.sh            (uses $VALKEY_NS, $REPL_NAME, $SENTINEL_NAME from env.sh)
set -uo pipefail
: "${WORKSHOP_HOME:?Run 'source ./env.sh' first}"
. "${WORKSHOP_HOME}/scripts/lib.sh"

ns="${VALKEY_NS}"
zone_of() { kubectl get node "$1" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null; }

echo "=== Sentinel view (master group: ${MASTER_GROUP}) ==="
addr="$(primary_addr 2>/dev/null)"
echo "Primary address reported by Sentinel: ${addr:-<unknown>}"
echo "Quorum check: $(scli SENTINEL ckquorum "${MASTER_GROUP}" 2>&1 | tr -d '\r')"
echo

printf "=== Valkey data pods (%s) ===\n" "${REPL_NAME}"
printf "%-16s %-8s %-15s %-28s %-12s %-12s %-10s %s\n" POD ROLE POD_IP NODE ZONE LINK OFFSET LAG_BYTES
master_off=""
rows=()
for p in $(repl_pods); do
  info="$(vcli "$p" INFO replication 2>/dev/null | tr -d '\r')"
  role="$(echo "$info" | awk -F: '/^role:/{print $2}')"
  off="$(echo "$info" | awk -F: '/^master_repl_offset:/{print $2}')"
  link="$(echo "$info" | awk -F: '/^master_link_status:/{print $2}')"
  [ "$role" = "master" ] && { master_off="$off"; link="-"; }
  ip="$(kubectl get pod -n "$ns" "$p" -o jsonpath='{.status.podIP}')"
  node="$(kubectl get pod -n "$ns" "$p" -o jsonpath='{.spec.nodeName}')"
  rows+=("$p|${role:-?}|$ip|$node|$(zone_of "$node")|${link:-?}|${off:-?}")
done
for r in "${rows[@]}"; do
  IFS='|' read -r p role ip node zone link off <<<"$r"
  lag="-"
  if [ "$role" != "master" ] && [ -n "$master_off" ] && [ "$off" != "?" ]; then lag=$((master_off - off)); fi
  label="$role"; [ "$role" = "master" ] && label="PRIMARY"; [ "$role" = "slave" ] && label="replica"
  printf "%-16s %-8s %-15s %-28s %-12s %-12s %-10s %s\n" "$p" "$label" "$ip" "$node" "${zone:--}" "$link" "$off" "$lag"
done
echo

printf "=== Sentinel pods (%s) ===\n" "${SENTINEL_NAME}"
printf "%-24s %-15s %-28s %s\n" POD POD_IP NODE ZONE
for p in $(sentinel_pods); do
  ip="$(kubectl get pod -n "$ns" "$p" -o jsonpath='{.status.podIP}')"
  node="$(kubectl get pod -n "$ns" "$p" -o jsonpath='{.spec.nodeName}')"
  printf "%-24s %-15s %-28s %s\n" "$p" "$ip" "$node" "$(zone_of "$node")"
done
echo

echo "=== Placement check ==="
nodes_data="$(for p in $(repl_pods); do kubectl get pod -n "$ns" "$p" -o jsonpath='{.spec.nodeName}{"\n"}'; done | sort | uniq -c | awk '$1>1{print "  WARNING: "$1" data pods share node "$2}')"
nodes_sent="$(for p in $(sentinel_pods); do kubectl get pod -n "$ns" "$p" -o jsonpath='{.spec.nodeName}{"\n"}'; done | sort | uniq -c | awk '$1>1{print "  WARNING: "$1" Sentinel pods share node "$2}')"
if [ -z "$nodes_data$nodes_sent" ]; then echo "  OK: no two data pods and no two Sentinels share a worker node"; else echo "$nodes_data"; echo "$nodes_sent"; fi

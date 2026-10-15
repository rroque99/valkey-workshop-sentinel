#!/usr/bin/env bash
# Pre/post-maintenance health check for the workshop Sentinel deployment.
# Exit code 0 = healthy, 1 = something needs attention.
set -uo pipefail
: "${WORKSHOP_HOME:?Run 'source ./env.sh' first}"
. "${WORKSHOP_HOME}/scripts/lib.sh"
rc=0
ok()   { printf "  [ OK ] %s\n" "$*"; }
bad()  { printf "  [FAIL] %s\n" "$*"; rc=1; }
warn() { printf "  [WARN] %s\n" "$*"; }

echo "Custom resources"
kubectl get valkeysentinel "${SENTINEL_NAME}" -n "${VALKEY_NS}" --no-headers 2>/dev/null | sed 's/^/    /'
kubectl get valkeyreplication "${REPL_NAME}" -n "${VALKEY_NS}" --no-headers 2>/dev/null | sed 's/^/    /'

echo "Pods"
notready="$(kubectl get pods -n "${VALKEY_NS}" --no-headers | awk '{split($2,a,"/"); if (a[1]!=a[2] || $3!="Running") print $1" "$2" "$3}' | grep -E "^(${REPL_NAME}|${SENTINEL_NAME})" || true)"
[ -z "$notready" ] && ok "all Valkey and Sentinel pods Running and Ready" || bad "not ready: $notready"

echo "Sentinel"
q="$(scli SENTINEL ckquorum "${MASTER_GROUP}" 2>&1 | tr -d '\r')"
case "$q" in OK*) ok "$q" ;; *) bad "ckquorum: $q" ;; esac
flags="$(scli SENTINEL master "${MASTER_GROUP}" 2>/dev/null | tr -d '\r' | awk 'f{print;exit} /^flags$/{f=1}')"
[ "$flags" = "master" ] && ok "primary flags: $flags" || bad "primary flags: $flags (expect 'master')"

echo "Replication"
primary="$(primary_pod 2>/dev/null)" || { bad "cannot resolve primary"; exit 1; }
ok "primary pod: $primary"
nrep="$(vcli "$primary" INFO replication | tr -d '\r' | awk -F: '/^connected_slaves:/{print $2}')"
[ "${nrep:-0}" -ge 2 ] && ok "connected replicas: $nrep" || bad "connected replicas: ${nrep:-0} (expect 2)"
for r in $(replica_pods); do
  link="$(vcli "$r" INFO replication | tr -d '\r' | awk -F: '/^master_link_status:/{print $2}')"
  [ "$link" = "up" ] && ok "$r master_link_status=up" || bad "$r master_link_status=$link"
done

echo "Persistence"
st="$(vcli "$primary" INFO persistence | tr -d '\r' | awk -F: '/^rdb_last_bgsave_status:/{print $2}')"
[ "$st" = "ok" ] && ok "rdb_last_bgsave_status=ok" || bad "rdb_last_bgsave_status=$st"
kubectl get pvc -n "${VALKEY_NS}" --no-headers | awk '$2!="Bound"{print "  [FAIL] PVC "$1" is "$2}'

echo "Memory"
mem="$(vcli "$primary" INFO memory | tr -d '\r')"
frag="$(echo "$mem" | awk -F: '/^mem_fragmentation_ratio:/{print $2}')"
maxm="$(echo "$mem" | awk -F: '/^maxmemory:/{print $2}')"
echo "    used_memory_human=$(echo "$mem" | awk -F: '/^used_memory_human:/{print $2}')  maxmemory=$maxm  fragmentation=$frag"
[ "${maxm:-0}" = "0" ] && warn "maxmemory=0 (unlimited) - the container memory limit is the real ceiling"

echo "PodDisruptionBudgets"
kubectl get pdb -n "${VALKEY_NS}" --no-headers 2>/dev/null | sed 's/^/    /'

echo
[ $rc -eq 0 ] && echo "RESULT: HEALTHY" || echo "RESULT: ATTENTION REQUIRED"
exit $rc

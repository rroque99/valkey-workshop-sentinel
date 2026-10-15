#!/usr/bin/env bash
# Collect a diagnostics bundle for troubleshooting or a Broadcom support case.
# Passwords are NOT collected (secrets are listed by name only).
#   collect-diagnostics.sh [output-dir]
set -uo pipefail
: "${WORKSHOP_HOME:?Run 'source ./env.sh' first}"
. "${WORKSHOP_HOME}/scripts/lib.sh"
out="${1:-valkey-diag-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
ns="${VALKEY_NS}"
echo "Collecting into $out ..."

kubectl version -o yaml                                   > "$out/k8s-version.yaml" 2>&1
kubectl get nodes -o wide --show-labels                   > "$out/nodes.txt" 2>&1
helm list -n "${OPERATOR_NS}" -o yaml                     > "$out/helm-release.yaml" 2>&1
kubectl get all,pvc,pdb,networkpolicy,secret -n "${OPERATOR_NS}" -o wide > "$out/operator-ns.txt" 2>&1
kubectl logs -n "${OPERATOR_NS}" "deploy/${OPERATOR_DEPLOY}" --tail=5000 > "$out/operator.log" 2>&1
kubectl get crd -o name | grep -i valkey                  > "$out/crds.txt" 2>&1
kubectl get valkeyversions,valkeyimageset -o yaml         > "$out/versions-imagesets.yaml" 2>&1

kubectl get all,pvc,pdb,networkpolicy,endpoints -n "$ns" -o wide > "$out/instance-ns.txt" 2>&1
kubectl get secrets -n "$ns"                              > "$out/secrets-names-only.txt" 2>&1
for kind in valkeysentinel valkeyreplication valkey valkeybackup valkeybackupschedule valkeybackuplocation valkeyrestore valkeyversionupgrade valkeyadmin valkeycommander; do
  kubectl get "$kind" -n "$ns" -o yaml > "$out/cr-$kind.yaml" 2>/dev/null
done
kubectl get events -n "$ns" --sort-by=.lastTimestamp      > "$out/events.txt" 2>&1

for p in $(kubectl get pods -n "$ns" -o jsonpath='{.items[*].metadata.name}'); do
  kubectl describe pod -n "$ns" "$p" > "$out/describe-$p.txt" 2>&1
  for c in $(kubectl get pod -n "$ns" "$p" -o jsonpath='{.spec.containers[*].name}'); do
    kubectl logs -n "$ns" "$p" -c "$c" --tail=5000 > "$out/log-$p-$c.log" 2>&1
    kubectl logs -n "$ns" "$p" -c "$c" --previous --tail=2000 > "$out/log-$p-$c.previous.log" 2>/dev/null || rm -f "$out/log-$p-$c.previous.log"
  done
done

for p in $(repl_pods); do
  for s in server replication memory persistence stats clients keyspace; do
    echo "# INFO $s"; vcli "$p" INFO "$s" 2>&1
  done > "$out/info-$p.txt"
  { echo "# SLOWLOG"; vcli "$p" SLOWLOG GET 50; echo "# LATENCY LATEST"; vcli "$p" LATENCY LATEST; echo "# MEMORY DOCTOR"; vcli "$p" MEMORY DOCTOR; } > "$out/diag-$p.txt" 2>&1
done
{ echo "# SENTINEL master"; scli SENTINEL master "${MASTER_GROUP}"; echo "# SENTINEL replicas"; scli SENTINEL replicas "${MASTER_GROUP}"; echo "# SENTINEL sentinels"; scli SENTINEL sentinels "${MASTER_GROUP}"; echo "# INFO sentinel"; scli INFO sentinel; } > "$out/sentinel.txt" 2>&1

tar -czf "$out.tar.gz" "$out" && echo "Bundle: $out.tar.gz"

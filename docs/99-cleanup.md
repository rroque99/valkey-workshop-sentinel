# Module 99: Cleanup

[← Module 12](12-troubleshooting-runbook.md) | [README](../README.md)

Tear down in **reverse dependency order**: instances first (so the operator can clean up after them), then backups, then the operator and CRDs, then the supporting components.

📘 **Docs:** [Uninstall Tanzu for Valkey on Kubernetes](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/uninstall.html)

⚠️ **Caution:** these commands delete data. On a shared cluster, only remove *your* namespaces. The instructor removes the operator and the monitoring stack.

```bash
source ./env.sh
```

## 1. Client, consoles and restore leftovers

```bash
kubectl delete pod valkey-client -n "${VALKEY_NS}" --ignore-not-found
kubectl delete valkeyrestore --all -n "${VALKEY_NS}"
kubectl delete valkey vk-restored -n "${VALKEY_NS}" --ignore-not-found
kubectl delete valkeysentinel vk-restored-ha -n "${VALKEY_NS}" --ignore-not-found
```

## 2. Backup schedules, backups and upgrade objects

```bash
kubectl delete valkeybackupschedule --all -n "${VALKEY_NS}"
kubectl delete valkeyversionupgrade --all -n "${VALKEY_NS}"
kubectl delete valkeybackup --all -n "${VALKEY_NS}"          # also deletes the objects in S3 when the operator handles retention
kubectl delete valkeybackuplocation --all -n "${VALKEY_NS}"
```

## 3. DR site

```bash
DRK="kubectl"; [ -n "${DR_CONTEXT}" ] && DRK="kubectl --context ${DR_CONTEXT}"
$DRK delete valkeysentinel --all -n "${DR_NS}" --ignore-not-found
$DRK delete valkeyreplication --all -n "${DR_NS}" --ignore-not-found
$DRK delete ns "${DR_NS}" --ignore-not-found
```

## 4. The Sentinel instance

```bash
kubectl delete valkeysentinel "${SENTINEL_NAME}" -n "${VALKEY_NS}"
kubectl get valkeyreplication,pods -n "${VALKEY_NS}"          # wait until the operator removed everything
kubectl delete valkeyreplication "${REPL_NAME}" -n "${VALKEY_NS}" --ignore-not-found
kubectl get pvc -n "${VALKEY_NS}"                             # PVCs may be retained by design
kubectl delete pvc --all -n "${VALKEY_NS}"
kubectl delete ns "${VALKEY_NS}"
```

## 5. MinIO

```bash
kubectl delete ns "${MINIO_NS}"
```

## 6. Monitoring and logging (instructor / shared)

```bash
helm uninstall alloy -n "${MONITORING_NS}" 2>/dev/null
helm uninstall loki  -n "${MONITORING_NS}" 2>/dev/null
helm uninstall kps   -n "${MONITORING_NS}"
kubectl delete ns "${MONITORING_NS}"
# kube-prometheus-stack CRDs are not removed by helm:
kubectl get crd -o name | grep monitoring.coreos.com | xargs -r kubectl delete
```

## 7. The operator (instructor / shared)

Make sure **no** Valkey custom resources remain in any namespace first:

```bash
for k in valkey valkeyreplication valkeysentinel valkeybackup valkeyrestore valkeyadmin valkeycommander valkeymcpserver; do
  kubectl get "$k" -A --no-headers 2>/dev/null
done

helm uninstall "${OPERATOR_RELEASE}" -n "${OPERATOR_NS}"
kubectl delete ns "${OPERATOR_NS}"
# CRDs are not removed by helm. Deleting them deletes ALL Valkey CRs cluster-wide:
kubectl get crd -o name | grep data.tanzu.vmware.com | xargs -r kubectl delete
```

## 8. Local files

```bash
rm -rf .secrets valkey-diag-* /tmp/tanzu-valkey-helm env.sh.bak
helm registry logout "${REGISTRY_SERVER}"
```

---

🎉 **Congratulations!** You have installed, secured, observed, failed over, backed up, replicated, patched and troubleshot a highly available Valkey deployment with Tanzu for Valkey on Kubernetes.

[← Module 12](12-troubleshooting-runbook.md) | [README](../README.md)

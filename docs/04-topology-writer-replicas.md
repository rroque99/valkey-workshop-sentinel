# Module 4: Topology: where are the writer and the replicas?

[← Module 3](03-deploy-valkey-sentinel.md) | [README](../README.md) | Next: [Module 5: Connections and security →](05-connections-and-security.md)

**Goal:** answer, at any moment and in under a minute: *which pod is the writer, which are replicas, how far behind are they, and on which Kubernetes nodes (and zones) are they running?*

📘 **Docs:** [Access instances](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/accessing.html) · [Monitor instances](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/monitoring.html) · [Valkey `INFO` reference](https://valkey.io/commands/info/) · [Sentinel commands](https://valkey.io/topics/sentinel/#sentinel-commands)

---

> 🧠 **Roles are dynamic.** After any failover the writer is a different pod. Never hard-code "`vk-repl-0` is the primary" in runbooks, scripts or dashboards. Always **ask**.

There are three authoritative sources, and they should agree:

| Source | Question it answers | Command |
|--------|---------------------|---------|
| **Sentinel** | Who *should* clients write to? | `SENTINEL get-master-addr-by-name valkey-server` |
| **Each Valkey node** | What role do *you* think you have? | `INFO replication` / `ROLE` |
| **Kubernetes** | Where does that pod run? | `kubectl get pod -o wide`, node labels |

## 4.1 Ask Sentinel

The operator registers the replication group with Sentinel under the master group name **`valkey-server`** (`$MASTER_GROUP`).

```bash
source ./env.sh
scli SENTINEL get-master-addr-by-name "${MASTER_GROUP}"
```

```
1) "10.244.2.15"     <- primary address (pod IP or hostname)
2) "6379"
```

Get the full Sentinel view of the primary:

```bash
scli SENTINEL master "${MASTER_GROUP}"
```

Fields to know:

| Field | Meaning | Healthy value |
|-------|---------|---------------|
| `flags` | state of the primary | `master` (not `s_down`, `o_down`, `failover_in_progress`) |
| `num-slaves` | replicas Sentinel knows about | 2 |
| `num-other-sentinels` | peers this Sentinel sees | 2 |
| `quorum` | configured quorum | 2 |
| `down-after-milliseconds` | detection time | 5000 (workshop) |
| `config-epoch` | increments on every failover | grows over time; a jump means a failover happened |

Replicas and peer Sentinels:

```bash
scli SENTINEL replicas "${MASTER_GROUP}"     # ip, flags, master-link-status, slave-repl-offset, slave-priority
scli SENTINEL sentinels "${MASTER_GROUP}"    # the other Sentinels
scli SENTINEL ckquorum "${MASTER_GROUP}"     # can a failover be authorised right now?
scli INFO sentinel                           # master0:name=valkey-server,status=ok,address=...,slaves=2,sentinels=3
```

🔎 **Check:** `ckquorum` returns `OK 3 usable Sentinels. Quorum and failover authorization can be reached`.

## 4.2 Ask every Valkey node

```bash
for p in $(repl_pods); do
  echo "== $p"; vcli "$p" ROLE | head -3
done
```

Detailed view on one pod:

```bash
vcli vk-repl-0 INFO replication
```

On the **primary**:

```
role:master
connected_slaves:2
slave0:ip=10.244.1.12,port=6379,state=online,offset=185023,lag=0
slave1:ip=10.244.3.9,port=6379,state=online,offset=185023,lag=1
master_replid:9f2b...
master_repl_offset:185023
```

On a **replica**:

```
role:slave
master_host:10.244.2.15
master_port:6379
master_link_status:up
master_last_io_seconds_ago:0
master_sync_in_progress:0
slave_repl_offset:185023
slave_priority:100
slave_read_only:1
```

| Field | Meaning | Watch for |
|-------|---------|-----------|
| `master_link_status` | replica connected to the primary? | `down` → replication broken |
| `master_last_io_seconds_ago` | seconds since the last data from the primary | > a few seconds while writes happen |
| `master_sync_in_progress` | full resync running | `1` for a long time = large dataset or slow network |
| `slaveN: ... lag=` | seconds since the replica's last ACK (primary view) | > 1–2 s sustained |
| `master_repl_offset` vs `slave_repl_offset` | bytes replicated | difference = lag in bytes |
| `slave_priority` | promotion preference (lower wins, 0 = never) | used for planned placement (module 9) |

## 4.3 Map roles to pods, nodes and zones

The helper functions in `env.sh` combine the views:

```bash
primary_pod        # e.g. vk-repl-1
replica_pods       # e.g. vk-repl-0, vk-repl-2
kubectl get pod "$(primary_pod)" -n "${VALKEY_NS}" -o wide
```

Or get everything at once with **`scripts/topology.sh`**:

```bash
topology.sh
```

```
=== Sentinel view (master group: valkey-server) ===
Primary address reported by Sentinel: 10.244.2.15
Quorum check: OK 3 usable Sentinels. Quorum and failover authorization can be reached

=== Valkey data pods (vk-repl) ===
POD              ROLE     POD_IP          NODE                         ZONE         LINK         OFFSET     LAG_BYTES
vk-repl-0        replica  10.244.1.12     vks-wl-np1-abc12-xyz         zone-a       up           185023     0
vk-repl-1        PRIMARY  10.244.2.15     vks-wl-np1-abc12-pqr         zone-b       -            185023     -
vk-repl-2        replica  10.244.3.9      vks-wl-np1-abc12-stu         zone-c       up           185023     0

=== Sentinel pods (vk-sentinel) ===
POD                      POD_IP          NODE                         ZONE
vk-sentinel-sentinel-0   10.244.1.13     vks-wl-np1-abc12-xyz         zone-a
...

=== Placement check ===
  OK: no two data pods and no two Sentinels share a worker node
```

Read the script ([`scripts/topology.sh`](../scripts/topology.sh)). It uses only `kubectl`, `valkey-cli INFO replication` and Sentinel commands, so you can reproduce it by hand during an incident.

### Pure kubectl views

```bash
# Pods sorted by node
kubectl get pods -n "${VALKEY_NS}" -o wide --sort-by=.spec.nodeName

# Pod -> node -> zone in one table
kubectl get pods -n "${VALKEY_NS}" -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,STATUS:.status.phase
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type

# Node health and pressure for the node hosting the primary
kubectl describe node "$(kubectl get pod "$(primary_pod)" -n "${VALKEY_NS}" -o jsonpath='{.spec.nodeName}')" | sed -n '/Conditions:/,/Addresses:/p'

# Resource usage per pod (requires metrics-server)
kubectl top pods -n "${VALKEY_NS}" --containers
```

> **Does the operator label pods with their role?** Look for role-like labels with `kubectl get pods -n $VALKEY_NS --show-labels`. If role labels exist, they're handy for selectors, but always confirm with Sentinel or `INFO replication`, which are the authoritative sources.

## 4.4 Replicas and placement: what "good" looks like

| Check | Command | Good |
|-------|---------|------|
| 1 primary, 2 replicas | `topology.sh` | exactly one `PRIMARY` |
| Replicas linked | `INFO replication` on replicas | `master_link_status:up` |
| Replicas current | `LAG_BYTES` column | 0 or near 0 |
| Spread across nodes | Placement check | no shared nodes |
| Spread across zones (multi-zone clusters) | ZONE column | data pods in different zones |
| Sentinels spread | Sentinel pods table | different nodes/zones |
| Sentinels agree | `ckquorum`, `INFO sentinel` on each Sentinel | `OK`, `sentinels=3` |

What if placement is bad, for example two data pods on one node? The workshop uses **preferred** anti-affinity, so on a small cluster the scheduler may co-locate pods. In production:

- use `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity on `kubernetes.io/hostname`, and
- add `spec.valkeyReplicationConfig.topologySpreadConstraints` on `topology.kubernetes.io/zone`.

Moving an already-scheduled pod means deleting it so it reschedules. If it's the primary, fail over first (module 9).

## 4.5 Web console view (preview)

Valkey Admin and Valkey Commander (module 6) show the same topology graphically. The Grafana dashboard you build in module 7 has a **Role and placement** table and a **Primary over time** timeline that records every failover.

## 4.6 Exercise

1. Write down the current primary pod, its node and its zone.
2. Compare `SENTINEL get-master-addr-by-name` with the pod IP of the pod that reports `role:master`. Do they match?
3. Run `scli SENTINEL master $MASTER_GROUP` and note `config-epoch`. You will compare it after the failover lab.
4. Run the same Sentinel query against **each** Sentinel pod. All three should agree:

   ```bash
   for s in $(sentinel_pods); do
     kubectl exec -n "$VALKEY_NS" "$s" -- valkey-cli -p 26379 SENTINEL get-master-addr-by-name "$MASTER_GROUP" | head -1
   done
   ```

---

[← Module 3](03-deploy-valkey-sentinel.md) | [README](../README.md) | Next: [Module 5: Connections and security →](05-connections-and-security.md)

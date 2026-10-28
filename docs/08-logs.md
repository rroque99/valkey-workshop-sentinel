# Module 8: Logs: access and analysis

[← Module 7](07-metrics-prometheus-grafana.md) | [README](../README.md) | Next: [Module 9: Failover →](09-failover.md)

**Goal:** know where every log lives (operator, Valkey, Sentinel, sidecars, Kubernetes events), read the Sentinel event vocabulary fluently, recognise the common error patterns, and optionally centralise logs with Loki.

📘 **Docs:** [Troubleshooting](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/troubleshooting.html) · [Access instances](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/accessing.html) · [Sentinel events (upstream)](https://valkey.io/topics/sentinel/#pubsub-messages)

---

## 8.1 Where the logs are

Valkey and Sentinel log to **stdout/stderr**, so Kubernetes captures them. Nothing has to be configured to *access* them; you only need to know which pod and container to ask.

| Log | Where | Read it when… |
|-----|-------|---------------|
| **Operator** | `deploy/valkey-operator` in `$OPERATOR_NS` | a CR isn't reconciling, webhooks reject manifests, backup/restore/upgrade issues |
| **Valkey server** | data pods `vk-repl-N`, Valkey container | replication, persistence, memory, auth and client errors |
| **Sentinel** | Sentinel pods | failovers, quorum, Sentinel auth |
| **Exporter** | data pods, exporter container | metrics missing, exporter can't authenticate |
| **Persistence** | data pods, `persistence` container | backup and restore |
| **Auth sidecar** | data pods, `auth` container | OAuth/LDAP logins |
| **Consoles** | Admin / Commander pods | UI can't connect |
| **Kubernetes events** | `kubectl get events` | scheduling, image pulls, probes, OOMKills, PVCs |

List the containers in each pod. You need the names for `-c`:

```bash
source ./env.sh
kubectl get pods -n "${VALKEY_NS}" -o custom-columns='POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
```

## 8.2 Operator logs

```bash
kubectl logs -n "${OPERATOR_NS}" deploy/${OPERATOR_DEPLOY} --tail=100
kubectl logs -n "${OPERATOR_NS}" deploy/${OPERATOR_DEPLOY} -f --since=10m          # follow
kubectl logs -n "${OPERATOR_NS}" deploy/${OPERATOR_DEPLOY} --since=1h | grep -iE 'error|fail|warn' | tail -30
kubectl logs -n "${OPERATOR_NS}" deploy/${OPERATOR_DEPLOY} --since=1h | grep -i "${SENTINEL_NAME}\|${REPL_NAME}" | tail -30
```

Operator logs are structured (key/value or JSON). Filter by the instance name, `controller`, `reconcile` or `error`. With `jq`:

```bash
kubectl logs -n "${OPERATOR_NS}" deploy/${OPERATOR_DEPLOY} --since=30m \
 | grep '^{' | jq -r 'select(.level=="error") | [.ts, .msg, .error] | @tsv' 2>/dev/null | tail
```

Also look at the CR status and events. They're often the quickest summary:

```bash
kubectl describe valkeysentinel "${SENTINEL_NAME}" -n "${VALKEY_NS}" | sed -n '/Status:/,$p'
kubectl get events -n "${VALKEY_NS}" --sort-by=.lastTimestamp | tail -25
```

## 8.3 Valkey server logs

```bash
P=$(primary_pod)
kubectl logs -n "${VALKEY_NS}" "$P" ${VALKEY_CONTAINER:+-c $VALKEY_CONTAINER} --tail=50
kubectl logs -n "${VALKEY_NS}" "$P" --timestamps --since=15m
kubectl logs -n "${VALKEY_NS}" "$P" --previous            # the crashed container (after a restart!)
```

⚠️ `--previous` is the most forgotten flag in Kubernetes troubleshooting. When a pod shows `RESTARTS > 0`, the reason is in the **previous** container's log, not the current one.

All data pods at once, prefixed with the pod name:

```bash
kubectl logs -n "${VALKEY_NS}" -l app="${REPL_NAME}" --prefix --tail=20 --max-log-requests=10
```

> Tip: [`stern`](https://github.com/stern/stern) makes multi-pod tailing much nicer: `stern -n $VALKEY_NS "${REPL_NAME}|${SENTINEL_NAME}"`.

### Reading a Valkey log line

```
1:M 15 Oct 2026 14:02:11.532 * Background saving terminated with success
│ │ └─ timestamp            │ └─ message
│ └─ role: M=primary  S=replica  C=child (fork, e.g. BGSAVE)  X=sentinel
└─ PID                      └─ level: . debug  - verbose  * notice  # warning
```

The **role letter** tells you instantly whether a line came from the primary or a replica.

### Messages to know

| Message | Meaning |
|---------|---------|
| `Ready to accept connections tcp` | server started |
| `DB loaded from disk: N seconds` / `Done loading RDB` | dataset loaded from the PVC at startup |
| `Connecting to MASTER <ip>:6379` → `MASTER <-> REPLICA sync started` | a replica starts syncing |
| `Partial resynchronization request accepted` / `Successful partial resynchronization` | cheap catch-up from the backlog ✅ |
| `Full resync requested by replica` / `Starting BGSAVE for SYNC` | expensive full sync (fork + RDB transfer) |
| `MASTER <-> REPLICA sync: Finished with success` | replica is current |
| `Connection with master lost` | replica lost the primary (failover, network, primary restart) |
| `MASTER MODE enabled (user request from 'id=…')` | **this node was promoted** (failover) |
| `REPLICAOF <ip>:6379 enabled (user request …)` | node reconfigured as a replica (by Sentinel) |
| `Background saving started by pid` / `terminated with success` | RDB snapshot |
| `Background saving error` / `Can't save in background: fork: Cannot allocate memory` | ❌ persistence failing (disk full, memory) |
| `WARNING overcommit_memory is set to 0!` | node kernel setting; fork may fail under memory pressure |
| `OOM command not allowed when used memory > 'maxmemory'` (client error) | maxmemory reached with `noeviction` |
| `Client id=… closed for overcoming of output buffer limits` | slow consumer (replica or pub/sub client) disconnected |
| `DENIED Running in protected mode` | `default` user without a password while ACL is active |
| `Asynchronous AOF fsync is taking too long (disk is busy?)` | slow storage |

## 8.4 Sentinel logs: the failover story

```bash
for s in $(sentinel_pods); do echo "== $s"; kubectl logs -n "${VALKEY_NS}" "$s" ${SENTINEL_CONTAINER:+-c $SENTINEL_CONTAINER} --tail=15; done
```

Sentinel log lines contain events (`+event` = happened, `-event` = cleared):

| Event | Meaning |
|-------|---------|
| `+monitor master valkey-server <ip> 6379 quorum 2` | Sentinel started monitoring |
| `+slave slave <ip>:6379 … @ valkey-server` | replica discovered |
| `+sentinel sentinel <id> <ip> 26379 …` | peer Sentinel discovered |
| `+sdown master valkey-server …` | **this** Sentinel thinks the primary is down |
| `-sdown …` | it's reachable again |
| `+odown master valkey-server … #quorum 2/2` | **quorum agrees** the primary is down |
| `+new-epoch N` / `+vote-for-leader <id> N` | leader election for epoch N |
| `+try-failover master valkey-server …` | failover attempt started |
| `+elected-leader master valkey-server …` | this Sentinel won and runs the failover |
| `+failover-state-select-slave` / `+selected-slave slave <ip>:6379` | promotion candidate chosen |
| `+failover-state-send-slaveof-noone` | sending `REPLICAOF NO ONE` to the candidate |
| `+promoted-slave` | candidate is now primary |
| `+failover-state-reconf-slaves` / `+slave-reconf-sent/inprog/done` | other replicas repointed |
| `+failover-end` | failover finished |
| **`+switch-master valkey-server <old-ip> 6379 <new-ip> 6379`** | **the authoritative "primary changed" event** (clients react to this) |
| `+convert-to-slave` | the old primary came back and was turned into a replica |
| `-failover-abort-*` | failover aborted (no good replica, timeout, …) |
| `+tilt` / `-tilt` | Sentinel entered TILT mode (clock jump / process paused) |

**Find all failovers in the retained logs:**

```bash
for s in $(sentinel_pods); do
  kubectl logs -n "${VALKEY_NS}" "$s" --timestamps | grep -E 'switch-master|odown|failover-end|elected-leader' | sed "s/^/$s  /"
done
```

> Logs inside a pod only go back to the last container restart and are capped by the kubelet (`containerLogMaxSize`). For a failover two days ago you need **centralised logging** (8.6).

## 8.5 Kubernetes events and container status

```bash
kubectl get events -n "${VALKEY_NS}" --sort-by=.lastTimestamp | tail -30
kubectl get events -n "${VALKEY_NS}" --field-selector type=Warning
kubectl describe pod "$(primary_pod)" -n "${VALKEY_NS}" | sed -n '/Containers:/,/Conditions:/p' | grep -E 'State|Reason|Exit Code|Restart Count|Last State' 
kubectl get pods -n "${VALKEY_NS}" -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount,LAST:.status.containerStatuses[*].lastState.terminated.reason'
```

| Event / reason | Meaning |
|----------------|---------|
| `OOMKilled` (Last State) | container exceeded its memory limit → raise the limit and/or set maxmemory |
| `FailedScheduling` | not enough CPU/memory, anti-affinity can't be satisfied, PVC zone mismatch |
| `ErrImagePull` / `ImagePullBackOff` | registry secret missing in this namespace |
| `Unhealthy … Readiness probe failed` | heartbeat failing (auth, `+ping` missing, slow startup) |
| `FailedMount` / `FailedAttachVolume` | storage problems |
| `Killing … Stopping container` | normal restart from a CR change or node drain |

## 8.6 Error pattern cheat sheet

| Log pattern | Probable cause | Action |
|-------------|----------------|--------|
| `NOAUTH Authentication required` | client didn't send credentials (for Commander: the `REDIS_*` env vars are missing, module 6.6) | check the client configuration and secret |
| `WRONGPASS invalid username-password pair` | wrong credentials / unrotated client | `ACL LOG`; verify the secret and ACL file |
| `NOPERM … no permissions` | user lacks a command/key permission | `ACL GETUSER <user>`, `ACL DRYRUN` |
| `DENIED Running in protected mode` | ACL active, `default` without password | give `default` a password or disable it |
| Sentinel: `-failover-abort-no-good-slave` | no replica eligible (all down, lagging or priority 0) | check replicas, `slave-priority` |
| Sentinel: auth errors to the primary | `valkeySecret` wrong or user missing in ACL | align the secret and ACL (not `sentinelSecret`) |
| Sentinel: `Aborting Valkey startup because of ACL errors … Unknown command or category name` | the data-node ACL file is mounted into Sentinel (top-level `spec.acl`) | reference the ACL from `valkeyReplicationConfig.acl` (module 3, rule 4) |
| Sentinel: `+sdown sentinel <id> …` right after `+sentinel` | Sentinels can't authenticate to each other: `ckquorum` → `NOQUORUM` | set `sentinelSecret`; ACL under `valkeyReplicationConfig.acl` |
| `MISCONF … unable to persist to disk` | RDB save failing, so writes are refused | PVC full or read-only; check `df` and events |
| `Can't save in background: fork: Cannot allocate memory` | not enough memory headroom to fork | raise the limit, lower maxmemory |
| `Client … closed for overcoming of output buffer limits` | slow replica/subscriber | check the network, `client-output-buffer-limit` |
| RDB→AOF conversion error at startup | persistence-mode change failed | see `ValkeyRdbToAof` in the docs; restore from backup if needed |

## 8.7 Optional lab: centralised logs with Loki

In production, ship logs to the platform your organisation already uses (Splunk, Elastic, Loki, Aria Operations for Logs, …). On VKS, the **Fluent Bit standard package** is a common forwarder. For the lab, install **Loki** (single binary) plus **Grafana Alloy**, which tails pod logs through the Kubernetes API with no hostPath mounts, so it is PSA-friendly.

```bash
# Chart repository (also in module 1.6; safe to re-run)
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update grafana

helm upgrade --install loki grafana/loki -n "${MONITORING_NS}" \
  -f manifests/08-logging/loki-values.yaml --wait --timeout 10m
helm upgrade --install alloy grafana/alloy -n "${MONITORING_NS}" \
  -f <(render manifests/08-logging/alloy-values.yaml | sed '/^---$/d') --wait

# Add Loki as a Grafana data source
helm upgrade kps prometheus-community/kube-prometheus-stack -n "${MONITORING_NS}" \
  -f manifests/07-monitoring/kube-prometheus-stack-values.yaml \
  -f <(render manifests/08-logging/kps-loki-datasource-values.yaml | sed '/^---$/d') \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  --set grafana.service.type="${MONITORING_SERVICE_TYPE}" \
  --set prometheus.service.type="${MONITORING_SERVICE_TYPE}" --wait
```

In Grafana → **Explore** → data source **Loki**, try the queries below (replace the namespace and instance names if you changed them in `env.sh`):

```logql
# All Sentinel failover events
{namespace="valkey-workshop", pod=~"vk-sentinel.*"} |= "+switch-master"

# Promotions and demotions on the data pods
{namespace="valkey-workshop", app="vk-repl"} |~ "MASTER MODE enabled|REPLICAOF .* enabled"

# Persistence or auth errors
{namespace="valkey-workshop"} |~ "(?i)background saving error|MISCONF|WRONGPASS|protected mode"

# Operator errors for this instance
{namespace="tanzu-for-valkey-on-kubernetes"} |= "vk-sentinel" |~ "(?i)error"

# Failovers per hour (as a metric)
sum(count_over_time({namespace="valkey-workshop"} |= "+switch-master" [1h]))
```

🧠 You can add a Loki-based annotation (`|= "+switch-master"`) to the Valkey dashboard to overlay failovers taken directly from Sentinel's own log.

## 8.8 Exercise

1. Find the line in the primary's log showing the last RDB save. How long ago was it?
2. In the Sentinel logs, find the `+monitor` line. Which quorum is configured?
3. Generate an auth failure (`valkey-cli --user appuser --pass wrong PING`) and find it in `ACL LOG`. Is it in the Valkey container log too? (Hint: Valkey doesn't log every failed AUTH. `ACL LOG` is the place.)
4. Keep a terminal following the Sentinel logs for the next module:
   ```bash
   kubectl logs -n "$VALKEY_NS" -f "$(sentinel_pod)"
   ```

---

[← Module 7](07-metrics-prometheus-grafana.md) | [README](../README.md) | Next: [Module 9: Failover →](09-failover.md)

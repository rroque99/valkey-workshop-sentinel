# Module 6: Broadcom tools: CLI and web consoles

[← Module 5](05-connections-and-security.md) | [README](../README.md) | Next: [Module 7: Metrics →](07-metrics-prometheus-grafana.md)

**Goal:** get fluent with the tools you will use to connect to, query and troubleshoot Valkey: `valkey-cli`, `valkey-benchmark`, **Valkey Admin**, **Valkey Commander** and the **Valkey MCP Server**. Also answer the question *"Is there a web console to monitor and manage Valkey?"*

📘 **Docs:** [Access instances (Commander)](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/accessing.html) · [Monitor instances (Valkey Admin)](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/monitoring.html) · [Benchmark instances](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/benchmarking.html) · [Valkey MCP Server](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/mcp-server.html) · [Tanzu Valkey Admin UI (9.1)](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-valkey/9-1/tanzu-valkey-docs/setup-valkey-admin.html)

---

## 6.1 The toolbox

| Tool | Type | Shipped as | Best for |
|------|------|------------|----------|
| `valkey-cli` | CLI | in every Tanzu Valkey image | queries, `INFO`, Sentinel commands, diagnostics (`--bigkeys`, `--latency`, …) |
| `valkey-benchmark` | CLI | in the Tanzu Valkey image | load generation, capacity tests |
| `kubectl` / `helm` | CLI | — | logs, status, CR lifecycle |
| **Valkey Admin** | Web UI | `ValkeyAdmin` CR or `valkeyAdminConfig.enabled` | visual observability, topology, cluster health |
| **Valkey Commander** | Web UI | `ValkeyCommander` CR or `valkeyCommanderConfig.enabled` (with login) | key browser, live stats, ad-hoc admin |
| **Prometheus exporter** | metrics sidecar | `valkeyExporter.enabled` | time-series metrics → Prometheus/Grafana (module 7) |
| **Valkey MCP Server** | API for AI agents | `ValkeyMCPServer` CR | letting LLM agents / AI IDEs query Valkey |
| Workshop scripts | bash | this repo | `topology.sh`, `health-check.sh`, `collect-diagnostics.sh` |

## 6.2 Deploy the workshop client pod

The client pod uses **the same Tanzu image as your instance**, so the tool versions match the server. It mounts the [client scripts](../scripts/client) at `/scripts`.

```bash
source ./env.sh
client_env        # exports SENTINEL_HOST and VALKEY_IMAGE (helper from scripts/lib.sh)

kubectl create configmap workshop-client-scripts -n "${VALKEY_NS}" \
  --from-file=scripts/client/ --dry-run=client -o yaml | kubectl apply -f -
render manifests/06-tools/01-client-credentials-secret.yaml | kubectl apply -f -
render manifests/06-tools/02-valkey-client-pod.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/valkey-client -n "${VALKEY_NS}" --timeout=120s
```

> If `containers[0]` isn't the Valkey container, list them with `kubectl get pod vk-repl-0 -n $VALKEY_NS -o jsonpath='{.spec.containers[*].name}'` and use the matching index.

```bash
kubectl exec -n "${VALKEY_NS}" valkey-client -- /scripts/whereis-primary.sh
```

## 6.3 `valkey-cli` for operators

Open a shell in the client pod and connect to the current primary:

```bash
kubectl exec -it -n "${VALKEY_NS}" valkey-client -- sh
# inside the pod:
. /scripts/common.sh
set -- $(current_primary); echo "primary=$1"
valkey-cli -h $1 -p 6379 --user admin --pass "$ADMIN_PASSWORD" --no-auth-warning
```

### Commands every Valkey operator should know

| Area | Command | What it tells you |
|------|---------|-------------------|
| Identity | `ROLE`, `INFO server` | role, version, uptime, `run_id`, config file |
| Replication | `INFO replication` | role, replicas, offsets, link status |
| Memory | `INFO memory`, `MEMORY STATS`, `MEMORY DOCTOR` | used/RSS/peak memory, fragmentation, advice |
| Keys | `DBSIZE`, `INFO keyspace`, `MEMORY USAGE <key>`, `TYPE`, `TTL`, `OBJECT ENCODING` | dataset size and shape |
| Clients | `CLIENT LIST`, `INFO clients`, `CLIENT KILL ID <id>` | who is connected, from where, as which user, idle time, buffers |
| Throughput | `INFO stats` | ops/sec, hits/misses, evictions, expired keys, rejected connections |
| Commands | `INFO commandstats` | calls, µs/call, rejected and failed calls per command |
| Slow commands | `SLOWLOG GET 20`, `SLOWLOG LEN`, `SLOWLOG RESET` | commands slower than `slowlog-log-slower-than` (µs) |
| Large requests/replies | `COMMANDLOG GET 10 large-request` (Valkey 8.1+) | oversized payloads that hurt latency |
| Latency events | `CONFIG SET latency-monitor-threshold 100`, then `LATENCY LATEST`, `LATENCY DOCTOR` | fork, AOF fsync, expire-cycle and command spikes |
| Persistence | `INFO persistence`, `LASTSAVE`, `BGSAVE` | RDB/AOF status, last save time and result |
| Config | `CONFIG GET maxmemory*`, `CONFIG GET save` | effective configuration |
| Security | `ACL LIST`, `ACL LOG`, `ACL WHOAMI` | users, denied attempts |
| Sentinel | `-p 26379 SENTINEL masters/replicas/sentinels/ckquorum` | HA state (module 4) |

### Diagnostic modes (run from the client pod)

```bash
H=$1   # primary address from above
A="--user admin --pass $ADMIN_PASSWORD --no-auth-warning"

valkey-cli -h $H $A --stat                       # live one-line-per-second stats (keys, mem, clients, ops)
valkey-cli -h $H $A --latency                    # round-trip latency from this pod
valkey-cli -h $H $A --latency-history -i 5       # latency in 5 s buckets
valkey-cli -h $H $A --bigkeys                    # largest key per type (SCAN-based, safe)
valkey-cli -h $H $A --memkeys                    # keys using the most memory
valkey-cli -h $H $A --scan --pattern 'app:*' | head   # iterate keys safely (never KEYS * in prod)
valkey-cli -h $H $A INFO commandstats | sort -t= -k3 -rn | head
```

⚠️ **Caution:**

- **Never run `KEYS *`** on a production instance. It blocks the single main thread. Use `--scan` / `SCAN`.
- **`MONITOR`** streams every command and can halve throughput. Use it for seconds, not minutes.
- `--hotkeys` requires an LFU `maxmemory-policy`.
- `DEBUG`, `FLUSHALL`, `CONFIG SET` and `SHUTDOWN` belong to the `@dangerous` category. Only the `admin`/`default` users have them in this workshop.

### Port-forward from your laptop (when you have a local `valkey-cli`)

```bash
kubectl port-forward -n "${VALKEY_NS}" pod/"$(primary_pod)" 6379:6379 &
valkey-cli -h 127.0.0.1 -p 6379 --user admin --pass "${VALKEY_ADMIN_PASSWORD}" --no-auth-warning INFO server
kill %1
```

> Port-forwarding to the **Sentinel** port from a laptop is fine for `SENTINEL` queries. A laptop client that *follows* Sentinel's answer will fail, though, because Sentinel returns in-cluster pod IPs. Port-forward straight to the primary pod instead.

## 6.4 `valkey-benchmark`: generate load

Start background load. You will use it in modules 7 and 9.

```bash
# finite run, quick numbers
kubectl exec -n "${VALKEY_NS}" valkey-client -- env REQUESTS=200000 /scripts/load.sh

# continuous load (leave running in a spare terminal, Ctrl-C to stop)
kubectl exec -it -n "${VALKEY_NS}" valkey-client -- /scripts/load.sh
```

Useful flags if you call `valkey-benchmark` directly:

| Flag | Meaning |
|------|---------|
| `-t set,get` | tests to run |
| `-c 50` | parallel connections |
| `-n 1000000` | total requests |
| `-d 256` | value size (bytes) |
| `-r 100000` | random keys from a keyspace of this size (creates misses for GET) |
| `-P 16` | pipelining (much higher throughput, less realistic for most apps) |
| `--threads 4` | client threads |
| `-l` | loop forever |
| `--csv` | machine-readable output |

🧠 **Operator insight:** benchmark numbers depend heavily on pipelining, connection count, TLS and the network path, as the Broadcom troubleshooting guide notes. Use benchmarks to compare configurations (same flags each run) and to validate sizing, then confirm with steady-state metrics from real traffic. Never benchmark a production primary.

## 6.5 Valkey Admin

**Valkey Admin** is the visual observability and cluster-management UI (released with operator 3.5.0, "UI, server and metrics as an all-in-one deployment"). You can deploy it in two ways:

| Option | How | When |
|--------|-----|------|
| **A. Auto-provisioned** | `spec.valkeyAdminConfig.enabled: true` on the `ValkeySentinel` | simplest: lifecycle tied to the instance |
| B. Stand-alone | a `ValkeyAdmin` CR pointing at a host/port ([example](../manifests/06-tools/06-valkey-admin-standalone.yaml)) | manage the UI separately, or point it at any endpoint |

⚠️ **Valkey Admin has no built-in web authentication.** Its service stays **ClusterIP** and you reach it with `kubectl port-forward`. Never expose it with a LoadBalancer or Ingress without an authenticating proxy (OAuth2 Proxy, VPN).

## 6.6 Valkey Commander

**Valkey Commander** is a web UI for browsing keys, viewing live statistics and doing administrative tasks. Unlike Admin, it supports a **login secret** (`username` / `password`). Like Admin, you can deploy it in two ways:

| Option | How | Status on operator 3.5.1 |
|--------|-----|--------------------------|
| Auto-provisioned | `spec.valkeyCommanderConfig.enabled: true` on the `ValkeySentinel` | ❌ can't log in to a password-protected instance (see the caution below) |
| **Stand-alone** | a `ValkeyCommander` CR pointing at the Sentinel group ([manifest](../manifests/06-tools/05-valkey-commander.yaml)) | ✅ used in this lab |

⚠️ **Caution: the built-in Commander gets `NOAUTH` on 3.5.1.** The operator passes the data-pod credentials to the Commander pod as `VALKEY_USER` / `VALKEY_PASSWORD`, but the Commander image only reads `REDIS_USERNAME` / `REDIS_PASSWORD`. Commander logs in to Sentinel and finds the primary, then connects to it **without** a password: the UI shows `ERROR: Status: reconnecting` and `NOAUTH Authentication required.` `valkeyCommanderConfig` has no field to fix this, and on a stand-alone `ValkeyCommander` the documented `kubernetesConfig.valkeySecret` is ignored. The lab therefore deploys a stand-alone `ValkeyCommander` and passes the credentials with `spec.env`:

| Env var | Secret | Used for |
|---------|--------|----------|
| `REDIS_USERNAME` / `REDIS_PASSWORD` | `vk-sentinel-commander-valkey` (`admin`) | login to the primary and replicas |
| `SENTINEL_USERNAME` / `SENTINEL_PASSWORD` | `vk-sentinel-sentinel-credentials` (module 3) | login to Sentinel |
| (`loginSecret`) | `vk-sentinel-commander-login` (`operator`) | login to the web UI |

## 6.7 Lab: enable both consoles

```bash
# Valkey Admin: auto-provisioned by the ValkeySentinel CR
patch-sentinel.sh manifests/06-tools/04-admin-patch.yaml

# Valkey Commander: stand-alone CR with its own secrets
render manifests/06-tools/03-commander-secrets.yaml | kubectl apply -f -
render manifests/06-tools/05-valkey-commander.yaml  | kubectl apply -f -

kubectl get valkeyadmins,valkeycommanders,pods,svc -n "${VALKEY_NS}"
```

> Applying the patch prints `Warning: spec.kubernetesConfig.valkeySecret and spec.acl are both set …`. That's expected: the `valkeySecret` user (`default`) has `+@all`, so the operator heartbeat can run `PING`. Only the Admin and Commander workloads change; the data and Sentinel pods don't restart.

🔎 **Check:** `vk-sentinel-admin` and `vk-sentinel-commander-standalone` are `Running`, each with a pod and a ClusterIP Service. There's **no** `vk-sentinel-commander`: the built-in Commander isn't enabled.

**Open Valkey Admin** (port 8080):

```bash
kubectl port-forward -n "${VALKEY_NS}" "svc/${SENTINEL_NAME}-admin" 8080:8080
# browse http://localhost:8080
```

Explore: connection/topology view (primary and replicas labelled), memory and ops charts, client lists, slow log and key browsing.

**Open Valkey Commander** (port 8081):

```bash
kubectl port-forward -n "${VALKEY_NS}" "svc/${SENTINEL_NAME}-commander-standalone" 8081:8081
# browse http://localhost:8081   user: operator   password: $(cat .secrets/commander)
```

Explore: the instance tree, `app:*` keys (create one, set a TTL, watch it expire), server info and the CLI tab.

🔎 **Check:** Commander shows the instance without errors, and the primary lists Commander as a client logged in as `admin`:

```bash
vcli "$(primary_pod)" CLIENT LIST | grep redis-commander    # ... name=redis-commander ... user=admin
```

> If a console can't connect, check its pod logs (`kubectl logs -n "${VALKEY_NS}" deploy/<name>`). `NOAUTH` from Commander means the `REDIS_*` env vars are missing (the built-in Commander, or `valkeySecret` used instead of `env`). `WRONGPASS` means the secret doesn't match the ACL file. See the troubleshooting guide.

## 6.8 Valkey MCP Server (overview)

The **`ValkeyMCPServer`** CR (operator 3.5.0+) exposes a Valkey instance as tools over the **Model Context Protocol**. MCP-compatible clients and AI agents (AI IDEs, chat assistants, agent frameworks) can then read and write data and perform vector search, with optional embedding providers (Bedrock, OpenAI, Ollama or hash).

For the operator persona this means:

- it's another **client** of your instance: give it its own ACL user with the least privileges (read-only for troubleshooting assistants),
- it's another **workload** to patch (its image is in `ValkeyImageSet.spec.mcp`),
- keep it internal and authenticated, like the other consoles.

📘 [Valkey MCP Server](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/mcp-server.html)

## 6.9 Which tool for which job?

| Task | Tool | Example |
|------|------|---------|
| Who is the writer? | Sentinel via `valkey-cli` | `scli SENTINEL get-master-addr-by-name valkey-server` |
| Quick health snapshot | script | `health-check.sh` |
| Is it slow? | `valkey-cli` | `SLOWLOG GET`, `LATENCY DOCTOR`, `--latency` |
| What uses the memory? | `valkey-cli` | `MEMORY STATS`, `--bigkeys`, `--memkeys` |
| Who is connected? | `valkey-cli` / Admin | `CLIENT LIST` |
| Trends and alerting | Prometheus/Grafana | module 7 |
| Visual topology / health | Valkey Admin | port-forward 8080 |
| Browse/edit keys | Commander | port-forward 8081 |
| Why did it fail? | `kubectl logs` | module 8 |
| Capacity test | `valkey-benchmark` | `/scripts/load.sh` |
| Support case | script | `collect-diagnostics.sh` |

| | Prometheus exporter | Valkey Admin | Valkey Commander |
|-|---------------------|--------------|------------------|
| Primary use | time-series metrics | visual observability and management | web administration |
| Interface | `/metrics` on 9121 (HTTPS) | Web UI (8080) | Web UI (8081) |
| Deployment | sidecar in each data pod | separate workload | separate workload |
| Authentication | network-level | **none** (keep internal) | login secret |
| Manages backups? | no | no | no (use CRs and kubectl) |

---

[← Module 5](05-connections-and-security.md) | [README](../README.md) | Next: [Module 7: Metrics →](07-metrics-prometheus-grafana.md)

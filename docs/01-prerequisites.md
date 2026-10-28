# Module 1: Prerequisites and lab environment

[← Module 0](00-introduction-sentinel-architecture.md) | [README](../README.md) | Next: [Module 2: Install the operator →](02-install-operator.md)

**Goal:** prepare your workstation and cluster, configure `env.sh`, and confirm registry access.

📘 **Docs:** [Prerequisites](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/prerequisites.html) · [Access the artifact repository](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/artifactory-access.html)

---

## 1.1 Workstation tools

| Tool | Version | Purpose |
|------|---------|---------|
| `kubectl` | within ±1 minor of the cluster | everything |
| `helm` | 3.8 or later (OCI registry support) | operator, Prometheus, Loki |
| `envsubst` | any (package `gettext`) | renders manifests (`scripts/render.sh`) |
| `openssl` | any | generates lab passwords |
| `bash` or `zsh` | | scripts and `env.sh` |
| `curl` | any | metrics endpoint checks |
| `jq` | optional | nicer JSON output |
| VKS: `kubectl vsphere` plugin | matching your Supervisor | log in to the VKS cluster |

macOS: `brew install kubectl helm gettext jq`. Linux: use your package manager (`gettext-base` on Debian/Ubuntu).

```bash
kubectl version --client && helm version && envsubst --version | head -1
```

## 1.2 Cluster requirements

| Requirement | Workshop minimum | Why |
|-------------|------------------|-----|
| Kubernetes | 1.21 or later | operator support matrix |
| Worker nodes | **3** (4 recommended) | anti-affinity: 3 data pods and 3 Sentinels on different nodes; module 9 drains a node |
| Allocatable capacity | ~6 vCPU / 12 GiB free | Valkey (6 pods), monitoring stack, MinIO, DR lab |
| Default StorageClass | required | PVCs for Valkey, Prometheus, MinIO |
| LoadBalancer | optional | only if `SERVICE_TYPE` / `MONITORING_SERVICE_TYPE` / `MINIO_SERVICE_TYPE` = `LoadBalancer` |
| NetworkPolicy-capable CNI | optional | module 5 NetworkPolicy lab (Antrea or Calico on VKS) |
| Permissions | `cluster-admin` | the operator installs CRDs, webhooks and cluster roles |
| Egress | `tanzu-valkey.packages.broadcom.com`, `quay.io` (MinIO), `ghcr.io`/`docker.io`/`registry.k8s.io` (monitoring charts) | or mirror to an internal registry |

### Log in to the cluster

<details>
<summary><b>VKS (vSphere Kubernetes Service)</b></summary>

```bash
kubectl vsphere login --server <SUPERVISOR_IP_OR_FQDN> \
  --vsphere-username <user@vsphere.local> \
  --tanzu-kubernetes-cluster-namespace <VSPHERE_NAMESPACE> \
  --tanzu-kubernetes-cluster-name <CLUSTER_NAME> \
  --insecure-skip-tls-verify
kubectl config use-context <CLUSTER_NAME>
```
</details>

<details>
<summary><b>Any other cluster</b></summary>

Use your normal kubeconfig. For example: `aws eks update-kubeconfig ...`, `az aks get-credentials ...`, `gcloud container clusters get-credentials ...`, or `kind create cluster --config kind-3-workers.yaml` for local practice.
</details>

### Verify the cluster

```bash
kubectl get nodes -o wide
kubectl get nodes -L topology.kubernetes.io/zone        # zones (if labelled)
kubectl auth can-i '*' '*' --all-namespaces              # expect: yes
kubectl get storageclass                                 # one class must show (default)
```

🔎 **Check:** at least 3 `Ready` worker nodes and one StorageClass marked `(default)`.

**No default StorageClass?** Mark one as default:

```bash
kubectl patch storageclass <NAME> \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

> **VKS note:** StorageClasses in a VKS cluster come from the vSphere Namespace's storage policies. You can also set a default when you create the cluster (`spec.topology.variables` → `defaultStorageClass` for ClusterClass-based clusters, or `spec.settings.storage.defaultClass` for older TanzuKubernetesCluster specs).

### Pod Security Admission (VKS and other hardened clusters)

Recent VKS releases (and many hardened clusters) apply the *restricted* Pod Security Standard. Check for namespace or cluster defaults:

```bash
kubectl get ns --show-labels | grep pod-security || echo "no namespace-level PSA labels"
```

If pods in a later module are rejected with `violates PodSecurity "restricted:latest"`, relax that **specific** namespace (never cluster-wide):

```bash
# monitoring: node-exporter needs hostNetwork/hostPID
kubectl label ns monitoring pod-security.kubernetes.io/enforce=privileged --overwrite
# Valkey instance namespace, only if the operator pods are rejected
kubectl label ns valkey-workshop pod-security.kubernetes.io/enforce=baseline --overwrite
```

## 1.3 Broadcom registry access

Tanzu for Valkey images and charts are served from `tanzu-valkey.packages.broadcom.com`. You need a **Broadcom Support Portal** account entitled to Tanzu for Valkey. Generate the registry credentials (username and token) by following [Access the artifact repository](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-for-valkey-on-kubernetes/3-5/valkey-on-kubernetes/artifactory-access.html).

Export them in your shell. Do **not** write them into files you commit:

```bash
export REGISTRY_USERNAME='<your-username>'
export REGISTRY_PASSWORD='<your-token>'
```

## 1.4 Configure `env.sh`

Open [`env.sh`](../env.sh) and review the **EDIT ME** section:

| Variable | Default | Change it when… |
|----------|---------|-----------------|
| `OPERATOR_NS` | `tanzu-for-valkey-on-kubernetes` | your org mandates a different namespace |
| `OPERATOR_VERSION` | `3.5.1` | a newer 3.5.x is available |
| `CLUSTER_DOMAIN` | `cluster.local` | your cluster uses a custom DNS suffix (`kubectl run -it --rm dns --image=busybox --restart=Never -- cat /etc/resolv.conf`) |
| `VALKEY_NS` | `valkey-workshop` | several students share one cluster (use `valkey-<name>`) |
| `VALKEY_VERSION` | `valkey-9.0.6` | not listed by `kubectl get valkeyversions` (module 2) |
| `VALKEY_TARGET_VERSION` | `valkey-9.1.2` | must be newer than `VALKEY_VERSION` |
| `STORAGE_SIZE` | `2Gi` | larger datasets |
| `SERVICE_TYPE` | `ClusterIP` | you want external access for apps outside the cluster |
| `MONITORING_SERVICE_TYPE` | `ClusterIP` | `LoadBalancer` saves port-forwarding to Grafana |
| `MINIO_SERVICE_TYPE` | `ClusterIP` | `LoadBalancer` saves port-forwarding to the MinIO console (module 10) |
| `DR_NS` / `DR_CONTEXT` | `valkey-workshop-dr` / empty | you have a second cluster for the DR lab |

> **Sharing one cluster between students?** Each student sets a unique `VALKEY_NS`, `DR_NS` and `MINIO_NS`. The operator and the monitoring stack are installed once by the instructor.

Load the environment. Do this in **every** new terminal:

```bash
cd valkey-workshop-sentinel
source ./env.sh
```

🔎 **Check:**

```
Workshop environment loaded (WORKSHOP_HOME=/.../valkey-workshop-sentinel)
  Valkey namespace : valkey-workshop   Sentinel: vk-sentinel   Replication: vk-repl
  kube context     : <your-cluster>
```

`env.sh` generates random lab passwords once and stores them in `.secrets/` (mode 700). To see one:

```bash
cat .secrets/admin
```

⚠️ **Caution:** `.secrets/` is for the lab only. In production, store credentials in a secrets manager (Vault, AWS Secrets Manager, CyberArk, …) and sync them into Kubernetes with External Secrets Operator or a CSI driver. Never commit them to Git.

## 1.5 cert-manager

The operator uses cert-manager by default for its admission-webhook certificate. Module 5 also uses it to issue Valkey TLS certificates.

```bash
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager not installed"
```

**If it is missing**, install it. On VKS you can instead install the **cert-manager VKS standard package** if that is your platform standard.

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait
kubectl get pods -n cert-manager
```

> No cert-manager allowed? Install the operator with `--set certManager.enabled=false` (module 2). The operator then generates and renews a self-signed webhook certificate itself. You can still use your own certificates for Valkey TLS.

## 1.6 Helm repositories for supporting components

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## 1.7 Checklist

- [ ] `kubectl get nodes` shows ≥ 3 Ready workers
- [ ] A default StorageClass exists
- [ ] `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` exported
- [ ] `source ./env.sh` works and shows the right context
- [ ] cert-manager is running (or you will use `certManager.enabled=false`)
- [ ] Helm repos added

---

[← Module 0](00-introduction-sentinel-architecture.md) | [README](../README.md) | Next: [Module 2: Install the operator →](02-install-operator.md)

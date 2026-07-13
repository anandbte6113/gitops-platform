# GitOps Platform — Personal Documentation

> Living document. Updated as the project is built.
> Covers: decisions made, problems encountered, fixes applied, interview insights, architecture, setup guide.

---

## Table of Contents

1. [What This Project Is](#1-what-this-project-is)
2. [Architecture](#2-architecture)
3. [Tooling — What, Why, How](#3-tooling--what-why-how)
4. [Phase 1 — Infrastructure Setup](#4-phase-1--infrastructure-setup)
5. [Phase 2 — App-of-Apps Bootstrap](#5-phase-2--app-of-apps-bootstrap)
6. [Phase 3 — api-gateway](#6-phase-3--api-gateway)
7. [Phase 4 — user-service](#7-phase-4--user-service)
8. [Phase 5 — order-service](#8-phase-5--order-service)
9. [Phase 6 — Sync Policies](#9-phase-6--sync-policies)
10. [Phase 7 — Documentation Files](#10-phase-7--documentation-files)
11. [Problems Encountered & Fixes](#11-problems-encountered--fixes)
12. [Interview Prep — Q&A](#12-interview-prep--qa)
13. [Setup Guide — Run on Any Machine](#13-setup-guide--run-on-any-machine)

---

## 1. What This Project Is

A production-grade GitOps platform built locally using ArgoCD. It manages 3 microservices deployed
across 2 environments (dev + staging) on 3 local Kubernetes clusters — all running on your laptop
via Docker.

**The core idea:** Git is the single source of truth. You push a change to Git, ArgoCD detects it
and applies it to the cluster. No manual `kubectl apply`. No ad-hoc changes. Everything is
declarative, versioned, and auditable.

**Why build this:** To demonstrate every major ArgoCD enterprise pattern in one repo — so you can
talk about it in depth in interviews, not just say "I've used ArgoCD."

---

## 2. Architecture

```
                     [ GitHub Repo: gitops-platform ]
                                  |
                          ONE kubectl apply
                          (root-app.yaml)
                                  |
                     [ ArgoCD on management-cluster ]
                                  |
                App-of-Apps syncs argocd/ directory
                                  |
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
 AppProject: dev        AppProject: staging     ApplicationSet
 RBAC policies          RBAC policies            (scans services/*)
 Sealed Secrets ctrl                                      │
 ESO ctrl + Store                         ┌──────────────┼──────────────┐
                                          │              │              │
                                    api-gateway    user-service   order-service
                                          │              │              │
                                ┌─────────┴──┐   ┌───────┴──┐  ┌───────┴──┐
                              dev-cluster  staging  dev  staging  dev  staging
```

### How It All Chains Together

```
1 kubectl apply root-app.yaml
  → ArgoCD watches argocd/ directory         [App-of-Apps pattern]
      → Creates AppProjects + RBAC + controllers + ApplicationSet
          → ApplicationSet scans services/*  [ApplicationSet pattern]
              → Generates one Application per service × per environment
                  → All 3 services deployed to dev-cluster AND staging-cluster
```

### Three Clusters

| Cluster | Purpose |
|---------|---------|
| `management-cluster` | Runs ArgoCD itself. Does not run application workloads. |
| `dev-cluster` | Runs dev environment. AutoSync ON — Git push = instant deploy. |
| `staging-cluster` | Runs staging environment. AutoSync OFF — requires manual approval. |

### Three Services

| Service | Image | Templating | Secrets Method |
|---------|-------|-----------|----------------|
| `api-gateway` | nginx | Kustomize | Sealed Secrets |
| `user-service` | kennethreitz/httpbin | Kustomize | ESO → LocalStack |
| `order-service` | postgres | Helm | ESO → LocalStack + PreSync migration |

---

## 3. Tooling — What, Why, How

### docker
**What:** Container runtime.
**Why:** `kind` creates Kubernetes clusters as Docker containers. Without Docker, no clusters.
**Installed:** Pre-installed on this machine.

### kind (Kubernetes IN Docker)
**What:** Creates real Kubernetes clusters that run entirely inside Docker containers.
**Why:** We need 3 clusters (management, dev, staging) but have no cloud account. `kind` simulates
multi-cluster locally — each cluster is a Docker container running a full K8s control plane.
**Why not minikube:** minikube creates one cluster. `kind` can create many named clusters on the
same machine, which is exactly what multi-cluster GitOps needs.
**Installed to:** `~/.local/bin/kind` (no sudo required)

### kubectl
**What:** The standard Kubernetes CLI — apply manifests, check pods, read logs.
**Why:** How you talk to any Kubernetes cluster.
**Installed:** Pre-installed on this machine.

### argocd (CLI)
**What:** ArgoCD's command-line client.
**Why:** ArgoCD itself runs as pods inside `management-cluster`. The CLI lets you interact with it
from your terminal — login, trigger syncs, check app health, view diffs. Think of it as the
`kubectl` specifically for ArgoCD objects.
**Installed to:** `~/.local/bin/argocd`

### helm
**What:** Kubernetes package manager. Templates YAML with values files.
**Why:** `order-service` is deployed as a Helm chart to demonstrate that ArgoCD handles both
Kustomize and Helm natively.
**Installed:** Pre-installed on this machine.

### kubeseal
**What:** CLI for the Sealed Secrets system. Encrypts a plain Kubernetes Secret into a
`SealedSecret` that is safe to commit to Git.
**Why:** You never commit raw secrets to Git. `kubeseal` uses the public key from the Sealed
Secrets controller running in the cluster to encrypt the secret. Only that controller can decrypt
it. Even if someone steals your Git repo, they get ciphertext.
**How it works:**
```
You create a plain Secret YAML → kubeseal encrypts it with cluster's public key
→ SealedSecret YAML (safe to commit) → ArgoCD applies it to cluster
→ Sealed Secrets controller decrypts it → real K8s Secret appears in cluster
```
**Installed to:** `~/.local/bin/kubeseal`

### aws CLI
**What:** AWS command-line tool.
**Why:** We use LocalStack (a local AWS simulator) to simulate AWS Secrets Manager. The `aws` CLI
talks to LocalStack to create/read secrets — same commands as real AWS, just pointed at localhost.
**Installed:** Pre-installed on this machine.

---

## 4. Phase 1 — Infrastructure Setup

### Goal
Create 3 kind clusters + install ArgoCD on management-cluster + start LocalStack.

### Steps

#### Step 1 — Create 3 kind clusters
**Status: DONE**

Commands run:
```bash
kind create cluster --name management-cluster
kind create cluster --name dev-cluster
kind create cluster --name staging-cluster
```

Verified with:
```bash
kind get clusters
# Output:
# dev-cluster
# management-cluster
# staging-cluster
```

**Docker containers created (one per cluster):**
```
NAMES                              IMAGE                  STATUS         SIZE
staging-cluster-control-plane      kindest/node:v1.30.0   Up 8 minutes   2.89MB (virtual 977MB)
dev-cluster-control-plane          kindest/node:v1.30.0   Up 8 minutes   2.89MB (virtual 977MB)
management-cluster-control-plane   kindest/node:v1.30.0   Up 8 minutes   2.89MB (virtual 977MB)
```
- Image: `kindest/node:v1.30.0` — Kubernetes v1.30.0 node image
- SIZE 2.89MB = writable layer on top of the shared base image. Virtual 977MB = full image size on disk (shared across all 3 containers — not 3×977MB)

**Resource consumption per cluster:**
```
NAME                               CPU %     MEM USAGE / LIMIT     MEM %
staging-cluster-control-plane      9.70%     881MiB / 23.15GiB     3.72%
dev-cluster-control-plane          10.99%    862.6MiB / 23.15GiB   3.64%
management-cluster-control-plane   8.88%     871.9MiB / 23.15GiB   3.68%
```
- Each cluster consumes ~870MB RAM and ~9-11% CPU at idle
- Total for 3 clusters: ~2.6GB RAM — well within the 23GB available on this machine

**What Kubernetes created inside management-cluster (`kubectl get all -A`):**
```
NAMESPACE            RESOURCE                                          WHAT IT IS
kube-system          pod/coredns (x2)                                  DNS for the cluster — resolves service names to IPs
kube-system          pod/etcd                                          The database — stores all cluster state
kube-system          pod/kindnet                                       CNI network plugin — handles pod networking
kube-system          pod/kube-apiserver                                The API server — everything talks to this
kube-system          pod/kube-controller-manager                       Reconciliation loops — keeps desired state = actual state
kube-system          pod/kube-proxy                                    Handles network rules for Services on each node
kube-system          pod/kube-scheduler                                Assigns pods to nodes
local-path-storage   pod/local-path-provisioner                        Auto-provisions PersistentVolumes using local disk
```

**Contexts added to ~/.kube/config:**
```
kind-dev-cluster          ← switch with: kubectl config use-context kind-dev-cluster
kind-management-cluster   ← switch with: kubectl config use-context kind-management-cluster
kind-staging-cluster      ← switch with: kubectl config use-context kind-staging-cluster
```
Note: This machine also has existing EKS, ArgoCD hub, minikube, and Nebius contexts — our kind clusters are just 3 more entries alongside them.

#### Step 2 — Install ArgoCD on management-cluster
**Status: DONE**

Commands run:
```bash
kubectl config use-context kind-management-cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/install.yaml
kubectl get pods -n argocd -w
```

All 7 pods reached Running state (~2.5 min):
```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m28s
argocd-applicationset-controller-8485455fd5-m75j6   1/1     Running   0          2m29s
argocd-dex-server-66779d96df-f96dg                  1/1     Running   0          2m29s
argocd-notifications-controller-c4b69fb67-fl526     1/1     Running   0          2m29s
argocd-redis-7bf7cb9748-mvtcb                       1/1     Running   0          2m29s
argocd-repo-server-795d79dfb6-vbgdc                 1/1     Running   0          2m28s
argocd-server-544b7f897d-gw8w2                      1/1     Running   0          2m28s
```

**What each pod does:**
| Pod | Role |
|-----|------|
| argocd-application-controller | The brain — watches Git + cluster, computes diffs, triggers syncs |
| argocd-applicationset-controller | Handles ApplicationSet CRDs — generates Applications from templates |
| argocd-dex-server | SSO/auth — handles login via GitHub, LDAP, OIDC |
| argocd-notifications-controller | Sends Slack/email alerts on sync events |
| argocd-redis | Cache — stores app state so controller doesn't re-query everything constantly |
| argocd-repo-server | Clones Git repos, renders Helm/Kustomize templates, returns plain YAML |
| argocd-server | The API + UI server — what you talk to via browser or argocd CLI |

**Registering dev-cluster and staging-cluster with ArgoCD:**
*(see Problem 2 in Section 11 for full troubleshooting trail)*

Final working commands:
```bash
DEV_IP=$(docker inspect dev-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')
STAGING_IP=$(docker inspect staging-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')

kubectl config view --context kind-dev-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${DEV_IP}:6443|g" > /tmp/dev-patched.yaml

kubectl config view --context kind-staging-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${STAGING_IP}:6443|g" > /tmp/staging-patched.yaml

KUBECONFIG=/tmp/dev-patched.yaml argocd cluster add kind-dev-cluster --name dev-cluster --upsert
KUBECONFIG=/tmp/staging-patched.yaml argocd cluster add kind-staging-cluster --name staging-cluster --upsert
```

Final verified state:
```
SERVER                          NAME             VERSION  STATUS
https://172.19.0.3:6443         dev-cluster      1.30     Successful
https://172.19.0.4:6443         staging-cluster  1.30     Successful
https://kubernetes.default.svc  in-cluster       1.30     Successful
```

Note: `/tmp` files are wiped on session end. These commands must be re-run after every reboot.
Will be automated in `bootstrap/01-create-clusters.sh`.

#### Step 3 — Start LocalStack + seed secrets
**Status: DONE**

```bash
docker run -d \
  --name localstack \
  --network kind \
  -p 4566:4566 \
  -e SERVICES=secretsmanager \
  localstack/localstack:3.0
```

`--network kind` puts LocalStack on the same Docker bridge as all kind clusters so pods can reach it at `http://localstack:4566` from inside the cluster.

Seeded 2 secrets:
```bash
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name user-service/db-password \
  --secret-string '{"password":"userpass123"}' \
  --region us-east-1

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name order-service/db-credentials \
  --secret-string '{"username":"orderuser","password":"orderpass123"}' \
  --region us-east-1
```

Verified:
```json
["user-service/db-password", "order-service/db-credentials"]
```

Note: curl to `/_localstack/health` got "connection reset" initially — LocalStack was still warming up despite Docker reporting healthy. The real readiness test is `aws secretsmanager list-secrets`.

#### Step 4 — Verify all clusters accessible
**Status: DONE**

```
kind clusters:     dev-cluster, management-cluster, staging-cluster
argocd clusters:   dev-cluster (Successful), staging-cluster (Successful), in-cluster (Successful)
localstack:        running on kind Docker bridge, secretsmanager seeded
```

Phase 1 complete.

---

## 5. Phase 2 — App-of-Apps Bootstrap

*(pending)*

---

## 6. Phase 3 — api-gateway

*(pending)*

---

## 7. Phase 4 — user-service

*(pending)*

---

## 8. Phase 5 — order-service

*(pending)*

---

## 9. Phase 6 — Sync Policies

*(pending)*

---

## 10. Phase 7 — Documentation Files

*(pending)*

---

## 11. Problems Encountered & Fixes

### Problem 1 — No sudo for tool installation
**Phase:** Phase 1 (tool install)
**What happened:** Tried to extract kubeseal to `/usr/local/bin` — got `Permission denied`.
**Why it happened:** This machine doesn't grant sudo to the user.
**Fix:** Install all user-space binaries to `~/.local/bin` instead, and add that to `$PATH` in
`~/.bashrc`.
```bash
mkdir -p ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```
**Lesson:** On shared/enterprise machines, always check sudo access first. `~/.local/bin` is the
standard user-local binary directory on Linux — it's the right place for this anyway.

---

### Problem 2 — ArgoCD cannot reach kind clusters (127.0.0.1 loopback issue)
**Phase:** Phase 1 — registering dev/staging clusters with ArgoCD

**What we were trying to do:**
Register dev-cluster and staging-cluster into ArgoCD so it can deploy workloads there.
Command: `argocd cluster add kind-dev-cluster --name dev-cluster`

**What happened:**
```
FATA[0015] rpc error: code = Unknown desc = Get "https://127.0.0.1:40105/version?timeout=32s": 
dial tcp 127.0.0.1:40105: connect: connection refused
```

**Why it happened:**
kind clusters use `https://127.0.0.1:<random-port>` in kubeconfig — that address works from the host machine because kind port-forwards the cluster API server to localhost.
But ArgoCD runs as a pod INSIDE management-cluster. From inside a pod, `127.0.0.1` = the pod's own loopback, not the host. So ArgoCD dials itself and gets connection refused.

```
Host machine:   127.0.0.1:40105  →  kind port-forward  →  dev-cluster API server  ✓
ArgoCD pod:     127.0.0.1:40105  →  pod's own loopback  →  nothing                ✗
```

---

**Attempt 1 — Pass internal Docker IP via `--server` flag:**
```bash
argocd cluster add kind-dev-cluster --name dev-cluster --server https://172.19.0.4:6443
```
**Error:**
```
FATA[0008] Failed to establish connection to https://172.19.0.4:6443: 
dial tcp: address https://172.19.0.4:6443: too many colons in address
```
**Why it failed:** `--server` in `argocd cluster add` means the ArgoCD server address (where to connect to ArgoCD), NOT the address of the cluster being registered. Wrong flag entirely.

---

**Attempt 2 — Use `kind get kubeconfig --internal`:**
```bash
kind get kubeconfig --name dev-cluster --internal > /tmp/dev-kubeconfig.yaml
KUBECONFIG=/tmp/dev-kubeconfig.yaml argocd cluster add kind-dev-cluster --name dev-cluster --upsert
```
**Error:**
```
FATA[0001] Failed to create service account "argocd-manager" in namespace "kube-system": 
Post "https://dev-cluster-control-plane:6443/...": 
dial tcp: lookup dev-cluster-control-plane on 127.0.0.53:53: server misbehaving
```
**Why it failed:** `kind get kubeconfig --internal` replaces the address with the Docker container hostname `dev-cluster-control-plane`. That hostname is only resolvable inside the Docker network (Docker has internal DNS for container names). The host terminal's DNS (`127.0.0.53`) has no idea what `dev-cluster-control-plane` is.

---

**Attempt 3 — Patch the kubeconfig with the Docker internal IP (WORKS):**

The Docker bridge network IP (`172.19.0.x`) is reachable from BOTH:
- The host machine (Linux Docker bridge is accessible from host)
- ArgoCD pods inside management-cluster (all kind clusters share the same Docker bridge network)

So patch the host kubeconfig to swap `127.0.0.1:<random-port>` → `172.19.0.x:6443`:

```bash
DEV_IP=$(docker inspect dev-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')
STAGING_IP=$(docker inspect staging-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')

kubectl config view --context kind-dev-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${DEV_IP}:6443|g" > /tmp/dev-patched.yaml

kubectl config view --context kind-staging-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${STAGING_IP}:6443|g" > /tmp/staging-patched.yaml

KUBECONFIG=/tmp/dev-patched.yaml argocd cluster add kind-dev-cluster --name dev-cluster --upsert
KUBECONFIG=/tmp/staging-patched.yaml argocd cluster add kind-staging-cluster --name staging-cluster --upsert
```

**Why this works:**
```
Host CLI:        172.19.0.x:6443  →  Docker bridge  →  dev-cluster container  ✓  (creates ServiceAccount)
ArgoCD pod:      172.19.0.x:6443  →  Docker bridge  →  dev-cluster container  ✓  (syncs apps)
```

**Lesson:** When running ArgoCD inside kind (local multi-cluster), never use kubeconfig addresses that reference `127.0.0.1` or container hostnames. Always use the Docker bridge IP (`docker inspect ... .NetworkSettings.Networks.kind.IPAddress`) with port 6443. Keep the patched kubeconfig files — you'll need them if clusters restart and IPs change.

---

## 12. Interview Prep — Q&A

### Q: What is GitOps?
**A:** GitOps is an operational pattern where Git is the single source of truth for infrastructure
and application state. You declare what you want in Git. An operator (ArgoCD) continuously watches
Git and ensures the cluster matches it. Changes happen by merging PRs — not by running kubectl
commands manually. Benefits: full audit trail, rollback = git revert, no config drift.

### Q: What is ArgoCD?
**A:** ArgoCD is a GitOps continuous delivery tool for Kubernetes. It runs inside your cluster,
watches a Git repo, computes the diff between desired state (Git) and actual state (cluster), and
syncs the cluster to match Git. It provides a UI, CLI, and API.

### Q: What is the App-of-Apps pattern?
**A:** You create one "root" ArgoCD Application that points to a directory containing other
Application manifests. ArgoCD syncs the root app, which creates all the child apps. This means
one `kubectl apply` bootstraps the entire platform. Adding a new app = adding a YAML file to that
directory.

### Q: What is an ApplicationSet?
**A:** An ArgoCD CRD that generates multiple Application objects from a template + a generator.
Instead of writing one Application per service per environment (which doesn't scale), you write one
ApplicationSet with a Matrix generator: services × clusters. When you add a new service directory,
the ApplicationSet automatically generates Applications for it in every environment.

### Q: What's the difference between Sealed Secrets and ESO?
**A:** Both solve "don't commit plain secrets to Git" but differently:
- **Sealed Secrets:** Encrypt the secret value at rest in Git. The secret lives in Git as
  ciphertext. Simple, self-contained, but the value is static — rotation means re-encrypting and
  re-committing.
- **ESO (External Secrets Operator):** Git stores only a *pointer* to a secret in an external
  store (AWS Secrets Manager, Vault, etc.). ESO fetches the actual value at runtime and creates a
  K8s Secret. Better for rotation — update the value in the secret store, ESO syncs automatically.

### Q: What are PreSync hooks and why do you need them for DB migrations?
**A:** ArgoCD sync hooks let you run a Job at a specific point in the sync lifecycle. `PreSync` runs
before any other resources are applied. For DB migrations: you want the migration Job to complete
successfully *before* the new version of the application pod starts. If you deployed both together,
the new pod could start against a schema it doesn't understand, causing errors. The wave system
(wave 0 = migration, wave 1 = deployment) enforces this ordering.

### Q: Why does dev have AutoSync ON but staging has it OFF?
**A:** AutoSync means ArgoCD automatically applies changes when it detects a Git diff — no human
approval needed. In dev, speed matters — developers want instant feedback. In staging, you're
testing release candidates and need a human to deliberately trigger the deploy after validation.
AutoSync in staging risks deploying broken changes automatically to an environment that mirrors
production.

### Q: What are AppProjects?
**A:** AppProjects are ArgoCD's multi-tenancy mechanism. They define:
- Which Git repos an Application can source from
- Which clusters/namespaces it can deploy to
- What Kubernetes resources it's allowed to create
- Which users/teams have access
In this project: the dev-project only allows deploying to dev-cluster, and staging-project only to
staging-cluster. This prevents a misconfigured dev Application from accidentally deploying to staging.

### Q: What does `kind create cluster --name management-cluster` actually do?
**A:** Kind = Kubernetes IN Docker. When you run that command:
1. Docker pulls a "node image" — a container image that has a full Kubernetes node baked in (kubelet, etcd, API server, scheduler, controller-manager)
2. Starts one Docker container named `management-cluster-control-plane` — this container IS the cluster
3. Runs kubeadm inside the container to bootstrap Kubernetes
4. Writes a new context `kind-management-cluster` to `~/.kube/config` so kubectl knows how to reach it

```
Docker container: management-cluster-control-plane
  └── kube-apiserver, etcd, scheduler, controller-manager, kubelet
kubectl context: kind-management-cluster
```

We run this 3 times with different names → 3 independent clusters, all as Docker containers on one laptop.

### Q: How does kubeseal work exactly?
**A:** kubeseal solves "I need secrets in Git but can't commit plain text." Here's the exact flow:

```
Step 1: Sealed Secrets controller installs into your cluster
        → Generates a public/private keypair on first boot
        → Private key stays INSIDE the cluster forever (never leaves)
        → Public key is fetchable by anyone with kubectl access

Step 2: You have a plain Secret YAML on your laptop
        → Run: kubeseal --fetch-cert   (fetches the cluster's public key)
        → Run: kubeseal < plain-secret.yaml > sealed-secret.yaml
        → kubeseal encrypts the secret values using that public key

Step 3: sealed-secret.yaml looks like this — safe to commit to Git:
        apiVersion: bitnami.com/v1alpha1
        kind: SealedSecret
        spec:
          encryptedData:
            api-key: AgBx9z3K....(long encrypted blob)....

Step 4: ArgoCD applies sealed-secret.yaml to the cluster
        → Sealed Secrets controller decrypts it with its private key
        → Creates a real K8s Secret automatically
        → Your pod reads the Secret normally — it never knew about SealedSecrets
```

Security guarantee: The encrypted blob is useless without the private key, which never leaves the cluster.

In this project: used for api-gateway's API key. We seal it separately against dev-cluster and staging-cluster keys (each cluster has its own keypair), producing two different sealed files committed to `secrets/sealed/dev/` and `secrets/sealed/staging/`.

---

## 13. Setup Guide — Run on Any Machine

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker | 20+ | https://docs.docker.com/get-docker/ |
| kind | v0.23.0 | `curl -sLo ~/.local/bin/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64 && chmod +x ~/.local/bin/kind` |
| kubectl | any recent | https://kubernetes.io/docs/tasks/tools/ |
| argocd CLI | v2.11.3 | `curl -sLo ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v2.11.3/argocd-linux-amd64 && chmod +x ~/.local/bin/argocd` |
| helm | v3+ | https://helm.sh/docs/intro/install/ |
| kubeseal | v0.26.3 | See below |
| aws CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |

**kubeseal install (no sudo):**
```bash
curl -sLo /tmp/kubeseal.tar.gz https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/kubeseal-0.26.3-linux-amd64.tar.gz
tar -xzf /tmp/kubeseal.tar.gz -C ~/.local/bin kubeseal
chmod +x ~/.local/bin/kubeseal
```

**Add ~/.local/bin to PATH if needed:**
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### Full Setup Steps

```bash
# 1. Clone the repo
git clone <repo-url>
cd gitops-platform

# 2. Create the 3 clusters
bash bootstrap/01-create-clusters.sh

# 3. Install ArgoCD on management cluster
bash bootstrap/02-install-argocd.sh

# 4. Start LocalStack and seed secrets
bash bootstrap/03-setup-localstack.sh

# 5. Bootstrap the entire platform with one command
bash bootstrap/04-apply-root-app.sh
```

*(Bootstrap scripts will be documented here as they are written)*

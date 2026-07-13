# GitOps Platform

A production-grade GitOps platform using ArgoCD managing 3 microservices across dev and staging environments on local Kubernetes clusters. Demonstrates every major ArgoCD enterprise pattern in a single repository.

## Architecture

```
                     [ GitHub Repo: gitops-platform ]
                                  |
                          ONE kubectl apply
                          (root-app.yaml)
                                  |
                     [ ArgoCD — management-cluster ]
                                  |
                App-of-Apps syncs argocd/ directory
                                  |
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
 AppProject: dev        AppProject: staging     ApplicationSets
 Sealed Secrets ctrl    Sealed Secrets ctrl     (scan services/*)
 ESO + ClusterStore     ESO + ClusterStore
          │                       │
    dev-cluster            staging-cluster
    ├── api-gateway         ├── api-gateway
    ├── user-service        ├── user-service
    └── order-service       └── order-service
```

### Patterns Demonstrated

| Pattern | Where |
|---------|-------|
| App-of-Apps | `root-app.yaml` → `argocd/` |
| ApplicationSets | `argocd/applicationsets/` — Matrix generator, auto-discovery |
| Kustomize (base + overlays) | All 3 services in `services/` |
| Sealed Secrets | `api-gateway` — encrypted secret safe to commit |
| External Secrets Operator | `user-service`, `order-service` → LocalStack |
| PreSync Hooks + Waves | `order-service` migration job runs before deployment |
| AppProjects + RBAC | `argocd/projects/` + `argocd/rbac/` |
| AutoSync dev / Manual staging | `microservices-dev` vs `microservices-staging` ApplicationSet |
| Multi-cluster | management + dev + staging kind clusters |

---

## Prerequisites

| Tool | Version |
|------|---------|
| Docker | 20+ |
| kind | v0.23.0 |
| kubectl | any recent |
| argocd CLI | v2.11.3 |
| helm | v3+ |
| kubeseal | v0.26.3 |
| aws CLI | v2 |

### Install tools (no sudo)
```bash
mkdir -p ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# kind
curl -sLo ~/.local/bin/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64 && chmod +x ~/.local/bin/kind

# argocd CLI
curl -sLo ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v2.11.3/argocd-linux-amd64 && chmod +x ~/.local/bin/argocd

# kubeseal
curl -sLo /tmp/kubeseal.tar.gz https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/kubeseal-0.26.3-linux-amd64.tar.gz
tar -xzf /tmp/kubeseal.tar.gz -C ~/.local/bin kubeseal && chmod +x ~/.local/bin/kubeseal
```

---

## Setup

```bash
git clone https://github.com/anandbte6113/gitops-platform.git
cd gitops-platform

# Step 1: Create clusters, install ArgoCD, start LocalStack, register clusters
bash bootstrap/01-create-clusters.sh

# Step 2: Bootstrap entire platform with one command
bash bootstrap/02-apply-root-app.sh

# Step 3: Seal the api-gateway secrets (after Sealed Secrets controllers are ready)
bash bootstrap/03-seal-secrets.sh
git add services/api-gateway/overlays/
git commit -m "Add sealed secrets"
git push
```

### Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Repository Structure

```
gitops-platform/
├── root-app.yaml                    ← apply this once to bootstrap everything
├── argocd/                          ← managed by root-app
│   ├── kustomization.yaml
│   ├── projects/                    ← AppProjects (dev, staging)
│   ├── rbac/                        ← RBAC policies
│   ├── controllers/                 ← ESO + Sealed Secrets per cluster
│   ├── secret-stores/               ← ClusterSecretStore → LocalStack
│   ├── cluster-config/              ← Per-cluster setup Applications
│   └── applicationsets/             ← Auto-generates service Applications
├── services/                        ← managed by ApplicationSets
│   ├── api-gateway/                 ← Kustomize + Sealed Secrets
│   ├── user-service/                ← Kustomize + ESO
│   └── order-service/               ← Kustomize + ESO + PreSync migration
├── cluster-config/                  ← ClusterSecretStore manifests per cluster
│   ├── dev/
│   └── staging/
├── bootstrap/                       ← one-time setup scripts
├── docs/
│   ├── architecture.md
│   ├── troubleshooting-runbook.md
│   └── dr-runbook.md
└── DOCUMENTATION.md                 ← living build journal with interview Q&A
```

---

## Key Operational Commands

```bash
# Switch cluster context
kubectl config use-context kind-management-cluster
kubectl config use-context kind-dev-cluster
kubectl config use-context kind-staging-cluster

# Check all ArgoCD apps
argocd app list

# Sync an app manually (staging)
argocd app sync order-service-staging

# Check app diff before syncing
argocd app diff user-service-staging

# Watch pods on dev cluster
kubectl get pods -A --context kind-dev-cluster -w

# Check ExternalSecret sync status
kubectl get externalsecret -n user-service --context kind-dev-cluster

# Rotate a secret (update in LocalStack, ESO auto-syncs within 1h)
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
  --secret-id user-service/db-password \
  --secret-string '{"password":"newpassword456"}' \
  --region us-east-1
```

---

## Interview Talking Points

- **"Bootstrapped entire platform with one `kubectl apply`"** — App-of-Apps pattern, `root-app.yaml`
- **"Adding a new service = adding a directory"** — ApplicationSet auto-discovers `services/*`
- **"PreSync hooks ensure migrations complete before pods start"** — order-service wave 0 = migration, wave 1 = deployment
- **"Two secret patterns for different use cases"** — Sealed Secrets for static secrets, ESO for rotation
- **"Dev auto-deploys, staging requires approval"** — demonstrates AutoSync risk tradeoff
- **"AppProjects prevent cross-environment accidents"** — dev-project locked to dev-cluster only

See `DOCUMENTATION.md` for full build journal, troubleshooting history, and detailed Q&A.

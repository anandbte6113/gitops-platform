# GitOps Platform — Project Plan

## What This Project Is

A production-grade GitOps platform using ArgoCD managing 3 microservices across 2 environments
(dev + staging) on local Kubernetes clusters. Every enterprise ArgoCD pattern is demonstrated in
one GitHub repo — built to showcase on a resume and explain in interviews.

---

## Resume Description

> "Designed and implemented a production-grade GitOps platform using ArgoCD managing
> multi-environment Kubernetes deployments across multiple clusters. Implemented App-of-Apps
> bootstrap pattern, ApplicationSets for automated application generation, PreSync hooks for
> zero-downtime database migrations, Sealed Secrets and External Secrets Operator for secure
> credential management, and AppProjects with RBAC for multi-tenant isolation."

---

## What Each Module Is Demonstrated By

| Module | Topic | Demonstrated By |
|--------|-------|----------------|
| 1 — Architecture | API Server, Repo Server, App Controller, Redis | ArgoCD install, documented in README |
| 2 — GitOps Core | Git as source of truth, 3-way diff | Every change flows Git → ArgoCD → cluster |
| 3 — App Lifecycle | Application CRDs | argocd/ directory, Application objects |
| 4 — Sync Mechanics | AutoSync, Prune, Self-Heal | dev=AutoSync ON, staging=AutoSync OFF |
| 5 — Templating | Helm + Kustomize | api-gateway/user-service=Kustomize, order-service=Helm |
| 6 — Advanced Sync | PreSync hooks, Waves | DB migration Job in order-service Helm chart |
| 7 — Multi-cluster | AppProjects, RBAC, cluster secrets | dev-project + staging-project, argocd-rbac-cm |
| 8 — Secrets | Sealed Secrets + ESO | api-gateway=Sealed Secrets, user/order-service=ESO |
| 9 — App-of-Apps + ApplicationSets | Both patterns | root-app.yaml + microservices-appset.yaml |
| 10 — Scaling | Sharding, processors, Redis | ArgoCD StatefulSet config + docs |
| 11 — Troubleshooting | 5 real scenarios | docs/troubleshooting-runbook.md |
| 12 — DR | Backup + recovery | docs/dr-runbook.md + backup script |

---

## Architecture

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

### Pattern Chain
```
1 kubectl apply (root-app.yaml)
  → ArgoCD syncs argocd/ directory  [App-of-Apps]
      → Creates AppProjects, RBAC, controllers, AND the ApplicationSet
          → ApplicationSet scans services/*  [ApplicationSets]
              → Generates Application CRDs per service × per cluster
                  → All microservices deployed to dev + staging
```

---

## Local Tooling Required

```bash
docker          # for kind clusters + LocalStack
kind            # Kubernetes in Docker (multi-cluster simulation)
kubectl
argocd          # ArgoCD CLI
helm
kubeseal        # for Sealed Secrets
aws CLI         # for LocalStack (AWS Secrets Manager simulation)
```

### Three Clusters (all local via kind)
```
management-cluster   ← ArgoCD runs here
dev-cluster          ← dev environment workloads
staging-cluster      ← staging environment workloads
```

---

## Services

### api-gateway
- **Image:** nginx (simulates an API gateway)
- **Templating:** Kustomize (base + dev/staging overlays)
- **Secrets:** Sealed Secrets (API key)
- **Sync:** AutoSync ON in dev, OFF in staging

### user-service
- **Image:** kennethreitz/httpbin (real HTTP API, curl-able)
- **Templating:** Kustomize (base + dev/staging overlays)
- **Secrets:** ESO → LocalStack (DB password with auto-rotation)
- **Sync:** AutoSync ON in dev, OFF in staging

### order-service
- **Image:** postgres (demonstrates DB with migrations)
- **Templating:** Helm chart
- **Secrets:** ESO → LocalStack (DB credentials)
- **Hooks:** PreSync Job (DB migration before deploy)
- **Waves:** wave 0 = migration job, wave 1 = deployment
- **Sync:** AutoSync ON in dev, OFF in staging

---

## Final Repo Structure

```
gitops-platform/
├── README.md                              ← architecture + setup guide
├── PLAN.md                                ← this file
│
├── bootstrap/                             ← run once to set up local environment
│   ├── 01-create-clusters.sh             ← kind: management + dev + staging
│   ├── 02-install-argocd.sh              ← install ArgoCD on management cluster
│   ├── 03-setup-localstack.sh            ← start LocalStack, create secrets in it
│   └── 04-apply-root-app.sh              ← kubectl apply root-app.yaml
│
├── root-app.yaml                          ← App-of-Apps root (applied manually once)
│
├── argocd/                                ← managed BY root App-of-Apps
│   ├── kustomization.yaml
│   ├── projects/
│   │   ├── dev-project.yaml              ← AppProject: dev repos + dev-cluster only
│   │   └── staging-project.yaml         ← AppProject: staging repos + staging-cluster only
│   ├── rbac/
│   │   └── argocd-rbac-cm.yaml          ← policy.default=readonly, team roles
│   ├── controllers/
│   │   ├── sealed-secrets.yaml          ← Sealed Secrets controller
│   │   └── eso.yaml                     ← ESO controller
│   ├── secret-stores/
│   │   └── cluster-secret-store.yaml    ← ESO ClusterSecretStore → LocalStack
│   └── applicationsets/
│       └── microservices-appset.yaml    ← Matrix: services/* × clusters
│
├── services/                             ← managed BY ApplicationSet
│   ├── api-gateway/
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── dev/
│   │       │   ├── kustomization.yaml
│   │       │   └── replica-patch.yaml
│   │       └── staging/
│   │           ├── kustomization.yaml
│   │           └── replica-patch.yaml
│   │
│   ├── user-service/
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── externalsecret.yaml      ← ESO pointer to LocalStack
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── dev/
│   │       └── staging/
│   │
│   └── order-service/                   ← Helm chart
│       ├── Chart.yaml
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── externalsecret.yaml
│       │   └── migration-job.yaml       ← PreSync hook (argocd.argoproj.io/hook: PreSync)
│       └── values/
│           ├── dev-values.yaml
│           └── staging-values.yaml
│
├── secrets/
│   └── sealed/
│       ├── dev/
│       │   └── api-gateway-sealed.yaml  ← SealedSecret (safe to commit)
│       └── staging/
│           └── api-gateway-sealed.yaml
│
└── docs/
    ├── architecture.md                  ← component deep-dive
    ├── troubleshooting-runbook.md       ← 5 scenarios with commands
    └── dr-runbook.md                    ← backup script + recovery steps
```

---

## Build Phases

### Phase 1 — Infrastructure (kind clusters + ArgoCD + LocalStack)
- Create 3 kind clusters
- Install ArgoCD on management cluster
- Start LocalStack and seed secrets
- Verify all 3 clusters accessible

### Phase 2 — App-of-Apps Bootstrap
- Write `root-app.yaml`
- Write `argocd/` directory: projects, RBAC, controller installs, AppSet
- Apply root-app.yaml once — watch ArgoCD bootstrap itself

### Phase 3 — api-gateway (Kustomize + Sealed Secrets)
- Write base manifests + dev/staging overlays
- Install Sealed Secrets controller (via App-of-Apps)
- Seal the API key secret with kubeseal
- ApplicationSet auto-discovers and deploys to both clusters

### Phase 4 — user-service (Kustomize + ESO)
- Write base manifests + dev/staging overlays
- Write ExternalSecret CRD pointing to LocalStack
- ESO creates K8s Secret automatically on both clusters

### Phase 5 — order-service (Helm + PreSync Hook + ESO)
- Write Helm chart with migration Job template
- Add PreSync + BeforeHookCreation annotations
- Write dev + staging values files
- Test migration failure scenario (migration blocks deploy)

### Phase 6 — Sync Policy Configuration
- dev-project: AutoSync ON, prune ON, selfHeal ON
- staging-project: AutoSync OFF, prune OFF (manual sync required)
- Demonstrate: push to Git → dev auto-deploys, staging waits

### Phase 7 — Documentation
- README.md: architecture diagram, prerequisites, setup steps
- troubleshooting-runbook.md: 5 scenarios with kubectl commands
- dr-runbook.md: backup script + step-by-step recovery

---

## Key Interview Talking Points This Project Enables

- "I bootstrapped the entire platform with a single kubectl apply using App-of-Apps"
- "ApplicationSet with Matrix generator automatically deploys every service to every cluster — adding a new service is just adding a directory"
- "PreSync hooks ensure DB migrations complete before any pods are replaced"
- "Sealed Secrets for static secrets, ESO for secrets needing cross-cluster rotation"
- "dev has full GitOps automation, staging requires manual sync approval — demonstrates the AutoSync risk tradeoff"
- "AppProjects enforce what can be deployed where — dev team can't touch staging cluster"

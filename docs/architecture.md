# Architecture Deep Dive

## Component Overview

### ArgoCD Components (management-cluster)

| Component | Role |
|-----------|------|
| argocd-application-controller | Watches Git + cluster state, triggers syncs |
| argocd-applicationset-controller | Generates Applications from ApplicationSet templates |
| argocd-repo-server | Clones Git repos, renders Helm/Kustomize, returns plain YAML |
| argocd-server | REST API + Web UI |
| argocd-dex-server | SSO provider (OIDC, GitHub, LDAP) |
| argocd-redis | In-memory cache for app state |
| argocd-notifications-controller | Slack/email alerts on sync events |

### Cluster Layout

```
management-cluster (kind)
├── ArgoCD (all components)
├── Sealed Secrets controller
└── External Secrets Operator

dev-cluster (kind)
├── Sealed Secrets controller     ← decrypts SealedSecrets for api-gateway
├── External Secrets Operator     ← fetches secrets from LocalStack
├── api-gateway (namespace)
├── user-service (namespace)
└── order-service (namespace)

staging-cluster (kind)
├── Sealed Secrets controller
├── External Secrets Operator
├── api-gateway (namespace)
├── user-service (namespace)
└── order-service (namespace)

localstack (Docker container, kind network)
└── AWS Secrets Manager (simulated)
    ├── user-service/db-password
    └── order-service/db-credentials
```

## GitOps Flow

```
Developer pushes to GitHub
        ↓
ArgoCD repo-server polls (every 3 min) or receives webhook
        ↓
app-controller computes 3-way diff:
  desired (Git) vs live (cluster) vs last-applied
        ↓
If diff found AND autoSync=true → apply changes
If diff found AND autoSync=false → mark OutOfSync, wait for manual sync
        ↓
Resources applied to destination cluster
        ↓
Health checks run → Healthy / Degraded / Progressing
```

## Secret Management

### Sealed Secrets (api-gateway)
```
Developer creates plain Secret YAML (never committed)
        ↓
kubeseal encrypts with cluster's public key → SealedSecret YAML
        ↓
SealedSecret committed to Git (safe — only cluster can decrypt)
        ↓
ArgoCD applies SealedSecret to cluster
        ↓
Sealed Secrets controller decrypts → real K8s Secret
        ↓
Pod reads Secret via secretKeyRef
```

### External Secrets Operator (user-service, order-service)
```
Git stores ExternalSecret CR (just a pointer, no secret value)
        ↓
ArgoCD applies ExternalSecret to cluster
        ↓
ESO reads ExternalSecret, contacts LocalStack at http://172.19.0.5:4566
        ↓
LocalStack returns secret value
        ↓
ESO creates real K8s Secret automatically
        ↓
ESO re-syncs every 1h (rotation support)
        ↓
Pod reads Secret via secretKeyRef
```

## Sync Waves (order-service)

```
Wave 0: migration-job runs (PreSync hook)
  → psql creates/alters schema
  → Job must complete successfully before wave 1 starts

Wave 1: deployment.yaml applied
  → New pods start with updated schema already in place
  → Zero downtime migration pattern
```

## AppProject Boundaries

```
dev-project:
  sourceRepos: [gitops-platform repo]
  destinations: [dev-cluster only]
  → dev team cannot accidentally deploy to staging

staging-project:
  sourceRepos: [gitops-platform repo]
  destinations: [staging-cluster only]
  → staging team cannot touch dev cluster
```

## ApplicationSet Matrix Pattern

```
microservices-dev ApplicationSet:
  generator: git (scans services/*)
  template: deploys services/*/overlays/dev → dev-cluster
  autoSync: ON

microservices-staging ApplicationSet:
  generator: git (scans services/*)
  template: deploys services/*/overlays/staging → staging-cluster
  autoSync: OFF (manual sync required)

Adding a new service = add services/new-service/ directory
→ ApplicationSet auto-discovers and creates Applications
→ No manual ArgoCD config needed
```

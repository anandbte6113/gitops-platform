# Disaster Recovery Runbook

## What Needs to be Backed Up

| Item | Location | How to Backup |
|------|----------|---------------|
| All K8s manifests | Git repo | Already versioned — Git IS the backup |
| ArgoCD Application state | management-cluster | `argocd-backup.sh` below |
| LocalStack secrets | Docker container | `localstack-backup.sh` below |
| Sealed Secrets private key | management/dev/staging kube-system | `seal-key-backup.sh` below |

---

## Backup Scripts

### Backup ArgoCD state
```bash
#!/bin/bash
# backup-argocd.sh
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

kubectl config use-context kind-management-cluster

# Export all ArgoCD Applications
kubectl get applications -n argocd -o yaml > "$BACKUP_DIR/applications.yaml"

# Export AppProjects
kubectl get appprojects -n argocd -o yaml > "$BACKUP_DIR/appprojects.yaml"

# Export RBAC configmap
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > "$BACKUP_DIR/rbac.yaml"

echo "ArgoCD backup saved to $BACKUP_DIR"
```

### Backup LocalStack secrets
```bash
#!/bin/bash
# backup-localstack.sh
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets \
  --region us-east-1 \
  --query 'SecretList[].Name' \
  --output text | tr '\t' '\n' | while read SECRET_NAME; do
    VALUE=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
      --secret-id "$SECRET_NAME" --region us-east-1 --query SecretString --output text)
    echo "$SECRET_NAME=$VALUE" >> "$BACKUP_DIR/localstack-secrets.env"
done

echo "LocalStack secrets backed up to $BACKUP_DIR/localstack-secrets.env"
echo "WARNING: This file contains plain-text secrets. Do not commit it."
```

### Backup Sealed Secrets private key
```bash
#!/bin/bash
# backup-seal-keys.sh — run for each cluster
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for CONTEXT in kind-management-cluster kind-dev-cluster kind-staging-cluster; do
  CLUSTER_NAME=$(echo $CONTEXT | sed 's/kind-//')
  kubectl get secret \
    -n kube-system \
    -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
    --context "$CONTEXT" \
    -o yaml > "$BACKUP_DIR/sealed-secret-key-${CLUSTER_NAME}.yaml"
  echo "Backed up Sealed Secrets key for $CLUSTER_NAME"
done

echo "WARNING: These files contain private keys. Store securely, never commit."
```

---

## Recovery Steps

### Full Platform Recovery (clusters destroyed)

```bash
# Step 1: Recreate clusters
bash bootstrap/01-create-clusters.sh

# Step 2: Restore LocalStack secrets
while IFS='=' read -r NAME VALUE; do
  aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name "$NAME" --secret-string "$VALUE" --region us-east-1
done < backups/<timestamp>/localstack-secrets.env

# Step 3: Restore Sealed Secrets private keys (CRITICAL — do before applying root-app)
for CONTEXT in kind-management-cluster kind-dev-cluster kind-staging-cluster; do
  CLUSTER_NAME=$(echo $CONTEXT | sed 's/kind-//')
  kubectl apply \
    --context "$CONTEXT" \
    -f backups/<timestamp>/sealed-secret-key-${CLUSTER_NAME}.yaml
  # Restart controller so it picks up the restored key
  kubectl rollout restart deployment/sealed-secrets-controller \
    -n kube-system --context "$CONTEXT"
done

# Step 4: Bootstrap platform
bash bootstrap/02-apply-root-app.sh

# Step 5: Verify
argocd app list
kubectl get pods -A --context kind-dev-cluster
kubectl get pods -A --context kind-staging-cluster
```

### Why restoring Sealed Secrets key matters
Each Sealed Secrets controller generates a unique keypair on first boot. If you let the new controller generate a new keypair, all existing SealedSecrets in Git become undecryptable. Always restore the backup key BEFORE the controller starts encrypting new secrets, or re-seal all secrets with the new key.

---

## RTO / RPO

| Metric | Value | Notes |
|--------|-------|-------|
| RPO (Recovery Point Objective) | 0 data loss | All K8s manifests are in Git |
| RTO (Recovery Time Objective) | ~15 minutes | Time to re-run bootstrap + sync |
| LocalStack secrets RPO | Depends on backup frequency | Seed data can be re-created from bootstrap script |

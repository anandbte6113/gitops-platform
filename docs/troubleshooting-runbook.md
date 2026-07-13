# Troubleshooting Runbook

## Scenario 1 — App stuck in OutOfSync

**Symptoms:** Application shows OutOfSync but sync doesn't fix it.

**Diagnose:**
```bash
argocd app get <app-name> --show-operation
kubectl describe application <app-name> -n argocd
```

**Common causes and fixes:**

*CRD not installed yet:*
```bash
# Check if the CRD exists
kubectl get crd | grep <resource-name>
# Fix: ensure the controller Application is in a lower sync wave
```

*Resource owned by another app:*
```bash
argocd app diff <app-name>
# Fix: add argocd.argoproj.io/managed-by annotation or remove from other app
```

*Sync failed mid-way:*
```bash
argocd app sync <app-name> --force
```

---

## Scenario 2 — Pod CrashLoopBackOff after deploy

**Symptoms:** New deployment goes to CrashLoopBackOff immediately after sync.

**Diagnose:**
```bash
kubectl get pods -n <namespace> --context kind-dev-cluster
kubectl logs <pod-name> -n <namespace> --context kind-dev-cluster --previous
kubectl describe pod <pod-name> -n <namespace> --context kind-dev-cluster
```

**Common causes:**
- Secret not found → ExternalSecret not synced, ESO not ready
- Wrong image tag → check deployment.yaml
- Resource limits too low → increase in overlay patch

**Check ESO sync:**
```bash
kubectl get externalsecret -n <namespace> --context kind-dev-cluster
kubectl describe externalsecret <name> -n <namespace> --context kind-dev-cluster
```

---

## Scenario 3 — Sealed Secret decryption fails

**Symptoms:** Pod fails with `secret "api-gateway-secret" not found` or `failed to decrypt`.

**Diagnose:**
```bash
kubectl get sealedsecret -n api-gateway --context kind-dev-cluster
kubectl describe sealedsecret api-gateway-secret -n api-gateway --context kind-dev-cluster
kubectl get events -n api-gateway --context kind-dev-cluster | grep sealed
```

**Common causes and fixes:**

*Sealed against wrong cluster key:*
The SealedSecret was sealed against a different cluster's key.
```bash
# Re-seal against the correct cluster
bash bootstrap/03-seal-secrets.sh
git add services/api-gateway/overlays/dev/sealed-secret.yaml
git commit -m "Re-seal api-gateway secret"
git push
```

*Controller not running:*
```bash
kubectl get pods -n kube-system --context kind-dev-cluster | grep sealed
# If missing, check ArgoCD: argocd app get sealed-secrets-dev
```

---

## Scenario 4 — ExternalSecret not creating K8s Secret

**Symptoms:** ExternalSecret exists but K8s Secret is not created.

**Diagnose:**
```bash
kubectl get externalsecret -n <namespace> --context kind-dev-cluster -o yaml
kubectl get clustersecretstore localstack-secret-store --context kind-dev-cluster
```

**Check ClusterSecretStore status:**
```bash
kubectl describe clustersecretstore localstack-secret-store --context kind-dev-cluster
```

**Common fixes:**

*aws-credentials secret missing:*
```bash
kubectl create secret generic aws-credentials \
  --namespace external-secrets \
  --from-literal=access-key=test \
  --from-literal=secret-key=test \
  --context kind-dev-cluster
```

*LocalStack not reachable from pod:*
```bash
# Verify LocalStack IP is still correct
docker inspect localstack --format '{{ .NetworkSettings.Networks.kind.IPAddress }}'
# If IP changed, update cluster-config/dev/cluster-secret-store.yaml
```

*Secret doesn't exist in LocalStack:*
```bash
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets --region us-east-1
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name user-service/db-password \
  --secret-string '{"password":"userpass123"}' \
  --region us-east-1
```

---

## Scenario 5 — PreSync migration job fails, deployment blocked

**Symptoms:** order-service sync stuck at wave 0. New pods never start.

**Diagnose:**
```bash
kubectl get jobs -n order-service --context kind-dev-cluster
kubectl describe job order-service-migration -n order-service --context kind-dev-cluster
kubectl logs job/order-service-migration -n order-service --context kind-dev-cluster
```

**Common causes:**

*DB not reachable:* Check the DB service is running and host/port are correct in the Job env vars.

*Schema already exists:* The migration uses `CREATE TABLE IF NOT EXISTS` so this shouldn't fail.

*Secret not available:* ExternalSecret hasn't synced yet. Wait for ESO to create the Secret.
```bash
kubectl get secret order-service-db-secret -n order-service --context kind-dev-cluster
```

**Force re-run the migration:**
```bash
# Delete the completed/failed job so ArgoCD can re-create it
kubectl delete job order-service-migration -n order-service --context kind-dev-cluster
argocd app sync order-service-dev
```

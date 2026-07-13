#!/bin/bash
set -e

echo "==> Creating 3 kind clusters..."
kind create cluster --name management-cluster
kind create cluster --name dev-cluster
kind create cluster --name staging-cluster

echo "==> Verifying clusters..."
kind get clusters

echo "==> Installing ArgoCD on management-cluster..."
kubectl config use-context kind-management-cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/install.yaml

echo "==> Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "==> Starting LocalStack..."
docker run -d \
  --name localstack \
  --network kind \
  -p 4566:4566 \
  -e SERVICES=secretsmanager,sts \
  -e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE \
  -e AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
  -e AWS_DEFAULT_REGION=us-east-1 \
  localstack/localstack:3.0

echo "==> Waiting for LocalStack to be healthy..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"secretsmanager"'; do
  sleep 3
done

echo "==> Seeding secrets in LocalStack..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name user-service/db-password \
  --secret-string '{"password":"userpass123"}' \
  --region us-east-1

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name order-service/db-credentials \
  --secret-string '{"username":"orderuser","password":"orderpass123"}' \
  --region us-east-1

echo "==> Registering dev and staging clusters with ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PF_PID=$!
sleep 5

argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

DEV_IP=$(docker inspect dev-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')
STAGING_IP=$(docker inspect staging-cluster-control-plane --format '{{ .NetworkSettings.Networks.kind.IPAddress }}')

kubectl config view --context kind-dev-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${DEV_IP}:6443|g" > /tmp/dev-patched.yaml

kubectl config view --context kind-staging-cluster --minify --flatten | \
  sed "s|https://127.0.0.1:[0-9]*|https://${STAGING_IP}:6443|g" > /tmp/staging-patched.yaml

KUBECONFIG=/tmp/dev-patched.yaml argocd cluster add kind-dev-cluster --name dev-cluster --upsert
KUBECONFIG=/tmp/staging-patched.yaml argocd cluster add kind-staging-cluster --name staging-cluster --upsert

kill $PF_PID 2>/dev/null || true

echo "==> Creating aws-credentials secrets on all clusters..."
for CONTEXT in kind-management-cluster kind-dev-cluster kind-staging-cluster; do
  kubectl create namespace external-secrets --context "$CONTEXT" 2>/dev/null || true
  kubectl create secret generic aws-credentials \
    --namespace external-secrets \
    --from-literal=access-key=AKIAIOSFODNN7EXAMPLE \
    --from-literal=secret-key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
    --context "$CONTEXT" \
    --dry-run=client -o yaml | kubectl apply --context "$CONTEXT" -f - 2>/dev/null || true
done

echo "==> All clusters ready. Run bootstrap/02-apply-root-app.sh to deploy the platform."

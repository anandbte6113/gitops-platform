#!/bin/bash
# Run this after the Sealed Secrets controllers are deployed to dev and staging clusters.
# Seals the api-gateway API key secret for both environments.
set -e

echo "==> Waiting for Sealed Secrets controller on dev-cluster..."
kubectl wait --for=condition=available deployment/sealed-secrets-controller \
  -n kube-system --context kind-dev-cluster --timeout=300s

echo "==> Waiting for Sealed Secrets controller on staging-cluster..."
kubectl wait --for=condition=available deployment/sealed-secrets-controller \
  -n kube-system --context kind-staging-cluster --timeout=300s

echo "==> Sealing api-gateway secret for dev-cluster..."
cat <<EOF > /tmp/api-gateway-plain.yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-gateway-secret
  namespace: api-gateway
type: Opaque
stringData:
  api-key: dev-api-key-abc123
EOF

kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --context kind-dev-cluster \
  --format yaml \
  < /tmp/api-gateway-plain.yaml \
  > services/api-gateway/overlays/dev/sealed-secret.yaml

echo "==> Sealing api-gateway secret for staging-cluster..."
cat <<EOF > /tmp/api-gateway-plain.yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-gateway-secret
  namespace: api-gateway
type: Opaque
stringData:
  api-key: staging-api-key-xyz789
EOF

kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --context kind-staging-cluster \
  --format yaml \
  < /tmp/api-gateway-plain.yaml \
  > services/api-gateway/overlays/staging/sealed-secret.yaml

rm /tmp/api-gateway-plain.yaml

echo "==> Sealed secrets written. Commit them to Git:"
echo "    git add services/api-gateway/overlays/dev/sealed-secret.yaml"
echo "    git add services/api-gateway/overlays/staging/sealed-secret.yaml"
echo "    git commit -m 'Add sealed secrets for api-gateway'"
echo "    git push"

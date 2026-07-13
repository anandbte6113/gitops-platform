#!/bin/bash
set -e

echo "==> Switching to management-cluster..."
kubectl config use-context kind-management-cluster

echo "==> Applying root-app (this bootstraps the entire platform)..."
kubectl apply -f root-app.yaml

echo "==> Port-forwarding ArgoCD UI on https://localhost:8080 ..."
echo "    Login: admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo ""
echo "==> Watching ArgoCD applications come up (Ctrl+C to stop watching)..."
kubectl get applications -n argocd -w

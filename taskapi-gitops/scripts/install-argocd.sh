#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║   Installing ArgoCD                  ║"
echo "╚══════════════════════════════════════╝"

# Create namespace (--dry-run + apply = idempotent)
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using the official stable manifest
echo "→ Installing ArgoCD (this takes 2–3 minutes)..."
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "→ Waiting for ArgoCD server to be available..."
kubectl wait --for=condition=available deployment/argocd-server \
  --namespace=argocd --timeout=300s
echo "  ✅ ArgoCD server ready"

# Expose ArgoCD UI on NodePort 30443 → accessible at https://localhost:8443
kubectl patch svc argocd-server -n argocd -p \
  '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443,"name":"https"}]}}'

# Get the initial admin password (auto-generated during install)
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ ArgoCD installed!               ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  UI:       https://localhost:8443"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "→ Logging in with CLI..."
argocd login localhost:8443 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure   # Self-signed cert in local dev only
echo "  ✅ CLI logged in"
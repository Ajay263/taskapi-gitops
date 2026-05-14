#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║   Configuring HashiCorp Vault        ║"
echo "╚══════════════════════════════════════╝"

# ── Wait for Vault pod to be ready ─────────────────────────────────────────
echo "→ Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault \
  -n vault \
  --timeout=120s
echo "  ✅ Vault pod ready"

# ── Start port-forward ──────────────────────────────────────────────────────
echo "→ Starting port-forward to Vault..."
# Kill any existing port-forward on 8200 to avoid conflicts
pkill -f "port-forward.*vault.*8200" 2>/dev/null || true
sleep 2
kubectl port-forward -n vault svc/vault 8200:8200 &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null; echo 'Port-forward stopped'" EXIT
sleep 5

# ── Set Vault connection ────────────────────────────────────────────────────
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

# ── Verify connection ───────────────────────────────────────────────────────
echo "→ Checking Vault is reachable..."
vault status
echo "  ✅ Vault reachable"

# ── Step 1: Kubernetes auth ─────────────────────────────────────────────────
echo ""
echo "→ Step 1: Enabling Kubernetes auth..."
# Check if already enabled before trying to enable
if vault auth list | grep -q "kubernetes/"; then
  echo "  ℹ️  Kubernetes auth already enabled — skipping"
else
  vault auth enable kubernetes
  echo "  ✅ Kubernetes auth enabled"
fi

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"
echo "  ✅ Kubernetes auth configured"

# ── Step 2: KV secrets engine ──────────────────────────────────────────────
echo ""
echo "→ Step 2: Enabling KV v2 secrets engine..."
# Check if already enabled before trying to enable
# Vault dev mode enables 'secret/' by default — this handles that case
if vault secrets list | grep -q "^secret/"; then
  echo "  ℹ️  KV engine already enabled at secret/ — skipping"
else
  vault secrets enable -path=secret kv-v2
  echo "  ✅ KV v2 enabled"
fi

# ── Step 3: Write secrets ───────────────────────────────────────────────────
echo ""
echo "→ Step 3: Writing secrets..."
# kv put is always safe to re-run — it creates a new version if secret exists
vault kv put secret/taskapi/dev \
  db-password="dev-$(openssl rand -hex 8)" \
  api-key="dev-api-$(openssl rand -hex 12)"

vault kv put secret/taskapi/staging \
  db-password="staging-$(openssl rand -hex 8)" \
  api-key="staging-api-$(openssl rand -hex 12)"

vault kv put secret/taskapi/prod \
  db-password="prod-$(openssl rand -hex 8)" \
  api-key="prod-api-$(openssl rand -hex 12)"
echo "  ✅ Secrets written for dev, staging, prod"

# ── Step 4: Policies ────────────────────────────────────────────────────────
echo ""
echo "→ Step 4: Writing policies..."
# Write policies from files to avoid heredoc formatting issues in terminals
cat > /tmp/policy-dev.hcl << 'EOF'
path "secret/data/taskapi/dev" {
  capabilities = ["read"]
}
path "secret/metadata/taskapi/dev" {
  capabilities = ["read", "list"]
}
path "secret/data/taskapi/staging" {
  capabilities = ["deny"]
}
path "secret/data/taskapi/prod" {
  capabilities = ["deny"]
}
EOF

cat > /tmp/policy-staging.hcl << 'EOF'
path "secret/data/taskapi/staging" {
  capabilities = ["read"]
}
path "secret/metadata/taskapi/staging" {
  capabilities = ["read", "list"]
}
EOF

cat > /tmp/policy-prod.hcl << 'EOF'
path "secret/data/taskapi/prod" {
  capabilities = ["read"]
}
path "secret/metadata/taskapi/prod" {
  capabilities = ["read", "list"]
}
EOF

vault policy write taskapi-dev     /tmp/policy-dev.hcl
vault policy write taskapi-staging /tmp/policy-staging.hcl
vault policy write taskapi-prod    /tmp/policy-prod.hcl
echo "  ✅ Policies written"

# ── Step 5: Kubernetes roles ────────────────────────────────────────────────
echo ""
echo "→ Step 5: Writing Kubernetes auth roles..."
vault write auth/kubernetes/role/taskapi-dev \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-dev \
  policies=taskapi-dev \
  ttl=24h

vault write auth/kubernetes/role/taskapi-staging \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-staging \
  policies=taskapi-staging \
  ttl=1h

vault write auth/kubernetes/role/taskapi-prod \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-prod \
  policies=taskapi-prod \
  ttl=1h
echo "  ✅ Kubernetes roles written"

# ── Verification ────────────────────────────────────────────────────────────
echo ""
echo "→ Verifying everything was created..."
echo ""
echo "  Secrets:"
vault kv list secret/taskapi/ | sed 's/^/    /'

echo ""
echo "  Policies:"
vault policy list | grep taskapi | sed 's/^/    /'

echo ""
echo "  Roles:"
vault list auth/kubernetes/role | grep taskapi | sed 's/^/    /'

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Vault fully configured!         ║"
echo "╚══════════════════════════════════════╝"
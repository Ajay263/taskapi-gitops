#!/bin/bash
set -e
VAULT_TOKEN=$1
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$VAULT_TOKEN

vault auth enable kubernetes 2>/dev/null || true
vault write auth/kubernetes/config \
  kubernetes_host=https://kubernetes.default.svc.cluster.local:443
vault secrets enable -path=secret kv-v2 2>/dev/null || true

vault policy write taskapi-dev /tmp/policy-dev.hcl
vault policy write taskapi-staging /tmp/policy-staging.hcl
vault policy write taskapi-prod /tmp/policy-prod.hcl

vault kv put secret/taskapi/dev db-password=dev-pass-123 api-key=dev-api-key-123
vault kv put secret/taskapi/staging db-password=staging-pass-123 api-key=staging-api-key-123
vault kv put secret/taskapi/prod db-password=prod-pass-123 api-key=prod-api-key-123

vault write auth/kubernetes/role/taskapi-dev \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-dev \
  policies=taskapi-dev ttl=24h

vault write auth/kubernetes/role/taskapi-staging \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-staging \
  policies=taskapi-staging ttl=1h

vault write auth/kubernetes/role/taskapi-prod \
  bound_service_account_names=taskapi \
  bound_service_account_namespaces=taskapi-prod \
  policies=taskapi-prod ttl=1h

echo "Vault configured successfully"

#!/bin/bash
# Run this if Vault pod restarted and lost its in-memory data.
# Symptoms: ExternalSecret shows SecretSyncedError, ClusterSecretStore shows InvalidProviderConfig

set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║   Vault Recovery (dev mode reset)    ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "ℹ️  Vault dev mode stores data in memory."
echo "   If the Vault pod restarted, all data was lost."
echo "   This script reconfigures everything from scratch."
echo ""

# Just re-run the full configure script — it's idempotent now
bash scripts/configure-vault.sh

# Force ESO to re-sync after Vault is reconfigured
echo ""
echo "→ Forcing ExternalSecret re-sync..."
for ns in taskapi-dev taskapi-staging taskapi-prod; do
  kubectl annotate externalsecret taskapi-secrets -n "$ns" \
    force-sync=$(date +%s) --overwrite 2>/dev/null || true
done

echo ""
echo "→ Waiting for ExternalSecret to sync..."
kubectl get externalsecret taskapi-secrets -n taskapi-dev --watch &
WATCH_PID=$!
sleep 20
kill $WATCH_PID 2>/dev/null

echo ""
echo "→ Final status:"
kubectl get externalsecret -A | grep taskapi
kubectl get clustersecretstore vault-backend
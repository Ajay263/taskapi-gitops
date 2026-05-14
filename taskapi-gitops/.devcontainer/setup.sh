#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║   DevOps Environment Setup           ║"
echo "╚══════════════════════════════════════╝"

# ── ArgoCD CLI ──────────────────────────────────────────────────────────────
echo "→ Installing ArgoCD CLI..."
curl -sSL -o /tmp/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /tmp/argocd
sudo mv /tmp/argocd /usr/local/bin/argocd

# ── HashiCorp Vault CLI ──────────────────────────────────────────────────────
echo "→ Installing Vault CLI..."
VAULT_VERSION="1.15.6"
curl -sSL -o /tmp/vault.zip \
  "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
cd /tmp && unzip -o vault.zip
chmod +x /tmp/vault
sudo mv /tmp/vault /usr/local/bin/vault

# ── Kustomize ──────────────────────────────────────────────────────────────
echo "→ Installing Kustomize..."
curl -sSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
  | bash -s -- /tmp
sudo mv /tmp/kustomize /usr/local/bin/kustomize

# ── kind ──────────────────────────────────────────────────────────────────
# Installed directly here rather than via the mpriscella devcontainer feature,
# which is unreliable across machine types and codespace prebuilds.
echo "→ Installing kind..."
KIND_VERSION="v0.20.0"
curl -sSL -o /tmp/kind \
  "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
chmod +x /tmp/kind
sudo mv /tmp/kind /usr/local/bin/kind

# ── istioctl ──────────────────────────────────────────────────────────────
echo "→ Installing istioctl..."
ISTIO_VERSION="1.20.3"
curl -sSL \
  "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz" \
  | tar -xz -C /tmp istioctl
chmod +x /tmp/istioctl
sudo mv /tmp/istioctl /usr/local/bin/istioctl

# ── Trivy ──────────────────────────────────────────────────────────────────
echo "→ Installing Trivy..."
curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sudo sh -s -- -b /usr/local/bin

# ── yq ──────────────────────────────────────────────────────────────────────
echo "→ Installing yq..."
YQ_VERSION="v4.44.1"
curl -sSL -o /tmp/yq \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
chmod +x /tmp/yq
sudo mv /tmp/yq /usr/local/bin/yq

# ── jq ──────────────────────────────────────────────────────────────────────
echo "→ Installing jq..."
sudo apt-get install -y jq

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Setup complete!                 ║"
echo "║   Run: bash .devcontainer/verify-tools.sh"
echo "╚══════════════════════════════════════╝"
#!/bin/bash
set -euo pipefail

CLUSTER_NAME="taskapi-local"

echo "╔══════════════════════════════════════╗"
echo "║   Creating KinD Kubernetes Cluster   ║"
echo "╚══════════════════════════════════════╝"

echo "→ Checking Docker..."
if ! docker info > /dev/null 2>&1; then
  echo "  ❌ Docker not running."
  echo "     Fix: sudo service docker start"
  exit 1
fi
echo "  ✅ Docker is running"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "  ℹ️  Cluster '${CLUSTER_NAME}' already exists — skipping creation"
else
  cat > /tmp/kind-config.yaml << 'KINDEOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: taskapi-local

nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            oidc-issuer-url: "http://keycloak.iam.svc.cluster.local:8080/realms/taskapi"
            oidc-username-claim: "preferred_username"
            oidc-groups-claim: "groups"
            oidc-client-id: "kubernetes"
            oidc-username-prefix: "oidc:"
            oidc-groups-prefix: "oidc:"
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP
      - containerPort: 30443
        hostPort: 8443
        protocol: TCP
      - containerPort: 30090
        hostPort: 9090
        protocol: TCP
      - containerPort: 30030
        hostPort: 3000
        protocol: TCP
      - containerPort: 30200
        hostPort: 8200
        protocol: TCP
      - containerPort: 30686
        hostPort: 16686
        protocol: TCP

  - role: worker
    labels:
      workload: app

  - role: worker
    labels:
      workload: infra

networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  disableDefaultCNI: false
KINDEOF

  echo "→ Creating cluster (3–5 minutes)..."
  kind create cluster --config /tmp/kind-config.yaml --wait 300s
fi

echo ""
echo "→ Verifying cluster..."
kubectl cluster-info
echo ""
echo "→ Nodes:"
kubectl get nodes -o wide

echo ""
echo "→ Waiting for system pods to be ready..."
kubectl wait --for=condition=ready pod \
  --all --namespace=kube-system --timeout=180s
echo "  ✅ System pods ready"

echo ""
echo "→ Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "→ Waiting for NGINX Ingress Controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
echo "  ✅ NGINX Ingress Controller ready"

echo ""
echo "→ Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl wait --for=condition=available deployment/metrics-server \
  --namespace=kube-system --timeout=120s
echo "  ✅ Metrics Server ready"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Cluster is ready!               ║"
echo "║   Run: bash scripts/verify-cluster.sh"
echo "╚══════════════════════════════════════╝"

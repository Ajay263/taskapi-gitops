#!/bin/bash
set -uo pipefail

NAMESPACE="${1:-taskapi-dev}"
PASS=0; FAIL=0; WARN=0

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Production Readiness Audit: $NAMESPACE"
echo "╚══════════════════════════════════════════════════╝"
echo ""

pass() { echo "  ✅  $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌  $1"; echo "      Fix: $2"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️   $1"; WARN=$((WARN+1)); }

echo "── Cluster ─────────────────────────────────────────────"
kubectl cluster-info > /dev/null 2>&1 \
  && pass "Cluster reachable" || fail "Cluster unreachable" "kind export kubeconfig --name taskapi-local"

NOTREADY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v ' Ready ' | wc -l)
[ "$NOTREADY" -eq 0 ] && pass "All nodes Ready" || fail "$NOTREADY node(s) not Ready" "kubectl describe node"

echo ""
echo "── Application ─────────────────────────────────────────"
kubectl get deployment taskapi -n "$NAMESPACE" > /dev/null 2>&1 \
  && pass "taskapi Deployment exists" || fail "Deployment missing" "kustomize build overlays/dev/ | kubectl apply -f -"

READY=$(kubectl get deployment taskapi -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
[ "${READY:-0}" -gt 0 ] && pass "At least 1 replica ready" || fail "No ready replicas" "kubectl describe deployment taskapi -n $NAMESPACE"

kubectl get pod -n "$NAMESPACE" -l app=taskapi \
  -o jsonpath='{.items[0].spec.securityContext.runAsNonRoot}' 2>/dev/null \
  | grep -q 'true' && pass "Pod runs as non-root" || fail "Pod may run as root" "Check securityContext in deployment.yaml"

kubectl get pod -n "$NAMESPACE" -l app=taskapi \
  -o jsonpath='{.items[0].spec.containers[0].resources.limits.memory}' 2>/dev/null \
  | grep -q '[0-9]' && pass "Memory limit set" || fail "Memory limit missing" "Add resources.limits to deployment.yaml"

kubectl get hpa taskapi -n "$NAMESPACE" > /dev/null 2>&1 \
  && pass "HPA configured" || fail "HPA missing" "Apply base/hpa.yaml"

echo ""
echo "── Secrets (Vault) ──────────────────────────────────────"
kubectl get pods -n vault 2>/dev/null | grep -q Running \
  && pass "Vault running" || fail "Vault not running" "helm install vault ..."

kubectl get externalsecret taskapi-secrets -n "$NAMESPACE" \
  -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null \
  | grep -q 'SecretSynced' && pass "ExternalSecret synced" || fail "ExternalSecret not synced" "bash scripts/recover-vault.sh"

kubectl exec -n "$NAMESPACE" deploy/taskapi -- env 2>/dev/null | grep ^DB_PASSWORD \
  | grep -qv "placeholder\|NOT_CONFIGURED" \
  && pass "DB_PASSWORD injected from Vault" || fail "DB_PASSWORD is placeholder" "bash scripts/recover-vault.sh"

echo ""
echo "── GitOps (ArgoCD) ──────────────────────────────────────"
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server 2>/dev/null | grep -q Running \
  && pass "ArgoCD running" || fail "ArgoCD not running" "bash scripts/install-argocd.sh"

echo ""
echo "── RBAC ─────────────────────────────────────────────────"
kubectl get role developer -n taskapi-dev > /dev/null 2>&1 \
  && pass "Developer role exists" || fail "Developer role missing" "kubectl apply -f rbac/roles.yaml"

RBAC_RESULT=$(kubectl auth can-i delete deployments \
  --namespace=taskapi-prod --as=alice --as-group=dev-team 2>/dev/null)
[ "$RBAC_RESULT" = "no" ] && pass "Dev team blocked from prod" || warn "RBAC may be too permissive"

echo ""
echo "── Istio ────────────────────────────────────────────────"
kubectl get pods -n istio-system -l app=istiod 2>/dev/null | grep -q Running \
  && pass "Istio running" || fail "Istio not running" "istioctl install --set profile=minimal -y"

CONTAINERS=$(kubectl get pod -n "$NAMESPACE" -l app=taskapi \
  -o jsonpath='{.items[0].status.containerStatuses}' 2>/dev/null \
  | python3 -c "import sys,json; cs=json.load(sys.stdin); print(len(cs))" 2>/dev/null || echo "1")
[ "${CONTAINERS:-1}" -ge 2 ] && pass "Istio sidecar injected (2/2)" || warn "Sidecar may not be injected"

echo ""
echo "── Monitoring ───────────────────────────────────────────"
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus 2>/dev/null | grep -q Running \
  && pass "Prometheus running" || fail "Prometheus not running" "helm install kube-prometheus-stack ..."

kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null | grep -q Running \
  && pass "Grafana running" || fail "Grafana not running" "helm install kube-prometheus-stack ..."

kubectl get servicemonitor taskapi -n monitoring > /dev/null 2>&1 \
  && pass "ServiceMonitor exists" || fail "ServiceMonitor missing" "kubectl apply -f infrastructure/monitoring/servicemonitor.yaml"

kubectl get prometheusrule taskapi-alerts -n monitoring > /dev/null 2>&1 \
  && pass "Alert rules configured" || fail "Alert rules missing" "kubectl apply -f infrastructure/monitoring/prometheusrule.yaml"

echo ""
echo "── Logging ──────────────────────────────────────────────"
kubectl get pod -n monitoring -l app.kubernetes.io/name=loki 2>/dev/null | grep -q Running \
  && pass "Loki running" || fail "Loki not running" "helm install loki grafana/loki --set loki.useTestSchema=true ..."

PROMTAIL_COUNT=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail 2>/dev/null | grep -c Running || echo 0)
[ "${PROMTAIL_COUNT:-0}" -ge 2 ] \
  && pass "Promtail running ($PROMTAIL_COUNT pods)" \
  || fail "Promtail missing" "helm install promtail grafana/promtail ..."

echo ""
echo "── Tracing ──────────────────────────────────────────────"
kubectl get pods -n observability 2>/dev/null | grep -q Running \
  && pass "Jaeger running" || warn "Jaeger not running — see Phase 15"

echo ""
echo "── DevSecOps ────────────────────────────────────────────"
kubectl get pods -n gatekeeper-system 2>/dev/null | grep -q Running \
  && pass "OPA Gatekeeper running" \
  || fail "OPA Gatekeeper not running" "kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml"

kubectl get requirenonroot require-non-root > /dev/null 2>&1 \
  && pass "OPA non-root policy active" \
  || fail "OPA policies missing" "kubectl apply OPA constraints"

echo ""
echo "── Live Endpoints ───────────────────────────────────────"
curl -sf http://localhost:8080/api/health > /dev/null 2>&1 \
  && pass "GET /api/health → 200" || fail "Health endpoint not responding" "Check ingress and pod"

curl -sf http://localhost:8080/api/tasks > /dev/null 2>&1 \
  && pass "GET /api/tasks → 200" || fail "Tasks endpoint not responding" "Check pod logs"

curl -sf http://localhost:8080/api/metrics 2>/dev/null | grep -q taskapi_requests_total \
  && pass "GET /api/metrics → has taskapi metrics" || fail "Metrics endpoint broken" "Check prometheus_client installed"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
printf "║  RESULTS: %-3s ✅  %-3s ❌  %-3s ⚠️                    ║\n" "$PASS" "$FAIL" "$WARN"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "  🟢 System is production-ready!"
else
  echo "  🔴 $FAIL issues — fix ❌ items in Phase order"
fi
echo ""

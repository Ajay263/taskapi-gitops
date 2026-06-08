#!/bin/bash
set -e
ENV=${1:-dev}
NS="taskapi-$ENV"
FAILURES=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILURES=$((FAILURES+1)); }

echo "=== Smoke tests: $ENV ($NS) ==="

# Pod health
kubectl get pods -n $NS -l app=taskapi --no-headers | grep -q Running \
  && pass "pods running" || fail "pods running"

# No crash loops
kubectl get pods -n $NS -l app=taskapi --no-headers | grep -q CrashLoop \
  && fail "no crash loops" || pass "no crash loops"

# Health endpoint
POD=$(kubectl get pods -n $NS -l app=taskapi \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD" ]; then
  kubectl exec -n $NS $POD -- \
    python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" \
    2>/dev/null && pass "health endpoint" || fail "health endpoint"

  kubectl exec -n $NS $POD -- \
    python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/metrics')" \
    2>/dev/null && pass "metrics endpoint" || fail "metrics endpoint"

  ENV_VAR=$(kubectl get pod $POD -n $NS \
    -o jsonpath='{.spec.containers[0].env[?(@.name=="ENVIRONMENT")].value}' 2>/dev/null)
  [ -n "$ENV_VAR" ] && pass "ENVIRONMENT=$ENV_VAR" || fail "ENVIRONMENT var missing"
else
  fail "no pods found in $NS"
fi

echo ""
if [ $FAILURES -eq 0 ]; then
  echo "All tests passed for $ENV"
else
  echo "$FAILURES test(s) FAILED for $ENV"
  exit 1
fi

#!/bin/bash
set -e
WEIGHT=${1:-10}

echo "Canary weight: $WEIGHT%"

case $WEIGHT in
  0)
    echo "Rolling back canary"
    kubectl scale deployment taskapi-canary -n taskapi-staging --replicas=0 2>/dev/null || true
    kubectl scale deployment taskapi -n taskapi-staging --replicas=2
    echo "Stable serving 100% traffic"
    ;;
  10)
    kubectl scale deployment taskapi -n taskapi-staging --replicas=2
    kubectl scale deployment taskapi-canary -n taskapi-staging --replicas=1 2>/dev/null || \
      kubectl apply -k overlays/staging-canary/
    echo "~33% canary (1 canary / 3 total pods)"
    ;;
  50)
    kubectl scale deployment taskapi -n taskapi-staging --replicas=2
    kubectl scale deployment taskapi-canary -n taskapi-staging --replicas=2 2>/dev/null || true
    echo "~50% canary (2 canary / 4 total pods)"
    ;;
  100)
    echo "Promoting canary to stable"
    IMG=$(kubectl get deployment taskapi-canary -n taskapi-staging \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
    if [ -n "$IMG" ]; then
      kubectl set image deployment/taskapi taskapi=$IMG -n taskapi-staging
    fi
    kubectl scale deployment taskapi-canary -n taskapi-staging --replicas=0 2>/dev/null || true
    echo "Stable now runs promoted image"
    ;;
  *)
    echo "Usage: $0 [0|10|50|100]"
    exit 1
    ;;
esac

echo ""
kubectl get pods -n taskapi-staging -l app=taskapi \
  --no-headers -o custom-columns="POD:.metadata.name,TRACK:.metadata.labels.track,STATUS:.status.phase"

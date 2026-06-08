#!/bin/bash
set -e
SLOT=${1:-green}
if [[ "$SLOT" != "blue" && "$SLOT" != "green" ]]; then
  echo "Usage: $0 [blue|green]"
  exit 1
fi

echo "Switching prod traffic to: $SLOT"
kubectl patch service taskapi-live -n taskapi-prod \
  --type=merge \
  -p "{\"spec\":{\"selector\":{\"app\":\"taskapi\",\"slot\":\"$SLOT\"}}}"

echo ""
echo "Active slot: $SLOT"
kubectl get pods -n taskapi-prod -l app=taskapi,slot=$SLOT \
  --no-headers -o custom-columns="POD:.metadata.name,STATUS:.status.phase,SLOT:.metadata.labels.slot"

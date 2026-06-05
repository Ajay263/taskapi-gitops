#!/bin/bash
# Import all 4 TaskAPI Grafana dashboards via API
GRAFANA_URL="http://localhost:3001"
CREDS="admin:devops-training-2024"

# Wait for Grafana API
until curl -sf -u "$CREDS" "$GRAFANA_URL/api/org" > /dev/null 2>&1; do
  sleep 3
done

# Import community dashboards
for ID in 16110 7249; do
  curl -sf -X POST "$GRAFANA_URL/api/dashboards/import" \
    -u "$CREDS" \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\":null,\"folderId\":0,\"overwrite\":true,\"inputs\":[{\"name\":\"DS_PROMETHEUS\",\"type\":\"datasource\",\"pluginId\":\"prometheus\",\"value\":\"Prometheus\"}],\"id\":$ID}" \
    > /dev/null && echo "Imported dashboard $ID"
done

echo "Grafana dashboards imported"
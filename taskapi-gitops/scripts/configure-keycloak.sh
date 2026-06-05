#!/bin/bash
set -euo pipefail

KEYCLOAK_URL="http://localhost:8888"
ADMIN_USER="admin"
ADMIN_PASS="admin123"
REALM="taskapi"

echo "╔══════════════════════════════════════╗"
echo "║   Configuring Keycloak IAM           ║"
echo "╚══════════════════════════════════════╝"

echo "→ Authenticating with Keycloak..."
ADMIN_TOKEN=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "  ✅ Admin token obtained"

kc_post() {
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms${1}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${2}"
}
kc_get() {
  curl -s -X GET "${KEYCLOAK_URL}/admin/realms${1}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}"
}

echo ""
echo "→ Step 1: Creating realm '${REALM}'..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"realm\": \"${REALM}\",
    \"enabled\": true,
    \"displayName\": \"TaskAPI Platform\",
    \"accessTokenLifespan\": 300,
    \"ssoSessionMaxLifespan\": 36000
  }" 2>/dev/null || echo "  ℹ️  Realm may already exist"
echo "  ✅ Realm '${REALM}' ready"

echo ""
echo "→ Step 2: Creating groups..."
for GROUP in "dev-team" "ops-team" "platform-eng" "readonly"; do
  kc_post "/${REALM}/groups" "{\"name\": \"${GROUP}\"}" > /dev/null 2>&1 || true
  echo "  ✅ Group: ${GROUP}"
done

echo ""
echo "→ Step 3: Creating users..."

create_user() {
  local USERNAME=$1
  local FIRSTNAME=$2
  local LASTNAME=$3
  local EMAIL=$4
  local PASSWORD=$5
  shift 5
  local USER_GROUPS=("$@")

  kc_post "/${REALM}/users" "{
    \"username\": \"${USERNAME}\",
    \"firstName\": \"${FIRSTNAME}\",
    \"lastName\": \"${LASTNAME}\",
    \"email\": \"${EMAIL}\",
    \"enabled\": true,
    \"emailVerified\": true,
    \"credentials\": [{
      \"type\": \"password\",
      \"value\": \"${PASSWORD}\",
      \"temporary\": false
    }]
  }" > /dev/null 2>&1 || true

  USER_ID=$(kc_get "/${REALM}/users?username=${USERNAME}" \
    | python3 -c "import sys,json; users=json.load(sys.stdin); print(users[0]['id'] if users else '')")

  for GROUP_NAME in "${USER_GROUPS[@]}"; do
    GROUP_ID=$(kc_get "/${REALM}/groups?search=${GROUP_NAME}" \
      | python3 -c "import sys,json; g=json.load(sys.stdin); print(g[0]['id'] if g else '')")
    if [ -n "$GROUP_ID" ] && [ -n "$USER_ID" ]; then
      curl -s -X PUT \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${USER_ID}/groups/${GROUP_ID}" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" > /dev/null 2>&1 || true
    fi
  done

  echo "  ✅ User: ${USERNAME} → groups: ${USER_GROUPS[*]}"
}

create_user "alice"   "Alice"   "Dev"      "alice@taskapi.dev"     "alice123"   "dev-team"
create_user "bob"     "Bob"     "Dev"      "bob@taskapi.dev"       "bob123"     "dev-team"
create_user "charlie" "Charlie" "Ops"      "charlie@taskapi.ops"   "charlie123" "ops-team" "dev-team"
create_user "diana"   "Diana"   "Platform" "diana@taskapi.platform" "diana123"  "platform-eng"
create_user "eve"     "Eve"     "Readonly" "eve@taskapi.dev"       "eve123"     "readonly"

echo ""
echo "→ Step 4: Creating Kubernetes OIDC client..."
kc_post "/${REALM}/clients" '{
  "clientId": "kubernetes",
  "name": "Kubernetes Cluster",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "kubernetes-client-secret",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "redirectUris": ["*"],
  "webOrigins": ["*"]
}' > /dev/null 2>&1 || true
echo "  ✅ Kubernetes client ready"

echo ""
echo "→ Step 5: Adding groups claim mapper..."
CLIENT_ID=$(kc_get "/${REALM}/clients?clientId=kubernetes" \
  | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['id'] if c else '')")

if [ -n "$CLIENT_ID" ]; then
  kc_post "/${REALM}/clients/${CLIENT_ID}/protocol-mappers/models" '{
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-group-membership-mapper",
    "config": {
      "full.path": "false",
      "id.token.claim": "true",
      "access.token.claim": "true",
      "claim.name": "groups",
      "userinfo.token.claim": "true"
    }
  }' > /dev/null 2>&1 || true
  echo "  ✅ Groups claim mapper added"
fi

echo ""
echo "→ Verifying..."
echo "  Users:"
kc_get "/${REALM}/users" \
  | python3 -c "
import sys,json
users = json.load(sys.stdin)
for u in users:
    print(f\"    {u['username']} ({u.get('firstName','')} {u.get('lastName','')})\")
"
echo ""
echo "  Groups:"
kc_get "/${REALM}/groups" \
  | python3 -c "
import sys,json
groups = json.load(sys.stdin)
for g in groups:
    print(f\"    {g['name']}\")
"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Keycloak configured!            ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  alice / alice123   → dev-team"
echo "  bob / bob123       → dev-team"
echo "  charlie / charlie123 → ops-team + dev-team"
echo "  diana / diana123   → platform-eng"
echo "  eve / eve123       → readonly"

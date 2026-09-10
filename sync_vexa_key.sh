#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "./.env" ]; then
  echo "[ER] .env file not found."
  exit 1
fi

VEXA_API_KEY="$(grep "^VEXA_API_KEY=" .env | cut -d'=' -f2- | tr -d ' "\r\n' || true)"

if [ -z "$VEXA_API_KEY" ]; then
  echo "[ER] VEXA_API_KEY is not defined in .env"
  exit 1
fi

echo "[>>] Checking Vexa API key in database: $VEXA_API_KEY"

# Ensure vexa postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q "vexa-v012-postgres-1"; then
  echo "[ER] vexa-v012-postgres-1 container is not running."
  exit 1
fi

# Check if token exists in vexa database
TOKEN_EXISTS=$(docker exec vexa-v012-postgres-1 psql -U postgres -d vexa -t -A -c "SELECT COUNT(*) FROM api_tokens WHERE token = '$VEXA_API_KEY';" 2>/dev/null || echo "0")

if [ "$TOKEN_EXISTS" -gt 0 ]; then
  echo "[OK] Token already exists in Vexa database."
else
  echo "[>>] Token missing from Vexa database. Provisioning..."
  # Ensure user 1 exists
  USER_ID=$(docker exec vexa-v012-postgres-1 psql -U postgres -d vexa -t -A -c "SELECT id FROM users LIMIT 1;" 2>/dev/null || echo "")
  if [ -z "$USER_ID" ]; then
    USER_ID=$(docker exec vexa-v012-postgres-1 psql -U postgres -d vexa -t -A -c "INSERT INTO users (email, name, max_concurrent_bots, created_at) VALUES ('meetingmind@local', 'meetingmind', 5, NOW()) RETURNING id;" 2>/dev/null || echo "1")
  fi
  docker exec vexa-v012-postgres-1 psql -U postgres -d vexa -c "INSERT INTO api_tokens (user_id, token, scopes, created_at) VALUES ($USER_ID, '$VEXA_API_KEY', '{bot,tx,browser}', NOW());"
  echo "[OK] Token inserted into Vexa database."
fi

# Validate via gateway
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "http://localhost:18056/meetings" -H "X-API-Key: $VEXA_API_KEY" || echo "000")
if [ "$STATUS_CODE" = "200" ]; then
  echo "[OK] Vexa API key validated successfully (HTTP 200)."
else
  echo "[!!] Gateway returned HTTP $STATUS_CODE. Please verify Vexa services are healthy."
fi

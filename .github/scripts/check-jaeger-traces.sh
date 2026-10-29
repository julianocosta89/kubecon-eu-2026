#!/usr/bin/env bash
# Waits for traces from a service to show up in Jaeger.
# Usage: check-jaeger-traces.sh <service-name>
#
# Uses the Jaeger v3 query API (the legacy /api/traces endpoint was removed
# in Jaeger 2.22). Polls for up to ATTEMPTS * INTERVAL seconds and, on
# failure, prints the last response and the Docker Compose state and logs.
set -euo pipefail

SERVICE="${1:?usage: $0 <service-name>}"
JAEGER_URL="${JAEGER_URL:-http://localhost:16686}"
ATTEMPTS="${ATTEMPTS:-12}"
INTERVAL="${INTERVAL:-5}"

START=$(date -u -d '-15 minutes' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u -d '+15 minutes' +%Y-%m-%dT%H:%M:%SZ)
URL="${JAEGER_URL}/api/v3/traces?query.service_name=${SERVICE}&query.start_time_min=${START}&query.start_time_max=${END}&query.search_depth=1"

echo "Checking for traces from ${SERVICE} in Jaeger..."
CODE=""
BODY=""
for i in $(seq 1 "$ATTEMPTS"); do
  RESPONSE=$(curl -s -w '\n%{http_code}' "$URL" || true)
  CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  # Jaeger answers 404 {"error":{"message":"No traces found"}} until traces arrive.
  TRACES=$(echo "$BODY" | jq '.result.resourceSpans // [] | length' 2>/dev/null || echo 0)
  if [ "$CODE" = "200" ] && [ "${TRACES:-0}" -gt 0 ]; then
    echo "Traces found in Jaeger!"
    exit 0
  fi
  echo "Attempt ${i}/${ATTEMPTS}: HTTP ${CODE}, traces=${TRACES:-0}. Retrying in ${INTERVAL}s..."
  sleep "$INTERVAL"
done

echo "No traces from ${SERVICE} found in Jaeger. Last response (HTTP ${CODE}):"
echo "$BODY" | head -c 1000
echo
docker compose ps -a || true
docker compose logs || true
exit 1

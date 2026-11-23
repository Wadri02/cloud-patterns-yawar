#!/usr/bin/env bash
# Local smoke test before AWS: builds the images, starts docker compose and runs the 3 resilience demos.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/backend"
(mvn -B -q test && echo "JUnit: all tests passed") | tee "$ROOT/evidence/local/00-mvn-test.log"
docker compose up -d --build
echo "waiting for the services..."
for p in 8081 8082 8083 8084; do until curl -sf localhost:$p/actuator/health >/dev/null; do sleep 2; done; done
curl -s localhost:8083/api/donors; echo
"$ROOT/01-circuit-breaker/test.sh" local
"$ROOT/02-retry/test.sh" local
"$ROOT/03-timeout/test.sh" local
echo "stop with: (cd backend && docker compose down)"

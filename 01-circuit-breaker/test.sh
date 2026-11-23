#!/usr/bin/env bash
# Runs the circuit-breaker demo of ms-requests with BOTH implementations (custom and Resilience4j).
#   ./test.sh aws     -> through the ALB deployed by scripts/aws/03-platform.sh   (evidence/aws/01-circuit-breaker.log)
#   ./test.sh local   -> against docker compose in backend/                     (evidence/local/01-circuit-breaker.log)
source "$(dirname "$0")/../scripts/aws/common.sh"
TARGET="${1:-aws}"
if [ "$TARGET" = aws ]; then
  BASE=$(tf_out infra/2-platform base_url); start_log 01-circuit-breaker
else
  BASE=http://localhost:8082; mkdir -p "$ROOT/evidence/local"; exec > >(tee "$ROOT/evidence/local/01-circuit-breaker.log") 2>&1
fi
echo "target: $BASE"
for impl in custom resilience4j; do
  step "GET $BASE/api/requests/demo/circuit-breaker?impl=$impl"
  curl -s --max-time 110 "$BASE/api/requests/demo/circuit-breaker?impl=$impl" | tee "$ROOT/evidence/$TARGET/01-circuit-breaker-$impl.json" | demo_lines
done

step "chart from the JSON evidence"
python3 "$ROOT/01-circuit-breaker/plot.py" "$ROOT/evidence/$TARGET" && echo "saved evidence/$TARGET/circuit-breaker-latency.png"

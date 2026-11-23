#!/usr/bin/env bash
# Runs the timeout demo of ms-requests with BOTH implementations (custom and Resilience4j).
#   ./test.sh aws     -> through the ALB deployed by scripts/aws/03-platform.sh   (evidence/aws/03-timeout.log)
#   ./test.sh local   -> against docker compose in backend/                     (evidence/local/03-timeout.log)
source "$(dirname "$0")/../scripts/aws/common.sh"
TARGET="${1:-aws}"
if [ "$TARGET" = aws ]; then
  BASE=$(tf_out infra/2-platform base_url); start_log 03-timeout
else
  BASE=http://localhost:8082; mkdir -p "$ROOT/evidence/local"; exec > >(tee "$ROOT/evidence/local/03-timeout.log") 2>&1
fi
echo "target: $BASE"
for impl in custom resilience4j; do
  step "GET $BASE/api/requests/demo/timeout?impl=$impl"
  curl -s --max-time 110 "$BASE/api/requests/demo/timeout?impl=$impl" | tee "$ROOT/evidence/$TARGET/03-timeout-$impl.json" | demo_lines
done

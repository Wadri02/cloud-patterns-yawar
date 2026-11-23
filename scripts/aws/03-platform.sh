#!/usr/bin/env bash
# Deploys VPC + ALB + ECS Fargate services and waits until every target is healthy (~6-10 min).
source "$(dirname "$0")/common.sh"
start_log 03-platform
tf infra/2-platform init -input=false -upgrade >/dev/null
tf infra/2-platform apply -auto-approve -input=false -var image_tag="${TAG:-v1}" || exit 1
URL=$(tf_out infra/2-platform base_url)

step "waiting for healthy targets behind the ALB"
for i in $(seq 1 60); do
  ok=0; total=0
  for tg in $(tf infra/2-platform output -json target_groups | python3 -c 'import json,sys;print(" ".join(json.load(sys.stdin).values()))'); do
    total=$((total + $(aws elbv2 describe-target-health --target-group-arn $tg --query 'length(TargetHealthDescriptions)' --output text)))
    ok=$((ok + $(aws elbv2 describe-target-health --target-group-arn $tg --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)))
  done
  echo "  $(date +%T) healthy targets: $ok/$total"
  [ "$total" -ge 5 ] && [ "$ok" -eq "$total" ] && break
  sleep 15
done

step "smoke test through the ALB: $URL"
curl -s -i "$URL/api/donors" | sed -n '1p;/[Xx]-[Ii]nstance/p'
curl -s "$URL/api/inventory"; echo
curl -s "$URL/api/requests/stock"; echo

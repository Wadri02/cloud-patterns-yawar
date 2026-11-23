#!/usr/bin/env bash
# Deploys the Python Lambda (API Gateway HTTP API + EventBridge hourly rule) and tests it (~2 min).
source "$(dirname "$0")/../../scripts/aws/common.sh"
start_log 04-lambda
D=04-serverless-and-containers/lambda/terraform

step "unit tests (pytest)"
(cd "$ROOT/04-serverless-and-containers/lambda" && python3 -m pytest -q tests)

step "terraform apply"
tf $D init -input=false -upgrade >/dev/null
tf $D apply -auto-approve -input=false | tail -5
API=$(tf_out $D api_url)

step "1st call through API Gateway (cold start expected)"
curl -s -X POST "$API/stock-alerts" -H 'Content-Type: application/json' \
  -d '{"center":"Hospital Eugenio Espejo","stock":{"O+":12,"O-":2,"A+":7,"B-":0}}'; echo
step "2nd call (warm)"
curl -s -X POST "$API/stock-alerts" -H 'Content-Type: application/json' \
  -d '{"center":"HCAM Quito","stock":{"O+":30,"AB-":1}}'; echo
step "invalid input -> 400"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "$API/stock-alerts" -d '{"center":"X","stock":{"Z+":1}}'
step "direct invoke with the EventBridge scheduled event"
aws lambda invoke --function-name yawar-blood-stock-alert \
  --payload fileb://"$ROOT/04-serverless-and-containers/lambda/events/eventbridge_schedule.json" /tmp/out.json >/dev/null && cat /tmp/out.json; echo
step "CloudWatch Logs (INIT / REPORT lines show cold start and billed duration)"
sleep 8
aws logs tail /aws/lambda/yawar-blood-stock-alert --since 10m --format short | grep -E "INIT_START|REPORT|coldStart" | tail -12

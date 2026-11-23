#!/usr/bin/env bash
# Deploys CloudFront -> API Gateway -> ALB in front of the platform and tests each layer (~10-15 min,
# CloudFront takes the longest). Requires scripts/aws/03-platform.sh to be deployed first.
source "$(dirname "$0")/../scripts/aws/common.sh"
start_log 05-edge
D=05-api-gateway-lb-reverse-proxy/terraform
CF_ON="${ENABLE_CLOUDFRONT:-true}"
tf $D init -input=false -upgrade >/dev/null
tf $D apply -auto-approve -input=false -var enable_cloudfront=$CF_ON | tail -4
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "terraform apply failed - if the error is about CloudFront, re-run with: ENABLE_CLOUDFRONT=false $0"; exit 1; }
CF=$(tf_out $D cloudfront_url); ALB=$(tf_out $D alb_url)
if [ -z "$CF" ]; then
  CF=$(tf_out $D api_gateway_url); CF=${CF%/prod}/prod
  echo "CloudFront disabled: testing API Gateway directly"
fi
KEY=$(tf $D output -json api_keys | python3 -c 'import json,sys;print(json.load(sys.stdin)["hospital-hcam"])')
KEY2=$(tf $D output -json api_keys | python3 -c 'import json,sys;print(json.load(sys.stdin)["web-app"])')
echo "entry point: $CF"
step "waiting for the entry point to answer (CloudFront can take 5-15 min)"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$CF/api/donors")
  echo "  $(date +%T) HTTP $code"
  [ "$code" = 403 ] && break      # 403 without key = the gateway is answering
  sleep 20
done
sleep 10

step "1. REVERSE PROXY (CloudFront): HTTPS at the edge, origin hidden"
curl -s -I "$CF/api/donors" -H "x-api-key: $KEY" | grep -iE "^HTTP|^via|^x-cache|^x-amz-cf-pop|^server"

step "2. API GATEWAY: no API key -> 403"
curl -s -w "  HTTP %{http_code}\n" "$CF/api/donors"

step "3. LOAD BALANCER: 6 calls with a valid key are spread over the ms-donors tasks"
for i in 1 2 3 4 5 6; do
  curl -s -D - -o /dev/null "$CF/api/donors" -H "x-api-key: $KEY" | grep -i "^x-instance"; sleep 1.2
done

step "4. EDGE CACHE: /api/inventory is cached 5 s by CloudFront"
for i in 1 2; do curl -s -D - -o /dev/null "$CF/api/inventory" -H "x-api-key: $KEY" | grep -i "^x-cache"; done

step "5. API GATEWAY THROTTLING (usage plan: 1 req/s, burst 5): 15 rapid calls from the web-app key"
for i in $(seq 1 15); do curl -s -o /dev/null -w "%{http_code} " "$CF/api/donors" -H "x-api-key: $KEY2"; done; echo

step "6. The same request straight to the ALB (no key, no throttling, no TLS): why the layers matter"
curl -s -o /dev/null -w "ALB direct -> HTTP %{http_code}\n" "$ALB/api/donors"

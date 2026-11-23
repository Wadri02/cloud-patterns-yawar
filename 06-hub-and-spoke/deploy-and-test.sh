#!/usr/bin/env bash
# Deploys the Transit Gateway hub + 4 VPCs + probe instances and reads the connectivity matrix from
# the instance consoles (~10 min). COST: ~$0.20/h while it exists -> destroy at the end (asked below).
source "$(dirname "$0")/../scripts/aws/common.sh"
start_log 06-hub-and-spoke
D=06-hub-and-spoke/terraform
tf $D init -input=false -upgrade >/dev/null
tf $D apply -auto-approve -input=false | tail -4
step "Transit Gateway route tables"
for rt in $(aws ec2 describe-transit-gateway-route-tables --filters Name=transit-gateway-id,Values=$(tf_out $D transit_gateway_id) --query 'TransitGatewayRouteTables[].TransitGatewayRouteTableId' --output text); do
  name=$(aws ec2 describe-transit-gateway-route-tables --transit-gateway-route-table-ids $rt --query 'TransitGatewayRouteTables[0].Tags[?Key==`Name`].Value' --output text)
  echo "$name:"; aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id $rt --filters Name=state,Values=active --query 'Routes[].DestinationCidrBlock' --output text
done
step "waiting for the probes (they start 90 s after boot)"
IDS=$(tf $D output -json probe_instances | python3 -c 'import json,sys;print(" ".join(f"{k}={v}" for k,v in json.load(sys.stdin).items()))')
for i in $(seq 1 30); do
  done_n=0
  for kv in $IDS; do
    aws ec2 get-console-output --instance-id ${kv##*=} --latest --output text 2>/dev/null | grep -q YAWAR-PROBE-DONE && done_n=$((done_n+1))
  done
  echo "  $(date +%T) probes finished: $done_n/4"; [ $done_n -eq 4 ] && break; sleep 30
done
step "connectivity matrix (expected: hospital cannot reach donors in either direction)"
for kv in $IDS; do
  aws ec2 get-console-output --instance-id ${kv##*=} --latest --output text | grep -o "YAWAR-PROBE from=.*" | grep -v DONE
done
echo
read -r -p "Destroy the hub-and-spoke stack now to stop the hourly cost? [Y/n] " a
[ "${a:-Y}" != n ] && tf $D destroy -auto-approve -input=false | tail -2

#!/usr/bin/env bash
# Verifies tools and AWS Academy credentials before deploying anything.
source "$(dirname "$0")/common.sh"
for t in aws terraform docker java mvn python3 curl ssh; do
  printf "%-10s " "$t"; command -v $t >/dev/null && echo OK || echo "MISSING"
done
echo; aws sts get-caller-identity || { echo "No AWS credentials. Copy them from Learner Lab > AWS Details > AWS CLI into ~/.aws/credentials"; exit 1; }
echo "region: $AWS_REGION   your IP: $(my_ip_cidr)"

#!/usr/bin/env bash
# Deletes EVERYTHING created by the project, in reverse order. Run it when you finish each session.
source "$(dirname "$0")/common.sh"
IP=$(my_ip_cidr)
for d in 08-bastion/terraform 07-lift-and-shift/terraform 06-hub-and-spoke/terraform \
         05-api-gateway-lb-reverse-proxy/terraform 04-serverless-and-containers/lambda/terraform \
         infra/2-platform infra/1-bootstrap; do
  st="$ROOT/$d/terraform.tfstate"
  if [ -f "$st" ] && [ "$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['resources']))" "$st")" != "0" ]; then
    echo "### destroying $d"
    extra=""; grep -q admin_cidr "$ROOT/$d/main.tf" && extra="-var admin_cidr=$IP"
    tf "$d" destroy -auto-approve -input=false $extra
  fi
done
BUCKET="yawar-artifacts-$(aws sts get-caller-identity --query Account --output text)"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "### deleting S3 bucket $BUCKET"; aws s3 rb "s3://$BUCKET" --force
fi
echo "Done. Check the AWS console (EC2, ECS, VPC, CloudFront, Transit Gateway) that nothing is left."

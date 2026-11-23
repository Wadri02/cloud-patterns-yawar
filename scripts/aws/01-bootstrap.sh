#!/usr/bin/env bash
# Creates the ECR repositories (Terraform) and the S3 artefact bucket (AWS CLI) (~1 min).
source "$(dirname "$0")/common.sh"
start_log 01-bootstrap
D=infra/1-bootstrap
tf $D init -input=false -upgrade >/dev/null
# clean up the state left by the first version of this stack, which managed the bucket in Terraform
for r in aws_s3_bucket_public_access_block.artifacts aws_s3_bucket.artifacts; do
  tf $D state list 2>/dev/null | grep -qx "$r" && tf $D state rm "$r"
done
tf $D apply -auto-approve -input=false || exit 1

BUCKET=$(tf_out $D artifact_bucket)
step "S3 artefact bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "bucket already exists"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" >/dev/null && echo "bucket created"
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging 'TagSet=[{Key=Project,Value=yawar-cloud-patterns}]'
aws s3 ls | grep "$BUCKET"
step "ECR repositories"
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `yawar/`)].[repositoryName,repositoryUri]' --output table

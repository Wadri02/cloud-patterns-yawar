#!/usr/bin/env bash
# Runs the unit tests, builds the 3 Java images for linux/amd64 and pushes them to Amazon ECR (~5-8 min).
source "$(dirname "$0")/common.sh"
start_log 02-build-push
TAG="${TAG:-v1}"
REG=$(tf_out infra/1-bootstrap ecr_registry)

step "mvn test (JUnit)"
(cd "$ROOT/backend" && mvn -B -q test && echo "all tests passed") || exit 1

step "docker login to $REG"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REG"

for m in ms-donors ms-inventory ms-requests; do
  step "build + push $m:$TAG"
  docker build --platform linux/amd64 --build-arg MODULE=$m -t "$REG/yawar/$m:$TAG" "$ROOT/backend" && docker push -q "$REG/yawar/$m:$TAG"
done
step "images in ECR"
for m in ms-donors ms-inventory ms-requests; do
  aws ecr describe-images --repository-name yawar/$m --query 'imageDetails[].[repositoryName,imageTags[0],imageSizeInBytes,imagePushedAt]' --output text
done

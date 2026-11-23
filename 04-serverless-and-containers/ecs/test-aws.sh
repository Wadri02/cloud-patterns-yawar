#!/usr/bin/env bash
# Shows the ECS Fargate side: services, tasks, logs and SELF-HEALING of an unhealthy task (~4 min).
source "$(dirname "$0")/../../scripts/aws/common.sh"
start_log 04-ecs
URL=$(tf_out infra/2-platform base_url); C=$(tf_out infra/2-platform cluster)

step "ECS services (desired vs running)"
aws ecs describe-services --cluster $C --services ms-donors ms-inventory ms-requests \
  --query 'services[].[serviceName,desiredCount,runningCount,launchType]' --output table
step "running tasks of ms-donors (one per IP)"
aws ecs list-tasks --cluster $C --service-name ms-donors --query 'taskArns' --output text | tr '\t' '\n' | while read t; do
  aws ecs describe-tasks --cluster $C --tasks $t --query 'tasks[0].[taskArn,lastStatus,healthStatus,cpu,memory,attachments[0].details[?name==`privateIPv4Address`].value|[0]]' --output text
done
step "task definition (cpu/memory/image)"
aws ecs describe-task-definition --task-definition yawar-ms-donors --query 'taskDefinition.[family,revision,cpu,memory,containerDefinitions[0].image]' --output text

step "inject a failure into ONE ms-donors task through the ALB"
curl -s -X POST "$URL/api/donors/chaos?mode=fail"; echo
TG=$(tf infra/2-platform output -json target_groups | python3 -c 'import json,sys;print(json.load(sys.stdin)["ms-donors"])')
step "ALB marks it unhealthy and ECS replaces the task (polling every 15 s)"
for i in $(seq 1 16); do
  echo "--- $(date +%T)"
  aws elbv2 describe-target-health --target-group-arn $TG --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
  sleep 15
done
step "ECS service events (look for 'unhealthy' and 'has started 1 tasks')"
aws ecs describe-services --cluster $C --services ms-donors --query 'services[0].events[:8].[createdAt,message]' --output text
step "last log lines of ms-donors in CloudWatch"
aws logs tail /ecs/yawar/ms-donors --since 15m --format short | grep -E "chaos|GET /api/donors|Started" | tail -10

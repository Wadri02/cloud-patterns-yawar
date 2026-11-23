# Stack 2 - the Yawar runtime on AWS:
#   VPC (2 public subnets / 2 AZ)  ->  Application Load Balancer (path routing + health checks)
#   ->  ECS Fargate services: ms-donors (x3), ms-inventory (x1), ms-requests (x1)
# Tasks run in public subnets with a public IP (to pull from ECR without a paid NAT gateway),
# but their security group only accepts traffic coming FROM the ALB.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = { Project = "yawar-cloud-patterns" } }
}

variable "region"        { default = "us-east-1" }
variable "image_tag"     { default = "v1" }
variable "donors_count"  { default = 3 }
variable "task_cpu"      { default = 512 }  # 0.5 vCPU (Spring Boot starts too slowly on 0.25)
variable "task_memory"   { default = 1024 } # 1 GB

data "aws_caller_identity" "me" {}
data "aws_iam_role" "lab" { name = "LabRole" } # AWS Academy: IAM roles cannot be created
data "aws_availability_zones" "az" { state = "available" }

locals {
  registry = "${data.aws_caller_identity.me.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  services = {
    ms-donors    = { path = "/api/donors*", count = var.donors_count, priority = 10 }
    ms-inventory = { path = "/api/inventory*", count = 1, priority = 20 } # 1 task: its failure mode lives in memory
    ms-requests  = { path = "/api/requests*", count = 1, priority = 30 }
  }
}

# ---------------------------------------------------------------- network
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "yawar-platform" }
}

resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id }

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.az.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "yawar-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name   = "yawar-alb"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tasks" {
  name   = "yawar-tasks"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "only from the ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------- load balancer
resource "aws_lb" "alb" {
  name               = "yawar-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = 120 # the circuit-breaker demo answers after ~30 s
}

resource "aws_lb_target_group" "svc" {
  for_each             = local.services
  name                 = "yawar-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 10
  health_check {
    path                = "/actuator/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"no route\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "svc" {
  for_each     = local.services
  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority
  condition {
    path_pattern { values = [each.value.path] }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }
}

# ---------------------------------------------------------------- ECS
resource "aws_ecs_cluster" "yawar" {
  name = "yawar-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each          = local.services
  name              = "/ecs/yawar/${each.key}"
  retention_in_days = 3
}

resource "aws_ecs_task_definition" "svc" {
  for_each                 = local.services
  family                   = "yawar-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name         = each.key
    image        = "${local.registry}/yawar/${each.key}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "INVENTORY_URL", value = "http://${aws_lb.alb.dns_name}/api/inventory" },
      { name = "JAVA_TOOL_OPTIONS", value = "-XX:TieredStopAtLevel=1" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.svc[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "svc" {
  for_each                          = local.services
  name                              = each.key
  cluster                           = aws_ecs_cluster.yawar.id
  task_definition                   = aws_ecs_task_definition.svc[each.key].arn
  desired_count                     = each.value.count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 120
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = each.key
    container_port   = 8080
  }
  depends_on = [aws_lb_listener_rule.svc]
}

output "alb_dns"       { value = aws_lb.alb.dns_name }
output "base_url"      { value = "http://${aws_lb.alb.dns_name}" }
output "cluster"       { value = aws_ecs_cluster.yawar.name }
output "target_groups" { value = { for k, t in aws_lb_target_group.svc : k => t.arn } }

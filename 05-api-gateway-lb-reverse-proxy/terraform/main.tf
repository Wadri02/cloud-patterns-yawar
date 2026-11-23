# Topic 5 on AWS - three layers in front of the ECS services of infra/2-platform:
#
#   Client --HTTPS--> CloudFront (REVERSE PROXY: TLS, edge cache 5 s for /api/inventory, hides origin)
#          --HTTPS--> Amazon API Gateway REST API (API GATEWAY: API key, usage plan throttling, routing)
#          --HTTP---> Application Load Balancer (LOAD BALANCER: round robin over 3 ms-donors tasks + health checks)
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

variable "region" { default = "us-east-1" }

data "terraform_remote_state" "platform" {
  backend = "local"
  config  = { path = "${path.module}/../../infra/2-platform/terraform.tfstate" }
}

locals {
  alb = data.terraform_remote_state.platform.outputs.alb_dns
}

# ---------------------------------------------------------------- API Gateway (REST)
resource "aws_api_gateway_rest_api" "yawar" {
  name = "yawar-api"
  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.yawar.id
  parent_id   = aws_api_gateway_rest_api.yawar.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.yawar.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id      = aws_api_gateway_rest_api.yawar.id
  resource_id      = aws_api_gateway_resource.proxy.id
  http_method      = "ANY"
  authorization    = "NONE"
  api_key_required = true
  request_parameters = { "method.request.path.proxy" = true }
}

resource "aws_api_gateway_integration" "alb" {
  rest_api_id             = aws_api_gateway_rest_api.yawar.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${local.alb}/api/{proxy}"
  request_parameters      = { "integration.request.path.proxy" = "method.request.path.proxy" }
  timeout_milliseconds    = 29000
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.yawar.id
  triggers = {
    redeploy = sha1(jsonencode([aws_api_gateway_method.proxy, aws_api_gateway_integration.alb]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.yawar.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
}

# One API key per client app, each with its own throttling (token bucket: 1 req/s, burst 5)
resource "aws_api_gateway_api_key" "client" {
  for_each = toset(["web-app", "hospital-hcam"])
  name     = "yawar-${each.key}"
}

resource "aws_api_gateway_usage_plan" "standard" {
  name = "yawar-standard"
  api_stages {
    api_id = aws_api_gateway_rest_api.yawar.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
  throttle_settings {
    rate_limit  = 1
    burst_limit = 5
  }
  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "client" {
  for_each      = aws_api_gateway_api_key.client
  key_id        = each.value.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.standard.id
}

# ---------------------------------------------------------------- CloudFront (reverse proxy)
# AWS Academy denies the CloudFront cache-policy APIs (List/Get/CreateCachePolicy), so the cache key and
# TTLs are set with the classic "forwarded_values" settings, which only need CreateDistribution.
# Set enable_cloudfront=false if the account does not allow CloudFront at all; the test then calls
# API Gateway directly and topic 5 is shown with two of its three layers on AWS.
variable "enable_cloudfront" { default = true }

resource "aws_cloudfront_distribution" "edge" {
  count           = var.enable_cloudfront ? 1 : 0
  enabled         = true
  comment         = "yawar reverse proxy"
  price_class     = "PriceClass_100"
  is_ipv6_enabled = true

  origin {
    origin_id   = "apigw"
    domain_name = "${aws_api_gateway_rest_api.yawar.id}.execute-api.${var.region}.amazonaws.com"
    origin_path = "/prod"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # everything: no caching, forward the API key and the query string (Host is NOT forwarded)
  default_cache_behavior {
    target_origin_id       = "apigw"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    forwarded_values {
      query_string = true
      headers      = ["x-api-key", "X-Request-ID"]
      cookies { forward = "none" }
    }
  }

  # blood stock: cached 5 s at the edge, one cache entry per API key
  ordered_cache_behavior {
    path_pattern           = "/api/inventory*"
    target_origin_id       = "apigw"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    min_ttl                = 5
    default_ttl            = 5
    max_ttl                = 5
    forwarded_values {
      query_string = true
      headers      = ["x-api-key"]
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}

output "cloudfront_url"  { value = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.edge[0].domain_name}" : "" }
output "api_gateway_url" { value = aws_api_gateway_stage.prod.invoke_url }
output "alb_url"         { value = "http://${local.alb}" }
output "api_keys" {
  value     = { for k, v in aws_api_gateway_api_key.client : k => v.value }
  sensitive = true
}

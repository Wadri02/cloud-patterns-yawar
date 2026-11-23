# Yawar - blood-stock-alert on AWS Lambda + API Gateway (HTTP API) + EventBridge schedule.
# Designed for AWS Academy: IAM roles cannot be created there, so the pre-existing LabRole is used.
#   terraform init && terraform apply      (then: curl -X POST $(terraform output -raw api_url)/stock-alerts ...)
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" { region = var.region }

variable "region"    { default = "us-east-1" }
variable "min_units" { default = 5 }

data "aws_iam_role" "lab" { name = "LabRole" }

data "archive_file" "zip" {
  type        = "zip"
  source_file = "${path.module}/../handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_lambda_function" "stock_alert" {
  function_name    = "yawar-blood-stock-alert"
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.14"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256
  memory_size      = 128
  timeout          = 3
  environment { variables = { MIN_UNITS = tostring(var.min_units) } }
}

resource "aws_cloudwatch_log_group" "logs" {
  name              = "/aws/lambda/${aws_lambda_function.stock_alert.function_name}"
  retention_in_days = 7
}

# --- HTTP API trigger -------------------------------------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "yawar-stock-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.stock_alert.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /stock-alerts"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stock_alert.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# --- Scheduled trigger (every hour) -----------------------------------------
resource "aws_cloudwatch_event_rule" "hourly" {
  name                = "yawar-hourly-stock-check"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.hourly.name
  arn  = aws_lambda_function.stock_alert.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stock_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly.arn
}

output "api_url" { value = aws_apigatewayv2_api.http.api_endpoint }

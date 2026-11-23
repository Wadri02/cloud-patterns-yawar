# Topic 7 on AWS - REHOST target for the legacy registry.
# The on-premises server is your own PC (java -jar legacy-registry.jar). migrate-to-aws.sh uploads the
# SAME jar + config + data + systemd unit to S3; this EC2 instance installs Java 21 (Amazon Corretto),
# copies them and starts the service exactly as on-premises. No code changes.
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

variable "region"     { default = "us-east-1" }
variable "admin_cidr" { description = "your public IP in CIDR form, e.g. 181.198.10.20/32" }
variable "key_name"   { default = "vockey" } # AWS Academy key pair (labsuser.pem)

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config  = { path = "${path.module}/../../infra/1-bootstrap/terraform.tfstate" }
}

data "aws_vpc" "default" { default = true }

# Latest Amazon Linux 2023 AMI, from the public SSM parameter AWS maintains for it
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "legacy" {
  name   = "yawar-legacy-sg"
  vpc_id = data.aws_vpc.default.id
  ingress {
    description = "app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "ssh for the final delta sync"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "legacy" {
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = "t3.small"           # 2 GB like a small on-prem VM; right-size AFTER migrating
  iam_instance_profile   = "LabInstanceProfile" # AWS Academy: lets the instance read the S3 bucket
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.legacy.id]
  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }
  user_data = <<-EOT
    #!/bin/bash
    set -e
    B=s3://${data.terraform_remote_state.bootstrap.outputs.artifact_bucket}/legacy
    dnf install -y java-21-amazon-corretto-headless
    mkdir -p /opt/yawar /etc/yawar /var/lib/yawar
    aws s3 cp $B/legacy-registry.jar   /opt/yawar/legacy-registry.jar
    aws s3 cp $B/app.aws.conf          /etc/yawar/app.conf
    aws s3 cp $B/donors.csv            /var/lib/yawar/donors.csv
    aws s3 cp $B/yawar-legacy.service  /etc/systemd/system/yawar-legacy.service
    systemctl daemon-reload
    systemctl enable --now yawar-legacy
  EOT
  tags = { Name = "yawar-legacy-rehosted" }
}

output "public_ip" { value = aws_instance.legacy.public_ip }
output "url"       { value = "http://${aws_instance.legacy.public_ip}:8080" }

# Topic 8 on AWS - classic bastion host.
#   public subnet  : bastion (t3.nano, SSH 22 only from your IP)
#   private subnet : ms-donors-db (no public IP, no internet route). Accepts SSH and 8080 ONLY from the
#                    bastion's security group. It serves the donor list on :8080 (python3 http.server).
# Use it:  ssh -J ec2-user@<bastion> ec2-user@<private_ip>        (ProxyJump)
#          ssh -N -L 9090:<private_ip>:8080 ec2-user@<bastion>  (port forwarding) then curl localhost:9090
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

data "aws_availability_zones" "az" { state = "available" }

# Latest Amazon Linux 2023 AMI, from the public SSM parameter AWS maintains for it
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "yawar-bastion-vpc" }
}

resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id }

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.30.1.0/24"
  availability_zone       = data.aws_availability_zones.az.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.30.2.0/24"
  availability_zone = data.aws_availability_zones.az.names[0]
  tags              = { Name = "private-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# the private subnet keeps the VPC main route table: local routes only, no internet

resource "aws_security_group" "bastion" {
  name   = "yawar-bastion-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    description = "SSH from the administrator only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    description = "only towards the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_security_group" "private" {
  name   = "yawar-private-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "SSH only from the bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description     = "app only from the bastion (port forwarding)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  metadata_options { http_tokens = "required" } # IMDSv2
  tags = { Name = "yawar-bastion" }
}

resource "aws_instance" "private" {
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.private.id]
  user_data              = <<-EOT
    #!/bin/bash
    mkdir -p /srv/api && cd /srv
    echo '[{"id":"D-001","name":"Ana Quishpe","bloodType":"O+"},{"id":"D-002","name":"Luis Andrade","bloodType":"A-"}]' > /srv/api/donors
    nohup python3 -m http.server 8080 >/dev/null 2>&1 &
  EOT
  tags = { Name = "yawar-ms-donors-db" }
}

output "bastion_public_ip" { value = aws_instance.bastion.public_ip }
output "private_ip"        { value = aws_instance.private.private_ip }

# Topic 6 on AWS - hub-and-spoke with AWS Transit Gateway.
#   hub (shared services) 10.0.0.0/16 | spoke-donors 10.1.0.0/16 | spoke-inventory 10.2.0.0/16 | spoke-hospital 10.3.0.0/16
# Two TGW route tables implement the policy:
#   rt-internal (hub, donors, inventory) -> can reach every attachment
#   rt-partner  (hospital)               -> can reach ONLY hub + inventory (never the donors' personal data)
# Each VPC has a tiny probe instance (10.x.0.10) that serves HTTP on 8080 and, at boot, tries to reach
# the other three. Results are printed to the instance console:  aws ec2 get-console-output --latest
# COST: 4 TGW attachments x $0.05/h -> destroy right after taking the evidence.
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

locals {
  vpcs = {
    hub       = "10.0.0.0/16"
    donors    = "10.1.0.0/16"
    inventory = "10.2.0.0/16"
    hospital  = "10.3.0.0/16"
  }
  probe_ip    = { for k, c in local.vpcs : k => cidrhost(cidrsubnet(c, 8, 0), 10) }
  association = { hub = "internal", donors = "internal", inventory = "internal", hospital = "partner" }
  propagate_internal = ["hub", "donors", "inventory", "hospital"]
  propagate_partner  = ["hub", "inventory"]
}

data "aws_availability_zones" "az" { state = "available" }

# Latest Amazon Linux 2023 AMI, from the public SSM parameter AWS maintains for it
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value
  enable_dns_hostnames = true
  tags                 = { Name = "yawar-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each          = local.vpcs
  vpc_id            = aws_vpc.this[each.key].id
  cidr_block        = cidrsubnet(each.value, 8, 0)
  availability_zone = data.aws_availability_zones.az.names[0]
  tags              = { Name = "yawar-${each.key}-private" }
}

# ---------------------------------------------------------------- the hub
resource "aws_ec2_transit_gateway" "hub" {
  description                     = "yawar hub"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags                            = { Name = "yawar-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att" {
  for_each           = local.vpcs
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  vpc_id             = aws_vpc.this[each.key].id
  subnet_ids         = [aws_subnet.private[each.key].id]
  tags               = { Name = "yawar-${each.key}-att" }
}

resource "aws_ec2_transit_gateway_route_table" "internal" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = { Name = "rt-internal" }
}

resource "aws_ec2_transit_gateway_route_table" "partner" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = { Name = "rt-partner" }
}

resource "aws_ec2_transit_gateway_route_table_association" "assoc" {
  for_each                       = local.association
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att[each.key].id
  transit_gateway_route_table_id = each.value == "internal" ? aws_ec2_transit_gateway_route_table.internal.id : aws_ec2_transit_gateway_route_table.partner.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "internal" {
  for_each                       = toset(local.propagate_internal)
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.internal.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "partner" {
  for_each                       = toset(local.propagate_partner)
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.partner.id
}

# every VPC sends 10.0.0.0/8 to the hub (spokes never peer with each other)
resource "aws_route_table" "rt" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  route {
    cidr_block         = "10.0.0.0/8"
    transit_gateway_id = aws_ec2_transit_gateway.hub.id
  }
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.att]
}

resource "aws_route_table_association" "rta" {
  for_each       = local.vpcs
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.rt[each.key].id
}

# ---------------------------------------------------------------- probe instances
resource "aws_security_group" "probe" {
  for_each = local.vpcs
  name     = "yawar-${each.key}-probe"
  vpc_id   = aws_vpc.this[each.key].id
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }
}

resource "aws_instance" "probe" {
  for_each               = local.vpcs
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.private[each.key].id
  private_ip             = local.probe_ip[each.key]
  vpc_security_group_ids = [aws_security_group.probe[each.key].id]
  user_data = templatefile("${path.module}/probe.sh.tftpl", {
    name    = each.key
    targets = join(" ", [for k, ip in local.probe_ip : "${k}=${ip}" if k != each.key])
  })
  tags       = { Name = "yawar-${each.key}-probe" }
  depends_on = [aws_route_table_association.rta, aws_ec2_transit_gateway_route_table_propagation.internal, aws_ec2_transit_gateway_route_table_propagation.partner]
}

output "probe_instances" { value = { for k, i in aws_instance.probe : k => i.id } }
output "transit_gateway_id" { value = aws_ec2_transit_gateway.hub.id }

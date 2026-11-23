#!/usr/bin/env bash
# Deploys the bastion + private instance and proves the private one is only reachable through it (~5 min).
#   KEY=~/.ssh/labsuser.pem ./deploy-and-test.sh     (download labsuser.pem from Learner Lab > AWS Details)
source "$(dirname "$0")/../scripts/aws/common.sh"
start_log 08-bastion
KEY="${KEY:-$HOME/.ssh/labsuser.pem}"; chmod 400 "$KEY"
D=08-bastion/terraform; IP=$(my_ip_cidr)
tf $D init -input=false -upgrade >/dev/null
tf $D apply -auto-approve -input=false -var admin_cidr=$IP | tail -3
B=$(tf_out $D bastion_public_ip); P=$(tf_out $D private_ip)
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o IdentitiesOnly=yes"
echo "bastion=$B (public)  private=$P  admin=$IP"
step "waiting for SSH on the bastion"
until $SSH ec2-user@$B true 2>/dev/null; do sleep 10; done

step "1. the private instance has no public IP: direct access from the internet is impossible"
aws ec2 describe-instances --filters Name=private-ip-address,Values=$P --query 'Reservations[0].Instances[0].[InstanceId,PrivateIpAddress,PublicIpAddress]' --output text
curl -s -m 5 "http://$P:8080/api/donors" || echo "curl http://$P:8080 -> unreachable (private address)"

step "2. Jump through the bastion (= ssh -J bastion private) -> run a command ON the private instance"
sleep 20
$SSH -o ProxyCommand="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -W %h:%p ec2-user@$B" \
  ec2-user@$P 'hostname; curl -s localhost:8080/api/donors; echo'

step "3. Port forwarding through the bastion: localhost:9090 -> $P:8080"
$SSH -f -N -L 9090:$P:8080 ec2-user@$B; sleep 2
curl -s localhost:9090/api/donors; echo
pkill -f "9090:$P:8080"

step "4. SSH from the bastion to the private host is allowed, but the bastion cannot reach the internet"
$SSH ec2-user@$B "curl -s -m 5 https://aws.amazon.com >/dev/null && echo internet OK || echo 'no internet egress from the bastion (SG egress = VPC only)'"

step "5. audit trail on the bastion (sshd log)"
$SSH ec2-user@$B "sudo journalctl -u sshd --since '-15 min' --no-pager | grep -E 'Accepted|session opened|Disconnected' | tail -8"

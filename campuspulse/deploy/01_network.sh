#!/usr/bin/env bash
# Creates the isolated network the platform lives in:
#   VPC -> internet gateway -> route table -> 2 public subnets in 2 AZs
#   plus a security group that is the platform's firewall.
set -euo pipefail
source "$(dirname "$0")/00_config.sh"

echo "== VPC"
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT}-vpc},{Key=Project,Value=${PROJECT}}]" \
  --query 'Vpc.VpcId' --output text)
save VPC_ID "$VPC_ID"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support

echo "== internet gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT}-igw},{Key=Project,Value=${PROJECT}}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
save IGW_ID "$IGW_ID"
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

echo "== subnets (two availability zones, for the high-availability story)"
AZ_A="${AWS_REGION}a"; AZ_B="${AWS_REGION}b"
SUBNET_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_A_CIDR" \
  --availability-zone "$AZ_A" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-public-a},{Key=Project,Value=${PROJECT}}]" \
  --query 'Subnet.SubnetId' --output text)
SUBNET_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_B_CIDR" \
  --availability-zone "$AZ_B" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-public-b},{Key=Project,Value=${PROJECT}}]" \
  --query 'Subnet.SubnetId' --output text)
save SUBNET_A "$SUBNET_A"
save SUBNET_B "$SUBNET_B"
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_A" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_B" --map-public-ip-on-launch

echo "== route table"
RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-public-rt},{Key=Project,Value=${PROJECT}}]" \
  --query 'RouteTable.RouteTableId' --output text)
save RTB_ID "$RTB_ID"
aws ec2 create-route --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_A" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_B" >/dev/null

echo "== security group"
SG_ID=$(aws ec2 create-security-group --group-name "${PROJECT}-web-sg" \
  --description "CampusPulse web tier: HTTP/HTTPS public, SSH from admin IP only" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)
save SG_ID "$SG_ID"

MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
save MY_IP "$MY_IP"
echo "   locking SSH to ${MY_IP}/32"

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --ip-permissions \
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MY_IP}/32,Description=admin-ssh}]" \
  "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=dashboard}]" \
  "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0,Description=dashboard-tls}]" >/dev/null

echo
echo "network ready. Ids stored in $STATE_FILE"

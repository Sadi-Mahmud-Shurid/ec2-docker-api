#!/usr/bin/env bash
set -euo pipefail

# --- Configuration Variables ---
REGION="eu-central-1"
AZ="eu-central-1a"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
NAME_PREFIX="ec2-docker-api"

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${NAME_PREFIX}-vpc}]" \
  --query "Vpc.VpcId" \
  --output text)

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames "{\"Value\":true}"

echo "Creating public subnet..."
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-subnet}]" \
  --query "Subnet.SubnetId" \
  --output text)

aws ec2 modify-subnet-attribute \
  --subnet-id "$SUBNET_ID" \
  --map-public-ip-on-launch

echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-igw}]" \
  --query "InternetGateway.InternetGatewayId" \
  --output text)

aws ec2 attach-internet-gateway \
  --vpc-id "$VPC_ID" \
  --internet-gateway-id "$IGW_ID"

echo "Creating route table..."
RT_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-rt}]" \
  --query "RouteTable.RouteTableId" \
  --output text)

aws ec2 create-route \
  --route-table-id "$RT_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"

aws ec2 associate-route-table \
  --route-table-id "$RT_ID" \
  --subnet-id "$SUBNET_ID"

# --- Write resource IDs to .env.local ---
# source with `source .env.local` in a new session
cat > .env.local << EOF
export VPC_ID=$VPC_ID
export SUBNET_ID=$SUBNET_ID
export IGW_ID=$IGW_ID
export RT_ID=$RT_ID
EOF

echo "Done. Resource IDs written to .env.local"
echo "VPC_ID=$VPC_ID"
echo "SUBNET_ID=$SUBNET_ID"
echo "IGW_ID=$IGW_ID"
echo "RT_ID=$RT_ID"
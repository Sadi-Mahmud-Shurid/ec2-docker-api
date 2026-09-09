#!/usr/bin/env bash
set -euo pipefail

# ─── Config ───────────────────────────────────────────────
NAME_PREFIX="ec2-docker-api"
KEY_NAME="ec2-docker-api-key"
KEY_FILE="${KEY_NAME}.pem"
INSTANCE_TYPE="t3.micro"
SSH_PORT=22
APP_PORT=5000

# Requires VPC_ID and SUBNET_ID already set (source .env.local from create-network.sh first)
: "${VPC_ID:?VPC_ID not set — run 'source .env.local' first}"
: "${SUBNET_ID:?SUBNET_ID not set — run 'source .env.local' first}"

# ─── Security Group ───────────────────────────────────────
echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "${NAME_PREFIX}-sg" \
  --description "Security group for ${NAME_PREFIX} EC2 instance" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)

MY_IP=$(curl -s https://checkip.amazonaws.com)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port "$SSH_PORT" \
  --cidr "${MY_IP}/32"

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port "$APP_PORT" \
  --cidr 0.0.0.0/0

# ─── Key Pair ──────────────────────────────────────────────
# Only create if it doesn't already exist — re-running this script
# with an existing key name would otherwise error out.
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair '$KEY_NAME' already exists — skipping creation."
  echo "NOTE: if you don't have the matching ${KEY_FILE} locally, SSH will not work."
else
  echo "Creating key pair..."
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query "KeyMaterial" \
    --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
fi

# ─── AMI Lookup ────────────────────────────────────────────
echo "Looking up latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)

# ─── Launch Instance ───────────────────────────────────────
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}-instance}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

INSTANCE_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

# ─── Persist for later sessions ───────────────────────────
cat >> .env.local << EOF
export SG_ID=$SG_ID
export AMI_ID=$AMI_ID
export INSTANCE_ID=$INSTANCE_ID
export INSTANCE_IP=$INSTANCE_IP
EOF

echo "Done."
echo "SG_ID=$SG_ID"
echo "AMI_ID=$AMI_ID"
echo "INSTANCE_ID=$INSTANCE_ID"
echo "INSTANCE_IP=$INSTANCE_IP"
echo ""
echo "SSH with: ssh -i $KEY_FILE ec2-user@$INSTANCE_IP"
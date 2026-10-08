#!/usr/bin/env bash
# Launches the single t3.micro that runs the containers.
set -euo pipefail
source "$(dirname "$0")/00_config.sh"
need VPC_ID; need SUBNET_A; need SG_ID; need PROFILE

echo "== SSH key pair"
mkdir -p "${HOME}/.ssh"
umask 077
if [ ! -f "${HOME}/.ssh/${KEY_NAME}.pem" ]; then
  aws ec2 create-key-pair --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "${HOME}/.ssh/${KEY_NAME}.pem"
  chmod 400 "${HOME}/.ssh/${KEY_NAME}.pem"
  echo "   private key written to ~/.ssh/${KEY_NAME}.pem - it is never shown again"
else
  echo "   reusing ~/.ssh/${KEY_NAME}.pem"
fi

echo "== latest Ubuntu 24.04 LTS AMI for ${AWS_REGION}"
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' --output text)
save AMI_ID "$AMI_ID"

echo "== launching ${INSTANCE_TYPE}"
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_A" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile "Name=${PROFILE}" \
  --user-data "file://$(dirname "$0")/user-data.sh" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${ROOT_VOLUME_GB},\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":true}}]" \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-app},{Key=Project,Value=${PROJECT}}]" \
  --query 'Instances[0].InstanceId' --output text)
save INSTANCE_ID "$INSTANCE_ID"

echo "   waiting for the instance to run..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save PUBLIC_IP "$PUBLIC_IP"

echo
echo "instance ${INSTANCE_ID} is up at ${PUBLIC_IP}"
echo "the bootstrap script needs about 3 minutes. Then:"
echo "  ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${PUBLIC_IP}"

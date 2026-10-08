#!/usr/bin/env bash
# Identity and secrets.
#   * one IAM role the EC2 instance assumes  -> no access keys on the box
#   * one least-privilege policy             -> only these tables, only this
#                                               bucket prefix, only this
#                                               parameter, nothing else
#   * one SSM SecureString                   -> the JWT signing key, encrypted
set -euo pipefail
source "$(dirname "$0")/00_config.sh"
need BUCKET

ROLE="${PROJECT}-ec2-role"
POLICY="${PROJECT}-app-policy"
PROFILE="${PROJECT}-instance-profile"
save ROLE "$ROLE"; save POLICY "$POLICY"; save PROFILE "$PROFILE"

echo "== trust policy: only the EC2 service may assume this role"
cat > /tmp/${PROJECT}-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Service":"ec2.amazonaws.com"},
  "Action":"sts:AssumeRole"}]}
JSON

echo "== permission policy (least privilege)"
sed -e "s|__REGION__|${AWS_REGION}|g" \
    -e "s|__ACCOUNT__|${ACCOUNT_ID}|g" \
    -e "s|__EVENTS_TABLE__|${EVENTS_TABLE}|g" \
    -e "s|__USERS_TABLE__|${USERS_TABLE}|g" \
    -e "s|__BUCKET__|${BUCKET}|g" \
    -e "s|__JWT_PARAM__|${JWT_PARAM}|g" \
    -e "s|__LOG_GROUP__|${LOG_GROUP}|g" \
    -e "s|__METRIC_NS__|${METRIC_NS}|g" \
    "$(dirname "$0")/iam-policy.json" > /tmp/${PROJECT}-policy.json

aws iam create-role --role-name "$ROLE" \
  --assume-role-policy-document file:///tmp/${PROJECT}-trust.json \
  --description "CampusPulse application role" \
  --tags Key=Project,Value="$PROJECT" >/dev/null

POLICY_ARN=$(aws iam create-policy --policy-name "$POLICY" \
  --policy-document file:///tmp/${PROJECT}-policy.json \
  --query 'Policy.Arn' --output text)
save POLICY_ARN "$POLICY_ARN"

aws iam attach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN"
# lets the CloudWatch agent publish host metrics and logs
aws iam attach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

aws iam attach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name "$PROFILE" >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"

echo "== JWT signing key -> SSM Parameter Store (SecureString, KMS encrypted)"
SECRET=$(openssl rand -base64 48 | tr -d '\n')
aws ssm put-parameter --name "$JWT_PARAM" --type SecureString \
  --value "$SECRET" --overwrite \
  --description "CampusPulse JWT signing key" >/dev/null
unset SECRET      # never leaves this shell, never touches a file

echo "   IAM is eventually consistent - waiting 15s before the instance uses it"
sleep 15
echo
echo "identity ready."

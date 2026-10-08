#!/usr/bin/env bash
# Shared configuration for every deploy script. Sourced, never run directly.
# Change values here once and the whole stack follows.

export AWS_REGION="${AWS_REGION:-eu-west-3}"        # Paris
export PROJECT="${PROJECT:-campuspulse}"

# networking
export VPC_CIDR="10.20.0.0/16"
export SUBNET_A_CIDR="10.20.1.0/24"
export SUBNET_B_CIDR="10.20.2.0/24"

# compute
export INSTANCE_TYPE="t3.micro"                     # verify account credits and regional pricing
export KEY_NAME="${PROJECT}-key"
export ROOT_VOLUME_GB=8                             # small encrypted root volume

# data
export EVENTS_TABLE="${PROJECT}-events"
export USERS_TABLE="${PROJECT}-users"
export JWT_PARAM="/${PROJECT}/jwt-secret"

# observability
export LOG_GROUP="/${PROJECT}/app"
export METRIC_NS="CampusPulse"
export ALERT_EMAIL="${ALERT_EMAIL:-CHANGE_ME@example.com}"

# cost guard
export MONTHLY_BUDGET_USD="${MONTHLY_BUDGET_USD:-20}"

# ---------------------------------------------------------------- internals
export STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.env"
touch "$STATE_FILE"
# shellcheck disable=SC1090
source "$STATE_FILE"

save() {   # save VAR value   -> remembers an id between scripts
  local key="$1" val="$2"
  grep -v "^export ${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "export ${key}=\"${val}\"" >> "$STATE_FILE"
  export "${key}=${val}"
  echo "  ${key} = ${val}"
}

need() {   # need VAR   -> fail early with a clear message instead of a stack trace
  local key="$1"
  if [ -z "${!key:-}" ]; then
    echo "missing ${key}. Run the earlier deploy scripts first." >&2
    exit 1
  fi
}

export AWS_PAGER=""  # disable the CLI pager
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ACCOUNT_ID

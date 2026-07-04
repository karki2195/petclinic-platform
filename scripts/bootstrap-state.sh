#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time provisioning of the Terraform remote state backend
#
# Creates the S3 bucket (versioned, encrypted, public access blocked) and the
# DynamoDB table (LockID partition key) that terraform/environments/{dev,prod}/backend.tf
# point to. This is run ONCE, outside of Terraform itself, because Terraform
# cannot manage the backend it also depends on (chicken-and-egg problem).
#
# Idempotent: safe to run multiple times. Existing resources are left alone;
# their versioning/encryption/public-access settings are re-applied so drift
# gets corrected.
#
# Usage:
#   ./scripts/bootstrap-state.sh [--region eu-central-1]
#
# See docs/technical-spec.md#terraform-state-backend for the values this
# script implements.
#

REGION="eu-central-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Options:"
  echo "  --region   AWS region to create the state bucket/table in (default: eu-central-1)"
  echo ""
  echo "Examples:"
  echo "  $0                       # Bootstrap in eu-central-1 (default)"
  echo "  $0 --region eu-central-1 # Explicit region"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="${2:-}"
      [[ -z "$REGION" ]] && usage
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI is required but not found." >&2; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "Region:  ${REGION}"
echo "Bucket:  ${BUCKET_NAME}"
echo "Table:   ${TABLE_NAME}"
echo ""

# --- S3 bucket for state files -------------------------------------------

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "S3 bucket ${BUCKET_NAME} already exists — skipping creation."
else
  echo "Creating S3 bucket ${BUCKET_NAME}..."
  # us-east-1 rejects an explicit LocationConstraint; every other region requires one.
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

echo "Enabling versioning on ${BUCKET_NAME}..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "Enabling default encryption (AES256) on ${BUCKET_NAME}..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }
    }]
  }'

echo "Blocking all public access on ${BUCKET_NAME}..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-tagging \
  --bucket "${BUCKET_NAME}" \
  --tagging 'TagSet=[{Key=Project,Value=petclinic},{Key=Purpose,Value=terraform-state}]'

# --- DynamoDB table for state locking --------------------------------------

if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE_NAME} already exists — skipping creation."
else
  echo "Creating DynamoDB table ${TABLE_NAME}..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=petclinic Key=Purpose,Value=terraform-state

  echo "Waiting for ${TABLE_NAME} to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
fi

echo ""
echo "Bootstrap complete."
echo "Backend config for terraform/environments/{dev,prod}/backend.tf:"
echo "  bucket         = \"${BUCKET_NAME}\""
echo "  region         = \"${REGION}\""
echo "  dynamodb_table = \"${TABLE_NAME}\""

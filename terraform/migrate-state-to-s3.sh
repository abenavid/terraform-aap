#!/usr/bin/env bash
# Migrate local terraform.tfstate into the S3 bucket created by this same config.
#
# Prerequisites:
#   1) Successful apply with backend "local" (e.g. deploy.yml).
#   2) In terraform/main.tf replace backend "local" {} with backend "s3" {}
#   3) Export TF_STATE_KEY, TF_S3_BACKEND_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#      (optional: TF_STATE_BUCKET — defaults to terraform output state_bucket_name)
#
# Run from repo root:  ./terraform/migrate-state-to-s3.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
  TF_STATE_BUCKET="$(terraform output -raw state_bucket_name)"
  export TF_STATE_BUCKET
fi

: "${TF_STATE_BUCKET:?}"
: "${TF_STATE_KEY:=terraform/terraform.tfstate}"
: "${TF_S3_BACKEND_REGION:?Set TF_S3_BACKEND_REGION (S3 bucket region)}"
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"

export TF_INPUT=0
terraform init -migrate-state -input=false \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="region=${TF_S3_BACKEND_REGION}" \
  -backend-config="access_key=${AWS_ACCESS_KEY_ID}" \
  -backend-config="secret_key=${AWS_SECRET_ACCESS_KEY}"

echo "Done. State should now live in s3://${TF_STATE_BUCKET}/${TF_STATE_KEY}"

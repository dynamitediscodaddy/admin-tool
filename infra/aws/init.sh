#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${AWS_REGION:?Set AWS_REGION}"
: "${TF_STATE_BUCKET:?Set TF_STATE_BUCKET to the bootstrap output}"
terraform -chdir=infra/aws/terraform init -input=false \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=app/terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"

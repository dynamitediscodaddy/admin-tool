#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source infra/aws/environment.sh
all=false
if [ "${1:-}" = --all ]; then all=true; shift; fi
if [ -z "${TF_STATE_BUCKET:-}" ]; then
  export TF_STATE_BUCKET="$(terraform -chdir=infra/aws/bootstrap output -raw state_bucket)"
fi
./infra/aws/init.sh
terraform -chdir=infra/aws/terraform destroy "$@"
if [ "$all" = true ]; then
  # Human bootstrap credentials are required; the GitHub role cannot delete itself/state storage.
  terraform -chdir=infra/aws/bootstrap init -input=false
  terraform -chdir=infra/aws/bootstrap destroy "$@"
fi

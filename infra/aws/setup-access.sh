#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source infra/aws/environment.sh
repository="${GITHUB_REPOSITORY:-dynamitediscodaddy/admin-tool}"
export TF_VAR_github_repository="$repository"
export TF_VAR_github_branch="${DEPLOY_BRANCH:-feature/container-deployment}"
for tool in aws terraform gh; do command -v "$tool" >/dev/null || { echo "Install $tool first." >&2; exit 1; }; done
# New GitHub repositories may include immutable owner/repository IDs in OIDC subjects.
# Query the actual prefix instead of assuming the historic name-only format.
if [ -z "${TF_VAR_github_subject_prefix:-}" ]; then
  custom_subject="$(gh api "repos/$repository/actions/oidc/customization/sub" --jq 'if .use_default == false then "custom" else "default" end')"
  if [ "$custom_subject" = custom ]; then
    echo 'Custom GitHub OIDC claims are configured. Set TF_VAR_github_subject_prefix to the exact repository prefix before continuing.' >&2
    exit 1
  fi
  subject_prefix="$(gh api "repos/$repository/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty')"
  if [ -z "$subject_prefix" ]; then
    canonical_repository="$(gh api "repos/$repository" --jq '.full_name')"
    subject_prefix="repo:$canonical_repository"
  fi
  export TF_VAR_github_subject_prefix="$subject_prefix"
fi
# This requires an existing human/admin session; no credential is stored by this script.
aws sts get-caller-identity --region "$AWS_REGION" --query '{Account:Account,Arn:Arn}'
terraform -chdir=infra/aws/bootstrap init -input=false
terraform -chdir=infra/aws/bootstrap apply "$@"
role="$(terraform -chdir=infra/aws/bootstrap output -raw role_arn)"
bucket="$(terraform -chdir=infra/aws/bootstrap output -raw state_bucket)"
audience="$(terraform -chdir=infra/aws/bootstrap output -raw audience)"
gh variable set AWS_DEPLOY_ROLE_ARN --repo "$repository" --body "$role"
gh variable set AWS_REGION --repo "$repository" --body "$AWS_REGION"
gh variable set AWS_OIDC_AUDIENCE --repo "$repository" --body "$audience"
gh variable set TF_STATE_BUCKET --repo "$repository" --body "$bucket"
printf 'Access ready for %s on branch %s. Keep infra/aws/bootstrap/terraform.tfstate safe and private.\n' "$repository" "$TF_VAR_github_branch"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source infra/aws/environment.sh
export TF_VAR_image_tag="$(git rev-parse HEAD)"
if [ -n "$(git status --porcelain)" ]; then
  echo 'Commit source changes before deploying so image tags identify the source.' >&2; exit 1
fi
./infra/aws/init.sh
# Bootstrap registries only on the first run; never disable an existing service.
terraform_outputs="$(terraform -chdir=infra/aws/terraform output -json)"
if ! grep -q '"web_repository_url"' <<<"$terraform_outputs"; then
  if terraform -chdir=infra/aws/terraform state list | grep -q '^module.app'; then
    echo 'Existing service state found without registry outputs. Repair state before continuing.' >&2; exit 1
  fi
  terraform -chdir=infra/aws/terraform apply -var=enable_service=false "$@"
fi
web="$(terraform -chdir=infra/aws/terraform output -raw web_repository_url)"
api="$(terraform -chdir=infra/aws/terraform output -raw api_repository_url)"
# Empty state can produce a warning with exit code zero for `terraform output -raw`.
# Validate the origins before passing them to Docker, even after registry bootstrap.
for repository_url in "$web" "$api"; do
  if [[ ! "$repository_url" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.(eu|com|com\.cn)/[a-z0-9_./-]+$ ]]; then
    echo 'Missing or invalid ECR repository output. Inspect Terraform state before retrying.' >&2
    exit 1
  fi
done
registry="${web%%/*}"
# Use the existing Docker configuration so proxy and registry settings are preserved.
error_file="$(mktemp)"
trap 'rm -f "$error_file"' EXIT
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
for component in api web; do
  if [ "$component" = api ]; then image="$api"; else image="$web"; fi
  repository="${image#*/}"
  if aws ecr describe-images --region "$AWS_REGION" --repository-name "$repository" --image-ids "imageTag=$TF_VAR_image_tag" >/dev/null 2>"$error_file"; then
    echo "Reusing immutable $component image for commit $TF_VAR_image_tag"
  elif grep -q ImageNotFoundException "$error_file"; then
    docker build --platform linux/amd64 -f "apps/$component/Dockerfile" -t "$image:$TF_VAR_image_tag" .
    docker push "$image:$TF_VAR_image_tag"
  else
    cat "$error_file" >&2; exit 1
  fi
done
terraform -chdir=infra/aws/terraform apply -var=enable_service=true "$@"
url="$(terraform -chdir=infra/aws/terraform output -raw url)"
curl --fail --silent --show-error --retry 6 --retry-delay 5 --retry-all-errors "$url/api/dashboard?year=2026" >/dev/null
printf 'Deployed and API checked: %s\n' "$url"

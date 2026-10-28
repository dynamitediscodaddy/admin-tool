#!/usr/bin/env bash
# Exercise first deployment with empty Terraform outputs that still return exit code 0.
set -euo pipefail
source_root="$(cd "$(dirname "$0")/../../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/infra/aws" "$test_root/bin"
cp "$source_root/infra/aws/"{deploy.sh,init.sh,environment.sh} "$test_root/infra/aws/"
export DEPLOY_TEST_ROOT="$test_root"
export PATH="$test_root/bin:$PATH"
export AWS_REGION=eusc-de-east-1 TF_STATE_BUCKET=test-state
unset APP_DOMAIN_NAME APP_HOSTED_ZONE_ID
cat > "$test_root/bin/terraform" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
shift # -chdir
case "$*" in
  init*) ;;
  'output -json')
    if [ -f "$DEPLOY_TEST_ROOT/registries" ]; then printf '{"web_repository_url":{},"api_repository_url":{}}\n'; else printf '{}\n'; fi ;;
  'state list') ;;
  'apply -var=enable_service=false'*) echo bootstrap >> "$DEPLOY_TEST_ROOT/trace"; touch "$DEPLOY_TEST_ROOT/registries" ;;
  'apply -var=enable_service=true'*) echo deploy >> "$DEPLOY_TEST_ROOT/trace" ;;
  'output -raw web_repository_url') echo 123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu/admin-tool-demo-web ;;
  'output -raw api_repository_url') echo 123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu/admin-tool-demo-api ;;
  'output -raw url') echo http://dashboard.example.test ;;
  *) echo "Unexpected Terraform call: $*" >&2; exit 1 ;;
esac
STUB
cat > "$test_root/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  rev-parse) echo abc123 ;;
  status) ;;
  *) exit 1 ;;
esac
STUB
cat > "$test_root/bin/aws" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'ecr get-login-password'*) echo fake-test-password ;;
  'ecr describe-images'*) exit 0 ;;
  *) exit 1 ;;
esac
STUB
cat > "$test_root/bin/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = 'login --username AWS --password-stdin 123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu' ]
cat >/dev/null
echo registry-login >> "$DEPLOY_TEST_ROOT/trace"
STUB
cat > "$test_root/bin/curl" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == *'http://dashboard.example.test/api/dashboard?year=2026'* ]]
echo verified >> "$DEPLOY_TEST_ROOT/trace"
STUB
chmod +x "$test_root/bin/"*
bash "$test_root/infra/aws/deploy.sh" -auto-approve
printf 'bootstrap\nregistry-login\ndeploy\nverified\n' > "$test_root/expected"
diff -u "$test_root/expected" "$test_root/trace"
# A repeat must reuse registries, never disable or recreate the running service.
: > "$test_root/trace"
bash "$test_root/infra/aws/deploy.sh" -auto-approve
printf 'registry-login\ndeploy\nverified\n' > "$test_root/expected"
diff -u "$test_root/expected" "$test_root/trace"
printf 'PASS: first deployment bootstraps registries; repeat keeps the service enabled.\n'

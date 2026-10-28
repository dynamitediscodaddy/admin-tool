# Sourced by the deployment scripts. Optional domain configuration must be paired.
export AWS_REGION="${AWS_REGION:-eusc-de-east-1}"
export TF_VAR_region="$AWS_REGION"
if [ -n "${APP_DOMAIN_NAME:-}" ] || [ -n "${APP_HOSTED_ZONE_ID:-}" ]; then
  : "${APP_DOMAIN_NAME:?Set both APP_DOMAIN_NAME and APP_HOSTED_ZONE_ID}"
  : "${APP_HOSTED_ZONE_ID:?Set both APP_DOMAIN_NAME and APP_HOSTED_ZONE_ID}"
  export TF_VAR_domain_name="$APP_DOMAIN_NAME"
  export TF_VAR_hosted_zone_id="$APP_HOSTED_ZONE_ID"
fi

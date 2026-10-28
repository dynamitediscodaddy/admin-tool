mock_provider "aws" {
  override_during = plan
  mock_data "aws_partition" { defaults = { partition = "aws-eusc", dns_suffix = "amazonaws.eu" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
}
run "repository_scoped_access" {
  command = apply
  assert {
    condition     = jsondecode(aws_iam_role.github.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:dynamitediscodaddy@346496808/admin-tool@1437431666:ref:refs/heads/feature/container-deployment"
    error_message = "Only the intended repository and branch may assume the role."
  }
  assert {
    condition     = jsondecode(aws_iam_role.github.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.eu"
    error_message = "The sovereign partition must use the configured audience."
  }
  assert {
    condition     = length(aws_iam_role_policy.deploy.policy) < 10240
    error_message = "The inline deployment policy exceeds IAM's role policy quota."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State storage must be private and versioned."
  }
}

run "legacy_repository_subject" {
  command = apply
  variables {
    github_subject_prefix = "repo:dynamitediscodaddy/admin-tool"
  }
  assert {
    condition     = jsondecode(aws_iam_role.github.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:dynamitediscodaddy/admin-tool:ref:refs/heads/feature/container-deployment"
    error_message = "Repositories using legacy subjects must remain supported without broadening branch access."
  }
}

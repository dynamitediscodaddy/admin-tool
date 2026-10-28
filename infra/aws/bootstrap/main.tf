variable "region" {
  type    = string
  default = "eusc-de-east-1"
}
variable "name" {
  type    = string
  default = "admin-tool-demo"
}
variable "github_repository" {
  type    = string
  default = "dynamitediscodaddy/admin-tool"
}
variable "github_branch" {
  type    = string
  default = "feature/container-deployment"
}
variable "existing_oidc_provider_arn" {
  type        = string
  default     = null
  description = "Use an existing account-wide GitHub OIDC provider instead of creating one."
}
variable "hosted_zone_id" {
  type    = string
  default = null
}
provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.name, ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
locals {
  partition      = data.aws_partition.current.partition
  account        = data.aws_caller_identity.current.account_id
  audience       = "sts.${data.aws_partition.current.dns_suffix}"
  bucket         = "${var.name}-tfstate-${local.account}-${var.region}"
  execution_role = "arn:${local.partition}:iam::${local.account}:role/${var.name}-task-execution"
}
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
    Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = [local.audience]
}
resource "aws_iam_role" "github" {
  name                 = "${var.name}-github-deploy"
  max_session_duration = 3600
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity",
    Principal = { Federated = var.existing_oidc_provider_arn != null ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = local.audience,
      "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
    } }
  }] })
}
resource "aws_iam_role_policy" "deploy" {
  name = "${var.name}-infrastructure"
  role = aws_iam_role.github.id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Sid = "StateBucket", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = aws_s3_bucket.state.arn },
    { Sid = "StateAndLock", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.state.arn}/app/terraform.tfstate", "${aws_s3_bucket.state.arn}/app/terraform.tfstate.tflock"] },
    { Sid = "RegistryLogin", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Sid = "AppImages", Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:DescribeRepositories", "ecr:DeleteRepository", "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource", "ecr:GetLifecyclePolicy", "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy", "ecr:GetRepositoryPolicy", "ecr:BatchGetImage", "ecr:BatchDeleteImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"], Resource = "arn:${local.partition}:ecr:${var.region}:${local.account}:repository/${var.name}-*" },
    { Sid = "RegionalInfrastructure", Effect = "Allow", Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }, Action = [
      "ec2:Describe*", "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:CreateTags", "ec2:DeleteTags",
      "ecs:CreateCluster", "ecs:DescribeClusters", "ecs:DeleteCluster", "ecs:UpdateCluster", "ecs:UpdateClusterSettings", "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource", "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices", "ecs:ListTasks", "ecs:DescribeTasks",
      "elasticloadbalancing:Describe*", "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags", "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
      "acm:RequestCertificate", "acm:DescribeCertificate", "acm:DeleteCertificate", "acm:ListTagsForCertificate", "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate"
    ] },
    { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"], Resource = "arn:${local.partition}:logs:${var.region}:${local.account}:log-group:/ecs/${var.name}:*" },
    { Sid = "DescribeLogs", Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" },
    { Sid = "ExecutionRole", Effect = "Allow", Action = ["iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:ListRolePolicies", "iam:ListRoleTags", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy"], Resource = local.execution_role },
    { Sid = "ExecutionRolePolicy", Effect = "Allow", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = local.execution_role, Condition = { ArnEquals = { "iam:PolicyARN" = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" } } },
    { Sid = "PassExecutionRole", Effect = "Allow", Action = ["iam:PassRole"], Resource = local.execution_role, Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } },
    { Sid = "ServiceLinkedRoles", Effect = "Allow", Action = ["iam:CreateServiceLinkedRole"], Resource = "arn:${local.partition}:iam::${local.account}:role/aws-service-role/*", Condition = { StringEquals = { "iam:AWSServiceName" = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"] } } }
    ], var.hosted_zone_id == null ? [] : [
    { Sid = "ApplicationDns", Effect = "Allow", Action = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone"], Resource = "arn:${local.partition}:route53:::hostedzone/${var.hosted_zone_id}" },
    { Sid = "DnsChangeStatus", Effect = "Allow", Action = ["route53:GetChange"], Resource = "arn:${local.partition}:route53:::change/*" }
  ]) })
}
output "role_arn" { value = aws_iam_role.github.arn }
output "state_bucket" { value = aws_s3_bucket.state.id }
output "region" { value = var.region }
output "audience" { value = local.audience }

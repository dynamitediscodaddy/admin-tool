mock_provider "aws" {
  override_during = plan
  mock_data "aws_partition" {
    defaults = { partition = "aws-eusc", dns_suffix = "amazonaws.eu" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eusc-de-east-1a", "eusc-de-east-1b"] }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws-eusc:iam::123456789012:role/admin-tool-demo-task-execution" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws-eusc:acm:eusc-de-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      domain_validation_options = [{
        domain_name           = "dashboard.example.com"
        resource_record_name  = "_validation.dashboard.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_token.acm-validations.aws"
      }]
    }
  }
}
run "registries_only_bootstrap" {
  command = plan
  variables { enable_service = false }
  assert {
    condition     = length(module.app) == 0 && length(aws_ecr_repository.images) == 2
    error_message = "Initial bootstrap must create registries without a service."
  }
  assert {
    condition     = alltrue([for repository in aws_ecr_repository.images : repository.force_delete && repository.image_tag_mutability == "IMMUTABLE"])
    error_message = "Images must be immutable and removable during destroy."
  }
}
run "sovereign_cloud_demo" {
  command = plan
  module { source = "./modules/app" }
  variables {
    name           = "admin-tool-demo"
    region         = "eusc-de-east-1"
    web_image      = "123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu/admin-tool-demo-web:commit"
    api_image      = "123456789012.dkr.ecr.eusc-de-east-1.amazonaws.eu/admin-tool-demo-api:commit"
    domain_name    = null
    hosted_zone_id = null
  }
  assert {
    condition     = aws_ecs_service.app.desired_count == 1 && !aws_ecs_service.app.wait_for_steady_state && aws_ecs_service.app.force_delete
    error_message = "The helper must own health waiting for the single task; the service must support destroy."
  }
  assert {
    condition     = aws_iam_role_policy_attachment.execution.policy_arn == "arn:aws-eusc:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "IAM policies must use the selected partition."
  }
  assert {
    condition     = alltrue([for rule in aws_security_group.task.ingress : rule.from_port == 3000 && try(length(rule.cidr_blocks), 0) == 0])
    error_message = "API port must not be exposed and frontend must only allow the ALB."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[1].environment[0].value == "http://127.0.0.1:8080"
    error_message = "Frontend must reach the API within the same task."
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "forward" && length(aws_lb_listener.https) == 0
    error_message = "The no-domain mock demo should use HTTP without a certificate."
  }
}
run "https_with_owned_domain" {
  command = plan
  module { source = "./modules/app" }
  variables {
    name           = "admin-tool-demo"
    region         = "eusc-de-east-1"
    web_image      = "example/web:commit"
    api_image      = "example/api:commit"
    domain_name    = "dashboard.example.com"
    hosted_zone_id = "Z0123456789"
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && length(aws_lb_listener.https) == 1 && length(aws_acm_certificate.app) == 1 && length(aws_route53_record.app) == 1
    error_message = "Owned domains must receive a managed certificate, HTTPS listener, DNS record and HTTP redirect."
  }
}

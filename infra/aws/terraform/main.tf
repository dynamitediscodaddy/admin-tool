provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.name, ManagedBy = "Terraform" } }
}
resource "aws_ecr_repository" "images" {
  for_each             = toset(["web", "api"])
  name                 = "${var.name}-${each.key}"
  force_delete         = true
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = "Remove untagged layers after one day"
    selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
    action       = { type = "expire" }
  }] })
}
module "app" {
  source         = "./modules/app"
  count          = var.enable_service ? 1 : 0
  name           = var.name
  region         = var.region
  web_image      = "${aws_ecr_repository.images["web"].repository_url}:${var.image_tag}"
  api_image      = "${aws_ecr_repository.images["api"].repository_url}:${var.image_tag}"
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
}

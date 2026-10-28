output "web_repository_url" { value = aws_ecr_repository.images["web"].repository_url }
output "api_repository_url" { value = aws_ecr_repository.images["api"].repository_url }
output "url" { value = try(module.app[0].url, null) }
output "cluster" { value = try(module.app[0].cluster, null) }
output "service" { value = try(module.app[0].service, null) }

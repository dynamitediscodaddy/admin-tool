data "aws_partition" "current" {}
data "aws_availability_zones" "available" { state = "available" }
locals { https = var.domain_name != null && var.hosted_zone_id != null }
resource "aws_vpc" "app" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  lifecycle {
    precondition {
      condition     = (var.domain_name == null) == (var.hosted_zone_id == null)
      error_message = "Set domain_name and hosted_zone_id together, or leave both unset for the HTTP demo."
    }
  }
}
resource "aws_internet_gateway" "app" { vpc_id = aws_vpc.app.id }
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.app.id
  cidr_block        = cidrsubnet(aws_vpc.app.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}
resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}
resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = aws_vpc.app.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  dynamic "ingress" {
    for_each = local.https ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.app.cidr_block]
  }
}
resource "aws_security_group" "task" {
  name_prefix = "${var.name}-task-"
  vpc_id      = aws_vpc.app.id
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_lb" "app" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.load_balancer.id]
  subnets            = aws_subnet.app[*].id
}
resource "aws_lb_target_group" "app" {
  name                 = var.name
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.app.id
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path    = "/api/dashboard"
    matcher = "200"
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = local.https ? "redirect" : "forward"
    target_group_arn = local.https ? null : aws_lb_target_group.app.arn
    dynamic "redirect" {
      for_each = local.https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}
resource "aws_acm_certificate" "app" {
  count             = local.https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_route53_record" "validation" {
  for_each = local.https ? {
    for dvo in aws_acm_certificate.app[0].domain_validation_options : dvo.domain_name => {
      name = dvo.resource_record_name, type = dvo.resource_record_type, record = dvo.resource_record_value
    }
  } : {}
  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}
resource "aws_acm_certificate_validation" "app" {
  count                   = local.https ? 1 : 0
  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
resource "aws_lb_listener" "https" {
  count             = local.https ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app[0].certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
resource "aws_route53_record" "app" {
  count   = local.https ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
resource "aws_ecs_cluster" "app" { name = var.name }
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}
resource "aws_iam_role" "execution" {
  name = "${var.name}-task-execution"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([
    { name         = "api", image = var.api_image, essential = true, memory = 512,
      portMappings = [{ containerPort = 8080 }],
      logConfiguration = { logDriver = "awslogs", options = {
        awslogs-group = aws_cloudwatch_log_group.app.name, awslogs-region = var.region, awslogs-stream-prefix = "api"
      } }
    },
    { name         = "web", image = var.web_image, essential = true, memory = 512,
      dependsOn    = [{ containerName = "api", condition = "START" }],
      environment  = [{ name = "API_BASE_URL", value = "http://127.0.0.1:8080" }],
      portMappings = [{ containerPort = 3000 }],
      logConfiguration = { logDriver = "awslogs", options = {
        awslogs-group = aws_cloudwatch_log_group.app.name, awslogs-region = var.region, awslogs-stream-prefix = "web"
      } }
    }
  ])
}
resource "aws_ecs_service" "app" {
  name                              = var.name
  cluster                           = aws_ecs_cluster.app.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  wait_for_steady_state             = true
  force_delete                      = true
  health_check_grace_period_seconds = 180
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "web"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.http, aws_lb_listener.https, aws_route_table_association.app, aws_iam_role_policy_attachment.execution]
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}
output "url" { value = local.https ? "https://${var.domain_name}" : "http://${aws_lb.app.dns_name}" }
output "cluster" { value = aws_ecs_cluster.app.name }
output "service" { value = aws_ecs_service.app.name }

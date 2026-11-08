resource "aws_lb" "api" {
  name                       = "taxbilling-dev-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.network.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = false # dev only
}

resource "aws_lb_target_group" "api" {
  name                 = "taxbilling-dev-api"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate (awsvpc networking)
  vpc_id               = module.network.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

output "alb_url" {
  value = "http://${aws_lb.api.dns_name}"
}

variable "image_tag" {
  description = "Image tag (git SHA) to deploy"
  type        = string
  default     = "1bab5c7" # the trimmed image with the Datadog tracer (5A.3); the pipeline overrides this
}

variable "datadog_site" {
  description = "Datadog site for your account (e.g. datadoghq.com for US1). Confirm at signup."
  type        = string
  default     = "datadoghq.com"
}

# The Datadog API key secret is owned by infra/ci; dev only reads it
data "aws_secretsmanager_secret" "datadog_api_key" {
  name = "taxbilling/datadog-api-key"
}

locals {
  dd_service = "taxbilling-api"
  dd_env     = "dev"
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/taxbilling-dev-api"
  retention_in_days = 7 # don't keep (and pay for) logs forever
}

# ---------- Cluster ----------
resource "aws_ecs_cluster" "this" {
  name = "taxbilling-dev"
}

# ---------- IAM ----------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: used by ECS itself to pull images, write logs and read secrets
resource "aws_iam_role" "task_execution" {
  name               = "taxbilling-dev-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_db_instance.this.master_user_secret[0].secret_arn, # DB password
        data.aws_secretsmanager_secret.datadog_api_key.arn,    # Datadog API key
      ]
    }]
  })
}

# Task role: used by the app code itself (no permissions needed yet)
resource "aws_iam_role" "task" {
  name               = "taxbilling-dev-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ---------- Task definition: the API + a Datadog agent sidecar ----------
resource "aws_ecs_task_definition" "api" {
  family                   = "taxbilling-dev-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"  # 0.5 vCPU, shared by the app and the agent
  memory                   = "1024" # MiB
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      environment = [
        { name = "ConnectionStrings__TaxBillingDb", value = "Host=${aws_db_instance.this.address};Port=5432;Database=taxbilling;Username=taxbilling_admin" },
        { name = "DD_SERVICE", value = local.dd_service },
        { name = "DD_ENV", value = local.dd_env },
        { name = "DD_VERSION", value = var.image_tag },
        { name = "DD_LOGS_INJECTION", value = "true" },
        { name = "DD_RUNTIME_METRICS_ENABLED", value = "true" },
      ]

      secrets = [{
        name      = "DB_PASSWORD"
        valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:password::"
      }]

      dockerLabels = {
        "com.datadoghq.tags.service" = local.dd_service
        "com.datadoghq.tags.env"     = local.dd_env
        "com.datadoghq.tags.version" = var.image_tag
      }

      dependsOn = [{ containerName = "datadog-agent", condition = "START" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "api"
        }
      }
    },
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:7"
      essential = false # if the agent fails, the app keeps serving traffic

      portMappings = [{ containerPort = 8126, protocol = "tcp" }]

      environment = [
        { name = "ECS_FARGATE", value = "true" },
        { name = "DD_SITE", value = var.datadog_site },
        { name = "DD_APM_ENABLED", value = "true" },
        { name = "DD_ENV", value = local.dd_env },
      ]

      secrets = [{
        name      = "DD_API_KEY"
        valueFrom = data.aws_secretsmanager_secret.datadog_api_key.arn
      }]

      healthCheck = {
        command     = ["CMD-SHELL", "agent health"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "datadog"
        }
      }
    }
  ])
}

# ---------- Service (keeps N copies running behind the ALB) ----------
resource "aws_ecs_service" "api" {
  name            = "taxbilling-dev-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2 # two tasks, spread across AZs
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.network.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true # a bad deploy automatically rolls back to the last working version
  }

  depends_on = [aws_lb_listener.http]
}

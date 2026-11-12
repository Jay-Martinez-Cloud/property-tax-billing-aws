# The ECR repo is owned by infra/ci (long-lived); dev only reads it
data "aws_ecr_repository" "api" {
  name = "taxbilling-api"
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.api.repository_url
}

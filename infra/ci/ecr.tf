resource "aws_ecr_repository" "api" {
  name                 = "taxbilling-api"
  image_tag_mutability = "IMMUTABLE" # a tag can never be overwritten

  image_scanning_configuration {
    scan_on_push = true # basic vulnerability scan on every push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = true # learning project: allows teardown with images inside. Set false in real orgs.

}

# Keep only the 10 most recent images (old ones are deleted automatically)
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 15 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 15
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

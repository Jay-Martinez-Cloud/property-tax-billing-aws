provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "tax-billing"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}


module "network" {
  source = "../../modules/network"

  name               = "taxbilling-dev"
  enable_nat_gateway = false # turn on in 2E when Fargate needs outbound access
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}

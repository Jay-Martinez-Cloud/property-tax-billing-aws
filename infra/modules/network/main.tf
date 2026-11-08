data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_index = { for i, az in local.azs : az => i } # e.g. { "us-east-1a" = 0, "us-east-1b" = 1, ... }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# Public: ALB + NAT gateway live here
resource "aws_subnet" "public" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value) # 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

# Private app: ECS tasks live here (outbound only, via NAT)
resource "aws_subnet" "private" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 10) # 10.0.10.0/24, ...

  tags = { Name = "${var.name}-private-${each.key}", Tier = "private" }
}

# Isolated DB: RDS lives here (no route to the internet at all)
resource "aws_subnet" "db" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 20) # 10.0.20.0/24, ...

  tags = { Name = "${var.name}-db-${each.key}", Tier = "db" }
}

# Which subnets RDS may use: the isolated DB tier from the network module
resource "aws_db_subnet_group" "this" {
  name       = "taxbilling-dev-db"
  subnet_ids = module.network.db_subnet_ids
  tags       = { Name = "taxbilling-dev-db-subnets" }
}

# Firewall for the database. No inbound rules yet; the app's access is added in 2E.
resource "aws_security_group" "db" {
  name        = "taxbilling-dev-db"
  description = "PostgreSQL access for the tax billing app"
  vpc_id      = module.network.vpc_id
  tags        = { Name = "taxbilling-dev-db-sg" }
}

resource "aws_db_instance" "this" {
  identifier     = "taxbilling-dev"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "taxbilling"
  username                    = "taxbilling_admin"
  manage_master_user_password = true # RDS generates the password and stores it in Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = true

  backup_retention_period    = 1
  auto_minor_version_upgrade = true

  # Dev-only settings so `terraform destroy` is quick and clean
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

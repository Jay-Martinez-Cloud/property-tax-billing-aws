# The Datadog API key. Terraform creates the secret; the VALUE is added once by hand (5C),
# so the real key never appears in Terraform code or state.
resource "aws_secretsmanager_secret" "datadog_api_key" {
  name                    = "taxbilling/datadog-api-key"
  description             = "Datadog API key used by the ECS agent sidecar"
  recovery_window_in_days = 7 # deleted secrets can be restored for 7 days
}

output "datadog_api_key_secret_arn" {
  value = aws_secretsmanager_secret.datadog_api_key.arn
}

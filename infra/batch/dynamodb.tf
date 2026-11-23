# One item per payment. paymentId is the key, so a second insert of the same id is rejected.
resource "aws_dynamodb_table" "payments" {
  name         = "taxbilling-batch-payments"
  billing_mode = "PAY_PER_REQUEST" # on-demand: pay per read/write, $0 when idle
  hash_key     = "paymentId"

  attribute {
    name = "paymentId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true # restore the table to any second in the last 35 days
  }

  server_side_encryption {
    enabled = true
  }
}

output "payments_table" {
  value = aws_dynamodb_table.payments.name
}

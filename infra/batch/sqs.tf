# ---------- Dead-letter queue: where messages go after repeated failures ----------
resource "aws_sqs_queue" "dlq" {
  name                      = "taxbilling-batch-dlq"
  message_retention_seconds = 1209600 # 14 days (the max): time to investigate failures
  sqs_managed_sse_enabled   = true    # encrypted at rest
}

# ---------- Main queue: "a payment file arrived" messages ----------
resource "aws_sqs_queue" "files" {
  name                       = "taxbilling-batch-files"
  visibility_timeout_seconds = 180    # ≥ 6x the Lambda timeout (30s), per AWS guidance
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # after 3 failed attempts → DLQ
  })
}

# Only the main queue may send messages to this DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.files.arn]
  })
}

output "files_queue_url" {
  value = aws_sqs_queue.files.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

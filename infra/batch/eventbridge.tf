# Match: a .csv file created under incoming/ in the incoming bucket
resource "aws_cloudwatch_event_rule" "csv_uploaded" {
  name        = "taxbilling-batch-csv-uploaded"
  description = "Batch payment CSV uploaded to incoming/"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.incoming.bucket] }
      object = { key = [{ wildcard = "incoming/*.csv" }] }
    }
  })
}

# Send matching events to the SQS queue
resource "aws_cloudwatch_event_target" "to_files_queue" {
  rule      = aws_cloudwatch_event_rule.csv_uploaded.name
  target_id = "files-queue"
  arn       = aws_sqs_queue.files.arn
}

# Allow EventBridge to send messages to the queue, but ONLY from this rule
resource "aws_sqs_queue_policy" "files" {
  queue_url = aws_sqs_queue.files.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.files.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.csv_uploaded.arn } }
    }]
  })
}

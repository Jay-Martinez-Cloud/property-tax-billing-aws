variable "alert_email" {
  description = "Where DLQ alerts are sent (set in terraform.tfvars, which is gitignored)"
  type        = string
}

resource "aws_sns_topic" "alerts" {
  name = "taxbilling-batch-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Fire when ANY message is sitting in the DLQ
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "taxbilling-batch-dlq-not-empty"
  alarm_description   = "Batch payment file(s) failed processing 3 times and landed in the DLQ. Check Lambda logs, fix the file, then redrive."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn] # email when it goes into ALARM
  ok_actions    = [aws_sns_topic.alerts.arn] # email when it recovers (DLQ emptied)
}

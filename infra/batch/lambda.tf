# ---------- Package the code ----------
data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/../../services/batch-processor/handler.py"
  output_path = "${path.module}/build/batch-processor.zip"
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/taxbilling-batch-processor"
  retention_in_days = 14
}

# ---------- IAM: least privilege ----------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "processor" {
  name               = "taxbilling-batch-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "processor" {
  name = "batch-processor-least-privilege"
  role = aws_iam_role.processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.processor.arn}:*"
      },
      {
        Sid      = "ReadIncomingFiles"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.incoming.arn}/incoming/*"
      },
      {
        Sid    = "ConsumeQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage", "sqs:DeleteMessage",
          "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.files.arn
      },
      {
        Sid      = "InsertPayments"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.payments.arn
      }
    ]
  })
}

# ---------- The function ----------
resource "aws_lambda_function" "processor" {
  function_name    = "taxbilling-batch-processor"
  role             = aws_iam_role.processor.arn
  runtime          = "python3.13"
  architectures    = ["arm64"] # Graviton: cheaper, consistent with ECS
  handler          = "handler.handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 30 # queue visibility timeout (180s) is 6x this
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.payments.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.processor, aws_iam_role_policy.processor]
}

# ---------- SQS → Lambda trigger ----------
resource "aws_lambda_event_source_mapping" "files_queue" {
  event_source_arn        = aws_sqs_queue.files.arn
  function_name           = aws_lambda_function.processor.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"] # pairs with batchItemFailures in handler.py

  scaling_config {
    maximum_concurrency = 2 # cap parallel Lambdas (protects DynamoDB and downstream systems)
  }
}

output "processor_function" {
  value = aws_lambda_function.processor.function_name
}

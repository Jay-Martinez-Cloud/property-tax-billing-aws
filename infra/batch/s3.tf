data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Where batch payment files are dropped off (incoming/*.csv)
resource "aws_s3_bucket" "incoming" {
  bucket        = "taxbilling-batch-incoming-${local.account_id}"
  force_destroy = true # learning project: allows teardown with files inside
}

# Keep every version of every file (audit trail if a file is re-sent or overwritten)
resource "aws_s3_bucket_versioning" "incoming" {
  bucket = aws_s3_bucket.incoming.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "incoming" {
  bucket = aws_s3_bucket.incoming.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "incoming" {
  bucket                  = aws_s3_bucket.incoming.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "incoming_tls_only" {
  bucket = aws_s3_bucket.incoming.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.incoming.arn, "${aws_s3_bucket.incoming.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.incoming]
}

# 🔑 Send "Object Created" (and other) events to EventBridge
resource "aws_s3_bucket_notification" "incoming" {
  bucket      = aws_s3_bucket.incoming.id
  eventbridge = true
}

output "incoming_bucket" {
  value = aws_s3_bucket.incoming.bucket
}

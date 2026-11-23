"""Batch payment processor.

Triggered by SQS (fed by EventBridge when a CSV lands in s3://<bucket>/incoming/).
Each message points to one CSV file. Every payment row is written to DynamoDB
with a conditional write, so re-sent files and duplicate SQS deliveries never
create a second payment.
"""

import csv
import io
import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

REQUIRED_COLUMNS = {"paymentId", "parcelId", "amount"}


def handler(event, context):
    """Entry point. Returns partial batch failures so only failed messages are retried."""
    failures = []
    for record in event["Records"]:
        try:
            process_message(record)
        except Exception:
            logger.exception("Failed to process message %s",
                             record["messageId"])
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}


def process_message(record):
    s3_event = json.loads(record["body"])
    bucket = s3_event["detail"]["bucket"]["name"]
    key = s3_event["detail"]["object"]["key"]

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
    rows = parse_and_validate(body, key)

    created, duplicates = 0, 0
    for row in rows:
        if write_payment(row, key):
            created += 1
        else:
            duplicates += 1

    logger.info(json.dumps({
        "event": "batch_processed",
        "file": key,
        "rows": len(rows),
        "created": created,
        "duplicates": duplicates,
    }))


def parse_and_validate(body, key):
    """Validate the WHOLE file before writing anything. A bad file raises, and SQS retries → DLQ."""
    reader = csv.DictReader(io.StringIO(body))
    if not reader.fieldnames or not REQUIRED_COLUMNS.issubset(reader.fieldnames):
        raise ValueError(
            f"{key}: header must include {sorted(REQUIRED_COLUMNS)}, got {reader.fieldnames}")

    rows = []
    for line_no, row in enumerate(reader, start=2):  # line 1 is the header
        payment_id = (row.get("paymentId") or "").strip()
        parcel_id = (row.get("parcelId") or "").strip()
        try:
            amount = Decimal((row.get("amount") or "").strip())
        except InvalidOperation:
            raise ValueError(
                f"{key} line {line_no}: amount is not a number: {row.get('amount')!r}")

        if not payment_id or not parcel_id:
            raise ValueError(
                f"{key} line {line_no}: paymentId and parcelId are required")
        if amount <= 0:
            raise ValueError(
                f"{key} line {line_no}: amount must be greater than 0")

        rows.append({"paymentId": payment_id,
                    "parcelId": parcel_id, "amount": amount})

    if not rows:
        raise ValueError(f"{key}: file has no payment rows")
    return rows


def write_payment(row, source_file):
    """Insert the payment only if this paymentId has never been seen. Returns True if created."""
    try:
        table.put_item(
            Item={
                **row,
                "sourceFile": source_file,
                "processedAt": datetime.now(timezone.utc).isoformat(),
            },
            ConditionExpression="attribute_not_exists(paymentId)",
        )
        return True
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False  # already processed: idempotent skip
        raise

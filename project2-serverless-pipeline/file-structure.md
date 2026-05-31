# P2 File Structure — Serverless Pipeline

```
project2-serverless-pipeline/
│
├── main.tf               # S3 ×3, SQS ×4 (2 queues + 2 DLQs), DynamoDB,
│                         #   SNS, Lambda ×3, API Gateway (HTTP v2),
│                         #   CloudWatch alarms + dashboard
│
├── iam.tf                # One least-privilege role per Lambda:
│                         #   router-role, parser-role, extractor-role
│                         #   Uses AWSLambdaBasicExecutionRole /
│                         #   AWSLambdaSQSQueueExecutionRole managed policies
│                         #   + custom inline policies per function
│
├── variables.tf          # suffix, alert_email, aws_region,
│                         #   project_name, common_tags
│
├── outputs.tf            # Bucket names, API endpoint, DynamoDB table,
│                         #   test curl commands
│
├── lambda/
│   ├── router/
│   │   └── index.py      # Triggered by S3 ObjectCreated; routes by
│   │                     #   file extension → structured/unstructured SQS
│   │                     #   or quarantine bucket
│   ├── parser/
│   │   └── index.py      # SQS-triggered; validates CSV/JSON;
│   │                     #   writes records to DynamoDB
│   └── extractor/
│       └── index.py      # SQS-triggered; calls Textract (PDF) /
│                         #   Rekognition (image); writes results to S3
│
├── sample_data/          # Test files for manual pipeline testing
│   ├── test.csv
│   ├── test.json
│   ├── test.pdf
│   ├── test.png
│   └── test.xyz          # Unknown type → quarantine path
│
├── terraform.tfstate
└── terraform.tfstate.backup
```

## Key relationships

- S3 `ObjectCreated` → Router Lambda (direct trigger, not via SQS).
- Router → SQS structured queue → Parser Lambda (batch 10).
- Router → SQS unstructured queue → Extractor Lambda (batch 5).
- Each SQS queue has a DLQ (`maxReceiveCount=3`); CloudWatch alarms on DLQ depth.
- Parser and Extractor share the DynamoDB table and quarantine bucket but have separate SQS-triggered roles.
- Textract/Rekognition require `Resource: "*"` — AWS does not support resource-level ARNs for these APIs.

## Design reference

[Full architecture and IAM notes](../docs/design/p2-serverless-pipeline/design.md)

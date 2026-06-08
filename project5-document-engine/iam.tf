########################################################
# iam.tf
########################################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

locals {
  log_policy = {
    Effect   = "Allow"
    Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    Resource = "arn:aws:logs:*:*:*"
  }
  bedrock_policy = {
    Effect = "Allow"
    Action = ["bedrock:InvokeModel"]
    Resource = [
      "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*",
    ]
  }
}

########################################################
# Ingest Lambda IAM
########################################################

resource "aws_iam_role" "ingest" {
  name               = "${var.project_name}-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "ingest" {
  name = "${var.project_name}-ingest-policy"
  role = aws_iam_role.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.log_policy,
      local.bedrock_policy,
      {
        # S3: 문서 읽기
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        # Textract: 문서 텍스트 추출
        Effect   = "Allow"
        Action   = ["textract:DetectDocumentText", "textract:AnalyzeDocument"]
        Resource = "*"
      },
      {
        # DynamoDB: 메타데이터 저장
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.documents.arn
      },
      {
        # OpenSearch: 색인 쓰기
        Effect   = "Allow"
        Action   = ["es:ESHttpPut", "es:ESHttpPost", "es:ESHttpGet"]
        Resource = "${aws_opensearch_domain.engine.arn}/*"
      },
      {
        # SNS: 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}

########################################################
# Query Lambda IAM
########################################################

resource "aws_iam_role" "query" {
  name               = "${var.project_name}-query-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "query" {
  name = "${var.project_name}-query-policy"
  role = aws_iam_role.query.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.log_policy,
      local.bedrock_policy,
      {
        # OpenSearch: 검색 읽기
        Effect   = "Allow"
        Action   = ["es:ESHttpPost", "es:ESHttpGet"]
        Resource = "${aws_opensearch_domain.engine.arn}/*"
      },
    ]
  })
}

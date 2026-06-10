########################################################
# iam.tf — Lambda 실행 역할 및 권한 (순환 참조 해결 버전)
########################################################

# ── 공통: Lambda 신뢰 정책 ────────────────────────────
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

########################################################
# 1. Router Lambda IAM
########################################################

resource "aws_iam_role" "router" {
  name               = "${var.project_name}-router-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

# CloudWatch 로그 생성을 위한 AWS 표준 관리형 정책 연결 (순환참조 근본적 해결)
resource "aws_iam_role_policy_attachment" "router_logs" {
  role       = aws_iam_role.router.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "router_custom" {
  name = "${var.project_name}-router-custom-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3: Ingestion 버킷 읽기 + Quarantine 버킷 쓰기
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.ingestion.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.quarantine.arn}/*"
      },
      {
        # SQS: 두 큐에 메시지 전송
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.structured.arn,
          aws_sqs_queue.unstructured.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "router_custom_attach" {
  role       = aws_iam_role.router.name
  policy_arn = aws_iam_policy.router_custom.arn
}

########################################################
# 2. Parser Lambda IAM
########################################################

resource "aws_iam_role" "parser" {
  name               = "${var.project_name}-parser-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

# SQS 트리거 폴링 및 CloudWatch 로그를 위한 AWS 표준 관리형 정책 연결
resource "aws_iam_role_policy_attachment" "parser_sqs_core" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_policy" "parser_custom" {
  name = "${var.project_name}-parser-custom-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SQS: DLQ 전송 권한 추가
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.structured_dlq.arn
      },
      {
        # S3: Ingestion 읽기 + Quarantine 쓰기
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.ingestion.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.quarantine.arn}/*"
      },
      {
        # DynamoDB 쓰기
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
        Resource = aws_dynamodb_table.records.arn
      },
      {
        # SNS 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "parser_custom_attach" {
  role       = aws_iam_role.parser.name
  policy_arn = aws_iam_policy.parser_custom.arn
}

########################################################
# 3. Extractor Lambda IAM
########################################################

resource "aws_iam_role" "extractor" {
  name               = "${var.project_name}-extractor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

# SQS 트리거 폴링 및 CloudWatch 로그를 위한 AWS 표준 관리형 정책 연결
resource "aws_iam_role_policy_attachment" "extractor_sqs_core" {
  role       = aws_iam_role.extractor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_policy" "extractor_custom" {
  name = "${var.project_name}-extractor-custom-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SQS: DLQ 전송 권한 추가
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.unstructured_dlq.arn
      },
      {
        # S3: Ingestion 읽기 + Processed/Quarantine 쓰기
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.ingestion.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.processed.arn}/*",
          "${aws_s3_bucket.quarantine.arn}/*"
        ]
      },
      {
        # Rekognition 권한 (AI 서비스는 리소스 단위 제어가 불가능하므로 "*" 필수)
        # Textract는 계정 레벨 구독 불가로 제거, PDF는 pypdf로 처리 (ERR-003)
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectText"
        ]
        Resource = "*"
      },
      {
        # DynamoDB 쓰기
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.records.arn
      },
      {
        # SNS 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "extractor_custom_attach" {
  role       = aws_iam_role.extractor.name
  policy_arn = aws_iam_policy.extractor_custom.arn
}

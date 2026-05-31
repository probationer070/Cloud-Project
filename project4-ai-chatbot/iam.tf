########################################################
# iam.tf — Chatbot Lambda 실행 역할
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

resource "aws_iam_role" "chatbot" {
  name               = "${var.project_name}-chatbot-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "chatbot" {
  name = "${var.project_name}-chatbot-policy"
  role = aws_iam_role.chatbot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logs — scoped to this function's log group only
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-chatbot",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-chatbot:*",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/${var.project_name}",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/${var.project_name}:*",
        ]
      },
      {
        # DynamoDB: 대화 이력 읽기/쓰기
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchWriteItem",
        ]
        Resource = [
          aws_dynamodb_table.sessions.arn,
          "${aws_dynamodb_table.sessions.arn}/index/*",
        ]
      },
      {
        # SNS: 상담원 연결 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        # Bedrock: Claude 모델 호출 (AI_PROVIDER=bedrock 시 사용)
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*"
      },
    ]
  })
}

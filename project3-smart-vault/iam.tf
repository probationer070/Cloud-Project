########################################################
# iam.tf — Lambda 실행 역할 및 권한
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
    Effect = "Allow"
    Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    Resource = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-backup",
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-backup:*",
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-cleanup",
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-cleanup:*",
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-restore",
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-restore:*",
    ]
  }
}

########################################################
# Backup Lambda IAM
########################################################

resource "aws_iam_role" "backup" {
  name               = "${var.project_name}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "backup" {
  name = "${var.project_name}-backup-policy"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.log_policy,
      {
        # EC2: 인스턴스 조회 + 스냅샷 생성
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeSnapshots",
        ]
        Resource = "*"
      },
      {
        # SNS 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}

########################################################
# Cleanup Lambda IAM
########################################################

resource "aws_iam_role" "cleanup" {
  name               = "${var.project_name}-cleanup-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "cleanup" {
  name = "${var.project_name}-cleanup-policy"
  role = aws_iam_role.cleanup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.log_policy,
      {
        # EC2: 스냅샷 조회 + 삭제
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        # S3: 아카이브 버킷에 로그 저장
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.archive.arn}/*"
      },
      {
        # SNS 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}

########################################################
# Restore Lambda IAM
########################################################

resource "aws_iam_role" "restore" {
  name               = "${var.project_name}-restore-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy" "restore" {
  name = "${var.project_name}-restore-policy"
  role = aws_iam_role.restore.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.log_policy,
      {
        # EC2: 스냅샷 조회 + 볼륨 생성
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeSnapshots",
          "ec2:CreateVolume",
          "ec2:CreateTags",
          "ec2:DescribeVolumes",
        ]
        Resource = "*"
      },
      {
        # SNS 알림
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}

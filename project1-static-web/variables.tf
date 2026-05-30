########################################################
# variables.tf — 수정이 필요한 값들
########################################################

variable "aws_region" {
  description = "기본 AWS 리전"
  type        = string
  default     = "ap-northeast-2" # 서울
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 이름에 사용)"
  type        = string
  default     = "p1-static-web"
}

variable "bucket_name" {
  description = "S3 버킷 이름 (전 세계 고유해야 함 — 본인 이름이나 날짜 포함 권장)"
  type        = string
  default     = "p1-static-web-jaehwan-20260527" # ← 반드시 변경
}

variable "alert_email" {
  description = "CloudWatch 알람 수신 이메일"
  type        = string
  default     = "qkrwoghks0717@gmail.com" # ← 반드시 변경
}

# 도메인 있을 때만 사용 (없으면 무시)
variable "domain_name" {
  description = "커스텀 도메인 (없으면 비워두세요)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
  default = {
    Project     = "cloud-portfolio"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

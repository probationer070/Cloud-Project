########################################################
# variables.tf
########################################################

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 이름 prefix)"
  type        = string
  default     = "p2-pipeline"
}

variable "suffix" {
  description = "S3 버킷 이름 고유화용 suffix (이름+날짜 권장)"
  type        = string
  default     = "jaehwan-20260528" # ← 반드시 변경
}

variable "alert_email" {
  description = "에러 알림 수신 이메일"
  type        = string
  default     = "qkrwoghks0717@gmail.com" # ← 반드시 변경
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cloud-portfolio"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

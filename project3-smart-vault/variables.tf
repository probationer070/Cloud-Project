########################################################
# variables.tf
########################################################

variable "aws_region" {
  description = "기본 리전 (서울)"
  type        = string
  default     = "ap-northeast-2"
}

variable "dr_region" {
  description = "재해 복구 리전 (크로스 리전 복제 대상)"
  type        = string
  default     = "ap-southeast-1" # 싱가포르
}

variable "project_name" {
  type    = string
  default = "p3-smart-vault"
}

variable "suffix" {
  description = "S3 버킷 이름 고유화 suffix"
  type        = string
  default     = "jaehwan-20260528" # ← 반드시 변경
}

variable "alert_email" {
  description = "알림 수신 이메일"
  type        = string
  default     = "qkrwoghks0717@gmail.com" # ← 반드시 변경
}

variable "retention_days" {
  description = "스냅샷 보관 기간 (일)"
  type        = number
  default     = 7
}

variable "cleanup_dry_run" {
  description = "true 시 실제 삭제 없이 대상만 출력 (테스트 시 true 권장)"
  type        = bool
  default     = true # ← 첫 테스트는 true로 시작, 확인 후 false로 변경
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cloud-portfolio"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}


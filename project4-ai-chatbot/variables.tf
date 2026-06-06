########################################################
# variables.tf
########################################################

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "p4-chatbot"
}

variable "suffix" {
  description = "S3 버킷 이름 고유화"
  type        = string
  default     = "jaehwan-20260606" # ← 반드시 변경
}

variable "alert_email" {
  description = "상담원 연결 알림 수신 이메일"
  type        = string
  default     = "qkrwoghks0717@gmail.com" # ← 반드시 변경
}

variable "company_name" {
  description = "챗봇에 표시될 회사/서비스 이름"
  type        = string
  default     = "클라우드 고객센터"
}

# ── AI 제공자 설정 ─────────────────────────────────────
# "gemini" 또는 "bedrock" 으로 전환 가능

variable "ai_provider" {
  description = "AI 제공자: gemini | bedrock"
  type        = string
  default     = "gemini" # ← 기본값: Gemini (무료 티어)
}

# Gemini 설정
variable "gemini_model" {
  description = "사용할 Gemini 모델"
  type        = string
  default     = "gemini-3.1-flash-lite"
  // default     = "gemma-4-26b-a4b-it"
}

# Bedrock 설정
variable "bedrock_model_id" {
  description = "사용할 Bedrock 모델 ID (ai_provider=bedrock 시 사용)"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "bedrock_region" {
  description = "Bedrock 리전 (서울은 Claude 미지원 → us-east-1 권장)"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cloud-portfolio"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

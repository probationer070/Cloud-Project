########################################################
# variables.tf
########################################################

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "p5-doc-engine"
}

variable "suffix" {
  description = "S3 버킷 이름 고유화"
  type        = string
  default     = "jaehwan-20250608" # ← 반드시 변경
}

variable "alert_email" {
  type    = string
  default = "qkrwoghks0717@gmail.com" # ← 반드시 변경
}

# ── OpenSearch 설정 ───────────────────────────────────
variable "opensearch_index" {
  description = "OpenSearch 인덱스 이름"
  type        = string
  default     = "documents"
}

# ── Bedrock 설정 ──────────────────────────────────────
variable "bedrock_region" {
  description = "Bedrock 리전 (Titan 임베딩 + Claude 사용)"
  type        = string
  default     = "us-east-1"
}

variable "bedrock_model_id" {
  description = "답변 생성용 Claude 모델"
  type        = string
  default     = "anthropic.claude-3-5-haiku-20241022-v1:0"
}

# ── 청크 설정 ─────────────────────────────────────────
variable "chunk_size" {
  description = "청크당 단어 수 (클수록 문맥 풍부, 작을수록 정밀)"
  type        = number
  default     = 500
}

variable "chunk_overlap" {
  description = "청크 간 겹치는 단어 수 (문맥 연속성)"
  type        = number
  default     = 50
}

variable "top_k" {
  description = "검색 시 반환할 청크 수"
  type        = number
  default     = 5
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "cloud-portfolio"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

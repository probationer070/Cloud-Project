########################################################
# bootstrap/variables.tf
########################################################

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state. Must match every backend.tf and be globally unique."
  type        = string
  default     = "cloud-portfolio-tfstate-jaehwan-20260606"
}

variable "common_tags" {
  type = map(string)
  default = {
    Project   = "cloud-portfolio"
    ManagedBy = "terraform"
    Purpose   = "remote-state-backend"
  }
}

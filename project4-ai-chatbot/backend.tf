########################################################
# backend.tf — S3 remote state with native lockfile locking
#
# The state bucket is created by the /bootstrap config.
# Locking uses an S3 lock object (use_lockfile, TF >= 1.10);
# no DynamoDB table needed.
# All values MUST be literals — backend blocks cannot use
# variables or interpolation.
#
# Fixes ERR-001 (local state not shared across machines):
# laptop and desktop now read/write this one shared state.
########################################################

terraform {
  backend "s3" {
    bucket       = "cloud-portfolio-tfstate-jaehwan-20260606"
    key          = "project4-ai-chatbot/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}

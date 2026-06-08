########################################################
# bootstrap/outputs.tf
# Copy this literal into each project's backend.tf
# (backend blocks cannot read variables/outputs).
########################################################

output "state_bucket" {
  description = "S3 bucket name — set as backend.tf `bucket`"
  value       = aws_s3_bucket.tfstate.id
}

output "github_actions_role_arn" {
  description = "Paste this into GitHub → Settings → Secrets → AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

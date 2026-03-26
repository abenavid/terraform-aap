output "state_bucket_name" {
  description = "Actual S3 bucket name for state (use this in migrate-state-to-s3.sh as TF_STATE_BUCKET)."
  value       = aws_s3_bucket.terraform_state.id
}

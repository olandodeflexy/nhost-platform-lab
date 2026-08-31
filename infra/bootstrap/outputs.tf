output "state_bucket_name" {
  description = "S3 bucket used by the Terragrunt remote-state configuration."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB lock table used by Terraform."
  value       = aws_dynamodb_table.locks.name
}

output "backend_configuration" {
  description = "Values to copy into the matching account.hcl file."
  value = {
    bucket         = aws_s3_bucket.state.id
    dynamodb_table = aws_dynamodb_table.locks.name
    region         = var.aws_region
  }
}

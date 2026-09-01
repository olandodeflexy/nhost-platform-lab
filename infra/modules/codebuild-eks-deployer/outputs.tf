output "project_name" {
  description = "CodeBuild project name configured in the matching GitHub repository variable."
  value       = aws_codebuild_project.this.name
}

output "project_arn" {
  description = "Exact CodeBuild project ARN allowed in the GitHub OIDC starter role."
  value       = aws_codebuild_project.this.arn
}

output "service_role_arn" {
  description = "CodeBuild service role that receives namespace-scoped EKS access."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Private CloudWatch log group for deployment output."
  value       = aws_cloudwatch_log_group.this.name
}

output "role_arn" {
  description = "IAM role assumed by GitHub Actions."
  value       = aws_iam_role.this.arn
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN in this account."
  value       = local.oidc_provider_arn
}

output "github_subjects" {
  description = "Exact immutable GitHub OIDC subjects trusted by this role."
  value       = local.github_subjects
}

output "github_job_workflow_refs" {
  description = "Exact reusable workflows on refs/heads/main trusted by this role."
  value       = local.github_job_workflow_refs
}

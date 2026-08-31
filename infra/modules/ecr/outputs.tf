output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Source-region ECR repository URL used by release workflows."
  value       = aws_ecr_repository.this.repository_url
}

output "regional_repository_urls" {
  description = "ECR repository URLs keyed by source and replica region."
  value = merge(
    { (var.aws_region) = aws_ecr_repository.this.repository_url },
    { for region, repository in aws_ecr_repository.replica : region => repository.repository_url },
  )
}

output "registry_id" {
  description = "AWS account ID that owns the registry."
  value       = aws_ecr_repository.this.registry_id
}

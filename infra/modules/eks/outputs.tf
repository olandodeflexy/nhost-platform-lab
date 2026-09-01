output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "EKS control-plane security group ID."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Shared EKS node security group ID."
  value       = module.eks.node_security_group_id
}

output "private_runner_security_group_id" {
  description = "Security group to attach to private execution hosts that need EKS API access."
  value       = aws_security_group.private_runner.id
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for workloads that still require IRSA."
  value       = module.eks.oidc_provider_arn
}

output "karpenter_queue_name" {
  description = "SQS interruption queue consumed by Karpenter."
  value       = module.karpenter.queue_name
}

output "karpenter_node_role_name" {
  description = "IAM role name used by Karpenter-created nodes."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_role_arn" {
  description = "IAM role ARN used by Karpenter-created nodes."
  value       = module.karpenter.node_iam_role_arn
}

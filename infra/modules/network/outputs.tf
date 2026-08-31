output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS workers."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs for internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "intra_subnet_ids" {
  description = "Isolated subnet IDs for the EKS control plane or data services."
  value       = module.vpc.intra_subnets
}

output "availability_zones" {
  description = "Availability zones used by this VPC."
  value       = local.azs
}

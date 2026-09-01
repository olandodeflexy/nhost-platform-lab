variable "project" {
  description = "Project name used in tags."
  type        = string
}

variable "environment" {
  description = "Environment name such as nonprod or prod."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the EKS cluster."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC ID from the network module."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for managed and Karpenter worker nodes."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Intra subnets for EKS control-plane network interfaces."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the EKS API publicly in addition to its private endpoint."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs permitted when public EKS API access is enabled."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "Human or break-glass IAM role ARNs granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "controller_instance_types" {
  description = "Instance types for the small managed controller node group."
  type        = list(string)
  default     = ["m7i.large"]
}

variable "controller_min_size" {
  description = "Minimum controller node count."
  type        = number
  default     = 2
}

variable "controller_max_size" {
  description = "Maximum controller node count."
  type        = number
  default     = 4
}

variable "controller_desired_size" {
  description = "Initial controller node count."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

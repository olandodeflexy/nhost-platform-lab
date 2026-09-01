variable "project" {
  description = "Project name used in tags."
  type        = string
}

variable "environment" {
  description = "Owning environment."
  type        = string
}

variable "aws_region" {
  description = "AWS region containing the CodeBuild project and EKS cluster."
  type        = string
}

variable "project_name" {
  description = "Name of the single-purpose CodeBuild deployment project."
  type        = string

  validation {
    condition     = length(var.project_name) >= 2 && length(var.project_name) <= 54 && can(regex("^[A-Za-z0-9][A-Za-z0-9_-]+$", var.project_name))
    error_message = "project_name must be 2-54 characters and contain only letters, numbers, underscores, or hyphens."
  }
}

variable "github_repository" {
  description = "Public GitHub repository from which immutable release commits are fetched."
  type = object({
    owner = string
    name  = string
  })

  validation {
    condition = (
      can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_repository.owner)) &&
      length(var.github_repository.name) <= 100 &&
      can(regex("^[A-Za-z0-9._-]+$", var.github_repository.name))
    )
    error_message = "github_repository must contain a valid GitHub owner and repository name."
  }
}

variable "cluster_name" {
  description = "Name of the private-endpoint EKS cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC containing the EKS cluster and CodeBuild network interfaces."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "private_subnet_ids" {
  description = "Private NAT-routed subnets used by the CodeBuild project."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2 && alltrue([for id in var.private_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "private_subnet_ids must contain at least two AWS subnet IDs."
  }
}

variable "executor_security_group_id" {
  description = "Security group authorized to reach the private EKS API."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.executor_security_group_id))
    error_message = "executor_security_group_id must be an AWS security group ID."
  }
}

variable "target_overlay" {
  description = "Kustomize overlay this project is permanently allowed to deploy."
  type        = string

  validation {
    condition     = contains(["nonprod-eu-west-1", "prod-eu-west-1", "prod-us-east-1"], var.target_overlay)
    error_message = "target_overlay must be one of the repository's three deployment overlays."
  }
}

variable "deployment_namespace" {
  description = "Existing Kubernetes namespace targeted by the custom deployer RBAC group."
  type        = string
  default     = "demo-api"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.deployment_namespace))
    error_message = "deployment_namespace must be a valid Kubernetes namespace name."
  }
}

variable "deployment_kubernetes_groups" {
  description = "Non-system Kubernetes groups assigned to the CodeBuild EKS access entry."
  type        = list(string)
  default     = ["nhost-platform-lab:demo-api-deployers"]

  validation {
    condition     = length(var.deployment_kubernetes_groups) > 0 && alltrue([for group in var.deployment_kubernetes_groups : length(trimspace(group)) > 0 && !startswith(group, "system:")])
    error_message = "deployment_kubernetes_groups must contain non-empty, non-system group names."
  }
}

variable "image_repository_uri" {
  description = "Fixed regional ECR repository URI whose digests this project deploys."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9]+(?:[._/-][a-z0-9]+)*$", var.image_repository_uri))
    error_message = "image_repository_uri must be a private ECR repository URI without a tag or digest."
  }
}

variable "build_image" {
  description = "Immutable AWS CodeBuild image digest. Update only through a reviewed change."
  type        = string
  default     = "public.ecr.aws/codebuild/amazonlinux-x86_64-standard@sha256:95979ef409514d5559c49e40d701fc05f420f91198270017f6c18b79c18af532"

  validation {
    condition     = can(regex("^public\\.ecr\\.aws/codebuild/[A-Za-z0-9._/-]+@sha256:[a-f0-9]{64}$", var.build_image))
    error_message = "build_image must be an immutable AWS CodeBuild Public ECR sha256 digest."
  }
}

variable "log_retention_days" {
  description = "CloudWatch retention for private deployment logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.log_retention_days)
    error_message = "log_retention_days must be a supported short CloudWatch Logs retention period."
  }
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

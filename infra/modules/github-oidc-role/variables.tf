variable "project" {
  description = "Project name used in tags."
  type        = string
}

variable "environment" {
  description = "Owning environment."
  type        = string
}

variable "aws_region" {
  description = "AWS provider region. IAM resources remain global."
  type        = string
}

variable "role_name" {
  description = "Name of the GitHub Actions IAM role."
  type        = string
}

variable "github_repository" {
  description = "Immutable GitHub repository identity used to construct OIDC subject claims. IDs are decimal strings returned by the GitHub API."
  type = object({
    owner    = string
    owner_id = string
    name     = string
    id       = string
  })

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_repository.owner))
    error_message = "github_repository.owner must be a GitHub owner name, not a placeholder."
  }

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository.owner_id))
    error_message = "github_repository.owner_id must be the positive decimal GitHub owner ID."
  }

  validation {
    condition     = length(var.github_repository.name) <= 100 && can(regex("^[A-Za-z0-9._-]+$", var.github_repository.name))
    error_message = "github_repository.name must be a valid GitHub repository name."
  }

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository.id))
    error_message = "github_repository.id must be the positive decimal GitHub repository ID."
  }
}

variable "github_environments" {
  description = "GitHub Environments allowed to assume this role. Subjects are exact matches; wildcards are not accepted."
  type        = set(string)

  validation {
    condition = (
      length(var.github_environments) > 0 &&
      alltrue([for environment in var.github_environments : can(regex("^[A-Za-z0-9._-]+$", environment))])
    )
    error_message = "At least one GitHub Environment containing only letters, numbers, dots, underscores, or hyphens is required."
  }
}

variable "github_job_workflow_files" {
  description = "Reusable workflow filenames under .github/workflows that may assume this role from refs/heads/main."
  type        = set(string)

  validation {
    condition = (
      length(var.github_job_workflow_files) > 0 &&
      alltrue([for file in var.github_job_workflow_files : can(regex("^[A-Za-z0-9._-]+\\.ya?ml$", file))])
    )
    error_message = "At least one reusable workflow filename ending in .yml or .yaml is required."
  }
}

variable "mode" {
  description = "Permission bundle for this role."
  type        = string

  validation {
    condition     = contains(["ecr-publish", "eks-deploy", "codebuild-start"], var.mode)
    error_message = "mode must be ecr-publish, eks-deploy, or codebuild-start."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the publish role may push to."
  type        = list(string)
  default     = []
}

variable "ecr_pull_repository_arns" {
  description = "ECR repositories a deployment or CodeBuild starter role may read while verifying promoted images."
  type        = list(string)
  default     = []
}

variable "eks_cluster_arns" {
  description = "EKS clusters the deploy role may describe."
  type        = list(string)
  default     = []
}

variable "codebuild_project_arns" {
  description = "Exact CodeBuild projects a codebuild-start role may start, inspect, and stop."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.codebuild_project_arns : can(regex("^arn:[a-z0-9-]+:codebuild:[a-z0-9-]+:[0-9]{12}:project/[A-Za-z0-9][A-Za-z0-9_-]+$", arn))])
    error_message = "codebuild_project_arns must contain valid CodeBuild project ARNs."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider in this AWS account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN when creation is disabled."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

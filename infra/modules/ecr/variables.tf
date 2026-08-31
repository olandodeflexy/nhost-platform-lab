variable "project" {
  description = "Project name used in tags."
  type        = string
}

variable "environment" {
  description = "Owning environment, normally core."
  type        = string
}

variable "aws_region" {
  description = "AWS region for ECR."
  type        = string
}

variable "repository_name" {
  description = "ECR repository name."
  type        = string
  default     = "demo-api"
}

variable "pull_account_ids" {
  description = "AWS accounts allowed to pull images from this repository."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.pull_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Every pull_account_ids entry must be a 12-digit AWS account ID."
  }
}

variable "replication_regions" {
  description = "Regions in the same registry account that receive immutable repository replicas."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.replication_regions) == length(distinct(var.replication_regions)) &&
      alltrue([
        for region in var.replication_regions :
        can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))
      ])
    )
    error_message = "replication_regions must contain unique AWS region names."
  }
}

variable "untagged_retention_days" {
  description = "Days to retain untagged images. Immutable version-tagged release images are intentionally excluded from lifecycle expiry."
  type        = number
  default     = 14

  validation {
    condition     = var.untagged_retention_days >= 1
    error_message = "untagged_retention_days must be at least 1."
  }
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

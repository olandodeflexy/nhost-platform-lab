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

variable "pull_role_arns" {
  description = "Exact cross-account EKS node-role ARNs allowed to pull images. The roles may be created after the repository because they are matched through aws:PrincipalArn."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.pull_role_arns) == length(distinct(var.pull_role_arns)) &&
      alltrue([
        for arn in var.pull_role_arns :
        can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", arn))
      ])
    )
    error_message = "pull_role_arns must contain unique, exact IAM role ARNs in the aws partition."
  }
}

variable "promotion_reader_role_arns" {
  description = "Exact cross-account CI role ARNs allowed to pull and inspect images while verifying a production promotion."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.promotion_reader_role_arns) == length(distinct(var.promotion_reader_role_arns)) &&
      alltrue([
        for arn in var.promotion_reader_role_arns :
        can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", arn))
      ])
    )
    error_message = "promotion_reader_role_arns must contain unique, exact IAM role ARNs in the aws partition."
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

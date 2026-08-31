variable "project" {
  description = "Project name used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment name such as nonprod or prod."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the VPC."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used by subnet discovery tags."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "az_count" {
  description = "Number of availability zones to use."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be two or three."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for cost savings instead of one per AZ."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs in CloudWatch."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

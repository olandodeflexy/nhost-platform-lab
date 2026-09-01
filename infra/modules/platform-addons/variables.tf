variable "project" {
  description = "Project name used in tags and ownership IDs."
  type        = string
}

variable "environment" {
  description = "Environment name such as nonprod or prod."
  type        = string
}

variable "aws_region" {
  description = "AWS region containing the EKS cluster."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by the AWS Load Balancer Controller."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA certificate."
  type        = string
  sensitive   = true
}

variable "cluster_access_role_arn" {
  description = "Optional EKS administrator role assumed only by the Helm provider when requesting a cluster token."
  type        = string
  default     = null

  validation {
    condition     = var.cluster_access_role_arn == null || can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.cluster_access_role_arn))
    error_message = "cluster_access_role_arn must be an IAM role ARN when set."
  }
}

variable "karpenter_queue_name" {
  description = "SQS interruption queue created by the EKS module."
  type        = string
}

variable "karpenter_node_role_name" {
  description = "IAM role name used by Karpenter-created nodes."
  type        = string
}

variable "karpenter_ami_alias" {
  description = "Karpenter AL2023 AMI alias. Production must use a tested version, not @latest."
  type        = string
  default     = "al2023@latest"

  validation {
    condition     = can(regex("^al2023@(latest|v[0-9]{8})$", var.karpenter_ami_alias))
    error_message = "karpenter_ami_alias must be al2023@latest or a dated alias such as al2023@v20260820."
  }
}

variable "domain_filters" {
  description = "DNS suffixes external-dns is allowed to manage."
  type        = list(string)
  default     = []

  validation {
    condition = length(var.domain_filters) > 0 && alltrue([
      for domain in var.domain_filters :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", lower(trimspace(domain)))) &&
      !can(regex("(^|\\.)example\\.(com|net|org)$|\\.(invalid|test)$", lower(trimspace(domain))))
    ])
    error_message = "domain_filters must contain real DNS suffixes, not reserved example or test domains."
  }
}

variable "route53_zone_arns" {
  description = "Route 53 hosted-zone ARNs cert-manager and external-dns may modify."
  type        = list(string)
  default     = []

  validation {
    condition = length(var.route53_zone_arns) > 0 && alltrue([
      for zone_arn in var.route53_zone_arns :
      can(regex("^arn:aws:route53:::hostedzone/[A-Z0-9]+$", zone_arn))
    ])
    error_message = "route53_zone_arns must contain valid commercial-partition Route 53 hosted-zone ARNs."
  }
}

variable "letsencrypt_email" {
  description = "Email used for Let's Encrypt expiry and account notices."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.letsencrypt_email)) &&
      !can(regex("@example\\.(com|net|org|invalid)$", lower(var.letsencrypt_email)))
    )
    error_message = "letsencrypt_email must be a real contact address, not a reserved example address."
  }
}

variable "workload_namespace" {
  description = "Namespace provisioned for the example workload before namespace-scoped CI access is used."
  type        = string
  default     = "demo-api"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid Kubernetes namespace name."
  }
}

variable "deployment_kubernetes_groups" {
  description = "EKS access-entry groups allowed to manage VictoriaMetrics scrape objects in the workload namespace."
  type        = list(string)
  default     = ["nhost-platform-lab:demo-api-deployers"]

  validation {
    condition     = length(var.deployment_kubernetes_groups) > 0 && alltrue([for group in var.deployment_kubernetes_groups : length(trimspace(group)) > 0 && !startswith(group, "system:")])
    error_message = "deployment_kubernetes_groups must contain non-empty, non-system Kubernetes group names."
  }
}

variable "storage_class_name" {
  description = "Encrypted gp3 StorageClass used for stateful platform components."
  type        = string
  default     = "gp3-encrypted"
}

variable "victoria_metrics_storage_size" {
  description = "Persistent volume size requested by VMSingle."
  type        = string
  default     = "20Gi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.victoria_metrics_storage_size))
    error_message = "victoria_metrics_storage_size must be a positive binary quantity such as 20Gi."
  }
}

variable "cilium_chart_version" {
  description = "Pinned Cilium Helm chart version."
  type        = string
  default     = "1.20.1"
}

variable "karpenter_chart_version" {
  description = "Pinned Karpenter Helm chart version."
  type        = string
  default     = "1.14.1"
}

variable "ingress_nginx_chart_version" {
  description = "Pinned ingress-nginx Helm chart version."
  type        = string
  default     = "4.13.2"
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Pinned AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "3.5.0"
}

variable "external_dns_chart_version" {
  description = "Pinned external-dns Helm chart version."
  type        = string
  default     = "1.19.0"
}

variable "cert_manager_chart_version" {
  description = "Pinned cert-manager Helm chart version."
  type        = string
  default     = "1.18.2"
}

variable "metrics_server_chart_version" {
  description = "Pinned metrics-server Helm chart version."
  type        = string
  default     = "3.12.2"
}

variable "victoria_metrics_chart_version" {
  description = "Pinned VictoriaMetrics Kubernetes stack chart version."
  type        = string
  default     = "0.90.0"
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

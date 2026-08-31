output "installed_releases" {
  description = "Platform Helm releases managed by this module."
  value = [
    helm_release.cilium.name,
    helm_release.karpenter.name,
    helm_release.cert_manager.name,
    helm_release.external_dns.name,
    helm_release.aws_load_balancer_controller.name,
    helm_release.ingress_nginx.name,
    helm_release.metrics_server.name,
    helm_release.victoria_metrics.name,
    helm_release.platform_config.name,
  ]
}

output "external_dns_role_arn" {
  description = "Pod Identity IAM role for external-dns."
  value       = aws_iam_role.external_dns.arn
}

output "cert_manager_role_arn" {
  description = "Pod Identity IAM role for cert-manager."
  value       = aws_iam_role.cert_manager.arn
}

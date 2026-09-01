provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
    })
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region],
        var.cluster_access_role_arn == null ? [] : ["--role-arn", var.cluster_access_role_arn],
      )
    }
  }
}

resource "terraform_data" "karpenter_ami_guard" {
  input = var.karpenter_ami_alias

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.karpenter_ami_alias != "al2023@latest"
      error_message = "Production requires a Karpenter AMI alias pinned to a version tested in non-production."
    }
  }
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    sid       = "ChangeAuthorizedZones"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.route53_zone_arns
  }

  statement {
    sid    = "DiscoverZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "route53"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = var.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

data "aws_iam_policy_document" "cert_manager" {
  statement {
    sid       = "ChangeAuthorizedZoneTxtRecords"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.route53_zone_arns

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }

    condition {
      test     = "Null"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["false"]
    }
  }

  statement {
    sid       = "ListAuthorizedZoneRecords"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets"]
    resources = var.route53_zone_arns
  }

  statement {
    sid       = "ReadRoute53Change"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid       = "DiscoverZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager" {
  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.cert_manager.json
}

resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = var.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager.arn
}

module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name                            = "${var.cluster_name}-aws-load-balancer-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = var.tags
}

resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [yamlencode({
    cni = {
      chainingMode = "aws-cni"
      exclusive    = false
    }
    enableIPv4Masquerade = false
    routingMode          = "native"
    rollOutCiliumPods    = true
    operator = {
      replicas = 2
      prometheus = {
        enabled = true
      }
    }
    prometheus = {
      enabled = true
    }
    hubble = {
      relay = { enabled = true }
      ui    = { enabled = true }
      metrics = {
        enabled = ["dns", "drop", "tcp", "flow", "icmp", "http"]
      }
    }
  })]
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [yamlencode({
    replicas = 2
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = var.karpenter_queue_name
    }
    serviceAccount = {
      name = "karpenter"
    }
    controller = {
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
    }
  })]

  depends_on = [helm_release.cilium]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [yamlencode({
    crds         = { enabled = true }
    replicaCount = 2
    serviceAccount = {
      name = "cert-manager"
    }
  })]
}

resource "helm_release" "external_dns" {
  name             = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = var.external_dns_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    provider      = { name = "aws" }
    policy        = "upsert-only"
    registry      = "txt"
    txtOwnerId    = var.cluster_name
    domainFilters = var.domain_filters
    sources       = ["ingress", "service"]
    serviceAccount = {
      create = true
      name   = "external-dns"
    }
    env = [{
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }]
  })]

  depends_on = [aws_eks_pod_identity_association.external_dns]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [yamlencode({
    controller = {
      replicaCount = 2
      ingressClassResource = {
        default = true
      }
      service = {
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        }
      }
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = false }
      }
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.cilium,
    helm_release.victoria_metrics,
  ]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.aws_region
    vpcId        = var.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
  })]

  depends_on = [module.aws_load_balancer_controller_pod_identity]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    replicas = 2
    podDisruptionBudget = {
      enabled      = true
      minAvailable = 1
    }
  })]
}

resource "helm_release" "cluster_prerequisites" {
  name      = "cluster-prerequisites"
  namespace = "kube-system"
  chart     = "${path.module}/charts/cluster-prerequisites"

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    clusterName            = var.cluster_name
    workloadNamespace      = var.workload_namespace
    workloadDeployerGroups = var.deployment_kubernetes_groups
    storageClass = {
      name = var.storage_class_name
    }
  })]
}

resource "helm_release" "victoria_metrics" {
  name             = "victoria-metrics"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-k8s-stack"
  version          = var.victoria_metrics_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200

  values = [yamlencode({
    "victoria-metrics-operator" = {
      serviceMonitor = { enabled = false }
      operator = {
        disable_prometheus_converter = true
      }
    }
    vmsingle = {
      enabled = true
      spec = {
        retentionPeriod = var.environment == "prod" ? "30d" : "7d"
        replicaCount    = 1
        storage = {
          storageClassName = var.storage_class_name
          accessModes      = ["ReadWriteOnce"]
          resources = {
            requests = {
              storage = var.victoria_metrics_storage_size
            }
          }
        }
      }
    }
    vmagent = {
      spec = {
        selectAllByDefault = true
      }
    }
    grafana = {
      enabled     = true
      persistence = { enabled = false }
    }
    alertmanager = { enabled = true }
  })]

  depends_on = [
    helm_release.cilium,
    helm_release.cluster_prerequisites,
  ]
}

resource "helm_release" "platform_config" {
  name      = "platform-config"
  namespace = "kube-system"
  chart     = "${path.module}/charts/platform-config"

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    clusterName      = var.cluster_name
    environment      = var.environment
    awsRegion        = var.aws_region
    letsencryptEmail = var.letsencrypt_email
    karpenter = {
      nodeRole = var.karpenter_node_role_name
      amiAlias = var.karpenter_ami_alias
    }
  })]

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
    helm_release.karpenter,
    helm_release.victoria_metrics,
    terraform_data.karpenter_ami_guard,
  ]
}

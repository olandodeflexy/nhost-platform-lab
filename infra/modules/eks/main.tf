provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(local.base_tags, {
      ManagedBy = "Terraform"
      Project   = var.project
    })
  }
}

data "aws_partition" "current" {}

locals {
  base_tags = merge(
    {
      for key, value in var.tags : key => value
      if key != "karpenter.sh/discovery"
    },
    {
      Environment = var.environment
    },
  )

  private_runner_tags = merge(local.base_tags, {
    Name    = "${var.cluster_name}-private-runner"
    Purpose = "private-eks-api-access"
  })

  admin_access_entries = {
    for index, principal_arn in var.admin_principal_arns : "admin-${index}" => {
      principal_arn = principal_arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  access_entries = local.admin_access_entries
}

check "private_runner_not_discovered_by_karpenter" {
  assert {
    condition     = lookup(local.private_runner_tags, "karpenter.sh/discovery", null) == null
    error_message = "The private-runner security group must not carry the Karpenter discovery tag."
  }
}

resource "aws_security_group" "private_runner" {
  name                   = "${var.cluster_name}-private-runner"
  description            = "Private execution hosts approved to reach the EKS API"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  # The EC2NodeClass selects every group with karpenter.sh/discovery, so this
  # source identity deliberately uses the sanitized, non-discovery tag set.
  tags = local.private_runner_tags
}

resource "aws_vpc_security_group_egress_rule" "private_runner_https" {
  security_group_id = aws_security_group.private_runner.id
  description       = "HTTPS to the private EKS endpoint and required external services"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

data "aws_iam_policy_document" "ebs_csi_pod_identity" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = ["kube-system"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = ["ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_pod_identity.json

  tags = merge(local.base_tags, {
    "eks-cluster-name" = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEBSCSIDriverEKSClusterScopedPolicy"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.25.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  compute_config = {
    enabled = false
  }

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = local.access_entries

  endpoint_private_access      = true
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  security_group_additional_rules = {
    ingress_private_runner_https = {
      description              = "HTTPS from an approved private execution security group"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = aws_security_group.private_runner.id
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 30

  encryption_config = {
    resources = ["secrets"]
  }
  create_kms_key                  = true
  enable_kms_key_rotation         = true
  kms_key_deletion_window_in_days = 30

  enable_irsa = true

  addons = {
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  eks_managed_node_groups = {
    controllers = {
      name                            = "${var.cluster_name}-controllers"
      use_name_prefix                 = false
      launch_template_name            = "${var.cluster_name}-controllers"
      launch_template_use_name_prefix = false
      iam_role_name                   = "${var.cluster_name}-controllers"
      iam_role_use_name_prefix        = false

      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.controller_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.controller_min_size
      max_size     = var.controller_max_size
      desired_size = var.controller_desired_size

      labels = {
        "node-role"     = "controllers"
        "capacity-type" = "on-demand"
      }

      update_config = {
        max_unavailable_percentage = 33
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node-to-node traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  deletion_protection = var.environment == "prod"
  tags                = local.base_tags

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.25.0"

  cluster_name                    = module.eks.cluster_name
  create_pod_identity_association = true
  enable_spot_termination         = true

  iam_role_name                 = "${var.cluster_name}-karpenter-controller"
  iam_role_use_name_prefix      = false
  iam_policy_name               = "${var.cluster_name}-karpenter-controller"
  iam_policy_use_name_prefix    = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  queue_name                    = "${var.cluster_name}-karpenter"
  rule_name_prefix              = "${var.cluster_name}-karpenter-"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.base_tags
}

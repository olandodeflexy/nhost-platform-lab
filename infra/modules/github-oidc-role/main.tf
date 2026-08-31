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

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
  github_subjects = [
    for environment in sort(tolist(var.github_environments)) :
    "repo:${var.github_repository.owner}@${var.github_repository.owner_id}/${var.github_repository.name}@${var.github_repository.id}:environment:${environment}"
  ]
}

resource "terraform_data" "configuration_guard" {
  input = var.mode

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != null
      error_message = "existing_oidc_provider_arn is required when create_oidc_provider is false."
    }
    precondition {
      condition     = var.mode != "ecr-publish" || length(var.ecr_repository_arns) > 0
      error_message = "ecr-publish mode requires at least one ECR repository ARN."
    }
    precondition {
      condition     = var.mode != "eks-deploy" || length(var.eks_cluster_arns) > 0
      error_message = "eks-deploy mode requires at least one EKS cluster ARN."
    }
    precondition {
      condition     = var.mode == "eks-deploy" || length(var.ecr_pull_repository_arns) == 0
      error_message = "ecr_pull_repository_arns may only be set for eks-deploy roles."
    }
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  depends_on = [terraform_data.configuration_guard]
}

data "aws_iam_policy_document" "permissions" {
  dynamic "statement" {
    for_each = var.mode == "ecr-publish" || length(var.ecr_pull_repository_arns) > 0 ? [1] : []
    content {
      sid       = "GetECRAuthorizationToken"
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.mode == "ecr-publish" ? [1] : []
    content {
      sid    = "PublishImages"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = var.ecr_repository_arns
    }
  }

  dynamic "statement" {
    for_each = var.mode == "eks-deploy" ? [1] : []
    content {
      sid       = "DescribeAuthorizedClusters"
      effect    = "Allow"
      actions   = ["eks:DescribeCluster"]
      resources = var.eks_cluster_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ecr_pull_repository_arns) > 0 ? [1] : []
    content {
      sid    = "ReadPromotionImages"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = var.ecr_pull_repository_arns
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = var.mode
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

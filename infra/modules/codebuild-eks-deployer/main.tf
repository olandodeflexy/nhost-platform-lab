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

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id            = data.aws_caller_identity.current.account_id
  service_role_name     = "${var.project_name}-service"
  project_arn           = "arn:${data.aws_partition.current.partition}:codebuild:${var.aws_region}:${local.account_id}:project/${var.project_name}"
  cluster_arn           = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${local.account_id}:cluster/${var.cluster_name}"
  log_group_name        = "/aws/codebuild/${var.project_name}"
  log_group_arn         = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${local.account_id}:log-group:${local.log_group_name}"
  repository_clone_url  = "https://github.com/${var.github_repository.owner}/${var.github_repository.name}.git"
  image_uri_parts       = split("/", var.image_repository_uri)
  image_registry_host   = local.image_uri_parts[0]
  image_registry_id     = split(".", local.image_registry_host)[0]
  image_registry_region = split(".", local.image_registry_host)[3]
  image_repository_name = join("/", slice(local.image_uri_parts, 1, length(local.image_uri_parts)))
  image_repository_arn  = "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${local.image_registry_id}:repository/${local.image_repository_name}"
  subnet_arns = [
    for subnet_id in var.private_subnet_ids :
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${local.account_id}:subnet/${subnet_id}"
  ]
  executor_security_group_arn = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${local.account_id}:security-group/${var.executor_security_group_id}"
  network_interface_arn       = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${local.account_id}:network-interface/*"
}

resource "terraform_data" "configuration_guard" {
  input = var.image_repository_uri

  lifecycle {
    precondition {
      condition     = local.image_registry_region == var.aws_region
      error_message = "image_repository_uri must use the same regional ECR replica as this CodeBuild project."
    }
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "CodeBuildOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.project_arn]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.service_role_name
  description          = "Namespace-scoped EKS deployer for ${var.project_name}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "service" {
  statement {
    sid    = "WritePrivateBuildLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${local.log_group_arn}:*"]
  }

  statement {
    sid       = "DescribeTargetCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [local.cluster_arn]
  }

  statement {
    sid       = "ResolveImmutableRegionalImage"
    effect    = "Allow"
    actions   = ["ecr:DescribeImages"]
    resources = [local.image_repository_arn]
  }

  statement {
    sid    = "DescribeCodeBuildVpcConfiguration"
    effect = "Allow"
    actions = [
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid     = "CreateCodeBuildNetworkInterfaces"
    effect  = "Allow"
    actions = ["ec2:CreateNetworkInterface"]
    resources = concat(
      [local.network_interface_arn, local.executor_security_group_arn],
      local.subnet_arns,
    )

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "DeleteCodeBuildNetworkInterfaces"
    effect    = "Allow"
    actions   = ["ec2:DeleteNetworkInterface"]
    resources = [local.network_interface_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "AuthorizeCodeBuildNetworkInterfaces"
    effect    = "Allow"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = [local.network_interface_arn]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "ec2:Subnet"
      values   = local.subnet_arns
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_role_policy" "service" {
  name   = "fixed-eks-deployment"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.service.json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "this" {
  name                   = var.project_name
  description            = "Fixed private-EKS deployment executor for ${var.target_overlay}"
  service_role           = aws_iam_role.this.arn
  build_timeout          = 30
  queued_timeout         = 5
  auto_retry_limit       = 0
  concurrent_build_limit = 1
  badge_enabled          = false

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "CLUSTER_NAME"
      type  = "PLAINTEXT"
      value = var.cluster_name
    }

    environment_variable {
      name  = "IMAGE_URI"
      type  = "PLAINTEXT"
      value = var.image_repository_uri
    }

    environment_variable {
      name  = "IMAGE_REGISTRY_ID"
      type  = "PLAINTEXT"
      value = local.image_registry_id
    }

    environment_variable {
      name  = "IMAGE_REPOSITORY_NAME"
      type  = "PLAINTEXT"
      value = local.image_repository_name
    }

    environment_variable {
      name  = "REPOSITORY_CLONE_URL"
      type  = "PLAINTEXT"
      value = local.repository_clone_url
    }

    environment_variable {
      name  = "TARGET_NAMESPACE"
      type  = "PLAINTEXT"
      value = var.deployment_namespace
    }

    environment_variable {
      name  = "TARGET_OVERLAY"
      type  = "PLAINTEXT"
      value = var.target_overlay
    }

    environment_variable {
      name  = "TARGET_REGION"
      type  = "PLAINTEXT"
      value = var.aws_region
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.this.name
      stream_name = "deploy"
      status      = "ENABLED"
    }

    s3_logs {
      status = "DISABLED"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnet_ids
    security_group_ids = [var.executor_security_group_id]
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.service,
    terraform_data.configuration_guard,
  ]
}

resource "aws_eks_access_entry" "this" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.this.arn
  kubernetes_groups = var.deployment_kubernetes_groups
  type              = "STANDARD"
}

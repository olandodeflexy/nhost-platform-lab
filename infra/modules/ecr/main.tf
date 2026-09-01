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

locals {
  replica_regions              = toset(var.replication_regions)
  pull_account_ids             = toset([for arn in var.pull_role_arns : split(":", arn)[4]])
  promotion_reader_account_ids = toset([for arn in var.promotion_reader_role_arns : split(":", arn)[4]])
  has_cross_account_readers    = length(var.pull_role_arns) > 0 || length(var.promotion_reader_role_arns) > 0
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after ${var.untagged_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_retention_days
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "terraform_data" "configuration_guard" {
  input = var.replication_regions

  lifecycle {
    precondition {
      condition     = !contains(var.replication_regions, var.aws_region)
      error_message = "replication_regions must not contain the source aws_region."
    }
  }
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Pre-create the same immutable repository in every production region. ECR
# replication copies image content and tags, but not repository settings,
# policies, or lifecycle policies.
resource "aws_ecr_repository" "replica" {
  for_each = local.replica_regions

  region               = each.value
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "replica" {
  for_each = local.replica_regions

  region     = each.value
  repository = aws_ecr_repository.replica[each.value].name
  policy     = local.lifecycle_policy
}

data "aws_iam_policy_document" "cross_account_pull" {
  count = local.has_cross_account_readers ? 1 : 0

  dynamic "statement" {
    for_each = length(var.pull_role_arns) > 0 ? [1] : []

    content {
      sid    = "CrossAccountNodePull"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [for id in local.pull_account_ids : "arn:aws:iam::${id}:root"]
      }

      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]

      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = var.pull_role_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.promotion_reader_role_arns) > 0 ? [1] : []

    content {
      sid    = "CrossAccountPromotionRead"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [for id in local.promotion_reader_account_ids : "arn:aws:iam::${id}:root"]
      }

      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]

      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = var.promotion_reader_role_arns
      }
    }
  }
}

resource "aws_ecr_repository_policy" "cross_account_pull" {
  count      = local.has_cross_account_readers ? 1 : 0
  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.cross_account_pull[0].json
}

resource "aws_ecr_repository_policy" "replica_cross_account_pull" {
  for_each = local.has_cross_account_readers ? local.replica_regions : toset([])

  region     = each.value
  repository = aws_ecr_repository.replica[each.value].name
  policy     = data.aws_iam_policy_document.cross_account_pull[0].json
}

resource "aws_ecr_replication_configuration" "this" {
  count = length(local.replica_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = local.replica_regions

        content {
          region      = destination.value
          registry_id = aws_ecr_repository.this.registry_id
        }
      }

      repository_filter {
        filter      = var.repository_name
        filter_type = "PREFIX_MATCH"
      }
    }
  }

  depends_on = [
    aws_ecr_lifecycle_policy.replica,
    aws_ecr_repository_policy.replica_cross_account_pull,
    terraform_data.configuration_guard,
  ]
}

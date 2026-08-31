locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  region  = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals

  common_tags = {
    Environment = local.account.environment
    ManagedBy   = "Terraform"
    Project     = "nhost-platform-lab"
    Repository  = "nhost-platform-lab"
  }
}

iam_role = local.account.terragrunt_role_arn

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local.account.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.account.state_region
    encrypt        = true
    dynamodb_table = local.account.lock_table

    s3_bucket_tags      = local.common_tags
    dynamodb_table_tags = local.common_tags
  }
}

terraform {
  extra_arguments "lock_timeout" {
    commands  = ["apply", "destroy", "import", "plan", "refresh"]
    arguments = ["-lock-timeout=20m"]
  }
}

inputs = {
  project     = "nhost-lab"
  environment = local.account.environment
  aws_region  = local.region.aws_region
  tags        = local.common_tags
}

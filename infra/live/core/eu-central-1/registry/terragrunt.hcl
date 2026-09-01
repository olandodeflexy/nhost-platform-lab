include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  live_dir        = dirname(find_in_parent_folders("root.hcl"))
  nonprod_account = read_terragrunt_config("${local.live_dir}/nonprod/account.hcl").locals
  prod_account    = read_terragrunt_config("${local.live_dir}/prod/account.hcl").locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/ecr"
}

inputs = merge(include.root.inputs, {
  repository_name = "demo-api"
  pull_role_arns = [
    "arn:aws:iam::${local.nonprod_account.account_id}:role/nhost-lab-nonprod-eu-west-1-controllers",
    "arn:aws:iam::${local.nonprod_account.account_id}:role/nhost-lab-nonprod-eu-west-1-karpenter-node",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-eu-west-1-controllers",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-eu-west-1-karpenter-node",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-us-east-1-controllers",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-us-east-1-karpenter-node",
  ]
  promotion_reader_role_arns = [
    "arn:aws:iam::${local.nonprod_account.account_id}:role/nhost-lab-nonprod-eu-west-1-demo-api-deploy-service",
    "arn:aws:iam::${local.prod_account.account_id}:role/github-actions-nhost-platform-lab-deploy",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-eu-west-1-demo-api-deploy-service",
    "arn:aws:iam::${local.prod_account.account_id}:role/nhost-lab-prod-us-east-1-demo-api-deploy-service",
  ]
  replication_regions = [
    "eu-west-1",
    "us-east-1",
  ]
  untagged_retention_days = 14
})

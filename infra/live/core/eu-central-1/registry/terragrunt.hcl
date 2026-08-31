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
  pull_account_ids = [
    local.nonprod_account.account_id,
    local.prod_account.account_id,
  ]
  replication_regions = [
    "eu-west-1",
    "us-east-1",
  ]
  untagged_retention_days = 14
})

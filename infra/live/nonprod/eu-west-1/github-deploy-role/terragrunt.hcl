include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  github  = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  region  = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/github-oidc-role"
}

inputs = merge(include.root.inputs, {
  role_name         = "github-actions-nhost-platform-lab-deploy"
  mode              = "eks-deploy"
  github_repository = local.github.repository
  github_environments = [
    "nonprod",
  ]
  eks_cluster_arns = [
    "arn:aws:eks:${local.region.aws_region}:${local.account.account_id}:cluster/${local.region.cluster_name}",
  ]
  create_oidc_provider = true
})

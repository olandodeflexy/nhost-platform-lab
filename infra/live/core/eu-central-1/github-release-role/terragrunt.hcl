include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  github  = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/github-oidc-role"
}

inputs = merge(include.root.inputs, {
  role_name         = "github-actions-nhost-platform-lab-release"
  mode              = "ecr-publish"
  github_repository = local.github.repository
  github_environments = [
    "release",
  ]
  github_job_workflow_files = [
    "demo-api-release-delivery.yml",
  ]
  ecr_repository_arns = [
    "arn:aws:ecr:eu-central-1:${local.account.account_id}:repository/demo-api",
  ]
  create_oidc_provider = true
})

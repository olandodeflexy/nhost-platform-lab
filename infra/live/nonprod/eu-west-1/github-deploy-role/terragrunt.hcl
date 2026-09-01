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
  mode              = "codebuild-start"
  github_repository = local.github.repository
  github_environments = [
    "nonprod",
  ]
  github_job_workflow_files = [
    "demo-api-release-delivery.yml",
  ]
  codebuild_project_arns = [
    "arn:aws:codebuild:${local.region.aws_region}:${local.account.account_id}:project/nhost-lab-nonprod-eu-west-1-demo-api-deploy",
  ]
  create_oidc_provider = true
})

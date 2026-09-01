include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  account      = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  core_account = read_terragrunt_config("${dirname(find_in_parent_folders("root.hcl"))}/core/account.hcl").locals
  github       = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/github-oidc-role"
}

inputs = merge(include.root.inputs, {
  role_name         = "github-actions-nhost-platform-lab-deploy"
  mode              = "codebuild-start"
  github_repository = local.github.repository
  github_environments = [
    "production",
  ]
  github_job_workflow_files = [
    "demo-api-production-delivery.yml",
  ]
  codebuild_project_arns = [
    "arn:aws:codebuild:eu-west-1:${local.account.account_id}:project/nhost-lab-prod-eu-west-1-demo-api-deploy",
    "arn:aws:codebuild:us-east-1:${local.account.account_id}:project/nhost-lab-prod-us-east-1-demo-api-deploy",
  ]
  ecr_pull_repository_arns = [
    "arn:aws:ecr:eu-central-1:${local.core_account.account_id}:repository/demo-api",
    "arn:aws:ecr:eu-west-1:${local.core_account.account_id}:repository/demo-api",
    "arn:aws:ecr:us-east-1:${local.core_account.account_id}:repository/demo-api",
  ]
  create_oidc_provider = true
})

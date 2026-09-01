include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  live_dir     = dirname(find_in_parent_folders("root.hcl"))
  core_account = read_terragrunt_config("${local.live_dir}/core/account.hcl").locals
  github       = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/codebuild-eks-deployer"
}

dependency "network" {
  config_path = "../network"

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    cluster_name                       = "nhost-lab-prod-us-east-1"
    private_executor_security_group_id = "sg-00000000000000000"
  }
}

inputs = merge(include.root.inputs, {
  project_name               = "nhost-lab-prod-us-east-1-demo-api-deploy"
  github_repository          = local.github.repository
  cluster_name               = dependency.eks.outputs.cluster_name
  vpc_id                     = dependency.network.outputs.vpc_id
  private_subnet_ids         = dependency.network.outputs.private_subnet_ids
  executor_security_group_id = dependency.eks.outputs.private_executor_security_group_id
  target_overlay             = "prod-us-east-1"
  deployment_namespace       = "demo-api"
  image_repository_uri       = "${local.core_account.account_id}.dkr.ecr.us-east-1.amazonaws.com/demo-api"
})

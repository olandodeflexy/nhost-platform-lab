include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  region  = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/eks"
}

dependency "network" {
  config_path = "../network"

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
    intra_subnet_ids   = ["subnet-00000000000000004", "subnet-00000000000000005", "subnet-00000000000000006"]
  }
}

inputs = merge(include.root.inputs, {
  cluster_name             = local.region.cluster_name
  kubernetes_version       = "1.34"
  vpc_id                   = dependency.network.outputs.vpc_id
  private_subnet_ids       = dependency.network.outputs.private_subnet_ids
  control_plane_subnet_ids = dependency.network.outputs.intra_subnet_ids

  endpoint_public_access       = false
  endpoint_public_access_cidrs = []
  admin_principal_arns = [
    "arn:aws:iam::${local.account.account_id}:role/platform-admin",
  ]
  controller_instance_types = ["m7i.large"]
  controller_min_size       = 2
  controller_max_size       = 3
  controller_desired_size   = 2
})

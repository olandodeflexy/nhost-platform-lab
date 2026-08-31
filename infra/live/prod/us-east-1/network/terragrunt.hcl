include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/network"
}

inputs = merge(include.root.inputs, {
  cluster_name       = local.region.cluster_name
  vpc_cidr           = local.region.vpc_cidr
  az_count           = 3
  single_nat_gateway = false
  enable_flow_logs   = true
})

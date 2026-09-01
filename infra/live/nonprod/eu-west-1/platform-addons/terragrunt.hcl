include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals
  region  = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules/platform-addons"
}

dependency "network" {
  config_path = "../network"

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    cluster_name                       = local.region.cluster_name
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "ZHVtbXk="
    karpenter_queue_name               = "mock-karpenter-queue"
    karpenter_node_role_name           = "mock-karpenter-node-role"
  }
}

inputs = merge(include.root.inputs, {
  vpc_id                             = dependency.network.outputs.vpc_id
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_access_role_arn            = "arn:aws:iam::${local.account.account_id}:role/platform-admin"
  karpenter_queue_name               = dependency.eks.outputs.karpenter_queue_name
  karpenter_node_role_name           = dependency.eks.outputs.karpenter_node_role_name
  karpenter_ami_alias                = get_env("KARPENTER_AMI_ALIAS", "al2023@latest")
  domain_filters                     = [get_env("NHOST_NONPROD_DOMAIN")]
  route53_zone_arns                  = ["arn:aws:route53:::hostedzone/${get_env("NHOST_NONPROD_ROUTE53_ZONE_ID")}"]
  letsencrypt_email                  = get_env("NHOST_LETSENCRYPT_EMAIL")
  workload_namespace                 = "demo-api"
  deployment_kubernetes_groups       = ["nhost-platform-lab:demo-api-deployers"]
})

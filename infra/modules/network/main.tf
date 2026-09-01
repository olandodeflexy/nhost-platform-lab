provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
    })
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "${var.project}-${var.environment}-${var.aws_region}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = [for index in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, index + 8)]
  intra_subnets   = [for index in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, index + 12)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = 30
  flow_log_cloudwatch_log_group_name_prefix       = "/aws/vpc-flow-log/${local.name}/"
  vpc_flow_log_iam_role_name                      = "${local.name}-flow-log"
  vpc_flow_log_iam_role_use_name_prefix           = false
  vpc_flow_log_iam_policy_name                    = "${local.name}-flow-log-to-cloudwatch"
  vpc_flow_log_iam_policy_use_name_prefix         = false

  # Network ACLs are stateless. Keep the shared default ACL permissive and use
  # security groups as the stateful traffic boundary for these subnets. An
  # empty managed ACL would deny all NAT, EKS, node, and runner traffic.
  manage_default_network_acl = true
  default_network_acl_ingress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    },
  ]
  default_network_acl_egress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    },
  ]
  manage_default_route_table     = true
  default_route_table_routes     = []
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "karpenter.sh/discovery"          = var.cluster_name
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

locals {
  account_id          = regex("^[0-9]{12}$", get_env("NHOST_NONPROD_ACCOUNT_ID"))
  environment         = "nonprod"
  state_region        = "eu-west-1"
  state_bucket        = "nhost-lab-nonprod-${local.account_id}-tfstate"
  lock_table          = "nhost-lab-terraform-locks"
  terragrunt_role_arn = "arn:aws:iam::${local.account_id}:role/terraform-deploy"
}

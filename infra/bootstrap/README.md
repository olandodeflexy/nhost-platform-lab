# Terraform remote-state bootstrap

This directory covers only the Terraform S3 state bucket and DynamoDB lock
table. Account and identity bootstrap records belong in an
organization-approved private change record. Continue with the
[EKS deployment runbook](../../docs/eks-deployment-runbook.md).

Run this directory once in each AWS account before using Terragrunt. Bootstrap
state remains local for this one operation because the remote backend does not
exist yet.

```bash
terraform init
terraform apply \
  -var='aws_region=eu-central-1' \
  -var="state_bucket_name=nhost-lab-core-${NHOST_CORE_ACCOUNT_ID}-tfstate" \
  -var='lock_table_name=nhost-lab-terraform-locks'
```

Use a unique bucket name and the real account ID. Repeat in `nonprod` and `prod`,
then export the corresponding `NHOST_CORE_ACCOUNT_ID`,
`NHOST_NONPROD_ACCOUNT_ID`, or `NHOST_PROD_ACCOUNT_ID` before running
Terragrunt. The live account configuration derives the bucket and role ARN from
that value.

The state bucket and lock table have `prevent_destroy`. Removing them requires a
reviewed source change; a normal destroy intentionally cannot delete them.

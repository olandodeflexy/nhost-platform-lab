# Live Terragrunt configuration

The hierarchy is `account/region/component`, which keeps account assumptions,
regional settings, and module inputs separate. Apply in this order:

1. bootstrap state in each account;
2. create `core/eu-central-1/github-release-role`,
   `nonprod/eu-west-1/github-deploy-role`, and
   `prod/global/github-deploy-role`;
3. create `core/eu-central-1/registry`; on the first replication apply, the
   core `terraform-deploy` role must be allowed to create only the
   `replication.ecr.amazonaws.com` service-linked role (or an account
   administrator must create it once beforehand);
4. create each region's `network`;
5. create each region's `eks` after every ARN in `admin_principal_arns` and
   `deployment_principal_arns` exists;
6. create each region's `platform-addons` from a runner with private API access.

The EKS cluster creator does not receive permanent Kubernetes administrator
access. Human `platform-admin` roles receive cluster-admin, while GitHub deploy
roles receive edit access only in the pre-provisioned `demo-api` namespace. The
platform add-ons Helm provider requests its cluster token through
`platform-admin`; allow the account's `terraform-deploy` role to assume that
role, while keeping Terraform's AWS API permissions on `terraform-deploy`.

Amazon ECR creates `AWSServiceRoleForECRReplication` on the first registry
replication configuration. Scope the one-time `iam:CreateServiceLinkedRole`
permission with `iam:AWSServiceName` equal to
`replication.ecr.amazonaws.com`; do not grant general IAM role creation to the
Terraform identity.

Account IDs are required through `NHOST_CORE_ACCOUNT_ID`,
`NHOST_NONPROD_ACCOUNT_ID`, and `NHOST_PROD_ACCOUNT_ID`; role ARNs and state
bucket names are derived from those values. Export all three as quoted 12-digit
strings before validating or planning. DNS zones and contact addresses remain
placeholders until explicitly configured.

Production platform plans deliberately fail while `KARPENTER_AMI_ALIAS` resolves
to `al2023@latest`. Test a dated AL2023 alias in non-production and export it for
production, for example:

```bash
export KARPENTER_AMI_ALIAS=al2023@vYYYYMMDD
```

Use a real version published by AWS and accepted by Karpenter; the example above
is a format marker, not an AMI recommendation.

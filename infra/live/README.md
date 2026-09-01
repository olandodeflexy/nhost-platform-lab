# Live Terragrunt configuration

The hierarchy is `account/region/component`, separating account assumptions,
regional settings, and module inputs. Apply units individually from reviewed
saved plans; never run an unreviewed repository-wide apply.

Use this dependency order:

1. bootstrap state and create each account's human `platform-admin` role;
2. create the regional `network` roots;
3. create the regional `eks` roots;
4. create `core/eu-central-1/github-release-role`,
   `nonprod/eu-west-1/github-deploy-role`, and
   `prod/global/github-deploy-role`;
5. create each regional `codebuild-deployer` root;
6. create `core/eu-central-1/registry` after reviewing every deterministic node,
   promotion-reader, and CodeBuild service-role ARN used by its repository policy;
7. create each regional `platform-addons` root from a separately authorized
   VPC-connected administrator path.

The repository policy uses existing account-root principals plus exact
`aws:PrincipalArn` conditions. The role ARNs in those condition values do not
need to pre-exist, but creating the roles first makes the first end-to-end access
test possible and catches a mistyped deterministic ARN before delivery is enabled.

Each EKS root outputs `private_executor_security_group_id`. The matching
CodeBuild project attaches that group to its VPC network interface; the EKS
cluster security group admits TCP/443 from it. GitHub-hosted runners never join
the VPC and never receive direct EKS access.

The cluster creator receives no permanent administrator entry. Human
`platform-admin` roles receive cluster-admin. CodeBuild service roles receive a
STANDARD EKS access entry with only the custom
`nhost-platform-lab:demo-api-deployers` group; the platform prerequisites bind
that group to a narrow namespace Role. No AWS-managed EKS edit/admin policy is
associated with a delivery identity.

The `platform-addons` Helm provider requests its cluster token through
`platform-admin`. Permit the account's `terraform-deploy` role to assume that
role, while keeping the application CodeBuild service roles unable to assume
roles or administer the cluster. The workload executor does not solve this
initial private-endpoint bootstrap; use a VPN/VPC-connected operator or a
separately reviewed one-time infrastructure executor.

The GitHub roles also require the exact trusted reusable workflow on protected
`refs/heads/main` through the OIDC `job_workflow_ref` claim; an unrelated
workflow cannot assume a starter role merely by naming an Environment.

The CodeBuild projects use on-demand small compute, `NO_SOURCE`, a
Terraform-owned buildspec, an immutable Public ECR image digest, no artifacts,
no cache, no privileged mode, concurrency one, and seven-day private logs. Idle
projects and IAM roles have no CodeBuild compute-hour charge. Builds, NAT, EKS,
nodes, load balancers, and observability have their normal charges.

Amazon ECR creates `AWSServiceRoleForECRReplication` on the first replication
configuration. Scope one-time `iam:CreateServiceLinkedRole` permission with
`iam:AWSServiceName=replication.ecr.amazonaws.com`; never grant general service
role creation to the Terraform identity.

Account IDs are required through `NHOST_CORE_ACCOUNT_ID`,
`NHOST_NONPROD_ACCOUNT_ID`, and `NHOST_PROD_ACCOUNT_ID`. Export all three as
quoted 12-digit strings before validation or planning. Platform-addons roots
also require the matching `NHOST_*_DOMAIN`, `NHOST_*_ROUTE53_ZONE_ID`, and
sensitive `NHOST_LETSENCRYPT_EMAIL`; there are no deployable fallbacks.

Production platform plans deliberately fail while `KARPENTER_AMI_ALIAS` is
`al2023@latest`. Test a real dated AL2023 alias in nonprod, then export the same
reviewed value before production plans:

```bash
export KARPENTER_AMI_ALIAS=al2023@vYYYYMMDD
```

The example is a format marker, not an AMI recommendation.

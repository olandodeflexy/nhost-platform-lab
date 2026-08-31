# EKS deployment runbook

## Purpose and scope

Use this runbook to provision the AWS foundation, EKS clusters, platform add-ons,
container registry, and GitHub delivery path in this repository. It deliberately
requires non-production to pass every verification gate before either production
region is created.

Record account creation, IAM bootstrap, console-access changes, and activation
evidence in an organization-approved private change record. This public runbook
starts from the required account boundaries and short-lived operator identities.

The complete topology is:

| AWS account | Region | Purpose |
| --- | --- | --- |
| `core` | `eu-central-1` | Source ECR repository and GitHub release role |
| `core` | `eu-west-1`, `us-east-1` | Regional ECR replicas |
| `nonprod` | `eu-west-1` | `nhost-lab-nonprod-eu-west-1` |
| `prod` | `eu-west-1` | `nhost-lab-prod-eu-west-1` |
| `prod` | `us-east-1` | `nhost-lab-prod-us-east-1` |

There are three milestones:

1. **Cluster only:** network and EKS control plane exist.
2. **Usable platform:** private access and platform add-ons are healthy.
3. **Delivery platform:** ECR, GitHub OIDC, private runners, release, and
   promotion are working.

If the intended deployment uses one AWS account or only one cluster, change and
review the account boundaries, role ARNs, ECR policies, and live configuration
before following this runbook. Do not point all three example account files at
one account without redesigning those boundaries.

## Safety rules

- Use IAM Identity Center or another federated source of short-lived AWS
  credentials. Do not create or store long-lived AWS keys.
- Run one Terragrunt unit at a time, review every plan, and verify the caller's
  account and region before applying.
- Do not run a repository-wide `terragrunt run --all apply`. Literal IAM role
  inputs are not represented in Terragrunt's dependency graph.
- Do not use `-auto-approve` during the first deployment.
- Stop on any unexpected destroy, replacement, account, region, IAM principal,
  CIDR, add-on version, or cost change.
- Preserve the local bootstrap state for every account. Do not force-unlock
  state unless no other run is active and the action is peer-reviewed.
- Production starts only after the non-production exit criteria are satisfied.
- DNS/traffic failover is not automated by this project and requires a separate,
  tested runbook.

The full deployment creates billable EKS control planes, NAT gateways, EC2
instances, load balancers, EBS volumes, logs, metrics, and replicated resources.
Create budgets and anomaly alerts before applying anything beyond state
bootstrap. A normal AWS Budget notification is an alert, not a spending cap;
confirm whether any budget action is configured before treating it as an
enforcement control.

## Deployment record

Record these values in the approved change record. Account IDs and GitHub IDs
are identifiers, not secrets. Do not record credentials, SSO tokens, private
keys, or application secrets.

| Parameter | Required value |
| --- | --- |
| Operator and change/ticket ID | Named operator and approval record |
| Start time and approved commit | UTC time and full Git SHA |
| Core AWS account ID/profile | Account ID and SSO source profile |
| Non-production AWS account ID/profile | Account ID and SSO source profile |
| Production AWS account ID/profile | Account ID and SSO source profile |
| GitHub owner/name and immutable IDs | Owner, owner ID, repository, repository ID |
| Route53 zones | Nonprod, production EU, and production US zone IDs |
| Certificate contact email | Operational email address |
| Karpenter AMI alias | Tested, dated AL2023 alias |
| Private runner security group | Source allowed to reach EKS TCP/443 |
| Plan and rollback owners | Evidence location and accountable owners |

Optional shell variables used by examples:

```bash
export NHOST_CORE_ACCOUNT_ID="<CORE_ACCOUNT_ID>"
export NHOST_NONPROD_ACCOUNT_ID="<NONPROD_ACCOUNT_ID>"
export NHOST_PROD_ACCOUNT_ID="<PROD_ACCOUNT_ID>"

export NHOST_CORE_PROFILE="core-sso"
export NHOST_NONPROD_PROFILE="nonprod-sso"
export NHOST_PROD_PROFILE="prod-sso"
export NHOST_MANAGEMENT_PROFILE="management-admin"

export NHOST_CORE_OPERATOR_PROFILE="core-terraform"
export NHOST_NONPROD_OPERATOR_PROFILE="nonprod-terraform"
export NHOST_PROD_OPERATOR_PROFILE="prod-terraform"

export NHOST_REPOSITORY_OWNER="olandodeflexy"
export NHOST_REPOSITORY_NAME="nhost-platform-lab"
```

The three account-ID variables are also required by `infra/live/*/account.hcl`.
Terragrunt rejects a missing or malformed value rather than falling back to an
account identifier stored in Git. Replace every example value before running an
AWS command.

## Phase 0: prepare the workstation and repository

Run commands from the repository root unless a step explicitly changes
directories.

### 0.1 Load the pinned Nix environment

If a new terminal cannot find Nix, reopen it or load the multi-user profile:

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version
```

This project requires flakes. If they are not enabled in the user's Nix
configuration, pass the feature flags explicitly:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  develop --no-update-lock-file
```

Use this development shell for Terraform and Terragrunt. The repository pins
Terragrunt 1.0.4; do not deploy with an older globally installed version.

```bash
terragrunt --version
terraform version
aws --version
kubectl version --client
helm version
```

**Gate:** Every command succeeds and Terragrunt reports 1.0.4.

### 0.2 Prepare the Git repository

Before the initial commit, ensure generated binaries cannot be staged:

```bash
git check-ignore services/demo-api/bin/demo-api
```

Expected result: the command prints the path. If it does not, add
`/services/demo-api/bin/` to `.gitignore` before using `git add .`.

Create the initial commit and push the default branch to the intended GitHub
repository. The OCI source label is configured for
`https://github.com/olandodeflexy/nhost-platform-lab`; update it if the repository
is transferred or forked for deployment.

```bash
git rev-parse --verify HEAD
git remote -v
git status --short
```

Expected result: `HEAD` and the intended remote exist, and every remaining
working-tree change is understood.

### 0.3 Run the local validation gate

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake check --no-update-lock-file

nix --extra-experimental-features 'nix-command flakes' \
  run --no-update-lock-file .#manifest-check

make infra-fmt
make infra-validate
```

On macOS, the local flake check is supported, but building the Linux OCI image
requires a Linux runner or configured Linux remote builder.

**Gate:** Do not proceed until every check succeeds from the pinned toolchain.

## Phase 1: prepare AWS accounts and identities

### 1.1 Confirm accounts, regions, quotas, and networks

Create or identify the `core`, `nonprod`, and `prod` accounts. Confirm these
regions are enabled:

- `eu-central-1` in core;
- `eu-west-1` in nonprod;
- `eu-west-1` and `us-east-1` in prod.

Verify that every cluster region exposes at least three usable Availability
Zones and quotas cover the VPCs, seven planned NAT/EIP allocations, three EKS
clusters, managed node groups, on-demand and Spot capacity, load balancers, and
EBS volumes.

Confirm these CIDRs do not overlap any corporate, VPN, peering, Transit Gateway,
runner, or existing VPC network:

| Environment | VPC CIDR |
| --- | --- |
| Non-production EU | `10.20.0.0/16` |
| Production EU | `10.40.0.0/16` |
| Production US | `10.60.0.0/16` |

### 1.2 Configure federated AWS profiles

```bash
aws configure sso --profile "${NHOST_CORE_PROFILE}"
aws configure sso --profile "${NHOST_NONPROD_PROFILE}"
aws configure sso --profile "${NHOST_PROD_PROFILE}"
```

Authenticate and verify each account separately:

```bash
aws sso login --profile "${NHOST_CORE_PROFILE}"
AWS_PROFILE="${NHOST_CORE_PROFILE}" aws sts get-caller-identity

aws sso login --profile "${NHOST_NONPROD_PROFILE}"
AWS_PROFILE="${NHOST_NONPROD_PROFILE}" aws sts get-caller-identity

aws sso login --profile "${NHOST_PROD_PROFILE}"
AWS_PROFILE="${NHOST_PROD_PROFILE}" aws sts get-caller-identity
```

**Gate:** Each returned account ID matches the deployment record. Stop on a
mismatch.

If the source profile uses the AWS CLI's newer `login_session` setting,
Terraform's AWS SDK might fail while loading the profile even though AWS CLI
commands work. Do not create an access key to work around that mismatch. Add a
local credential-process bridge that asks AWS CLI for the same temporary
session, then use the bridge profile as the Terragrunt source profile:

```bash
aws configure set credential_process \
  'aws configure export-credentials --profile nonprod-sso' \
  --profile nonprod-terraform-source
aws configure set region eu-west-1 \
  --profile nonprod-terraform-source

aws sts get-caller-identity --profile nonprod-terraform-source
```

Repeat for core and production. The bridge stores only a command in
`~/.aws/config`; AWS CLI supplies an expiring session to Terraform in memory.
Never run `export-credentials` for display, copy its output, or commit AWS
configuration files.

### 1.3 Create external deployment and administration roles

The repository does not create its infrastructure bootstrap roles. Create
`terraform-deploy` in all three accounts. Its trust policy must allow the
approved federated operator, and that source identity must have
`sts:AssumeRole` on the role.

Give each `terraform-deploy` role only the permissions needed for its account:

- object-level S3 state access and row-level DynamoDB lock operations after a
  separate bootstrap identity creates the backend;
- VPC, subnet, route, NAT, EIP, security-group, flow-log, and CloudWatch
  management;
- EKS cluster, node group, add-on, access-entry, and Pod Identity management;
- project-name-scoped IAM role, policy, attachment, and `iam:PassRole`
  management, with an approved managed-policy allowlist;
- KMS, EC2 launch-template, SQS, and EventBridge management for the named
  clusters and regions;
- `sts:AssumeRole` on the account's `platform-admin` role;
- in core, ECR repository, replication, and repository-policy management.

Terraform does not directly need `ec2:RunInstances`,
`ec2:TerminateInstances`, `ec2:CreateVolume`, `elasticloadbalancing:*`,
`autoscaling:*`, Route53 record mutation, secret access, or unrestricted
service-linked-role creation. Those capabilities belong to AWS services or
the narrowly scoped runtime roles created for Kubernetes controllers.

Because the current modules create IAM roles and policies alongside the
infrastructure, `terraform-deploy` is necessarily an IAM policy author inside
its member account. The dedicated sandbox accounts and SCP are therefore the
hard blast-radius boundary. For a long-lived production design, move identity
resources to a separately controlled bootstrap stack, require permissions
boundaries on every runtime role, and leave the routine Terraform role only
scoped `iam:PassRole` access.

Create a separate `platform-admin` role in nonprod and prod. Its trust policy
must permit approved human administrators and the corresponding
`terraform-deploy` role. The prod role serves both production clusters.

The cluster creator receives no implicit administrator access.
`platform-admin` receives cluster-scoped administrator access through EKS access
entries, while GitHub deploy roles receive edit access only in `demo-api`.

Test source-profile assumption without printing credentials:

```bash
AWS_PROFILE="${NHOST_NONPROD_PROFILE}" aws sts assume-role \
  --role-arn "arn:aws:iam::${NHOST_NONPROD_ACCOUNT_ID}:role/terraform-deploy" \
  --role-session-name nhost-preflight \
  --query 'AssumedRoleUser.Arn' \
  --output text

AWS_PROFILE="${NHOST_PROD_PROFILE}" aws sts assume-role \
  --role-arn "arn:aws:iam::${NHOST_PROD_ACCOUNT_ID}:role/terraform-deploy" \
  --role-session-name nhost-preflight \
  --query 'AssumedRoleUser.Arn' \
  --output text
```

For direct AWS and kubectl verification, configure role profiles backed by the
SSO source profiles. For example, add the equivalent of this to the AWS CLI
configuration, using the real account ID:

```ini
[profile nonprod-terraform]
source_profile = nonprod-sso
role_arn = arn:aws:iam::<NONPROD_ACCOUNT_ID>:role/terraform-deploy
region = eu-west-1
```

Use these operator profiles for direct resource checks. Continue to give
Terragrunt the SSO source profile because Terragrunt performs its own role
assumption.

Confirm SCPs and permission boundaries permit the service-linked roles required
by EKS, managed node groups, EC2 Spot/Karpenter, and Elastic Load Balancing.
Pre-create them through an approved bootstrap process if necessary.

ECR replication has a specific one-time requirement. Either pre-create
`AWSServiceRoleForECRReplication` or grant core `terraform-deploy`
condition-scoped `iam:CreateServiceLinkedRole` where `iam:AWSServiceName` equals
`replication.ecr.amazonaws.com`. Never grant unrestricted service-linked-role
creation.

### 1.4 Wait for newly created member-account service activation

AWS Organizations can report a new member account as active before every AWS
service has finished initializing. First inspect the account's current `State`;
AWS CLI 2.29.0 or later exposes this field:

```bash
AWS_PROFILE="${NHOST_MANAGEMENT_PROFILE}" aws organizations describe-account \
  --region us-east-1 \
  --account-id "${NHOST_CORE_ACCOUNT_ID}" \
  --query 'Account.{Id:Id,Name:Name,State:State,JoinedMethod:JoinedMethod,JoinedTimestamp:JoinedTimestamp}'
```

`PENDING_ACTIVATION` requires completing the verification step AWS requested or
contacting Account and Billing Support. For `ACTIVE`, make harmless service read
calls with each bootstrap profile:

```bash
AWS_PROFILE="${NHOST_CORE_PROFILE}" aws s3api list-buckets --max-items 1
AWS_PROFILE="${NHOST_CORE_PROFILE}" aws dynamodb list-tables \
  --region eu-central-1 --limit 1
```

Repeat in the non-production and production accounts. If AWS returns
`NotSignedUp`, `SubscriptionRequiredException`, or "needs a subscription for
the service," stop and retry later. Do not broaden IAM permissions: these are
account-activation errors, not authorization failures. General AWS activation
guidance says activation can take up to 24 hours, while Organizations guidance
notes that isolated service/billing propagation can sometimes take 48 hours.
Neither is a service-level agreement for Organizations `CreateAccount`. Open an
Account and Billing case if core services still fail 24 hours after creation;
do not recreate the accounts or repeatedly retry Terraform applies.

References: [AWS account activation](https://docs.aws.amazon.com/accounts/latest/reference/getting-started.html),
[AWS Organizations account troubleshooting](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_troubleshoot.html).

**Gate:** S3 and DynamoDB preflight calls succeed in all three accounts.

## Phase 2: bootstrap remote state

Bootstrap uses local state because the remote backend does not yet exist.
Isolate the three account states with distinct Terraform workspaces or separate
secured directories. These examples use workspaces.

```bash
terraform -chdir=infra/bootstrap init
```

Core:

```bash
terraform -chdir=infra/bootstrap workspace new core

AWS_PROFILE="${NHOST_CORE_PROFILE}" terraform -chdir=infra/bootstrap apply \
  -var='aws_region=eu-central-1' \
  -var="state_bucket_name=nhost-lab-core-${NHOST_CORE_ACCOUNT_ID}-tfstate" \
  -var='lock_table_name=nhost-lab-terraform-locks'

terraform -chdir=infra/bootstrap output backend_configuration
```

Non-production:

```bash
terraform -chdir=infra/bootstrap workspace new nonprod

AWS_PROFILE="${NHOST_NONPROD_PROFILE}" terraform -chdir=infra/bootstrap apply \
  -var='aws_region=eu-west-1' \
  -var="state_bucket_name=nhost-lab-nonprod-${NHOST_NONPROD_ACCOUNT_ID}-tfstate" \
  -var='lock_table_name=nhost-lab-terraform-locks'

terraform -chdir=infra/bootstrap output backend_configuration
```

Production:

```bash
terraform -chdir=infra/bootstrap workspace new prod

AWS_PROFILE="${NHOST_PROD_PROFILE}" terraform -chdir=infra/bootstrap apply \
  -var='aws_region=eu-west-1' \
  -var="state_bucket_name=nhost-lab-prod-${NHOST_PROD_ACCOUNT_ID}-tfstate" \
  -var='lock_table_name=nhost-lab-terraform-locks'

terraform -chdir=infra/bootstrap output backend_configuration
```

On retries, select the existing workspace instead of creating it:

```bash
terraform -chdir=infra/bootstrap workspace select core
```

Copy each output into the matching `infra/live/{core,nonprod,prod}/account.hcl`
file. Also replace the account ID and `terraform-deploy` ARN.

Verify the three S3 buckets and DynamoDB tables with their owning profiles. For
example:

```bash
AWS_PROFILE="${NHOST_NONPROD_PROFILE}" aws s3api head-bucket \
  --bucket "nhost-lab-nonprod-${NHOST_NONPROD_ACCOUNT_ID}-tfstate"

AWS_PROFILE="${NHOST_NONPROD_PROFILE}" aws dynamodb describe-table \
  --region eu-west-1 \
  --table-name nhost-lab-terraform-locks \
  --query 'Table.TableStatus' \
  --output text
```

**Gate:** All backends exist, outputs match the three account files, and each
local bootstrap workspace is preserved securely.

## Phase 3: configure GitHub identity, live values, and DNS

### 3.1 Populate the immutable GitHub identity

After the repository exists, retrieve its public immutable identifiers:

```bash
gh api "repos/${NHOST_REPOSITORY_OWNER}/${NHOST_REPOSITORY_NAME}" \
  --jq '{owner: .owner.login, owner_id: (.owner.id | tostring), name: .name, id: (.id | tostring)}'
```

Commit those values in `infra/live/github.hcl`. The OIDC module constructs exact
subjects such as:

```text
repo:olandodeflexy@42207883/nhost-platform-lab@1352263838:environment:nonprod
```

If a GitHub Actions OIDC provider already exists in an AWS account, import it or
change that account's live root to pass `existing_oidc_provider_arn`. Attempting
to create a duplicate provider will fail.

### 3.2 Resolve environment-specific values

Search for unresolved values:

```bash
rg -n 'REPLACE_ME|replace-me|example\.com|your-org|al2023@latest' \
  infra/live deploy/kustomize flake.nix \
  --glob '*.hcl' \
  --glob '*.yaml' \
  --glob '*.nix'
```

Replace and review:

- all three exported account IDs and the caller identity for each account;
- the state bucket and deployment role ARN derived by each account config;
- the public GitHub owner, owner ID, repository name, and repository ID;
- the OCI source URL in `flake.nix`;
- every Route53 zone ARN, domain filter, ingress host, and certificate email;
- the production Karpenter AMI alias.

The tracked Kustomize overlays intentionally retain an `example.invalid` image
sentinel. Do not replace it with an account-specific URI in Git: `scripts/deploy.sh`
copies the overlay and replaces the sentinel with the selected regional ECR URI
and immutable digest immediately before rendering.

The search targets deployment-bearing files rather than documentation. Resolve
every account, GitHub, DNS, email, and repository match before planning. Review
the intentional `al2023@latest` matches separately: nonprod may use it for the
initial test, while the guarded production fallback still requires the dated
environment value described below.

### 3.3 Create Route53 zones and delegation

Create the required hosted zones outside this repository and delegate them from
their parent domains:

- the non-production zone in the nonprod account;
- both production zones in the prod account.

With the current Pod Identity policies, external-dns and cert-manager expect the
zones to be in the same account as their cluster. Put each zone ARN, its domain
filter, and the real certificate contact email in the corresponding
`platform-addons` root.

Verify each zone and independently verify parent delegation:

```bash
AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}" aws route53 get-hosted-zone \
  --id NONPROD_ZONE_ID
```

### 3.4 Select a Karpenter AMI alias

Nonprod may initially use `al2023@latest`, but production deliberately rejects
it. Resolve a real dated AL2023 alias supported by the pinned Karpenter version,
test it in nonprod, record the evidence, and export it before production add-on
plans:

```bash
export KARPENTER_AMI_ALIAS='al2023@vYYYYMMDD'
```

The value above is a format marker, not an AMI recommendation.

## Phase 4: establish private EKS API access

All clusters set `endpoint_public_access = false`. AWS control-plane resources
can be created from an authenticated workstation, but `kubectl`, Helm, and the
`platform-addons` providers must run from the VPC or a connected network.

Provision one of these reviewed access paths before the add-on phase:

- an ephemeral or tightly managed EC2 runner reached through SSM;
- a VPN-connected operator workstation;
- a connected build network through peering or Transit Gateway;
- another private execution environment with equivalent controls.

The execution environment requires:

- private routing to the cluster VPC;
- DNS resolution for the private EKS endpoint;
- TCP/443 admission to the EKS cluster security group;
- HTTPS egress to AWS APIs and the public Helm/OCI sources used by the module;
- the pinned Nix toolchain and a clean checkout of the approved commit.

The repository does not provision VPN, peering, Transit Gateway, runners, or a
runner-to-cluster security-group rule. Represent the TCP/443 rule in Terraform,
scoped to the runner security-group ID. Do not create an untracked console rule
or allow `0.0.0.0/0`.

**Gate:** Do not apply any `platform-addons` root until the private host resolves
the cluster endpoint, reaches TCP/443, and authenticates as `platform-admin`.

## Phase 5: apply infrastructure in stages

Use this pattern for every Terragrunt unit:

```bash
cd TERRAGRUNT_UNIT
export NHOST_PLAN_FILE="${PWD}/deployment.tfplan"
AWS_PROFILE="SSO_SOURCE_PROFILE" terragrunt plan -out="${NHOST_PLAN_FILE}"
AWS_PROFILE="SSO_SOURCE_PROFILE" terragrunt run -- show -no-color "${NHOST_PLAN_FILE}"
# Review the complete plan, account, region, versions, and cost.
AWS_PROFILE="SSO_SOURCE_PROFILE" terragrunt apply "${NHOST_PLAN_FILE}"
cd -
```

Pass the SSO source profile, not a profile that has already assumed
`terraform-deploy`; `infra/live/root.hcl` performs that assumption. Terraform
plan files can contain sensitive values: keep them in the ignored unit working
directory, protect any retained copy, and never attach a raw plan to a public
record.

| Live path prefix | SSO source profile |
| --- | --- |
| `infra/live/core` | `${NHOST_CORE_PROFILE}` |
| `infra/live/nonprod` | `${NHOST_NONPROD_PROFILE}` |
| `infra/live/prod` | `${NHOST_PROD_PROFILE}` |

### 5.1 Create GitHub OIDC roles

Apply these first because EKS access entries reference their role ARNs:

| Profile | Terragrunt unit |
| --- | --- |
| Core | `infra/live/core/eu-central-1/github-release-role` |
| Non-production | `infra/live/nonprod/eu-west-1/github-deploy-role` |
| Production | `infra/live/prod/global/github-deploy-role` |

After each apply:

```bash
terragrunt output role_arn
terragrunt output github_subjects
```

Expected subjects contain the exact immutable owner ID, repository ID, and
environment. The environment names are `release`, `nonprod`, and `production`.

For cluster-only deployment, the core release role can be deferred. The
nonprod/prod deploy roles remain prerequisites while their ARNs are present in
the EKS live inputs.

### 5.2 Create the core registry

Before applying, inspect existing registry-wide replication configuration so
Terraform does not replace configuration owned elsewhere:

```bash
AWS_PROFILE="${NHOST_CORE_OPERATOR_PROFILE}" aws ecr describe-registry \
  --region eu-central-1 \
  --query replicationConfiguration
```

Apply:

```text
infra/live/core/eu-central-1/registry
```

Then verify:

```bash
terragrunt output repository_url
terragrunt output regional_repository_urls
```

The source and both regional repositories must exist before the first
production promotion. Registry creation can be deferred if the immediate goal
is only an empty nonprod cluster.

### 5.3 Create networks

Apply one at a time:

```text
infra/live/nonprod/eu-west-1/network
infra/live/prod/eu-west-1/network
infra/live/prod/us-east-1/network
```

For the recommended first deployment, apply only nonprod and inspect:

```bash
terragrunt output vpc_id
terragrunt output availability_zones
terragrunt output private_subnet_ids
terragrunt output intra_subnet_ids
```

**Gate:** Confirm the expected CIDR, three AZs, route/NAT design, flow logs, and
subnet roles before creating EKS.

### 5.4 Create EKS

Confirm that every ARN in `admin_principal_arns` and
`deployment_principal_arns` already exists. Apply one at a time:

```text
infra/live/nonprod/eu-west-1/eks
infra/live/prod/eu-west-1/eks
infra/live/prod/us-east-1/eks
```

For the first deployment, apply only nonprod. The module creates:

- Kubernetes 1.34 with private-only API access;
- API-based access entries, KMS encryption, and control-plane logging;
- a controller managed node group;
- Karpenter IAM, queue, and interruption resources;
- VPC CNI, CoreDNS, kube-proxy, Pod Identity Agent, and EBS CSI add-ons;
- an EBS CSI Pod Identity role.

Before planning, verify that Kubernetes 1.34 remains supported in the target
regions and schedule the next minor-version test before its standard-support
window ends.

The managed add-ons currently resolve with `most_recent = true`. Record every
resolved version from the plan and stop if the apply would introduce an
unreviewed upgrade. Pin exact versions before treating production as stable.

Capture outputs:

```bash
terragrunt output cluster_name
terragrunt output cluster_arn
terragrunt output cluster_security_group_id
terragrunt output node_security_group_id
terragrunt output karpenter_node_role_arn
```

Do not continue if the cluster is not `ACTIVE`, nodes cannot join, an access
entry is missing, an add-on is degraded, or the private operator path is absent.

### 5.5 Create platform add-ons

Run only from the private execution host. Confirm its source profile can assume
`terraform-deploy`, which in turn can assume `platform-admin`.

Apply nonprod first:

```text
infra/live/nonprod/eu-west-1/platform-addons
```

After nonprod passes all Phase 6 checks, apply production one region at a time:

```text
infra/live/prod/eu-west-1/platform-addons
infra/live/prod/us-east-1/platform-addons
```

Before each production plan and apply:

```bash
export KARPENTER_AMI_ALIAS='al2023@vYYYYMMDD'
```

The module installs Cilium, Karpenter, cert-manager, external-dns, AWS Load
Balancer Controller, ingress-nginx, metrics-server, VictoriaMetrics, the
encrypted `gp3` StorageClass, and prerequisites for `demo-api`.

## Phase 6: verify clusters and add-ons

Run AWS checks with an identity authorized to read the cluster. Run Kubernetes
checks from the private execution host.

### 6.1 Verify the control plane

Nonprod example:

```bash
AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}" aws eks describe-cluster \
  --name nhost-lab-nonprod-eu-west-1 \
  --region eu-west-1 \
  --query 'cluster.{status:status,version:version,private:resourcesVpcConfig.endpointPrivateAccess,public:resourcesVpcConfig.endpointPublicAccess}'

AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}" aws eks list-access-entries \
  --cluster-name nhost-lab-nonprod-eu-west-1 \
  --region eu-west-1

AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}" aws eks list-addons \
  --cluster-name nhost-lab-nonprod-eu-west-1 \
  --region eu-west-1

AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}" aws eks describe-addon \
  --cluster-name nhost-lab-nonprod-eu-west-1 \
  --addon-name aws-ebs-csi-driver \
  --region eu-west-1 \
  --query 'addon.{status:status,version:addonVersion}'
```

Expected results:

- cluster status is `ACTIVE`;
- Kubernetes version is the reviewed version;
- private endpoint is `true` and public endpoint is `false`;
- `platform-admin` has cluster-admin access;
- GitHub deploy has edit access only in `demo-api`;
- every managed add-on is healthy and uses the planned version.

Use `aws eks list-associated-access-policies` for each human and deployment
principal to record its actual access scope.

### 6.2 Configure kubectl and verify nodes

From the private host, use a temporary role chain that reaches
`platform-admin`, then create kubeconfig:

```bash
export AWS_PROFILE="${NHOST_NONPROD_OPERATOR_PROFILE}"

aws eks update-kubeconfig \
  --name nhost-lab-nonprod-eu-west-1 \
  --region eu-west-1 \
  --role-arn "arn:aws:iam::${NHOST_NONPROD_ACCOUNT_ID}:role/platform-admin"
```

```bash
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter
```

### 6.3 Verify storage and monitoring

```bash
kubectl get storageclass gp3-encrypted
kubectl -n monitoring get pods,pvc
kubectl get crd vmservicescrapes.operator.victoriametrics.com
kubectl get vmservicescrape -A
```

Expected results:

- `gp3-encrypted` uses the standard EBS CSI provisioner;
- the VictoriaMetrics PVC is `Bound`;
- monitoring pods are ready;
- the `VMServiceScrape` CRD and scrape objects exist;
- no `ServiceMonitor` CRD is required.

### 6.4 Verify platform controllers

```bash
helm list -A
kubectl get ns demo-api
kubectl get nodepool,ec2nodeclass
kubectl -n ingress-nginx get deploy,pod,svc
kubectl -n cert-manager get pods
kubectl -n external-dns get pods
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
```

Verify that external-dns changes only the intended zone, cert-manager completes
a test certificate, ingress obtains the expected load balancer, and Karpenter
can provision and retire a test node for an intentionally unschedulable nonprod
workload.

### 6.5 Verify the application after its first release

```bash
kubectl -n demo-api get deploy,pod,svc,hpa,pdb
kubectl -n demo-api rollout status deployment/demo-api
kubectl -n demo-api logs deployment/demo-api --tail=100
```

Verify `/healthz`, `/readyz`, `/metrics`, and the intended ingress hostname.

### 6.6 Non-production exit criteria

Production is blocked until all of the following are recorded:

- local checks and reviewed Terraform/Terragrunt plans passed;
- private routing, DNS, authentication, and TCP/443 access passed;
- EKS and every managed add-on are healthy;
- controller nodes are ready across the expected AZs;
- EBS dynamic provisioning produced a bound encrypted volume;
- Cilium, DNS, ingress, certificates, external-dns, metrics, and monitoring are
  healthy;
- Karpenter created and removed a test node;
- GitHub deploy access cannot modify resources outside `demo-api`;
- dashboards, logs, and alerts were inspected;
- cost and capacity remain within the approved envelope.

## Phase 7: configure GitHub delivery

This is not required for an empty EKS control plane, but it is required for the
repository's release and promotion workflows.

### 7.1 Protect environments, branch, and tags

Create exact, case-sensitive GitHub Environments:

- `release`, restricted to protected tags matching `demo-api@*`;
- `nonprod`, restricted to protected tags matching `demo-api@*`;
- `production`, restricted to the protected default branch with reviewers.

Protect the default branch and require pull requests plus `ci / checks`. Add a
tag ruleset that prevents force-updating or deleting `demo-api@*`, while
permitting the release GitHub App to create those tags.

Enable artifact attestations. Public repositories can use them on current
GitHub plans; private or internal repositories require the applicable GitHub
Enterprise Cloud capability.

### 7.2 Configure protected identifiers, variables, and release credentials

Store account IDs as protected GitHub Environment secrets. Account IDs are not
credentials, but treating them as secrets ensures that GitHub masks their values
in workflow logs.

| Environment | Required account-ID secrets |
| --- | --- |
| `release` | `AWS_CORE_ACCOUNT_ID` |
| `nonprod` | `AWS_CORE_ACCOUNT_ID`, `AWS_NONPROD_ACCOUNT_ID` |
| `production` | `AWS_CORE_ACCOUNT_ID`, `AWS_PROD_ACCOUNT_ID` |

Create these non-sensitive repository variables:

| Variable | Value |
| --- | --- |
| `ECR_REGION` | `eu-central-1` |
| `ECR_REPOSITORY` | `demo-api` |
| `NONPROD_CLUSTER_NAME` | `nhost-lab-nonprod-eu-west-1` |
| `PROD_EU_CLUSTER_NAME` | `nhost-lab-prod-eu-west-1` |
| `PROD_US_CLUSTER_NAME` | `nhost-lab-prod-us-east-1` |
| `RELEASE_BOT_CLIENT_ID` | GitHub App Client ID |

Install a GitHub App on the repository with the narrowly required permission to
create releases and tags. Store its credentials as:

- non-sensitive repository variable `RELEASE_BOT_CLIENT_ID` containing the
  App's Client ID, not its legacy numeric App ID;
- Actions secret `RELEASE_BOT_PRIVATE_KEY` containing the PEM private key.

Do not create AWS access-key secrets. GitHub jobs obtain temporary credentials
through OIDC.

The workflows also ask the AWS credential action to mask the authenticated
account ID, reject credentials issued for an unexpected account, clear inherited
credentials on self-hosted runners, and avoid credential step outputs. Do not
enable `TF_LOG`, Terragrunt debug/trace logging, `terragrunt render`, or public
Terraform plan output with real deployment values. Plans, state, and CLI errors
can contain ARNs, bucket names, network IDs, endpoints, and other account
metadata even when no secret value is present.

The public non-production attestation still names the fully qualified ECR image
so that production can verify the deployed artifact. Its subject therefore
publishes the registry account ID as non-secret metadata. If organizational
policy treats that identifier as confidential, redesign the provenance flow or
use a private repository before enabling releases.

Application secrets are also prohibited in Kustomize, Terraform variables,
GitHub variables, and state outputs. A real application should retrieve them
from AWS Secrets Manager through External Secrets or an equivalent operator
using EKS Pod Identity.

### 7.3 Register private runners

Register ephemeral or tightly managed self-hosted Linux runners with private
connectivity and these exact labels:

- `self-hosted`, `linux`, `nonprod`;
- `self-hosted`, `linux`, `prod-eu-west-1`;
- `self-hosted`, `linux`, `prod-us-east-1`.

Restrict runner groups to this repository, patch runner images, prevent
credential persistence, and replace runners after untrusted or failed jobs.

### 7.4 Verify ECR repositories and replication

```bash
for NHOST_ECR_REGION in eu-central-1 eu-west-1 us-east-1; do
  AWS_PROFILE="${NHOST_CORE_OPERATOR_PROFILE}" aws ecr describe-repositories \
    --registry-id "${NHOST_CORE_ACCOUNT_ID}" \
    --region "${NHOST_ECR_REGION}" \
    --repository-names demo-api
done
```

ECR replicates images pushed after replication is enabled. If releases existed
before replication, use a separately approved backfill procedure and compare
source and destination digests. Never delete or overwrite an immutable tag to
force a mismatch through promotion.

## Phase 8: release and production promotion

1. Merge ordinary changes only after CI succeeds.
2. Open and merge a PR titled `release(demo-api): X.Y.Z`.
3. Verify that the GitHub App creates tag and release `demo-api@X.Y.Z`.
4. Verify `demo-api-release.yml` builds once, pushes the immutable image,
   deploys nonprod, waits for rollout, and records the signed nonprod
   attestation.
5. Verify ECR replication reports the same digest in both production regions.
6. Run `promote-production.yml` from `main` with only `version=X.Y.Z`.
7. Approve `production` only after the workflow resolves the immutable source
   digest, matches each regional digest, and verifies the nonprod attestation.
8. Promote and verify one production region at a time.

Example dispatch:

```bash
gh workflow run promote-production.yml \
  --ref main \
  -f version=1.2.3
```

For a reviewed break-glass manual deployment, supply an immutable digest:

```bash
nix run .#deploy -- \
  OVERLAY \
  CLUSTER_NAME \
  AWS_REGION \
  ECR_REPOSITORY_URI \
  sha256:DIGEST
```

## Failure handling and rollback

### Plan or apply failure

- Stop the stage and do not continue to dependent units.
- Record account, region, unit, commit, command, and error.
- Check AWS identity and backend state before retrying.
- Run and review a fresh plan. Do not use destroy/recreate as generic recovery.
- If a resource exists outside state, review whether to import it or change the
  configuration. Do not delete it blindly.

### EKS succeeds but add-ons fail

- Leave the cluster and state intact.
- Check private DNS, routing, TCP/443 cluster security-group admission, role
  chaining, kubeconfig, Helm source egress, nodes, and managed add-ons.
- Fix the owning Terraform configuration and re-plan only the failed add-on
  unit.

### Workload release failure

- Freeze promotion and preserve workflow, Kubernetes, and AWS logs.
- Re-run an existing release-event workflow only when the failure was
  infrastructural and the immutable release is unchanged.
- Roll production back by promoting the last known-good released version. Never
  substitute an unrelated digest.
- If manifests caused the incident, revert the manifest commit and use the
  manual deployment path with the known-good digest.

### Teardown

Teardown is a separate, reviewed operation. Remove workloads and load balancers
first, followed by add-ons, EKS, networks, and shared ECR. State storage has
intentional deletion protection and requires a dedicated retirement procedure.

## Evidence to retain

Attach these artifacts to the deployment record:

- approved commit and working-tree status;
- Nix, Terraform, Terragrunt, AWS CLI, kubectl, and Helm versions;
- local validation output;
- AWS caller identities with account IDs, excluding credentials;
- reviewed plans and approvals for every unit;
- state outputs and secured local workspace location;
- GitHub OIDC role ARNs and exact trusted subjects;
- EKS versions, endpoint settings, access entries, and add-on versions/status;
- Kubernetes node, storage, controller, monitoring, and rollout evidence;
- ECR source/replica digest equality;
- GitHub environment approval and nonprod attestation evidence;
- observed cost, capacity, and deviations from this runbook.

## References

- [Live Terragrunt apply order](../infra/live/README.md)
- [State bootstrap](../infra/bootstrap/README.md)
- [Release and promotion details](deployment.md)
- [Operations checks and incident outline](operations.md)
- [Architecture](architecture.md)
- [AWS CLI IAM Identity Center authentication](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [Amazon EKS private API endpoints](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html)
- [Amazon EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [Amazon EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [Amazon EKS Kubernetes version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [GitHub Actions OIDC reference](https://docs.github.com/en/actions/reference/security/oidc)

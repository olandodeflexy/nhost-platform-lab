# Deployment

For first-time AWS and EKS provisioning, follow the ordered
[EKS deployment runbook](eks-deployment-runbook.md). This document covers the
release and promotion path after the cluster prerequisites are installed.

## Delivery architecture

GitHub-hosted runners build and publish the image, verify promotion evidence,
and create the public non-production attestation. They never connect to the
private EKS endpoints. Each deployment is performed by an ordinary on-demand
AWS CodeBuild project attached to the matching VPC:

1. A thin event workflow calls a trusted reusable delivery workflow from
   `refs/heads/main`; only jobs defined by that reusable workflow can obtain the
   short-lived AWS identity through OIDC.
2. The starter role may start, poll, and stop only the fixed regional project.
3. CodeBuild fetches the exact release tag, proves that it resolves to the
   requested commit, and resolves the immutable version tag in regional ECR.
4. A Terraform-owned `NO_SOURCE` buildspec renders only the fixed Kustomize
   overlay, checks an exact seven-resource allowlist, deploys the digest, and
   waits for rollout.
5. GitHub accepts success only when CodeBuild exports the same tag, commit, and
   digest that were requested.

No self-hosted GitHub runner is used or supported. The CodeBuild project has no
GitHub webhook, source credential, artifact store, cache, privileged mode, or
public build access. Its executor image, kubectl, and Kustomize are pinned by
SHA-256.

## Required GitHub configuration

Create case-sensitive GitHub Environments:

- `release`, restricted to protected tags matching `demo-api@*`;
- `nonprod`, restricted to protected tags matching `demo-api@*`;
- `production`, restricted to the protected default branch and requiring a
  reviewer.

Protect the default branch and add a tag ruleset that prevents force-updating
or deleting `demo-api@*`. Artifact attestations work for public repositories on
current GitHub plans. Private/internal repositories require GitHub Enterprise
Cloud; set `PRIVATE_ATTESTATIONS_SUPPORTED=true` only after confirming that
capability. Public repositories leave that variable unset.

Store account IDs as protected Environment secrets. They are identifiers, not
credentials, but this makes GitHub mask them in logs.

| Environment | Account-ID secrets |
| --- | --- |
| `release` | `AWS_CORE_ACCOUNT_ID` |
| `nonprod` | `AWS_CORE_ACCOUNT_ID`, `AWS_NONPROD_ACCOUNT_ID` |
| `production` | `AWS_CORE_ACCOUNT_ID`, `AWS_PROD_ACCOUNT_ID` |

Set these non-sensitive repository variables:

| Variable | Value |
| --- | --- |
| `DELIVERY_EXECUTOR` | `codebuild` only after all executor prerequisites pass |
| `ECR_REGION` | `eu-central-1` |
| `ECR_REPOSITORY` | `demo-api` |
| `NONPROD_CODEBUILD_PROJECT` | `nhost-lab-nonprod-eu-west-1-demo-api-deploy` |
| `PROD_EU_CODEBUILD_PROJECT` | `nhost-lab-prod-eu-west-1-demo-api-deploy` |
| `PROD_US_CODEBUILD_PROJECT` | `nhost-lab-prod-us-east-1-demo-api-deploy` |
| `RELEASE_BOT_CLIENT_ID` | GitHub App Client ID |
| `PRIVATE_ATTESTATIONS_SUPPORTED` | `true` only for verified private Enterprise use |

Install the release GitHub App with only the permissions needed to create tags
and releases. Store its Client ID in `RELEASE_BOT_CLIENT_ID` and its PEM private
key in the Actions secret `RELEASE_BOT_PRIVATE_KEY`. Do not store AWS access
keys in GitHub.

The immutable public repository identity is committed in
`infra/live/github.hcl`. Re-check it if the repository is transferred or
recreated:

```bash
gh api repos/olandodeflexy/nhost-platform-lab \
  --jq '{owner: .owner.login, owner_id: (.owner.id | tostring), name: .name, id: (.id | tostring)}'
```

## AWS identities and authorization

The core `github-actions-nhost-platform-lab-release` role can publish only to
the application ECR repository. Every AWS role trust requires both the exact
immutable repository/environment subject and the exact reusable
`job_workflow_ref` on `refs/heads/main`. A caller or a different workflow cannot
obtain the same role merely by naming the Environment. The nonprod and production
`github-actions-nhost-platform-lab-deploy` roles are starter identities: they
have no EKS access. Their CodeBuild permission is constrained to the exact
project ARN, the three plaintext inputs `RELEASE_TAG`, `RELEASE_COMMIT`, and
`EXPECTED_DIGEST`, and no source, buildspec, image, role, compute, privileged,
artifact, cache, retry, encryption, or logging override. Explicit deny
statements protect these restrictions and deny `iam:PassRole`.

Each regional CodeBuild project has a separate service role. Its trust policy
requires both the exact project ARN and source account. It may:

- manage only the VPC network interfaces CodeBuild requires;
- write only its private seven-day CloudWatch log stream;
- describe only its EKS cluster;
- resolve the exact regional `demo-api` ECR repository;
- authenticate to Kubernetes as the custom
  `nhost-platform-lab:demo-api-deployers` group.

The group has create/get/list/watch/update/patch only for Deployments, Services,
Ingresses, NetworkPolicies, HPAs, PDBs, and `VMServiceScrape` in `demo-api`.
It cannot manage Secrets, ConfigMaps, ServiceAccounts, RBAC, pod exec/attach,
other namespaces, or cluster-scoped resources. The administrator-owned
platform prerequisites create the namespace, ServiceAccount, Role, and
RoleBinding before application delivery.

AWS does not expose IAM condition keys for every `StartBuild` field, including
some timeout and debug-session overrides. The fixed buildspec bounds network
and Kubernetes commands, the service role has no SSM permissions, automatic
retry is disabled, and concurrency is one. A validating API/Lambda dispatcher
would be required if policy demands rejection of every unsupported API field.

## Provisioning order

Use this order so that every regional pull/deployment identity exists and can be
verified before delivery is enabled:

1. Bootstrap state and create human `platform-admin` roles.
2. Apply each network and EKS root.
3. Apply the GitHub OIDC starter roles.
4. Apply all three `codebuild-deployer` roots so their service roles exist.
5. Apply the core registry root, including regional replication and exact
   cross-account reader policies.
6. From a separately authorized VPC-connected administrator path, apply each
   `platform-addons` root. The application CodeBuild role cannot do this.
7. Validate CodeBuild, regional ECR, namespace/RBAC, and rollout behavior; then
   set `DELIVERY_EXECUTOR=codebuild`.

The first core registry apply may create
`AWSServiceRoleForECRReplication`. Pre-create it or grant the infrastructure
identity one-time `iam:CreateServiceLinkedRole` permission constrained to
`replication.ecr.amazonaws.com`.

## Release and promotion

1. Merge changes only after `ci.yml` succeeds.
2. Merge a PR titled `release(demo-api): X.Y.Z`.
3. The GitHub App creates immutable tag and release `demo-api@X.Y.Z`.
4. `demo-api-release.yml` calls the trusted
   `demo-api-release-delivery.yml@main` workflow. The reusable workflow validates
   the published release and builds/tests the image in a job with no OIDC
   permission, AWS credentials, or release environment. It transfers the raw
   image archive by immutable GitHub artifact ID and digest to a fresh publisher
   job. That job checks out publisher tooling from `job.workflow_sha`, verifies
   the archive digest and release-commit labels before requesting AWS
   credentials, publishes to source ECR, invokes nonprod CodeBuild, verifies the
   returned coordinates, and then creates the nonprod deployment attestation.
5. Run `promote-production.yml` from `main` with only `version=X.Y.Z`.
6. The thin dispatcher calls `demo-api-production-delivery.yml@main`. After
   production approval, each trusted GitHub-hosted matrix job resolves and
   verifies the signer-bound nonprod attestation and regional replica, then
   invokes its fixed CodeBuild project one region at a time.

The production workflow never accepts an independently supplied digest. It
derives the digest from the immutable ECR version tag, verifies the exact
release-workflow certificate identity, source ref, source commit, custom
predicate, and GitHub-hosted provenance, and passes that value as an assertion
to CodeBuild. CodeBuild independently resolves the same regional version tag
before deployment.

The attestation subject is the fully qualified source ECR image, so a public
attestation exposes the core ECR account ID as non-secret metadata. Its custom
predicate uses the account-free CodeBuild project name and build ID, not a build
ARN, so it does not additionally expose the nonprod account ID. If policy treats
AWS account IDs as confidential, redesign the provenance subject before enabling
delivery.

## Cost and bootstrap boundary

Idle on-demand CodeBuild projects and IAM roles do not incur compute-hour
charges. A deployment is billed only for its build minutes, plus small
CloudWatch Logs storage/ingestion. The VPC NAT gateways, EKS control planes,
nodes, load balancers, and observability stack remain the material recurring
costs.

This workload executor deliberately cannot bootstrap `platform-addons`, whose
Terraform Helm/Kubernetes providers need private API access and cluster-admin.
Use a VPN/VPC-connected operator or a separate, manually invoked infrastructure
executor. Never broaden the application CodeBuild role to cluster admin.

## Manual deployment and rollback

The local Nix command remains available to an already authorized operator with
private cluster connectivity:

```bash
nix run .#deploy -- \
  nonprod-eu-west-1 \
  nhost-lab-nonprod-eu-west-1 \
  eu-west-1 \
  "${NHOST_CORE_ACCOUNT_ID}.dkr.ecr.eu-west-1.amazonaws.com/demo-api" \
  sha256:DIGEST
```

For rollback, promote the last known-good released version through the same
attestation-backed path. Do not pair an old version with an unrelated digest.

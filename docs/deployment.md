# Deployment

For first-time AWS and EKS provisioning, follow the ordered
[EKS deployment runbook](eks-deployment-runbook.md). This document focuses on
release and promotion after the platform is available.

## Required GitHub configuration

Create GitHub Environments named `release`, `nonprod`, and `production`. Restrict
`release` and `nonprod` to protected tags matching `demo-api@*`; restrict
`production` to the protected default branch and require reviewers. Add a tag
ruleset that prevents force-updating or deleting `demo-api@*` tags, while allowing
the release GitHub App to create them. These environment rules are part of the
OIDC boundary, not optional workflow hygiene. Artifact attestations must be
enabled. They are available for public repositories on current GitHub plans;
private or internal repositories require GitHub Enterprise Cloud.

The EKS API endpoints are private. Register ephemeral or tightly managed
self-hosted runners with network access to each cluster and these labels:

- `self-hosted`, `linux`, `nonprod` for the non-production VPC;
- `self-hosted`, `linux`, `prod-eu-west-1` for the EU production VPC;
- `self-hosted`, `linux`, `prod-us-east-1` for the US production VPC.

Do not place a long-lived AWS key on those runners. The jobs still obtain their
AWS identity through GitHub OIDC.

Store account IDs as protected GitHub Environment secrets. AWS account IDs are
identifiers rather than credentials, but using environment secrets makes log
masking automatic and keeps them out of ordinary repository configuration.

| Environment | Required account-ID secrets |
| --- | --- |
| `release` | `AWS_CORE_ACCOUNT_ID` |
| `nonprod` | `AWS_CORE_ACCOUNT_ID`, `AWS_NONPROD_ACCOUNT_ID` |
| `production` | `AWS_CORE_ACCOUNT_ID`, `AWS_PROD_ACCOUNT_ID` |

Configure these non-sensitive repository variables:

| Variable | Example |
| --- | --- |
| `ECR_REGION` | `eu-central-1` |
| `ECR_REPOSITORY` | `demo-api` |
| `NONPROD_CLUSTER_NAME` | `nhost-lab-nonprod-eu-west-1` |
| `PROD_EU_CLUSTER_NAME` | `nhost-lab-prod-eu-west-1` |
| `PROD_US_CLUSTER_NAME` | `nhost-lab-prod-us-east-1` |

Install a GitHub App on the repository with permission to create releases. Store
its credentials as `RELEASE_BOT_APP_ID` and `RELEASE_BOT_PRIVATE_KEY`. The App
token is intentional: a release created with the workflow's default token does
not trigger the downstream release workflow.

Set the immutable repository identity in `infra/live/github.hcl` before applying
the OIDC roles. The IDs are public GitHub identifiers, not secrets, and should be
committed with the repository configuration. Retrieve all four values after the
repository exists:

```bash
gh api repos/olandodeflexy/nhost-platform-lab \
  --jq '{owner: .owner.login, owner_id: (.owner.id | tostring), name: .name, id: (.id | tostring)}'
```

The module constructs exact subjects such as
`repo:olandodeflexy@42207883/nhost-platform-lab@1352263838:environment:release`.
Name-only subjects and wildcards are rejected. Repositories created before July
15, 2026 must opt in to GitHub immutable OIDC subjects or these policies will not
match their tokens.

Create the referenced `platform-admin` roles before applying EKS. The cluster
creator receives no implicit administrator entry. Each `platform-addons` root
requests its Kubernetes token through `platform-admin`, so authorize the
Terragrunt infrastructure identity to assume that role for the add-on apply.

GitHub deployment roles receive `AmazonEKSEditPolicy` only in `demo-api`; they
are not cluster administrators and cannot create namespaces. The
`cluster-prerequisites` release creates the namespace and its narrowly scoped
VictoriaMetrics RBAC before application deployment begins.

Create these OIDC roles with trust restricted to this repository:

- `github-actions-nhost-platform-lab-release` in `core`, with ECR push access;
- `github-actions-nhost-platform-lab-deploy` in `nonprod`, with access to only
  the non-production cluster;
- `github-actions-nhost-platform-lab-deploy` in `prod`, with access to only the
  two production clusters and read-only access to the source and regional ECR
  repositories used to verify promotions.

The ECR repository policy grants pull access to the non-production and production
accounts. Worker-node roles still need the ECR read policies, which the EKS
module attaches.

The roles are implemented by `infra/modules/github-oidc-role`. Create the deploy
roles before EKS because the cluster configuration grants them access by ARN.

## Release

1. Merge ordinary changes only after `ci.yml` succeeds.
2. Open a final pull request titled `release(demo-api): 1.2.3`.
3. Merging that pull request creates tag and release `demo-api@1.2.3`.
4. `demo-api-release.yml` runs Nix checks, builds the image once, pushes it to
   ECR, resolves its digest, and automatically deploys the non-production overlay.
5. After the non-production rollout succeeds, the workflow signs a custom
   Sigstore-backed GitHub attestation binding the version, exact release commit,
   and digest to that successful deployment.
6. Run `promote-production.yml` with only the released version. GitHub pauses at
   the protected `production` environment before applying both regional overlays.

The production workflow does not accept a caller-provided digest. For each
production region it resolves the digest from the immutable source ECR version
tag, requires the regional replica to have the same digest, and verifies the
signed non-production deployment attestation from `demo-api-release.yml` before
deploying the regional repository URL. It resolves the published release tag
once, checks out that immutable commit in every production job, and requires the
attestation to name the same commit, so a moved Git tag cannot change production
manifests or promotion code. Verification also pins the attestation certificate
to the exact release workflow identity, release tag ref, and release commit. The
release workflow intentionally has no manual-dispatch path; re-run its existing
release-event workflow run if infrastructure failure requires a retry.

Account-ID masking protects workflow logs, but the successful non-production
attestation intentionally names the fully qualified ECR image. Because this is a
public repository, that signed attestation is public and its subject includes the
ECR registry account ID. AWS account IDs are not authentication credentials. If
the registry identity must nevertheless remain confidential, use a private
attestation/repository design instead of this public provenance workflow.

The core registry root pre-creates immutable `demo-api` repositories in
`eu-west-1` and `us-east-1`, applies the same pull and lifecycle policies, and
configures replication from `eu-central-1`. Apply that root before publishing the
first release. ECR replicates only images pushed after replication is enabled;
copy any existing release images to both regional repositories once before
promoting them. The first replication apply also creates the AWS-managed
`AWSServiceRoleForECRReplication`; either pre-create it as an account bootstrap
step or grant `terraform-deploy` a condition-scoped
`iam:CreateServiceLinkedRole` permission only for
`replication.ecr.amazonaws.com`.

## Manual deployment

After assuming the correct AWS role, the same deployment can be run locally with
Nix:

```bash
nix run .#deploy -- \
  nonprod-eu-west-1 \
  nhost-lab-nonprod-eu-west-1 \
  eu-west-1 \
  "${NHOST_CORE_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com/demo-api" \
  sha256:0123456789abcdef
```

The command copies the selected overlay into a temporary directory, sets the
image by digest, renders it, applies it server-side, and waits for the deployment
rollout.

## Rollback

Re-run the production promotion with the last known-good released version.
Kubernetes rolls back to its verified immutable regional digest while retaining
the current manifest configuration. If the manifest itself caused the failure,
revert that commit and deploy the same known-good digest from the reverted
revision through the manual procedure.

# Nhost-inspired AWS platform lab

This repository is a production-shaped learning project based on Nhost's public
engineering material. It creates a multi-account, multi-region AWS platform with
Terraform and Terragrunt, runs a small Go service on EKS, and uses Nix-driven
GitHub Actions to publish to ECR and deploy Kustomize overlays to EKS.

It is an independent reference implementation. It is not Nhost source code and
does not claim to reproduce private Nhost infrastructure exactly.

## What is included

- `infra/bootstrap`: encrypted S3 state and DynamoDB locking per AWS account.
- `infra/modules`: VPC, ECR, EKS/Karpenter, CodeBuild deployment, and cluster
  add-on modules.
- `infra/live`: Terragrunt account and region hierarchy for core, non-production,
  and production accounts.
- `services/demo-api`: a dependency-free Go HTTP service with health, readiness,
  metrics, graceful shutdown, and tests.
- `deploy/kustomize`: reusable Kubernetes base plus non-production and two
  production overlays.
- `flake.nix`: reproducible service, image, manifest checks, publish, and deploy
  packages.
- `.github/workflows`: pull-request and infrastructure checks, release creation,
  ECR publication, non-production deployment, and production promotion.

## Deployment shape

```mermaid
flowchart LR
  PR[Pull request] --> CI[Nix flake checks]
  CI --> REL[release(demo-api): x.y.z PR]
  REL --> TAG[GitHub release]
  TAG --> BUILD[Nix OCI image build]
  BUILD --> ECR[Core ECR source]
  ECR --> ECR_EU[ECR eu-west-1 replica]
  ECR --> ECR_US[ECR us-east-1 replica]
  ECR_EU --> NPBUILD[nonprod VPC CodeBuild]
  NPBUILD --> DEV[private nonprod EKS]
  DEV --> ATTEST[Signed nonprod attestation]
  ATTEST --> APPROVE[GitHub production approval]
  APPROVE --> EUBUILD[EU VPC CodeBuild]
  APPROVE --> USBUILD[US VPC CodeBuild]
  ECR_EU --> EUBUILD
  ECR_US --> USBUILD
  EUBUILD --> EU[prod eu-west-1 EKS]
  USBUILD --> US[prod us-east-1 EKS]
```

Nix builds the binary and OCI archive. Trusted reusable workflows on protected
`main` orchestrate from GitHub-hosted Actions with short-lived, workflow-bound
AWS OIDC identities; fixed, VPC-attached CodeBuild projects perform
private-cluster deployment. Kustomize owns the environment-specific Kubernetes
configuration.

## Start locally

The service requires only Go:

```bash
make test
make build
./services/demo-api/bin/demo-api
curl http://localhost:3000/healthz
```

With Nix installed, run the same path used in CI:

```bash
nix flake check
# Linux runner, or macOS with a configured Linux remote builder:
nix build .#demo-api-image
```

Enable the repository's local pre-commit and pre-push publication guard once per
clone, then run the complete local check before committing:

```bash
git config core.hooksPath .githooks
make check
```

The guard scans only files Git can add, reports filenames rather than matched
content, and rejects state, plans, private operational records, credential/key
signatures, personal paths, and literal 12-digit identifiers.

## Provision AWS

Provisioning is deliberately opt-in because three EKS clusters, NAT gateways,
and observability components incur meaningful cost.

1. Create the `core`, `nonprod`, and `prod` AWS accounts and deployment roles
   through an organization-approved private bootstrap process.
2. Bootstrap only the Terraform remote state in each account using
   [`infra/bootstrap/README.md`](infra/bootstrap/README.md).
3. Export `NHOST_CORE_ACCOUNT_ID`, `NHOST_NONPROD_ACCOUNT_ID`, and
   `NHOST_PROD_ACCOUNT_ID`; the live configuration derives state bucket names
   and role ARNs from them. Verify the public GitHub identifiers, then configure
   all `example.com` domains, `REPLACE_ME` hosted zones, contact addresses, and
   other environment-specific values before planning.
4. Enter the pinned Nix shell and run the local validation gate:

```bash
nix develop --no-update-lock-file
nix flake check --no-update-lock-file
make infra-fmt
make infra-validate
```

5. Follow [`docs/eks-deployment-runbook.md`](docs/eks-deployment-runbook.md) for
   the complete staged deployment. Use [`docs/deployment.md`](docs/deployment.md)
   for the release and promotion behavior after the platform is available.

Do not run `terragrunt run --all apply` across the repository without reviewing
the account, region, plan, and expected monthly cost.

## Design documentation

- [`docs/architecture.md`](docs/architecture.md): platform boundaries and request flow.
- [`docs/eks-deployment-runbook.md`](docs/eks-deployment-runbook.md): ordered AWS,
  EKS, add-on, verification, and delivery procedure.
- [`docs/deployment.md`](docs/deployment.md): release and promotion procedure.
- [`docs/operations.md`](docs/operations.md): health, rollback, scaling, and incidents.

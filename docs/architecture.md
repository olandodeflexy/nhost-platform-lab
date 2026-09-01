# Architecture

## Goals

The lab demonstrates the platform concerns described for Nhost's infrastructure
role without pretending that private implementation details are known:

- isolated AWS accounts and region-local failure domains;
- reusable Terraform modules composed by Terragrunt;
- EKS with Cilium policy enforcement and Karpenter workload capacity;
- ingress, DNS, certificates, metrics, dashboards, and alerts;
- reproducible Go and OCI builds with Nix;
- short-lived GitHub Actions credentials through AWS OIDC;
- fixed, VPC-attached CodeBuild executors for private EKS delivery;
- immutable image-digest promotion with Kustomize.

## AWS topology

| Account | Region | Purpose |
| --- | --- | --- |
| `core` | `eu-central-1` | Source immutable ECR artifacts |
| `core` | `eu-west-1` | Regional ECR replica for EU production |
| `core` | `us-east-1` | Regional ECR replica for US production |
| `nonprod` | `eu-west-1` | Integration cluster and automatic release deployment |
| `prod` | `eu-west-1` | Primary production cluster |
| `prod` | `us-east-1` | Second production region and regional failure boundary |

Each cluster receives a dedicated VPC across three availability zones. Public
subnets host internet-facing load balancers; private subnets host worker nodes;
intra subnets are reserved for data services. The lab deploys one small managed
node group for critical controllers and uses Karpenter NodePools for application
capacity.

Production overlays are separate even when their desired state is currently the
same. This keeps regional rollout and rollback independent.

## Cluster layers

1. **AWS-managed base:** EKS control plane, VPC CNI, CoreDNS, kube-proxy, and a
   small managed node group.
2. **Platform add-ons:** Cilium in AWS VPC CNI chaining mode, Karpenter,
   ingress-nginx, external-dns, cert-manager, and VictoriaMetrics/Grafana.
3. **Workloads:** Kustomize bases and overlays deployed by the release pipeline.

Cilium chaining is a conservative lab choice: AWS VPC CNI retains ENI/IPAM
responsibility while Cilium adds eBPF policy and observability. A full Cilium CNI
replacement should be treated as a separate migration with explicit bootstrap,
IPAM, and rollback design.

## Build and release flow

Nix is the build interface, not merely a developer shell:

- `.#demo-api` builds and tests the Go binary;
- `.#demo-api-image` creates the OCI/docker archive;
- `.#manifest-check` renders and validates every Kustomize overlay;
- `.#publish-image` authenticates to ECR and copies the archive;
- `.#verify-promotion` resolves regional ECR tags and verifies the signed
  non-production deployment claim;
- `.#deploy` is the equivalent local operator command for an already connected,
  authorized administrator.

GitHub-hosted Actions invokes the build, publish, and verification packages and
controls environment approvals. Release-controlled source is built and tested
without OIDC, AWS credentials, or environment secrets. The resulting raw image
archive crosses into a fresh publisher job by immutable artifact ID and digest;
that job executes only publisher tooling checked out from the trusted reusable
workflow SHA and verifies the archive digest and release-commit labels before
requesting AWS credentials. AWS accepts OIDC only from exact reusable delivery
workflows on `refs/heads/main`, in addition to checking the immutable
repository/environment subject. Those jobs may only publish to ECR or start and
poll exact CodeBuild projects; they have no EKS access. Each CodeBuild project
uses a Terraform-owned `NO_SOURCE` buildspec and
custom Kubernetes RBAC to render and apply one fixed overlay through the private
endpoint. A signed deployment attestation records the exact release commit,
digest, and executor build that passed non-production. Promotion verifies that
attestation and each regional replica before starting the corresponding fixed
production executor. Production is never rebuilt from source.

## Repository boundaries

The project uses one repository because it is a compact learning artifact. The
directory boundaries permit a future split:

- application teams own `services/` and workload Kustomize bases;
- platform engineering owns `infra/`, cluster add-ons, and deployment tooling;
- environment owners approve changes under `infra/live` and production overlays.

At larger scale, live account configuration and production deployment state
would normally move to a more restricted repository.

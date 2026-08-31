# Operations

## Workload signals

The demo service exposes:

- `/healthz`: process liveness, expected to return within five seconds;
- `/readyz`: readiness, disabled before shutdown starts;
- `/metrics`: Prometheus text metrics for total requests and process readiness;
- `/`: build version, commit, build time, and region metadata.

Kubernetes uses separate liveness and readiness probes, a disruption budget,
topology spread constraints, CPU autoscaling, resource requests and limits, and
a default-deny network policy with explicit ingress paths.

## Routine checks

```bash
kubectl -n demo-api get deploy,pod,svc,hpa,pdb
kubectl -n demo-api rollout status deployment/demo-api
kubectl -n demo-api logs deployment/demo-api --tail=100
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter
kubectl -n kube-system get pods -l k8s-app=cilium
```

Before an EKS or add-on upgrade, apply it to non-production, exercise a node
replacement, inspect Cilium connectivity, create an unschedulable test workload
for Karpenter, and verify dashboards and alerts. Promote one production region
at a time.

## Incident outline

1. Establish user impact and affected account, region, cluster, and release.
2. Freeze production promotion and preserve logs and events.
3. Roll back the workload digest when the incident correlates with a release.
4. Check control plane health, node readiness, Cilium, DNS, ingress, certificates,
   and Karpenter in that order.
5. Shift traffic only through a separately tested DNS or edge runbook; this lab
   does not automate multi-region failover.
6. Record timeline, contributing conditions, and a systemic follow-up change.

## Secrets

The repository intentionally contains no application secrets. A real workload
should retrieve secrets from AWS Secrets Manager through External Secrets or a
comparable operator using EKS Pod Identity. Do not put secret values in
Kustomize files, Terraform variables, GitHub variables, or state outputs.

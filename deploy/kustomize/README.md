# Kustomize deployment

`base/` contains environment-independent workload policy. Each overlay sets only
the differences that should be reviewed independently: image location, runtime
environment, region, host name, capacity, and production disruption tolerance.

The tracked image tag is a renderable placeholder. Release deployment copies an
overlay into a temporary directory and runs:

```bash
kustomize edit set image demo-api=<ecr-uri>@<sha256-digest>
kustomize build . | kubectl apply --server-side -f -
```

No mutable production image reference is committed or deployed. The tracked
`example.invalid` image is a fail-safe sentinel that the deployment command
replaces with an immutable ECR URI and digest. Replace the example DNS names
before provisioning the platform.

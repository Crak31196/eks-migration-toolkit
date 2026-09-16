# Fixtures (demo data)

These manifests are **synthetic demo data**, not a real client's
configuration. They exist purely to exercise
`scripts/migration-readiness-check.sh` and show the range of issues it
detects.

| File | Demonstrates |
|---|---|
| `good-deployment.yaml` | A compliant Deployment (current API, resource limits set, no hostPath) -- expect no findings. |
| `bad-hostpath.yaml` | A Deployment mounting a `hostPath` volume. |
| `bad-deprecated-api.yaml` | A Deployment using the removed `extensions/v1beta1` API. |
| `bad-no-limits.yaml` | A Deployment with no container resource limits. |
| `bad-privileged-hostnetwork.yaml` | A DaemonSet running a privileged container with `hostNetwork: true`. |

Run the checker against this directory:

```bash
./scripts/migration-readiness-check.sh scripts/fixtures
```

# Screenshots

Pending a real deployment. Once this toolkit has been applied against a
live AWS account, this folder will hold:

- `terraform-plan.png` -- a `terraform plan` run against `terraform/environments/dev`
- `eks-cluster-console.png` -- the resulting cluster in the AWS EKS console
- `kubectl-get-nodes.png` -- the managed node group visible via `kubectl get nodes`
- `helm-deployed-workload.png` -- `helm list` / `kubectl get pods,hpa` for `sample-workload`

Until then, see [`docs/architecture.md`](../architecture.md) for the
target architecture diagram, and the "Running tests" section of the
[README](../../README.md) for how to verify this repo's Terraform, Helm,
and shell tooling locally without any AWS credentials.

#!/usr/bin/env bash
#
# helm/tests/validate.sh
#
# Chart validation pipeline for helm/sample-workload:
#   1. `helm lint`      - chart structure / best-practice checks
#   2. `helm template`  - render manifests with default values
#   3. `kubeconform`    - validate the rendered manifests against upstream
#                         Kubernetes JSON schemas
#   4. `helm unittest`  - real unit tests (helm/sample-workload/tests/*_test.yaml),
#                         run only if the helm-unittest plugin is installed.
#                         Install it with:
#                           helm plugin install https://github.com/helm-unittest/helm-unittest
#                         This step is skipped (not failed) when the plugin
#                         isn't available, e.g. in an offline environment,
#                         so steps 1-3 remain the baseline CI gate.
#
# Usage: ./helm/tests/validate.sh [chart-dir] [k8s-version]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${1:-${SCRIPT_DIR}/../sample-workload}"
K8S_VERSION="${2:-1.30.0}"

echo "==> Validating chart: ${CHART_DIR} (Kubernetes v${K8S_VERSION})"

echo
echo "--- [1/4] helm lint ---"
helm lint "${CHART_DIR}" --strict

echo
echo "--- [2/4] helm template ---"
RENDERED="$(mktemp)"
trap 'rm -f "${RENDERED}"' EXIT
helm template ci-test "${CHART_DIR}" > "${RENDERED}"
echo "Rendered $(grep -c '^kind:' "${RENDERED}") manifest(s)."

echo
echo "--- [3/4] kubeconform ---"
kubeconform -strict -summary -kubernetes-version "${K8S_VERSION}" < "${RENDERED}"

echo
echo "--- [4/4] helm unittest ---"
if helm plugin list 2>/dev/null | grep -q '^unittest'; then
  helm unittest "${CHART_DIR}"
else
  echo "helm-unittest plugin not installed - skipping unit tests." >&2
  echo "Install with: helm plugin install https://github.com/helm-unittest/helm-unittest" >&2
fi

echo
echo "All chart validation checks passed."

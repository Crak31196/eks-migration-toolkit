#!/usr/bin/env bash
#
# migration-readiness-check.sh
#
# Audits a directory of plain Kubernetes YAML manifests for patterns that
# are incompatible with, or risky on, a managed AWS EKS cluster with
# default settings, e.g. after moving off a self-managed EC2 Kubernetes
# cluster. This is a heuristic, text-level scanner (no full YAML schema
# validation) intended as a fast first pass before a real migration --
# always follow up with `kubectl apply --dry-run=server` and admission
# controllers such as Kyverno/OPA for authoritative checks.
#
# Checks performed per manifest document:
#   - hostPath volumes            (node-coupled storage; breaks on EKS
#                                   managed/replaceable nodes and node
#                                   group rotations)
#   - missing resource limits     (pods with no CPU/memory limits can
#                                   starve neighbors and defeat the
#                                   Kubernetes/Cluster Autoscaler sizing
#                                   model)
#   - deprecated/removed API      (apiVersions removed by the Kubernetes
#     versions                     versions EKS currently supports, e.g.
#                                   extensions/v1beta1, batch/v1beta1)
#   - privileged containers       (securityContext.privileged: true --
#                                   flagged for CKS-style least-privilege
#                                   review before migrating)
#   - hostNetwork usage           (bypasses the VPC CNI's pod networking
#                                   model; rarely needed on EKS)
#
# Usage:
#   ./scripts/migration-readiness-check.sh [manifest-dir]
#
# Configuration (env vars, or set in a .env file -- see .env.example):
#   MANIFEST_DIR   Directory of manifests to scan (default: ./scripts/fixtures,
#                  overridden by the positional argument if given).
#   STRICT_MODE    "true" to exit non-zero when any issue is found
#                  (useful in CI); "false" (default) always exits 0 so the
#                  report can be reviewed without failing a pipeline.
#
# Exit codes:
#   0  scan completed (and, unless STRICT_MODE=true, regardless of findings)
#   1  STRICT_MODE=true and at least one issue was found
#   2  usage error (bad/missing manifest directory)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env from the repo root if present, without overriding variables
# already set in the calling shell's environment.
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

MANIFEST_DIR="${1:-${MANIFEST_DIR:-${SCRIPT_DIR}/fixtures}}"
STRICT_MODE="${STRICT_MODE:-false}"

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# apiVersions that are deprecated or fully removed as of the Kubernetes
# minor versions EKS currently supports (1.25+). Not exhaustive -- extend
# as new API removals land.
DEPRECATED_APIS=(
  "extensions/v1beta1"
  "apps/v1beta1"
  "apps/v1beta2"
  "batch/v1beta1"
  "policy/v1beta1"
  "networking.k8s.io/v1beta1"
  "rbac.authorization.k8s.io/v1beta1"
  "scheduling.k8s.io/v1beta1"
  "storage.k8s.io/v1beta1"
  "admissionregistration.k8s.io/v1beta1"
  "certificates.k8s.io/v1beta1"
  "coordination.k8s.io/v1beta1"
)

# Kinds for which "no resource limits" is worth flagging -- i.e. anything
# that ultimately schedules a pod template.
WORKLOAD_KINDS=(
  "Pod"
  "Deployment"
  "StatefulSet"
  "DaemonSet"
  "Job"
  "CronJob"
  "ReplicaSet"
)

total_files=0
total_docs=0
total_issues=0

TMP_ROOT=""
cleanup() {
  if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
    rm -rf "${TMP_ROOT}"
  fi
  return 0
}
trap cleanup EXIT

contains() {
  # contains <needle> <haystack items...>
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

# Splits a (possibly multi-document) YAML file into separate files inside
# the given directory, named doc0000.yaml, doc0001.yaml, etc.
split_documents() {
  local src_file="$1"
  local out_dir="$2"
  awk -v out="${out_dir}/doc" '
    BEGIN { n = 0 }
    /^---[[:space:]]*$/ { n++; next }
    { printf "%s\n", $0 > sprintf("%s%04d.yaml", out, n) }
  ' "${src_file}"
}

# Emits one finding line and increments the issue counter.
report_issue() {
  local severity="$1" # WARN | FAIL
  local file="$2"
  local message="$3"
  local color="${YELLOW}"
  [[ "${severity}" == "FAIL" ]] && color="${RED}"
  printf "  ${color}[%s]${RESET} %s: %s\n" "${severity}" "${file}" "${message}"
  total_issues=$((total_issues + 1))
}

check_document() {
  local doc="$1"
  local display_name="$2"

  # Skip empty/whitespace-only documents (e.g. leading "---" separators).
  if ! grep -qE '[^[:space:]]' "${doc}"; then
    return 0
  fi

  local kind api_version
  kind="$(grep -m1 -E '^kind:[[:space:]]*' "${doc}" | sed -E 's/^kind:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'"'\r')"
  api_version="$(grep -m1 -E '^apiVersion:[[:space:]]*' "${doc}" | sed -E 's/^apiVersion:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'"'\r')"

  [[ -z "${kind}" ]] && return 0

  total_docs=$((total_docs + 1))

  local label="${display_name} (kind: ${kind})"

  if [[ -n "${api_version}" ]] && contains "${api_version}" "${DEPRECATED_APIS[@]}"; then
    report_issue "FAIL" "${label}" "uses deprecated/removed apiVersion '${api_version}' -- update to a current stable API before migrating to EKS."
  fi

  if grep -qE '^\s*hostPath:\s*$' "${doc}"; then
    report_issue "FAIL" "${label}" "uses a hostPath volume -- incompatible with EKS managed/replaceable worker nodes; use EBS/EFS CSI volumes instead."
  fi

  if grep -qE '^\s*hostNetwork:\s*true\s*$' "${doc}"; then
    report_issue "WARN" "${label}" "sets hostNetwork: true -- bypasses the VPC CNI pod networking model; confirm this is intentional."
  fi

  if grep -qE '^\s*privileged:\s*true\s*$' "${doc}"; then
    report_issue "WARN" "${label}" "runs a privileged container -- review against least-privilege / CKS baseline before migrating."
  fi

  if contains "${kind}" "${WORKLOAD_KINDS[@]}"; then
    if grep -qE '^\s*containers:\s*$' "${doc}" && ! grep -qE '^\s*limits:\s*$' "${doc}"; then
      report_issue "WARN" "${label}" "no resource limits set on containers -- required for predictable bin-packing and Cluster Autoscaler sizing on EKS."
    fi
  fi
}

main() {
  if [[ ! -d "${MANIFEST_DIR}" ]]; then
    echo "Error: manifest directory '${MANIFEST_DIR}' does not exist." >&2
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [manifest-dir]" >&2
    exit 2
  fi

  echo -e "${BOLD}EKS Migration Readiness Check${RESET}"
  echo "Scanning: ${MANIFEST_DIR}"
  echo "Strict mode: ${STRICT_MODE}"
  echo

  local manifest_files=()
  while IFS= read -r -d '' f; do
    manifest_files+=("${f}")
  done < <(find "${MANIFEST_DIR}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)

  if [[ "${#manifest_files[@]}" -eq 0 ]]; then
    echo "No .yaml/.yml manifests found in ${MANIFEST_DIR}."
    exit 0
  fi

  TMP_ROOT="$(mktemp -d)"

  local file rel_name split_dir doc_file
  for file in "${manifest_files[@]}"; do
    total_files=$((total_files + 1))
    rel_name="${file#"${MANIFEST_DIR}"/}"
    echo "-> ${rel_name}"

    split_dir="${TMP_ROOT}/$(basename "${file}").$$-${total_files}"
    mkdir -p "${split_dir}"
    split_documents "${file}" "${split_dir}"

    local before_issues=${total_issues}
    while IFS= read -r -d '' doc_file; do
      check_document "${doc_file}" "${rel_name}"
    done < <(find "${split_dir}" -type f -name 'doc*.yaml' -print0 | sort -z)

    if [[ "${total_issues}" -eq "${before_issues}" ]]; then
      echo -e "  ${GREEN}[OK]${RESET} no issues found"
    fi
  done

  echo
  echo -e "${BOLD}Summary${RESET}"
  echo "  Files scanned:     ${total_files}"
  echo "  Documents scanned: ${total_docs}"
  echo "  Issues found:      ${total_issues}"

  if [[ "${total_issues}" -gt 0 ]]; then
    if [[ "${STRICT_MODE}" == "true" ]]; then
      echo -e "${RED}Failing due to STRICT_MODE=true with outstanding issues.${RESET}"
      exit 1
    fi
    echo -e "${YELLOW}Review the issues above before migrating these manifests to EKS.${RESET}"
  else
    echo -e "${GREEN}No migration-readiness issues detected.${RESET}"
  fi
}

main "$@"

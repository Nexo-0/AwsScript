#!/usr/bin/env bash

set -Eeuo pipefail

# Create a reusable KOPS lab cluster for short-lived practical sessions.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
DEFAULT_AWS_REGION="us-east-1"
DEFAULT_CLUSTER_NAME="online.k8s.local"
DEFAULT_KOPS_STATE_STORE="s3://aarush.kops.v2"
DEFAULT_ZONES="us-east-1a"
DEFAULT_CONTROL_PLANE_ZONES="us-east-1a"
DEFAULT_NODE_COUNT="1"
DEFAULT_NODE_SIZE="c7i-flex.large"
DEFAULT_CONTROL_PLANE_COUNT="1"
DEFAULT_CONTROL_PLANE_SIZE="c7i-flex.large"
DEFAULT_NETWORKING="calico"
DEFAULT_TOPOLOGY="public"
DEFAULT_VALIDATE_WAIT="25m"

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

log_info() {
  printf "%b[INFO]%b %s\n" "${BLUE}" "${NC}" "$1"
}

log_success() {
  printf "%b[SUCCESS]%b %s\n" "${GREEN}" "${NC}" "$1"
}

log_warn() {
  printf "%b[WARN]%b %s\n" "${YELLOW}" "${NC}" "$1"
}

log_error() {
  printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$1" >&2
}

on_error() {
  local exit_code=$?
  log_error "${SCRIPT_NAME} failed at line ${1} with exit code ${exit_code}."
  exit "${exit_code}"
}

trap 'on_error ${LINENO}' ERR

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "Required command not found: ${command_name}"
    exit 1
  fi
}

load_defaults() {
  export AWS_REGION="${AWS_REGION:-${DEFAULT_AWS_REGION}}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"
  export KOPS_CLUSTER_NAME="${KOPS_CLUSTER_NAME:-${DEFAULT_CLUSTER_NAME}}"
  export KOPS_STATE_STORE="${KOPS_STATE_STORE:-${DEFAULT_KOPS_STATE_STORE}}"
  export KOPS_ZONES="${KOPS_ZONES:-${DEFAULT_ZONES}}"
  export KOPS_CONTROL_PLANE_ZONES="${KOPS_CONTROL_PLANE_ZONES:-${DEFAULT_CONTROL_PLANE_ZONES}}"
  export KOPS_NODE_COUNT="${KOPS_NODE_COUNT:-${DEFAULT_NODE_COUNT}}"
  export KOPS_NODE_SIZE="${KOPS_NODE_SIZE:-${DEFAULT_NODE_SIZE}}"
  export KOPS_CONTROL_PLANE_COUNT="${KOPS_CONTROL_PLANE_COUNT:-${DEFAULT_CONTROL_PLANE_COUNT}}"
  export KOPS_CONTROL_PLANE_SIZE="${KOPS_CONTROL_PLANE_SIZE:-${DEFAULT_CONTROL_PLANE_SIZE}}"
  export KOPS_NETWORKING="${KOPS_NETWORKING:-${DEFAULT_NETWORKING}}"
  export KOPS_TOPOLOGY="${KOPS_TOPOLOGY:-${DEFAULT_TOPOLOGY}}"
  export KOPS_VALIDATE_WAIT="${KOPS_VALIDATE_WAIT:-${DEFAULT_VALIDATE_WAIT}}"
}

print_configuration() {
  log_info "Cluster configuration:"
  printf "  AWS_REGION=%s\n" "${AWS_REGION}"
  printf "  KOPS_STATE_STORE=%s\n" "${KOPS_STATE_STORE}"
  printf "  KOPS_CLUSTER_NAME=%s\n" "${KOPS_CLUSTER_NAME}"
  printf "  KOPS_ZONES=%s\n" "${KOPS_ZONES}"
  printf "  KOPS_CONTROL_PLANE_ZONES=%s\n" "${KOPS_CONTROL_PLANE_ZONES}"
  printf "  KOPS_CONTROL_PLANE_COUNT=%s\n" "${KOPS_CONTROL_PLANE_COUNT}"
  printf "  KOPS_CONTROL_PLANE_SIZE=%s\n" "${KOPS_CONTROL_PLANE_SIZE}"
  printf "  KOPS_NODE_COUNT=%s\n" "${KOPS_NODE_COUNT}"
  printf "  KOPS_NODE_SIZE=%s\n" "${KOPS_NODE_SIZE}"
  printf "  KOPS_NETWORKING=%s\n" "${KOPS_NETWORKING}"
  printf "  KOPS_TOPOLOGY=%s\n" "${KOPS_TOPOLOGY}"
}

verify_prerequisites() {
  require_command aws
  require_command kops
  require_command kubectl
  require_command ssh-keygen

  if [[ ! -f "${HOME}/.ssh/id_rsa.pub" ]]; then
    log_error "Missing SSH public key at ${HOME}/.ssh/id_rsa.pub. Run ./install-tools.sh first."
    exit 1
  fi
}

verify_aws_access() {
  log_info "Verifying AWS identity."
  aws sts get-caller-identity >/dev/null
  log_success "AWS credentials are valid."
}

verify_state_store() {
  local bucket_name
  bucket_name="${KOPS_STATE_STORE#s3://}"

  log_info "Checking KOPS state store bucket access."
  aws s3api head-bucket --bucket "${bucket_name}" >/dev/null
  log_success "KOPS state store bucket is reachable."
}

ensure_cluster_absent() {
  if kops get cluster --name "${KOPS_CLUSTER_NAME}" --state "${KOPS_STATE_STORE}" >/dev/null 2>&1; then
    log_error "Cluster ${KOPS_CLUSTER_NAME} already exists in the configured state store."
    log_error "Destroy the existing cluster first or change KOPS_CLUSTER_NAME."
    exit 1
  fi
}

verify_generated_configuration() {
  local instance_group_table
  local control_plane_groups
  local control_plane_min_total
  local control_plane_max_total
  local active_worker_groups
  local worker_min_total
  local worker_max_total

  log_info "Verifying generated KOPS instance groups."
  instance_group_table="$(kops get ig --name "${KOPS_CLUSTER_NAME}" --state "${KOPS_STATE_STORE}")"
  printf "%s\n" "${instance_group_table}"

  control_plane_groups="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && ($2 == "ControlPlane" || $2 == "Master") { count++ }
      END { print count + 0 }
    '
  )"
  control_plane_min_total="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && ($2 == "ControlPlane" || $2 == "Master") { total += $4 }
      END { print total + 0 }
    '
  )"
  control_plane_max_total="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && ($2 == "ControlPlane" || $2 == "Master") { total += $5 }
      END { print total + 0 }
    '
  )"
  active_worker_groups="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && $2 == "Node" && ($4 > 0 || $5 > 0) { count++ }
      END { print count + 0 }
    '
  )"
  worker_min_total="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && $2 == "Node" { total += $4 }
      END { print total + 0 }
    '
  )"
  worker_max_total="$(
    printf "%s\n" "${instance_group_table}" | awk '
      NR > 1 && NF > 0 && $2 == "Node" { total += $5 }
      END { print total + 0 }
    '
  )"

  if [[ "${control_plane_groups}" != "1" || "${control_plane_min_total}" != "1" || "${control_plane_max_total}" != "1" || "${active_worker_groups}" != "1" || "${worker_min_total}" != "1" || "${worker_max_total}" != "1" ]]; then
    log_error "Generated KOPS configuration does not match the expected topology."
    log_error "Expected 1 control plane at 1/1 and an effective worker capacity of 1/1 across worker instance groups."
    exit 1
  fi

  log_success "Generated KOPS configuration matches 1 control plane and 1 effective worker."
}

create_cluster_configuration() {
  log_info "Creating KOPS cluster configuration."

  kops create cluster \
    --name "${KOPS_CLUSTER_NAME}" \
    --state "${KOPS_STATE_STORE}" \
    --cloud aws \
    --zones "${KOPS_ZONES}" \
    --control-plane-zones "${KOPS_CONTROL_PLANE_ZONES}" \
    --control-plane-count "${KOPS_CONTROL_PLANE_COUNT}" \
    --control-plane-size "${KOPS_CONTROL_PLANE_SIZE}" \
    --node-count "${KOPS_NODE_COUNT}" \
    --node-size "${KOPS_NODE_SIZE}" \
    --networking "${KOPS_NETWORKING}" \
    --topology "${KOPS_TOPOLOGY}" \
    --ssh-public-key "${HOME}/.ssh/id_rsa.pub" \
    --dns private

  log_success "Cluster configuration created in the state store."
}

apply_cluster_configuration() {
  log_info "Applying cluster configuration to AWS."

  kops update cluster \
    --name "${KOPS_CLUSTER_NAME}" \
    --state "${KOPS_STATE_STORE}" \
    --yes

  kops export kubecfg \
    --name "${KOPS_CLUSTER_NAME}" \
    --state "${KOPS_STATE_STORE}" \
    --admin=18h

  log_success "Cluster resources have been requested from AWS."
}

validate_cluster() {
  log_info "Waiting for the cluster to become ready."

  kops validate cluster \
    --name "${KOPS_CLUSTER_NAME}" \
    --state "${KOPS_STATE_STORE}" \
    --wait "${KOPS_VALIDATE_WAIT}"

  log_success "Cluster validation succeeded."
}

print_cluster_status() {
  log_info "Current node status:"
  kubectl get nodes -o wide
}

main() {
  load_defaults
  print_configuration
  verify_prerequisites
  verify_aws_access
  verify_state_store
  ensure_cluster_absent
  create_cluster_configuration
  verify_generated_configuration
  apply_cluster_configuration
  validate_cluster
  print_cluster_status

  log_success "KOPS lab cluster is ready."
}

main "$@"

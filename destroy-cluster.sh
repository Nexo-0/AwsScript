#!/usr/bin/env bash

set -Eeuo pipefail

# Destroy the KOPS lab cluster without deleting the reusable S3 state store.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
DEFAULT_AWS_REGION="ap-south-1"
DEFAULT_CLUSTER_NAME="kunal.k8s.local"
DEFAULT_KOPS_STATE_STORE="s3://kunal-petare-kops-state-2026"

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
}

verify_prerequisites() {
  require_command aws
  require_command kops
}

verify_aws_access() {
  log_info "Verifying AWS identity."
  aws sts get-caller-identity >/dev/null
  log_success "AWS credentials are valid."
}

ensure_cluster_exists() {
  if ! kops get cluster --name "${KOPS_CLUSTER_NAME}" --state "${KOPS_STATE_STORE}" >/dev/null 2>&1; then
    log_warn "Cluster ${KOPS_CLUSTER_NAME} does not exist in ${KOPS_STATE_STORE}."
    log_warn "Nothing to destroy."
    exit 0
  fi
}

destroy_cluster() {
  log_info "Deleting cluster ${KOPS_CLUSTER_NAME}."

  kops delete cluster \
    --name "${KOPS_CLUSTER_NAME}" \
    --state "${KOPS_STATE_STORE}" \
    --yes

  log_success "Cluster deletion request submitted."
}

print_reuse_notice() {
  log_info "Reusable resources preserved:"
  printf "  S3 bucket: %s\n" "${KOPS_STATE_STORE}"
  printf "  IAM identity: unchanged\n"
  printf "  Local SSH key pair: unchanged\n"
}

main() {
  load_defaults
  verify_prerequisites
  verify_aws_access
  ensure_cluster_exists
  destroy_cluster
  print_reuse_notice

  log_success "KOPS lab cluster cleanup completed."
}

main "$@"

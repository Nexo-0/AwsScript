#!/usr/bin/env bash

set -Eeuo pipefail

# Configure and verify the management shell for KOPS cluster operations.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
DEFAULT_AWS_REGION="ap-south-1"
DEFAULT_CLUSTER_NAME="kabir.k8s.local"
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

  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return "${exit_code}"
  fi

  exit "${exit_code}"
}

trap 'on_error ${LINENO}' ERR

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "Required command not found: ${command_name}"
    return 1
  fi
}

export_environment() {
  export AWS_REGION="${AWS_REGION:-${DEFAULT_AWS_REGION}}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"
  export KOPS_CLUSTER_NAME="${KOPS_CLUSTER_NAME:-${DEFAULT_CLUSTER_NAME}}"
  export KOPS_STATE_STORE="${KOPS_STATE_STORE:-${DEFAULT_KOPS_STATE_STORE}}"
}

verify_aws_identity() {
  log_info "Verifying AWS caller identity."
  aws sts get-caller-identity >/dev/null
  log_success "AWS credentials are valid."
}

verify_kops() {
  log_info "Verifying kops installation."
  kops version
}

verify_kubectl() {
  log_info "Verifying kubectl installation."
  kubectl version --client
}

print_environment_summary() {
  log_info "Environment summary:"
  printf "  AWS_REGION=%s\n" "${AWS_REGION}"
  printf "  AWS_DEFAULT_REGION=%s\n" "${AWS_DEFAULT_REGION}"
  printf "  KOPS_CLUSTER_NAME=%s\n" "${KOPS_CLUSTER_NAME}"
  printf "  KOPS_STATE_STORE=%s\n" "${KOPS_STATE_STORE}"
}

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

main() {
  require_command aws
  require_command kops
  require_command kubectl

  export_environment
  print_environment_summary
  verify_aws_identity
  verify_kops
  verify_kubectl

  log_success "Environment configuration completed."
}

main "$@"

if ! is_sourced; then
  log_warn "This script was executed, not sourced."
  log_warn "To persist exported variables in your current shell, run: source ./setup.sh"
fi

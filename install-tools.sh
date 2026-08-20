#!/usr/bin/env bash

set -Eeuo pipefail

# Install kops and kubectl on Amazon Linux 2023 and generate SSH keys if needed.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
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

require_sudo_access() {
  if ! command -v sudo >/dev/null 2>&1; then
    log_error "sudo is required to install binaries into /usr/local/bin."
    exit 1
  fi
}

detect_architecture() {
  local machine_arch
  machine_arch="$(uname -m)"

  case "${machine_arch}" in
    x86_64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      log_error "Unsupported CPU architecture: ${machine_arch}"
      exit 1
      ;;
  esac
}

download_file() {
  local url="$1"
  local output_path="$2"

  curl -fsSL "${url}" -o "${output_path}"
}

install_kops() {
  local arch version binary_url temp_path
  arch="$(detect_architecture)"
  version="$(curl -fsSL https://api.github.com/repos/kubernetes/kops/releases/latest | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4)"

  if [[ -z "${version}" ]]; then
    log_error "Unable to determine the latest kops version."
    exit 1
  fi

  binary_url="https://github.com/kubernetes/kops/releases/download/${version}/kops-linux-${arch}"
  temp_path="$(mktemp)"

  log_info "Downloading kops ${version} for ${arch}."
  download_file "${binary_url}" "${temp_path}"
  chmod +x "${temp_path}"
  sudo install -m 0755 "${temp_path}" /usr/local/bin/kops
  rm -f "${temp_path}"

  log_success "kops installed successfully."
}

install_kubectl() {
  local arch version binary_url temp_path
  arch="$(detect_architecture)"
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

  if [[ -z "${version}" ]]; then
    log_error "Unable to determine the latest kubectl version."
    exit 1
  fi

  binary_url="https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
  temp_path="$(mktemp)"

  log_info "Downloading kubectl ${version} for ${arch}."
  download_file "${binary_url}" "${temp_path}"
  chmod +x "${temp_path}"
  sudo install -m 0755 "${temp_path}" /usr/local/bin/kubectl
  rm -f "${temp_path}"

  log_success "kubectl installed successfully."
}

ensure_ssh_keys() {
  local ssh_private_key ssh_public_key
  ssh_private_key="${HOME}/.ssh/id_rsa"
  ssh_public_key="${HOME}/.ssh/id_rsa.pub"

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"

  if [[ -f "${ssh_private_key}" && -f "${ssh_public_key}" ]]; then
    log_info "Existing SSH key pair found at ${ssh_private_key}."
    return
  fi

  log_info "Generating SSH key pair for KOPS access."
  ssh-keygen -t rsa -b 4096 -f "${ssh_private_key}" -N "" -C "kops-lab-management"
  chmod 600 "${ssh_private_key}"
  chmod 644 "${ssh_public_key}"
  log_success "SSH key pair generated successfully."
}

print_versions() {
  log_info "Installed tool versions:"
  kops version
  kubectl version --client
}

main() {
  log_info "Checking prerequisites."
  require_command curl
  require_command chmod
  require_command uname
  require_command mktemp
  require_command ssh-keygen
  require_sudo_access

  install_kops
  install_kubectl
  ensure_ssh_keys
  print_versions

  log_success "Tool installation completed."
}

main "$@"

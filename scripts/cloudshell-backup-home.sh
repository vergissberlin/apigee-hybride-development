#!/usr/bin/env bash
# Azure Cloud Shell (or any Linux home): create archive.zip without bundling
# google-cloud-sdk, ~/.docker, or ~/.kube. Default mode backs up only ~/apigee-hybrid.
#
# Usage:
#   ./cloudshell-backup-home.sh # apigee-hybrid only (recommended)
#   ./cloudshell-backup-home.sh full-home # entire $HOME with excludes
#
# Override: HOME_DIR=... ARCHIVE_NAME=... ./cloudshell-backup-home.sh

set -euo pipefail

HOME_DIR="${HOME_DIR:-$HOME}"
ARCHIVE_NAME="${ARCHIVE_NAME:-archive.zip}"
MODE="${1:-apigee-only}"

cd "$HOME_DIR"

case "$MODE" in
  apigee-only)
    zip -r "$ARCHIVE_NAME" apigee-hybrid
    ;;
  full-home)
    zip -r "$ARCHIVE_NAME" . \
      -x 'google-cloud-sdk/*' \
      -x '.docker/*' \
      -x '.kube/*' \
      -x "${ARCHIVE_NAME}"
    ;;
  *)
    echo "Usage: $0 [apigee-only|full-home]" >&2
    exit 1
    ;;
esac

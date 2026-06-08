#!/bin/bash
# Rebuild and reinstall the native macOS desktop app bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY=0
INSTALL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            VERIFY=1
            shift
            ;;
        *)
            INSTALL_ARGS+=("$1")
            shift
            ;;
    esac
done

echo "🔄 Updating Cotor Desktop..."
if [[ "${#INSTALL_ARGS[@]}" -gt 0 ]]; then
    "$SCRIPT_DIR/install-desktop-app.sh" "${INSTALL_ARGS[@]}"
else
    "$SCRIPT_DIR/install-desktop-app.sh"
fi

if [[ "$VERIFY" == "1" ]]; then
    "$SCRIPT_DIR/test-installed-desktop-app.sh"
fi

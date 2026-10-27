#!/bin/bash
# Installs the kdrive-open-local native messaging host for the current user.
#
# Run it from the folder you unzipped: ./install.sh
set -euo pipefail

HOST_NAME="com.sennadevos.kdrive_open_local"
EXTENSION_ID="kdrive-open-local@sennadevos.github.io"
INSTALL_DIR="$HOME/Library/Application Support/kdrive-open-local"
MANIFEST_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This installer is for macOS." >&2
    exit 1
fi

if [[ ! -f "$SOURCE_DIR/kdrive-open-local" ]]; then
    echo "kdrive-open-local is not next to this script in $SOURCE_DIR." >&2
    echo "Unzip the whole release archive and run ./install.sh from inside it." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR" "$MANIFEST_DIR"
cp "$SOURCE_DIR/kdrive-open-local" "$INSTALL_DIR/kdrive-open-local"
chmod +x "$INSTALL_DIR/kdrive-open-local"

# The binary came out of a downloaded zip, so Gatekeeper has flagged it. It is not signed by an
# Apple Developer ID, so without this it refuses to run and Firefox just sees a dead host.
xattr -d com.apple.quarantine "$INSTALL_DIR/kdrive-open-local" 2>/dev/null || true

cat > "$MANIFEST_DIR/$HOST_NAME.json" <<MANIFEST
{
  "name": "$HOST_NAME",
  "description": "Resolves kDrive links to files in the local kDrive sync",
  "path": "$INSTALL_DIR/kdrive-open-local",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
MANIFEST

echo "Installed:"
echo "  $INSTALL_DIR/kdrive-open-local"
echo "  $MANIFEST_DIR/$HOST_NAME.json"
echo
echo "Check it can see your sync (expects 'opened' or 'notSynced', not 'error'):"
echo "  '$INSTALL_DIR/kdrive-open-local' --resolve 'https://kdrive.infomaniak.com/app/drive/2133736/redirect/1'"
echo
echo "Then install the extension XPI in Firefox and restart Firefox."

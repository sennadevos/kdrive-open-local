#!/bin/bash
# Removes everything install.sh put on the machine.
set -euo pipefail

rm -rf "$HOME/Library/Application Support/kdrive-open-local"
rm -f "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.sennadevos.kdrive_open_local.json"
echo "Removed the native messaging host. Remove the extension from Firefox's add-ons page too."

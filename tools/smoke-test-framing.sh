#!/bin/bash
# Checks that the host speaks Firefox's native messaging framing: two framed requests in, two
# framed replies out, ids echoed. Run against a built binary:
#   tools/smoke-test-framing.sh host/.build/debug/kdrive-open-local
set -euo pipefail

BIN="${1:?usage: smoke-test-framing.sh <path to kdrive-open-local>}"

emit() {
    local msg="$1" n=${#1}
    printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((n & 255)) $(((n >> 8) & 255)) $(((n >> 16) & 255)) $(((n >> 24) & 255)))"
    printf '%s' "$msg"
}

output=$(
    {
        emit '{"id":7,"url":"https://kdrive.infomaniak.com/app/drive/2133736/files/42"}'
        emit '{"id":8,"url":"https://example.com/"}'
    } | "$BIN" | LC_ALL=C tr -d '\000-\037'
)

# Both replies must come back, each carrying its own id. JSON key order is not guaranteed, so
# match the pieces rather than a whole serialisation.
if [[ "$output" != *'"id":7'* || "$output" != *'"id":8'* || "$output" != *'"notALink"'* ]]; then
    echo "unexpected host output: $output" >&2
    exit 1
fi
echo "framing OK"

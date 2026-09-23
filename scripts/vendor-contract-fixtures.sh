#!/usr/bin/env bash
#
# vendor-contract-fixtures.sh — the contract document is the source of this
# repo's fixtures, not a hand copy of them.
#
# `../musaeum/docs/rest-api.md` carries one fenced block per payload, tagged
# `json payload=<name>`, and the Mac repo's own suite parses those same blocks to
# decide its shaper. This script extracts them here, so the client's decoding
# tests and the server's payload goldens read the same text — a field the
# document names and the app cannot decode, or a field the app requires and the
# document does not name, is then a failure on one side of the pair rather than a
# discovery on the phone.
#
#   scripts/vendor-contract-fixtures.sh                  # ../musaeum/docs/rest-api.md
#   MUSAEUM_DOC=/path/to/rest-api.md scripts/vendor-contract-fixtures.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${MUSAEUM_DOC:-$ROOT/../musaeum/docs/rest-api.md}"
OUT="$ROOT/Tests/Fixtures/contract"

if [ ! -f "$DOC" ]; then
    echo "no contract document at $DOC" >&2
    echo "pass it with MUSAEUM_DOC, or clone the Musaeum repo beside this one" >&2
    exit 1
fi

rm -f "$OUT"/*.json
mkdir -p "$OUT"

awk -v out="$OUT" '
    /^```json payload=/ { name = substr($0, index($0, "payload=") + 8); inside = 1; next }
    /^```[[:space:]]*$/  { inside = 0; next }
    inside               { print >> (out "/" name ".json") }
' "$DOC"

count=$(ls -1 "$OUT"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "no payload blocks found in $DOC — has the document's block format changed?" >&2
    exit 1
fi

echo "vendored $count payload(s) from $DOC"
for file in "$OUT"/*.json; do
    printf '  %-28s %s\n' "$(basename "$file")" "$(wc -c < "$file" | tr -d ' ') bytes"
done

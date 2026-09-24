#!/bin/bash
# The slice-4 campaign's runner: one test class per mutation, on the destination
# by id (never by name).
#
# `mutation-campaign.py` appends a row's own `test` value to whatever `--runner`
# it was given, so this takes one argument — the class selector — and prints the
# two things a row is read by: the executed/failed counts, and the name of every
# case that failed. Each run also appends to `slice4-runs.log`, which is the raw
# evidence behind the one-line rows in `slice4-campaign.log`.
set -o pipefail
cd "$(dirname "$0")/../../.." || exit 1
LOG="docs/evidence/slice4/slice4-runs.log"
out=$(xcodebuild -project Musaeum.xcodeproj -scheme Musaeum \
        -destination "id=DE0B5601-7874-455E-A965-9AD80567C30E" \
        -derivedDataPath ./DD test \
        -only-testing "$1" \
        -collect-test-diagnostics never 2>&1)
status=$?
summary=$(printf '%s\n' "$out" | grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' | tail -1)
printf 'Tests %s\n' "${summary:-did not run}"
printf '%s\n' "$out" | grep -E "^Test Case .* failed|error:" | sed 's/^/                /'
{
  printf '\n=== %s | %s | exit=%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status"
  printf '%s\n' "$out" | grep -E "Executed [0-9]+ tests|Test Case .* (failed|passed)" | tail -20
} >> "$LOG"
exit "$status"

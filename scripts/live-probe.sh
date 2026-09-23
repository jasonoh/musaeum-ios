#!/usr/bin/env bash
#
# live-probe.sh — the app's own evidence, re-run in one command.
#
# The standard this repo holds itself to is a **live probe**: a simulator run
# against a real Musaeum, with a number or a frame to show for it. This script is
# that run, so the next session re-runs it instead of rebuilding it.
#
# It needs a Mac-side Musaeum serving the contract (`../musaeum`,
# `docs/rest-api.md`). Bring one up on an isolated profile — never the real
# library — roughly so:
#
#   S=<scratch>/ios-probe
#   mkdir -p "$S/profile" "$S/library/imports"
#   sqlite3 "$S/profile/musaeum.db" < <(cat 001_initial.sql)   # then PRAGMA user_version = 1
#   sqlite3 "$S/profile/musaeum.db" \
#     "INSERT OR REPLACE INTO app_config (key,value) VALUES
#        ('library_root','$S/library'),
#        ('rest_api_enabled','true'),
#        ('rest_api_token','<openssl rand -hex 32>');"
#   cp some.epub "$S/library/imports/"
#   cd ../musaeum && env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA="$S/profile" npm run dev
#
# (`env -u ELECTRON_RUN_AS_NODE` matters: Hermes exports that variable, and with
# it set Electron runs as plain Node — no window, no app.)
#
# **Two things the probe must be told, and the script refuses to guess either:**
# `$ROOT/token.txt` (the profile's `rest_api_token`) and `$ROOT/base.txt` (the
# address the server binds — `lsof -nP -iTCP:8788 -sTCP:LISTEN` says which; the
# server binds the **tailnet address**, so `127.0.0.1` answers nothing). Both are
# overridable as `TOKEN=` and `BASE=`.
#
# Then, with the phone-side app installed and a book's id in $BOOK:
#
#   TAG=library ./scripts/live-probe.sh                        # the grid, covers
#   TAG=read    BOOK=<id> ./scripts/live-probe.sh              # download + read
#   # stop the Mac app, then the run that matters most:
#   TAG=offline BOOK=<id> ./scripts/live-probe.sh              # read with it off
#
# The upward path (slice 2) is two more runs, and the second one is a sequence:
#
#   # 2.6 — a report the Mac takes: the row moves, and the log says by how much
#   TAG=write ACTION=write BOOK=<id> ./scripts/live-probe.sh
#
#   # 2.7 — a report the Mac cannot take: read with the Mac stopped (the report is
#   # queued and `pending=1`), then start the Mac, then relaunch **without** ACTION
#   # so the launch-time flush runs:
#   TAG=queued  ACTION=write BOOK=<id> ./scripts/live-probe.sh   # Mac stopped
#   #   … start the Mac …
#   TAG=flushed BOOK=<id> ./scripts/live-probe.sh                # the queue drains
#
# Every run prints the Mac's own row for $BOOK at the end, read straight out of the
# probe profile's SQLite — so the decider is the Mac's number rather than the app's.
#
# Results: `Documents/probe.log` in the app's own container, a frame per run, and
# the container listing — printed below.
set -uo pipefail

DEV=${DEVICE:-DE0B5601-7874-455E-A965-9AD80567C30E}   # iPhone 17 Pro, iOS 26.1
BUNDLE=dev.jasonoh.Musaeum
ROOT=${PROBE_ROOT:-$HOME/.hermes/profiles/dev/cache/scratch/ios-probe}
APP=${APP:-$(cd "$(dirname "$0")/.." && pwd)/DD/Build/Products/Debug-iphonesimulator/Musaeum.app}
TAG=${TAG:-run}
WAIT=${WAIT:-25}
# `write` makes the reader report the fraction it landed at through the app's own
# door and read the row back (`ReaderScreen.runWriteProbe`); empty is a read run.
ACTION=${ACTION:-}
DB=${DB:-$ROOT/profile/musaeum.db}
BASE=${BASE:-$(cat "$ROOT/base.txt" 2>/dev/null || true)}

die() { echo "$1" >&2; exit 1; }

[ -f "$ROOT/token.txt" ] || die "no $ROOT/token.txt — see this script's header for the server recipe"
# A run with no base URL is not a run that failed: the app would come up
# unconfigured, log nothing, and read as "the probe found nothing".
[ -n "$BASE" ] || die "no base URL — write the server's address into $ROOT/base.txt, or run with BASE=http://<host>:8788"
[ -d "$APP" ] || die "no app at $APP — build first: xcodebuild -scheme Musaeum -destination 'id=$DEV' build"

xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1
xcrun simctl install "$DEV" "$APP" || die "install failed"
xcrun simctl terminate "$DEV" "$BUNDLE" >/dev/null 2>&1
sleep 1

CONT=$(xcrun simctl get_app_container "$DEV" "$BUNDLE" data) || die "the app has never run on this device"
rm -f "$CONT/Documents/probe.log"

echo "=== launched ($TAG) ==="
SIMCTL_CHILD_MUSAEUM_PROBE_LOG="$CONT/Documents/probe.log" \
SIMCTL_CHILD_MUSAEUM_PROBE_BASE="$BASE" \
SIMCTL_CHILD_MUSAEUM_PROBE_TOKEN="${TOKEN:-$(cat "$ROOT/token.txt")}" \
SIMCTL_CHILD_MUSAEUM_PROBE_OPEN="${BOOK:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_ACTION="$ACTION" \
  xcrun simctl launch "$DEV" "$BUNDLE" | cat
sleep "$WAIT"

echo "=== probe lines ==="
cat "$CONT/Documents/probe.log" 2>/dev/null || echo "(no probe log — nothing logged)"

xcrun simctl io "$DEV" screenshot "$ROOT/frame-$TAG.png" >/dev/null 2>&1
echo "=== frame === $ROOT/frame-$TAG.png"

echo "=== what the phone holds ==="
find "$CONT/Library/Application Support/Musaeum" -type f 2>/dev/null | sed "s|$CONT|<container>|"

if [ -n "${BOOK:-}" ]; then
  echo "=== the Mac's own row for $BOOK ==="
  if [ -f "$DB" ]; then
    sqlite3 "$DB" \
      "select read_status, ifnull(reading_percent,'(null)'), ifnull(reading_updated_at,'(null)'), ifnull(reading_position,'(null)') from books where id='$BOOK';" \
      2>/dev/null || echo "(could not read $DB)"
  else
    echo "(no $DB — see this script's header for the server recipe)"
  fi
fi

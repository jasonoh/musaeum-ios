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
# **That recipe is a script now, and it carries one thing the prose could not:
# a shelf.** `bash scripts/seed-probe-profile.sh` writes the profile (port **8789**
# — the owner's packaged app holds 8788), seeds eight books with covers
# (`scripts/seed-epubs.py`, which needs nothing but the Mac's own sidecar venv),
# and, once the Mac has imported them, a second run writes the two
# `shelves.json` shelves a *scoped* run needs — a shelf is created by the Mac's
# own UI and nowhere else, so the file is the only way to put one in a profile.
# Scratch is pruned when idle, so this is the recipe a later session runs.
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
#   TAG=chrome  READER=chrome BOOK=<id> ./scripts/live-probe.sh # the reader's raised chrome (slice 6; also contents|typography|ink|paper)
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
# The library's own ordering and search (slice 3) is four runs, and **the order
# matters** — the sort is *remembered* on the phone (the Mac's own rule: sorting is
# a preference, so it is restored; the query is not), so the run that names one
# leaves it stored for the run after it:
#
#   TAG=library SORT=title:asc   ./scripts/live-probe.sh   # the control: 8 books, title order
#   TAG=sort    SORT=author:desc ./scripts/live-probe.sh   # the order reverses — and is stored
#   TAG=kept                       ./scripts/live-probe.sh   # no SORT: `sort=author:desc` in the
#                                                          # log is the persistence, decided
#   TAG=search  QUERY=negotiate  ./scripts/live-probe.sh   # a total below the library's own
#   TAG=nomatch QUERY=zzzz       ./scripts/live-probe.sh   # the frame says "Nothing matches"
#
# **The filters (slice 3b) are three more runs, and the sheet is a fourth.** They
# are independent of the two above — a filter names no term and changes no sort —
# so they run in any order, and `FILTERS=` carries the app's own encoding of a
# filter set (`LibraryFilters.probe`), which the log line then reads back as
# `filters=` so a run states what it applied rather than what it meant to:
#
#   TAG=filters      FILTERS='status=reading'             # 2 of the 8 books
#   TAG=narrow       FILTERS='status=unread;format=epub'  # two axes ANDed: 6
#   TAG=filter-empty FILTERS='status=read'                # no book is read: the card
#                                                         # names the FILTERS, not an
#                                                         # empty library
#   TAG=sheet        SHEET=1                              # the sheet itself, opened by the
#                                                         # run, with the Mac's counts on it
#
# A token this build does not know is **logged** (`probe: filters '…' carried …`),
# so a run that named something unreadable says so instead of looking like one that
# found nothing. Filters are a narrowing and are never stored, so a filter run
# leaves nothing behind — unlike `SORT=`, which is remembered.
#
# **The upload (slice 4a) is one more action, and it needs the book given to it.**
# `UPLOAD=` names a file on *this Mac*; the script copies it into the app's own
# container first, because a `simctl` launch cannot open a security scope and a
# `fileImporter` cannot be driven at all — so the run exercises the app's own
# upload path, its copy into the outbox, the composed request and the refusal
# classes, while the *picker* stays a claim for a human frame:
#
#   TAG=upload UPLOAD=/path/to/book.epub ./scripts/live-probe.sh
#   TAG=upload UPLOAD=<a 600 MiB file named .epub> WAIT=180 ./scripts/live-probe.sh  # R1/R2, with
#                                        # `ps -o rss` watching the app while it sends
#   TAG=sheet  UPLOAD_SHEET=1 ./scripts/live-probe.sh      # the sheet itself, presented by the run
#
# The last `upload …` line in the log is the reading (`upload sending`, then either
# `upload added` or `upload refused kind=…`), and the container listing below it
# shows what the app is still holding: **empty after a settled send, and one file
# after a `waitAndTry` refusal, which is the copy a retry sends.** A refusal run
# wants the Mac's own refusal reproduced — stop the Mac for `unreachable`, hold two
# transfers for `busy`, or hand it a body past the cap for `tooLarge`.
#
# **The share (slice 5) is one more action, and the run that matters most is the
# one with the Mac stopped.** `ACTION=share BOOK=<id>` stages what a share door
# would hand the sheet, through the store's own call and under the name a
# recipient reads, and reports it in two lines: the app's own
# (`share staged book=… name=… linked=1 bytes=…`) and the probe's reading of it
# (`share reading name=… bytes=… source=… same=1 dir=…`). The container listing
# then shows the staged file itself.
#
#   TAG=share ACTION=share BOOK=<id> ./scripts/live-probe.sh     # with the Mac up: it downloads, then stages
#   TAG=share-offline ACTION=share BOOK=<id> ./scripts/live-probe.sh   # Mac stopped: the run falls back to the
#                                                         # phone's own copy — the same reading, and
#                                                         # the one that decides a share needs no Mac
#
# What no run can decide is the sheet itself: `simctl` presents nothing and taps
# nothing, so AirDrop/Mail/Messages appearing for the staged file is a human frame
# and is named as one rather than implied.
#
# **And the door's own screen is a third run, with its own variable.** A book's
# detail is reached by tapping a cover, so `DETAIL=<id>` opens it directly — it is
# deliberately not `OPEN=`, which would open the reader over the very screen:
#
#   TAG=detail DETAIL=<id> ./scripts/live-probe.sh   # the detail with Read, Share and Remove on it
#
# **And the shelf's own screen is a fourth: a row's geometry is a frame's
# business.** `DownloadsScreen` is behind a `NavigationLink` on the library
# screen, so `DOWNLOADS=1` pushes the same destination by state instead:
#
#   TAG=downloads DOWNLOADS=1 ./scripts/live-probe.sh   # the downloaded shelf, one row per book
#
# **The list's own scroll is a fifth, and it is the one `simctl` cannot make.**
# `SCROLL=` names positions in the list as it stands (1 is the first book), one
# leg each, comma-separated, each leg logged with the book that landed there and
# what the library's header did. It is the instrument the header's own rule is
# read with — `SCROLL=14` for the header giving way, `SCROLL=14,4` for it coming
# back with the list still scrolled — and the two runs are worth keeping as a
# pair, because the second is the half that decides anything:
#
#   TAG=recede    SCROLL=14   ./scripts/live-probe.sh   # the header out of the way
#   TAG=returned  SCROLL=14,4 ./scripts/live-probe.sh   # …and back, mid-list
#
# Each line reports `sort=<field>:<direction> q=<term> filters=<set>` (with `-` for
# an absent one) so all three halves of a query are readable without a frame: what
# was asked for, and what came back. A QUERY is never stored, a SORT always is —
# `SORT=title:asc` is also how you put the phone back.
#
# **The shelves (slice 7) are two more actions, and they reach the two surfaces a
# tap cannot.** `ACTION=shelf SHELF=<id>` opens the scope through the app's own door
# (`LibraryModel.openShelf`) and reports the scoped page — the run's own `sort=`
# line reads `shelf_added:desc`, which is the Mac's default inside a shelf, and
# `shelf=` names the scope on the request. `ACTION=shelf-toggle BOOK=<id> SHELF=<id>`
# opens the book's detail (through `DETAIL`'s own path) and drives the checklist's
# own call, logging the membership **before and after**; the Mac's own count for the
# shelf is printed below, so one run decides both halves of the write and its retry.
# The picker menu and the checklist sheet themselves are frames for the owner:
#
#   TAG=shelf        ACTION=shelf        SHELF=<id>        ./scripts/live-probe.sh
#   TAG=shelf-add    ACTION=shelf-toggle BOOK=<id> SHELF=<id> ./scripts/live-probe.sh
#   TAG=shelf-remove ACTION=shelf-toggle BOOK=<id> SHELF=<id> ./scripts/live-probe.sh
#
# Every run prints the Mac's own row for $BOOK at the end, read straight out of the
# probe profile's SQLite — so the decider is the Mac's number rather than the app's.
#
# Results: `Documents/probe.log` in the app's own container, a frame per run, and
# the container listing — printed below.
set -uo pipefail

# iPhone 18 Pro, iOS 27.0 — verified 2026-09-28, after the 26.1 runtime left this
# machine and took `DE0B5601-…` (the id in AGENTS.md and the README) with it.
DEV=${DEVICE:-39D29C73-B2DD-4041-8ECD-46923376D0F9}
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

# **A tag is a label, not a switch.** `TAG=share` names a run; `ACTION=share` is
# what makes it one — and a run that names an action it did not pass comes up,
# lists the library, downloads and reads, then logs nothing about the action: it
# reads as a share that found nothing, which is the one failure mode this script
# already refuses for a missing base URL. Measured on this slice's first share run,
# which reported four ordinary lines and no `share` line at all.
case "${TAG:-}" in
  share|upload|write|shelf|shelf-add|shelf-remove|shelf-toggle)
    if [ -z "$ACTION" ]; then
      echo "warning: TAG=$TAG names an action but ACTION is empty — pass ACTION=$TAG" >&2
    fi
    ;;
esac

CONT=$(xcrun simctl get_app_container "$DEV" "$BUNDLE" data) || die "the app has never run on this device"
rm -f "$CONT/Documents/probe.log"

# **A book for the run to send, put where the app can read it.** The path is
# *inside the app's own container* on purpose: a `simctl` launch cannot open a
# security scope, so the security-scoped half of the picker's flow (and the whole
# of R4's question) is a claim for a human frame — this is the half a run can
# decide. The file keeps its own name, because the name is what the wire carries
# as `filename`.
UPLOAD_PATH=""
if [ -n "${UPLOAD:-}" ]; then
  [ -f "$UPLOAD" ] || die "no file at $UPLOAD"
  mkdir -p "$CONT/Documents/Probe"
  UPLOAD_PATH="$CONT/Documents/Probe/$(basename "$UPLOAD")"
  cp "$UPLOAD" "$UPLOAD_PATH"
  echo "=== the run will send $(basename "$UPLOAD") ($(wc -c < "$UPLOAD" | tr -d ' ') bytes)"
  rm -rf "$CONT/Library/Application Support/Musaeum/Outbox"
fi

echo "=== launched ($TAG) ==="
SIMCTL_CHILD_MUSAEUM_PROBE_LOG="$CONT/Documents/probe.log" \
SIMCTL_CHILD_MUSAEUM_PROBE_BASE="$BASE" \
SIMCTL_CHILD_MUSAEUM_PROBE_TOKEN="${TOKEN:-$(cat "$ROOT/token.txt")}" \
SIMCTL_CHILD_MUSAEUM_PROBE_OPEN="${BOOK:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_ACTION="$ACTION" \
SIMCTL_CHILD_MUSAEUM_PROBE_SHELF="${SHELF:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_QUERY="${QUERY:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_SORT="${SORT:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_FILTERS="${FILTERS:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_SHEET="${SHEET:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_UPLOAD="$UPLOAD_PATH" \
SIMCTL_CHILD_MUSAEUM_PROBE_UPLOAD_SHEET="${UPLOAD_SHEET:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_DETAIL="${DETAIL:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_DOWNLOADS="${DOWNLOADS:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_SCROLL="${SCROLL:-}" \
SIMCTL_CHILD_MUSAEUM_PROBE_READER="${READER:-}" \
  xcrun simctl launch "$DEV" "$BUNDLE" | cat
sleep "$WAIT"

echo "=== probe lines ==="
cat "$CONT/Documents/probe.log" 2>/dev/null || echo "(no probe log — nothing logged)"

xcrun simctl io "$DEV" screenshot "$ROOT/frame-$TAG.png" >/dev/null 2>&1
echo "=== frame === $ROOT/frame-$TAG.png"

echo "=== what the phone holds ==="
find "$CONT/Library/Application Support/Musaeum" -type f 2>/dev/null | sed "s|$CONT|<container>|"

# **The staged share is the one thing in this listing nothing else explains**:
# empty until a share asks for it, one file while the sheet has it, empty again
# once the sheet is dismissed.
echo "=== staged for a share ==="
find "$CONT/Library/Application Support/Musaeum/Share" -type f 2>/dev/null | sed "s|$CONT|<container>|"
echo "(end of the staged listing)"

if [ -n "${SHELF:-}" ]; then
  echo "=== the Mac's own count for shelf $SHELF ==="
  if [ -f "$DB" ]; then
    sqlite3 "$DB" "select count(*) from shelf_books where shelf_id='$SHELF';" 2>/dev/null || echo "(could not read $DB)"
    if [ -n "${BOOK:-}" ]; then
      echo "=== the Mac's own membership of $BOOK on it (1 = on) ==="
      sqlite3 "$DB" "select count(*) from shelf_books where shelf_id='$SHELF' and book_id='$BOOK';" 2>/dev/null || echo "(could not read $DB)"
    fi
  else
    echo "(no $DB — see this script's header for the server recipe)"
  fi
fi

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

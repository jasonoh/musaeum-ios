#!/usr/bin/env bash
#
# seed-probe-profile.sh — rebuild the live probe's library and profile in one
# command.
#
# `scripts/live-probe.sh`'s header carries the recipe in prose, and it is six
# commands of SQL plus a book to import. This script is that recipe, plus the one
# thing the prose could not carry: **a shelf**. A scoped screen is a screen a run
# can only reach if the Mac has a shelf to open, and hand-writing
# `{library_root}/shelves.json` is the only way to put one there (creating a shelf
# is the Mac's own UI, `../musaeum/docs/invariants/shelves.md`).
#
#   bash scripts/seed-probe-profile.sh
#   cd ../musaeum && env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<the profile> npm run dev
#
# What it leaves: a profile whose `app_config` points at its own library root,
# serves the REST API on **8789** (the owner's packaged app holds 8788 — never
# this port), and whose `imports/` holds **8 EPUBs** with covers. The Mac imports
# them on startup through its own watcher and hydrates them; then this script can
# be run once more to add the two shelves, which adoption picks up on the next
# launch (`syncOnConnect` — shelves.json is canonical and the cache is derived).
#
# The app migrates the database itself, but `002` calls SQL functions only it
# registers, so this applies `001` by hand (and `app_config` with it) and lets the
# app finish the rest at boot.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MAC="${MUSAEUM_REPO:-$(cd "$HERE/../musaeum" && pwd)}"
S="${PROBE_ROOT:-$HOME/.hermes/profiles/dev/cache/scratch/ios-probe}"
PORT="${PROBE_PORT:-8789}"
BIND="${PROBE_BIND:-$(tailscale ip -4 2>/dev/null | head -n1)}"
[ -n "$BIND" ] || { echo "set PROBE_BIND to this Mac's tailnet address (tailscale ip -4)" >&2; exit 1; }
TOKEN="${PROBE_TOKEN:-$(cat "$S/token.txt" 2>/dev/null || true)}"

[ -d "$MAC/electron/main/schema/migrations" ] || {
  echo "no Musaeum checkout at $MAC — set MUSAEUM_REPO" >&2
  exit 1
}

mkdir -p "$S/profile" "$S/library/imports" "$S/library/books" "$S/library/exports"

if [ ! -f "$S/profile/musaeum.db" ]; then
  sqlite3 "$S/profile/musaeum.db" < "$MAC/electron/main/schema/migrations/001_initial.sql"
  sqlite3 "$S/profile/musaeum.db" "PRAGMA user_version = 1;"
fi

if [ -z "$TOKEN" ]; then
  TOKEN="$(openssl rand -hex 32)"
  printf '%s' "$TOKEN" >"$S/token.txt"
fi
printf 'http://%s:%s' "$BIND" "$PORT" >"$S/base.txt"

sqlite3 "$S/profile/musaeum.db" \
  "INSERT OR REPLACE INTO app_config (key, value) VALUES
     ('library_root', '$S/library'),
     ('rest_api_enabled', 'true'),
     ('rest_api_token', '$TOKEN'),
     ('rest_api_port', '$PORT'),
     ('rest_api_bind', '$BIND');"

# The books. `imports/` is watched with `ignoreInitial: false`, so a file already
# there is imported on launch — no tap, no picker.
if [ -z "$(ls -A "$S/library/imports" 2>/dev/null)" ]; then
  "$MAC/sidecar/.venv/bin/python" "$HERE/scripts/seed-epubs.py" "$S/library/imports"
else
  echo "imports/ already holds $(ls -1 "$S/library/imports" | wc -l | tr -d ' ') file(s) — left alone"
fi

# The shelves — after the books, because a shelf names book ids and those exist
# only once the Mac has imported them.
count="$(sqlite3 "$S/profile/musaeum.db" "select count(*) from books;" 2>/dev/null || echo 0)"
if [ "$count" -gt 0 ] && [ ! -f "$S/library/shelves.json" ]; then
  "$MAC/sidecar/.venv/bin/python" - "$S" <<'PY'
import datetime, json, pathlib, sqlite3, sys, uuid

S = pathlib.Path(sys.argv[1])
rows = sqlite3.connect(S / "profile/musaeum.db").execute(
    "select id, title from books order by sort_title, id").fetchall()
ids = [row[0] for row in rows]


def stamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def entry(name, members, created):
    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "kind": "manual",
        "created_at": stamp(created),
        "updated_at": stamp(created),
        "books": [
            {"id": book, "added_at": stamp(created + datetime.timedelta(hours=i + 1))}
            for i, book in enumerate(members)
        ],
    }


now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
shelves = [
    entry("gov & politics", ids[: (len(ids) + 1) // 2], now),
    entry("Twentieth Century Politics and its Discontents", ids[(len(ids) + 1) // 2 :], now),
]
(S / "library/shelves.json").write_text(json.dumps({"version": 1, "shelves": shelves}, indent=2) + "\n")
print("shelves: " + ", ".join(f"{s['name']} ({len(s['books'])}) — {s['id']}" for s in shelves))
PY
  echo "shelves.json written — restart the Mac so adoption lands it"
else
  echo "shelves.json: $( [ -f "$S/library/shelves.json" ] && echo "already there, left alone" || echo "not written — the library holds no books yet; run this again once the Mac has imported them")"
fi

echo
echo "profile: $S"
echo "base:    $(cat "$S/base.txt")"
echo "start:   cd $MAC && env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=$S/profile npm run dev"

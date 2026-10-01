# Slice 2's evidence

Frames from the live probe of 2026-09-23 — the same simulator and the same isolated profile slice 1 used (8 EPUBs at `http://100.64.0.1:8788`, iPhone 17 Pro / iOS 26.1), now exercising the **write** rather than the read.

They are committed because the probe profile is throwaway and a measurement that lives only in a session is not a decider. The numbers beside each frame are in *Built — slice 2* of `docs/specs/2026-09-22-client-v1-design.md`; the command that reproduces them is `scripts/live-probe.sh`, whose header now carries the write recipes.

**The book throughout is `ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d`** (*Negotiation Genius*), and the decider in every run below is the Mac's **own row**, read straight out of the probe profile's SQLite:

```bash
sqlite3 ~/.hermes/profiles/dev/cache/scratch/ios-probe/profile/musaeum.db \
  "select read_status, reading_percent, reading_updated_at, reading_position from books where id='ef91875e-…';"
```

## The three runs

| Frame | The Mac's row before → after | What the app logged |
| ----- | ---------------------------- | ------------------- |
| `write-live-mac-held-0.05.png` | `0.05` + a stale CFI, `updated_at 2026-09-22T00:00:00.000Z` → **`0.419826517967782`**, position **blanked**, `updated_at 2026-09-23T13:46:48.560Z` | `reader opened … requested=0.4198265179677819 local=0.4198265179677819 server=0.05` → `probe write … percent=0.4198265179677819` → `report accepted` → `probe write pending=0` → `probe write the Mac now holds percent=0.4198265179677819` |
| `write-queued-mac-asleep.png` | `0.05` + a stale CFI, **unchanged** — `lsof` shows **no listener** on 8788 | `library failed the Mac is not answering` → `probe offline id=… bytes=660053` → `reader opened … local=0.4198265179677819 server=0.4198265179677819` → `report queued … percent=0.4198265179677819` → `probe write pending=1` → `probe write readback failed the Mac is not answering` |
| `write-flushed.png` | the same `0.05` + stale CFI (set again after the Mac was up, in the same breath as the flush) → **`0.419826517967782`**, position **blanked**, `updated_at 2026-09-23T13:50:37.387Z` | `report queue drained` → `probe downloaded … serverPercent=0.05` → `reader opened … requested=0.4198265179677819 local=0.4198265179677819 server=0.05` → `reader landed=0.4198265179677819 atHref=OEBPS/Malh_9780553904949_epub_c06_r1.htm` |

## What each one decides

- **`write-live…` decides the write moved the Mac's number, and that it is the phone's number.** The Mac held `0.05` (a stale row with a stale CFI); the phone's own position was `0.4198265179677819`, so CD5's rule opened it there and the report carried **that** number — not the `0.05` the Mac had just sent. The row's `reading_position` came back `(null)`: the Mac's D5 blanking, reached through the phone's report.
- **The earlier `write2` run decides the same thing in the other direction, one frame back.** The Mac held `0.42` and the phone had its own `0.09777541747801971`; the reader opened at the Mac's `0.42`, landed at `0.4198265179677819`, and the Mac's row became `0.4198265179677819` — **not** the `0.42` it held. A report that merely echoed the request back would have left `0.42` in place. That run's log is quoted in the design doc rather than committed as a frame, because its frame is the same page.
- **`write-queued…` decides the report is kept, not lost**: the queue on disk held exactly one entry — `{"bookId":"ef91875e-…","percent":0.4198265179677819,"readAt":811864237.386502}` — and the Mac's row was untouched while it was asleep.
- **`write-flushed…` decides the queue drains when the Mac answers, carrying the report's own clock.** `reports.json` went from that one entry to `[]`; the row's `updated_at` is `2026-09-23T13:50:37.387Z`, which is the **queued report's `readAt`** and not the flush's clock (the flush ran some minutes later); and `metadata.json` beside the book agrees — `{"position": null, "percent": 0.4198265179677819, "updated_at": "2026-09-23T13:50:37.387Z"}`. That is the client's half of the Mac's D6, measured.

## Two traps these runs paid for, worth knowing before the next probe

1. **The Mac writes reading state *after* its listener closes.** Stopping the dev app by its listener pid frees `8788` first and runs the quit handshake — which flushes its in-memory reading state into SQLite and `metadata.json` — a second or two later. An edit to the profile's row made in that window is silently overwritten, and the next startup restores the old value from the derived store as well. The edit that decides anything is the one made **once the Electron process is fully gone** (`pgrep -f 'electron/dist/Musaeum.app'` empty, not just `lsof` clean), or **after startup and immediately before the run**.
2. **A stale row is what makes the run decisive.** With the Mac's percent equal to the phone's, a report "succeeds" and moves nothing — which is exactly what the first attempt at 2.6 did (`0.1` → `0.1`, only `updated_at` moving). The profile's row is therefore set to a *different* number (and a stale CFI, to see the blanking) before each run that is meant to decide something.

## The other half of the evidence: the mutations

`mutation-campaign.log` is the raw output of `mutation-campaign.json` — **8 mutations, one per criterion that has a unit decider, 8/8 killed**, each with the mutated file restored and sha256-verified. It is committed beside the frames because the two decide different things and neither is a substitute for the other: the frames decide that a *screen* moved a *row* on the Mac, and the mutations decide that the unit suite would have **noticed** if the rule underneath were removed. Slice 1's record has no equivalent, and its criteria were argued from their assertions — a suite proves the cases ran, never that they decide.

The runner is not the Mac repo's `mutation-campaign.py`: that appends the test path as a bare argument, while `xcodebuild` needs it inside the flag (`-only-testing:<path>`). The Swift-shaped version lives in the `musaeum-ios-client` skill (`scripts/swift-campaign.py`), and one row costs about **eight minutes** of wall clock — an incremental build plus a simulator install per mutation, which is why the campaign is a background job with a log, not a foreground step.

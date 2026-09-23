# Slice 1's evidence

Frames from the live probe of 2026-09-22 — the simulator against a real Musaeum on an isolated profile (8 EPUBs, 7 of them with covers) at `http://100.125.135.108:8788`, iPhone 17 Pro / iOS 26.1. They are committed because the probe profile they came from is throwaway, and a measurement that lives only in a session is not a decider. The numbers beside each frame are in *Built — slice 1* of `docs/specs/2026-09-22-client-v1-design.md`; the command that reproduces them is `scripts/live-probe.sh`.

## The three probe runs

| Frame | What the app logged | What it shows |
| ----- | ------------------- | ------------- |
| `library-grid.png` | `library page count=8 total=8 limit=100 offline=online` | eight books, covers painted, titles in the display serif over warm near-black. The one placeholder tile ("In Defense of Selfishness") has no cover on the Mac either — its row's `cover_thumb_path` is null |
| `reader-at-42-percent.png` | `reader opened … requested=0.42 local=0 server=0.42` → `reader landed=0.4198265179677819 atHref=OEBPS/Malh_9780553904949_epub_c06_r1.htm` | the book open **42%** under the title, mid-chapter 6. Asked for 0.42, landed at 0.41983 — the same number the pre-build Readium harness measured for the same request |
| `reader-with-the-mac-asleep.png` | `library failed the Mac is not answering` → `probe offline id=…` → `reader opened … requested=0.4198265179677819 local=0.4198265179677819 server=0.1` | the same page, the same 42%, with `lsof` showing **no listener** on 8788. The phone's own position was further along than the Mac's stale `0.1`, so `initialFraction(local:server:)` took the phone's — CD5 decided in the opposite direction to the frame above |

The reader's page background is Readium's own dark theme, not `Palette.ink` (`EPUBPreferences(theme: .dark)` was the only preference that compiled; CD1's consequence records why). The owner reviewed the typography on 2026-09-22 and **accepted it for v1** — CD1's revival condition for foliate-js is not fired.

## What the three probes could not see, and the frames that did (same day)

The owner ran the app **from Xcode** and got a blank white screen; it stayed white long enough that he quit the app. Reproduced with an instrument the probes never used — `xcrun simctl launch` immediately followed by `xcrun simctl io … screenshot`, **no sleep in between**:

| Frame | What it is |
| ----- | ---------- |
| `launch-before-fix-white.png` | the first frame of a cold launch, before the fix: a **white** launch screen with the connect screen laid out white-on-white on top of it. The app forces dark in SwiftUI, but that only applies once SwiftUI paints |
| `launch-after-fix-dark.png` | the same frame after `UIUserInterfaceStyle: Dark` went into `project.yml`: **black**, from the first frame |
| `connect-screen.png` | the settled screen after the fix — the connect form on the dark palette, its field's placeholder now `host:8788` instead of the owner's tailnet address |

**Why three green probes missed it:** every probe run launched with `MUSAEUM_PROBE_BASE`/`TOKEN` (so the app was always already configured and went straight to the library) and sampled its frame after a 20–35 s wait. The defect lived in the first two seconds, and the configured path never draws the connect screen at all. Both defects are recorded in the design doc under *Defects the owner found by looking, and what fixed them*.

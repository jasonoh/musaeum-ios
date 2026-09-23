# Changelog

## [Unreleased] — 2026-09-23

### Added

- **Where you stop on the phone now travels back to the Mac.** Closing the book — or putting the phone away mid-page — sends where you got to, so the same book opens on the Mac at the place you left it on the phone.
- The reading is **kept when the Mac cannot take it**: with it asleep, shut, or off the network the report waits on the phone and is sent the next time the Mac answers, so nothing read on the phone is lost to a closed lid.
- The position that travels is the one the reader is actually at, not the one the app asked for — a Mac holding a *different* number gets the phone's, which is what makes the two machines meet somewhere real.

### Fixed

- The app's own probe script (`scripts/live-probe.sh`) was committed without its executable bit, so the documented `TAG=library ./scripts/live-probe.sh` answered *Permission denied*; and it never passed the server's address, so a re-run came up unconfigured and read as a probe that found nothing. It now takes the address from the probe profile (or `BASE=`) and refuses to run without one.

### Not yet

- A download that drops starts again rather than resuming.
- The queue of reports waiting for the Mac has no screen of its own; it announces itself in the probe log only.
- A report taken while the phone is being locked is usually sent when the app is next opened rather than at that moment — it is never lost, but it is not instant.

## [Unreleased] — 2026-09-22

### Added

- The app exists: it can be pointed at a Musaeum library on the Mac over the tailnet (URL + bearer token from the Mac's Settings row) and check the connection.
- The library, paged, as a cover grid — with the covers fetched two at a time, because that is the server's own transfer budget.
- A book's detail: cover, metadata, which formats the Mac holds, and what it knows about where you are in it.
- Download a book into the app's own storage and read it there, starting at the fraction the Mac recorded — so a book carries on where you left it on the other machine.
- Books already downloaded are readable with the Mac asleep, shut, or off the network.

### Fixed

- The app opens dark. It used to show a white launch screen — and a white window for as long as Xcode's debugger took to attach — before drawing its own dark screen, which looks like an app that has hung.
- The connect form no longer shows a real tailnet address as its example; the field says `host:8788`.

### Not yet

- Where you stop on the phone is not yet reported back to the Mac. That is the next slice.
- A download that drops starts again rather than resuming.

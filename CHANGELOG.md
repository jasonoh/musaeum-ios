# Changelog

## [Unreleased] — 2026-09-23

### Added

- **The library can be sorted and searched from the phone.** A sort menu with the Mac's own eight orders — Title A–Z through Read Status — and a search field that runs the Mac's own full-text search, so the same query returns the same books in the same order on both machines. The order you pick is remembered between launches; the search is not, so the app never opens looking like a much smaller library with nothing on screen to explain why. A search that matches nothing now says *that*, instead of claiming the library is empty.
- **The library can be narrowed the way the Mac's sidebar narrows it.** Read status, format, a rating floor, and the library's own authors, series and tags — and every tick applies at once, the way it does on the Mac. The toolbar says how many are on, so a library that only *looks* small never reads as a library that is small; one control clears them, and a set that matches nothing says so rather than claiming there are no books to show. Filters and the search field narrow together, so a term and a tick are one answer instead of two.
- **Where you stop on the phone now travels back to the Mac.** Closing the book — or putting the phone away mid-page — sends where you got to, so the same book opens on the Mac at the place you left it on the phone.
- The reading is **kept when the Mac cannot take it**: with it asleep, shut, or off the network the report waits on the phone and is sent the next time the Mac answers, so nothing read on the phone is lost to a closed lid.
- The position that travels is the one the reader is actually at, not the one the app asked for — a Mac holding a *different* number gets the phone's, which is what makes the two machines meet somewhere real.

### Fixed

- The app's own probe script (`scripts/live-probe.sh`) was committed without its executable bit, so the documented `TAG=library ./scripts/live-probe.sh` answered *Permission denied*; and it never passed the server's address, so a re-run came up unconfigured and read as a probe that found nothing. It now takes the address from the probe profile (or `BASE=`) and refuses to run without one.
- **A cover no longer takes its size from the cover art.** Every cover is now bounded by the cell it sits in — the Mac's own 2:3 box, the artwork filling it and cropped to it — instead of growing to the jacket's own shape. A wide cover used to be drawn wider than its column and cover the books beside it (and their titles); a very tall one ran down over its own title and author line. The same box now applies to a book's detail cover and to a download's thumbnail, which had the same defect in a smaller frame.

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

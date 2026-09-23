# Changelog

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

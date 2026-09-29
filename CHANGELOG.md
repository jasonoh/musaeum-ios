# Changelog

## [Unreleased] — 2026-09-29

### Fixed

- **Opening a shelf no longer takes the page with it.** Inside a shelf the sort control drew the Mac's own *Date Added to Shelf, Newest First* — **255.5 pt** of label on a 402 pt phone — so the bar's title row came to **532 pt**, and because the header is drawn *over* the grid rather than above it, the whole screen grew to that width: the grid was laid out to match, and every page came out centred with about 65 pt cut off each edge until the phone was turned. Landscape was never wrong (874 pt holds that row); portrait never fitted it. The bar now draws **Shelf: Newest** / **Shelf: Oldest** — the order's own state, with the Mac's whole sentence still on the sort menu — and the row gives way by construction: the title may step down to nothing and a label past the bar's budget may lose its tail, but neither can widen the screen again. The scope chip also outranks the search field's hint now, so a long shelf name shortens the chip rather than swallowing the field. Measured on the built app: `chrome=532 overflow=130` before, `chrome=402 overflow=0` after (`docs/evidence/shelf-bar/`).

## [Unreleased] — 2026-09-28

### Added

- **Shelves, on the phone.** The Mac's shelves appear in the library's own row of narrowings — *All Books* first, then every shelf with its count — and choosing one scopes the list to it the way the sort and the filters already narrow it: search and filters keep working inside a shelf, the field says *Search “To Read”*, and an empty shelf says **that** rather than blaming the library. Inside a shelf the order starts at *Date Added to Shelf, Newest First*, and leaving restores the order you had. A book's page gains a **Shelves** row whose checklist is the phone's only membership surface: each tap is one add or one remove, the row refreshes from the Mac's own answer, and a failure is a sentence rather than a lost tap — retrying is safe, because the Mac's writes are idempotent. **Against a Mac without the feature the app says nothing rather than guessing**: it asks once, and the picker and the row are absent rather than wrong.

## [Unreleased] — 2026-09-25

### Added

- **The Mac's wordmark.** The library's header and the connect screen set *MUSAEUM* the way the Mac's sidebar does — Iowan Old Style Roman caps, widely tracked, in the gold — embossed as raised metal, in the same fine hand as the app icon's M. Beside the longest order label on a narrow phone it steps down to the largest size that fits whole rather than truncating.

- **The reader gets out of the way.** A book opens full-screen with only a faint chapter-and-percent line at the foot of the page. Tap the middle for the title, a close button and the book's contents; tap the edges to turn pages; swipe down to close.
- **Typography, like the Mac's.** *Aa* opens serif or sans, size, line height, spacing, and an Ink or Paper page in the Mac reader's own colours. The page changes as you move each control, and the phone remembers your choice.
- **Contents.** Every chapter and section, the one you are in highlighted; tap one to go there, and the Mac hears where you are as if you had turned the pages.

- **A book can be sent to the Mac from the phone.** Pick an EPUB, MOBI, AZW3 or PDF in the app, or share one to Musaeum from Files, Safari or Mail, and it goes to the Mac's own importer — so what lands is what the Mac would have imported itself: the same metadata pass, the same covers, the same rule for a book you already had. The row reports what happened in the Mac's own words and does not claim the book is in the library until the Mac has answered.
- **A refusal is reported as the refusal it is, and only the ones worth retrying offer a retry.** A book past the Mac's own limit, or one it cannot take, is that book's problem and says so; a Mac that is busy, or whose library drive is not mounted, is worth waiting out — and the app keeps its own copy of the bytes, so *Try again* sends the same book instead of asking you to find it again; a refused token offers the way back to the connect screen.
- **A book shared while the phone cannot send it is kept, not lost.** The file another app hands over stays in Musaeum's own storage and goes out the next time the app can send it.
- **A book you have on the phone can be sent to someone else.** Share it from the book's own screen or from a row on the downloaded shelf and the system share sheet takes it: AirDrop, Mail, Messages, *Save to Files*, or whatever else is installed. The recipient gets the book under **the title and author you know it by** rather than the file's internal name, and — because it comes off the phone's own storage — this works with the Mac asleep, shut, or off the network.
- **Sharing a big book costs nothing extra.** The copy the sheet hands out is the download itself, one file with two names, so a 500 MB book is not duplicated on the phone to send it.
- **The Mac's *content too large* answer is understood now, and it was not before.** An upload past the Mac's limit used to be reported as *the Mac is not answering* — and then sent again, indefinitely, on a book that could never fit.

### Fixed

- **The library's header gets out of the way.** The title, the send and order controls, the search field and the `Downloaded … N books` row were pinned to the top of the screen whatever you did with the list — so on a long shelf the top fifth of the phone was paid for on every scroll, in portrait and in landscape. The whole band now recedes as you push the list away and comes straight back when you drag the other way, **mid-list rather than only at the top**: an inch of pull brings it back with the grid still scrolled. It goes as one — the shelf's row, the filter's cause, an upload's progress and the offline notice included — so nothing is left sitting under a departed bar; and a pull *at the top* is still a refresh, so the band never hides while the list is being dragged past its own start. (`docs/evidence/header-recede/`)
- **The downloaded shelf's two row icons are one size now, so the row's own tap and the share door beside it read as a pair.** The share glyph was drawing **56 px of ink against the read glyph's 46** (measured at 3×, `docs/evidence/downloads-row-alignment/`) — a fifth taller, which is what "the icons are not properly aligned" was: not a glyph sitting higher than the other, but one glyph standing out of the pair with nothing in the row to say which of the two was the right size. The pair now lands on one ink box, `46 / 46`, level within a third of a point — the same rule, and the same kind of measurement, as the library bar's four controls. Both sizes now live in one measured table on the screen rather than as a single `.body` applied to two glyphs that do not draw the same.
- **The library's control bar is one set now, and the `Send` control no longer stands out of it.** The share glyph was drawing a fifth taller than the sort arrows beside it and sitting a point lower than the three controls to its right — so the bar read as a control plus three others rather than as four controls. Every control in the bar is now built from one place: the symbols land on the same ink box (measured, 65 px at 3×), the words are one size, and the bar has a single colour rule at last — **gold means the library is narrowed**, and nothing else in the bar is ever gold. The sort control's order and the shelf ring used to be gold for no reason a reader could act on; both are parchment now, and the filter's filled glyph and its count stay gold, which is *the* signal. The filter also says what it is to VoiceOver (`Filters` / `Filters, 2 on`).
- **The bar holds three controls instead of four, and the phone's shelf moved to a door on the library screen.** Measuring the bar turned up a defect the report had not named: at 402 pt it cannot hold four controls and the longest sort label at once, and iOS's answer is to take the sort control — with the order it was displaying — off the bar into a `•••` menu, hiding exactly the thing 3a's label exists to show. The shelf was the one control of the four that is a *destination* rather than something done to the list, so it is the one that left. The library screen now draws a `⤓ Downloaded … N books ›` row under the search field — the same strip shape as the filter bar and the upload's row — and only when the shelf holds something, since a door that leads nowhere is 44 pt of the grid spent on nothing. Three controls measure 307 pt with `Recently Added` and stay inline, where four needed about 363 pt and collapsed. Moving the ring to the bar's *leading* end was measured first and is **not** a way out — the bar's width is a single budget, not one per group — which is why the door is on the screen rather than at the bar's other end (`docs/evidence/toolbar-alignment/`).

### Not yet

- The book is sent while the app is open. A send that outlives the app is a new send rather than a resumed one — the Mac's route has no resume, and a book it already has is added again rather than refused, so nothing is lost by trying; it just costs the transfer a second time.
- One book at a time. Neither the picker nor the share sheet takes a batch, and a share is one book at a time too.
- A book the app cannot read as a file — an iCloud Drive file that has not been downloaded, a photo, a link — is reported rather than worked around.
- Only what is on the phone can be shared. A book you have not downloaded has no Share button, rather than one that downloads first.
- A book is shared as the format it is on the phone — usually the EPUB, which Apple Books opens anywhere. A book the Mac holds only as a Kindle file is shared as that Kindle file, and a DRM-locked one is no more usable to the recipient than it was to you.
- The share sheet is the system's list, unchanged. No subject line for a mail, no activities hidden, no link variant.

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

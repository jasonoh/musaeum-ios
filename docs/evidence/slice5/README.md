# Slice 5 — sharing a downloaded book out: what the runs decided

Annex: `docs/plans/2026-09-24-slice5-share-out.md`. The instrument is `scripts/live-probe.sh`; its header carries the server recipe and the `MUSAEUM_PROBE_*` contract.

The Mac answered on **8789** (the probe profile's own `rest_api_port`), because the owner's packaged app holds 8788. Nothing here touched his instance.

## The frame that is evidence

`detail-with-share-door.png` — `TAG=detail DETAIL=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d`, the door's own screen: the gold **Read**, the raised **Share** with its words (a `Label` in a `VStack`, so the icon-only trap that bit the toolbar does not apply), and *Remove the download* under them in the danger colour. A share run's own frame is the reader — `OPEN=` opens it too — and it is **not kept here**: a screenshot of a state decides, a screenshot of an arrangement does not, and the share's reading is the log line below rather than the picture.

## Run 1 — the Mac up (`TAG=share ACTION=share BOOK=ef91875e-…`)

```
library page count=13 total=13 limit=100 offline=online sort=title:asc q=- filters=- first=Caliban's war | Dragon Wing | The Hidden Palace
probe downloaded id=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d format=epub serverPercent=0.4198265179677819
share staged book=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d name=Negotiation Genius - Deepak Malhotra.epub linked=1 bytes=660053
share reading name=Negotiation Genius - Deepak Malhotra.epub bytes=660053 source=660053 same=1 dir=…/Library/Application Support/Musaeum/Share
reader opened book=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d requested=0.4198265179677819 local=0.4198265179677819 server=0.4198265179677819
reader landed=0.4198265179677819 atHref=OEBPS/Malh_9780553904949_epub_c06_r1.htm
```

The container listing then carries the staged file itself:

```
<container>/Library/Application Support/Musaeum/Share/Negotiation Genius - Deepak Malhotra.epub
```

**What it decides:** the name is the title and the byline (AC1) and not the id; `linked=1` says the hard link was taken rather than the copy (AC4, live half); `same=1` with equal byte counts says the staged file **is** the download (AC3); the listing says where it landed (AC5). AC8's "no capability" is not a reading at all — it is the diff: no `.entitlements` file, `LSSupportsOpeningDocumentsInPlace` still `false`.

## The run that decided nothing, and now cannot

The first attempt was `TAG=share BOOK=<id>` with **no `ACTION=`** — and it reported four ordinary lines with no `share` line at all:

```
library page count=13 total=13 limit=100 offline=online sort=title:asc q=- filters=- first=Caliban's war | Dragon Wing | The Hidden Palace
probe downloaded id=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d format=epub serverPercent=0.4198265179677819
reader opened … reader landed=0.4198265179677819 atHref=OEBPS/…
```

Nothing failed. The run downloaded, listed and read, and exercised none of this slice — **a tag is a label, not a switch**, and this is exactly the class of failure this repo's traps are about (a seam declared but never consumed). It is recorded because the script now says so instead of staying silent: a `TAG` that names an action it was not passed prints

```
warning: TAG=share names an action but ACTION is empty — pass ACTION=share
```

## Run 2 — the detail door, and the launch sweep

`TAG=detail DETAIL=ef91875e-…` (no `ACTION`, no `OPEN`):

```
probe detail book=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d title=Negotiation Genius
```

and the staged listing is **empty** — where run 1's copy was still on disk when this run started, because a killed app never reaches the sheet's dismissal. That is the launch sweep, decided on real data rather than asserted:

```
=== staged for a share ===
(end of the staged listing)
```

## Run 3 — the Mac stopped (`TAG=share-offline ACTION=share BOOK=ef91875e-…`)

`lsof -nP -iTCP:8789 -sTCP:LISTEN` empty, `pgrep -f 'electron/dist/Musaeum.app'` empty, before the run:

```
library failed the Mac is not answering — Could not connect to the server.
probe: the Mac did not answer (the Mac is not answering — Could not connect to the server.) — falling back to the phone's own copy
probe offline id=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d bytes=660053
share staged book=ef91875e-92ef-47ae-8ef2-3dc0bc1a8b9d name=Negotiation Genius - Deepak Malhotra.epub linked=1 bytes=660053
share reading name=Negotiation Genius - Deepak Malhotra.epub bytes=660053 source=660053 same=1 dir=…/Library/Application Support/Musaeum/Share
```

**What it decides:** AC7. With nothing listening, and with the library route itself failing, the share staged **the same name, the same link, the same bytes**. The file a share hands out comes off the phone's own disk; there is no client anywhere in that path.

## What no run here decides

**The sheet, and what is on it.** `simctl` presents no sheet and taps nothing, so AirDrop, Mail and Messages appearing for the staged file — and the name the receiving app shows — are the owner's frames, taken on his phone. Everything above is the app's own path plus what its container holds.

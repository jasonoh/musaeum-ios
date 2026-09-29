# Slice 7 — shelves on the phone: the readings

The live probe runs behind `## Built — slice 7` in `docs/specs/2026-09-22-client-v1-design.md`. They reproduce against the Mac plan's own scratch profile (`../musaeum/docs/superpowers/plans/2026-09-28-bookshelves-slice5.md`, its *Built* section — port **8791**, three books, one shelf of two):

```bash
# the scope (7a)
PROBE_ROOT=$P DB=$P/musaeum.db TAG=shelf ACTION=shelf SHELF=2c8e4c18-… ./scripts/live-probe.sh
# the checklist's own call (7b), twice — the add, then the remove
TAG=shelf-add    ACTION=shelf-toggle DETAIL=2ee7b426-… SHELF=2c8e4c18-… ./scripts/live-probe.sh
TAG=shelf-remove ACTION=shelf-toggle DETAIL=2ee7b426-… SHELF=2c8e4c18-… ./scripts/live-probe.sh
```

## What each artifact decides

| Artifact | The reading |
| --- | --- |
| `frame-scoped-grid.png` | the scope control in the narrowing row — `▤ To Read`, gold because the list is narrowed — the field reading *Search “To Read”*, the sort at *Date Added to Shelf, Newest First*, and the footer **2 books** |
| `frame-detail-shelves-row.png` | the detail's *Shelves* row: `Shelves  To Read ›`, under Status — the membership as the server answered it |
| `run-add.log` | `shelves count=1 names=To Read`; `probe: shelf-toggle before … shelves=` (empty); `shelf added … shelves=2c8e4c18-…`; after: on the shelf, `failure=-`; and **the Mac's own count for the shelf: 2 → 3** |
| `run-remove.log` | before `shelves=2c8e4c18-…`; `shelf removed … shelves=`; after: empty; **the Mac's own count: 3 → 2** |

The scope run's own lines, kept in the design doc's table: `library page count=2 total=2 sort=shelf_added:desc first=Seed Two | Seed One` — **the phone's order matches the Mac's `/api/library?shelf=…` answer exactly** (newest added first), and `probe: shelf open id=… count=2 total=2 first=3725db1f-…,2f91b9be-…`.

## What was restored

The shelf's members are the two seeds again — `shelves.json` and the cache agree, and `updatedAt` moved with the runs — the extra book is off it, and the probe profile's port (8791) and the owner's packaged app (8788) were never touched.

## What no run decided

- **The picker menu open, and the checklist sheet itself.** `simctl` presents no menu and taps no check; both are the owner's frames (AC12's stated half).
- **The capability 404** (a pre-shelves Mac): no such Mac can be built now that the route exists; the stub-server case decides it (`ShelvesTests`), and it is recorded as the case's reading rather than the run's.
- **R5's live 404** (a shelf deleted on the Mac while the phone has it open): the same case's business — the run's profile held a shelf that exists.

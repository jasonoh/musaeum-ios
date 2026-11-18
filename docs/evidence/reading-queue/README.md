# Slice 9 — a reading queue, moved from the phone: the readings

The live probe runs behind *Built — slice 9* in `docs/specs/2026-09-22-client-v1-design.md` and the annex `docs/plans/2026-11-18-slice9-reading-queue.md`. They reproduce against the Mac-side scratch profile the reading-queue wire was measured on (`~/.hermes/profiles/dev/cache/scratch/s3pass` — port **8799**, bound `127.0.0.1`, three books `b1 Alpha / b2 Bravo / b3 Charlie`, queue `q-1` *Up Next* ordered `b3,b1,b2`, manual shelf `s-1` *Plain Shelf* holding `b1`). The Mac was started from `../musaeum-macos` at `32919f9` with `env -u ELECTRON_RUN_AS_NODE MUSAEUM_USER_DATA=<that profile>/profile npm run dev`; its own log is `mac-server.log` here.

**The owner's packaged app held 8788 and 8789 throughout and was never touched or signalled.** `scripts/stub-old-mac.py` ran on 8798 for the fourth run only.

```bash
S=~/.hermes/profiles/dev/cache/scratch/s3pass
# 1 — the control: a queue opens sending no sort, in the Mac's own order
PROBE_ROOT=$S TAG=queue-sort  ACTION=shelf      SHELF=q-1                                  ./scripts/live-probe.sh
# 2 and 3 — the move, both ends; each is the other's inverse
PROBE_ROOT=$S TAG=move-top    ACTION=shelf-move SHELF=q-1 MOVE_BOOK=b2 TO=top              ./scripts/live-probe.sh
PROBE_ROOT=$S TAG=move-bottom ACTION=shelf-move SHELF=q-1 MOVE_BOOK=b2 TO=bottom           ./scripts/live-probe.sh
# 4 — a Mac that serves a queue and answers 404 to the place route
python3 scripts/stub-old-mac.py --port 8798 &
PROBE_ROOT=$S BASE=http://127.0.0.1:8798 TOKEN=stub TAG=old-mac \
  ACTION=shelf-move SHELF=c3d4e5f6-7081-4293-a4b5-c6d7e8f90123 MOVE_BOOK=b2 TO=top        ./scripts/live-probe.sh
```

## What each artifact decides

| Artifact | The reading |
| --- | --- |
| `run-shelf-sort.log` | `sort=shelf-default` on the scoped page — **no `sort` and no `dir` are sent inside a queue** — and `first=Charlie \| Alpha \| Bravo`, the Mac's own `shelf_books.position` order. `probe: shelf open id=q-1 name=Up Next count=3 total=3 first=b3,b1,b2`; the Mac's own `kind` is `queue` and its order `b3,b1,b2`. This is AC15's follow-on, and the reason the installed build used to show *Date Added to Shelf* order here. |
| `frame-queue-sort.png` | the bar reading **Queue Order**, the scope chip **Up Next** gold (the list is narrowed), the field reading *Search “Up Ne…”*, the grid **Charlie / Alpha / Bravo**, footer **3 books** — the order the Mac holds, on screen |
| `run-move-top.log` | `move-menu=offered` before, `shelf move book=b2 to=top result=ok title=Bravo`, then `library page … sort=shelf-default first=Bravo \| Charlie \| Alpha` — **the list re-queried in the same scope and shows the new order** — `after move-menu=offered notice=-`, and the Mac's own order `b2,b3,b1` |
| `frame-move-top.png` | the grid **Bravo / Charlie / Alpha** in the queue — the move as a screen |
| `run-move-bottom.log` | `to=bottom` on the same book: `first=Charlie \| Alpha \| Bravo`, the Mac's own order back to `b3,b1,b2` — **the two legs are each other's inverse**, so the slice's runs leave the queue exactly as they found it |
| `frame-move-bottom.png` | the grid back to **Charlie / Alpha / Bravo** |
| `run-old-mac.log` | `probe: shelf-move scope=Up Next kind=queue … move-menu=offered` → `shelf move book=b2 to=top result=route-absent (404) — the Move menu is withheld` → **a `library page … sort=shelf-default` line** (the 404 re-reads the scope, so a *deleted* queue would be noticed here rather than being mistaken for a missing route) → `after move-menu=absent notice=This Mac can't move books in a queue.` — **absent, not disabled**, one sentence rather than a silent withdrawal, and the queue still listed by the Mac so the sentence stands |
| `frame-old-mac.png` | the same queue, unchanged order, with the notice row *This Mac can't move books in a queue.* under the search row |
| `mac-server.log` | the server every run but the last talked to — the Mac's own `npm run dev` on the probe profile |

The fourth run's server is `scripts/stub-old-mac.py`: it serves the vendored contract goldens (health, the shelf list **carrying a queue**, and a three-book page in the queue's order) and answers **404** to the `…/position` path. It is the only state worth deciding here — a Mac old enough to lack the route also has no queue to open (the wire's `kind` and the route landed in one Mac slice), so a *real* older build would show no queue and the 404 reading would never be reached. It is a server-side stand-in; nothing in `Musaeum/` knows it exists. Two things about its answers are the stub's own rather than a Mac's: the books' author line reads the golden's *James S. A. Corey*, and the covers are absent (the stub serves no cover route).

## The numbers the runs moved

| Reading | Before | After the pair |
| --- | --- | --- |
| `q-1`'s order in `shelves.json` and in `shelf_books` | `b3,b1,b2` | `b3,b1,b2` — restored by the second leg, read back from both |
| `q-1`'s `updated_at` | `2026-11-18T16:17:25.634Z` | `2026-11-18T17:05:16.785Z` — the two moves wrote, and the *no-op* third attempt did not (checked with `{"to":"middle"}`: **400**, nothing written) |
| the place route's presence on the probe Mac | not asked | **present**: a move on the *manual* shelf `s-1` answers **400** (the contract's non-queue refusal), which proves the route without writing |

## What no run decided

- **The menu itself.** A `.contextMenu` is a system presentation: `simctl` can neither hold a card nor photograph the popup. What the runs decide is the *rule* (`move-menu=offered` / `absent`) and the *effect* of an item (`LibraryModel.move`, through the app's own door); **the popup with its two rows is the owner's frame.**
- **The two rows' words on screen** (*Move to Top* / *Move to End*) — same reason: they are inside the popup.
- **A drag-to-reorder** does not exist on the phone and is not deferred (the Mac design's non-goal).

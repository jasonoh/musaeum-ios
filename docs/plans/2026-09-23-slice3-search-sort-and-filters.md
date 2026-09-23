# Slice 3 — the phone's library: sorting, search and filters

**Date:** 2026-09-23
**Slice:** 3 of the workstream, in **two stages** — **3a: sort and search**, **3b: filters**. CD8 drew v1 as two slices; this one is **revived from the parent design's own deferred list**, where the item *Search and filters in the client* carried its condition in writing: "revived the first time the owner reaches for search on the phone and it is not there". It fired on 2026-09-23, and the owner settled the three resulting forks in one form the same day (see *The forks, and what was chosen*).
**Annex to:** `docs/specs/2026-09-22-client-v1-design.md`. It settles **readings and wiring**, not product decisions: CD1–CD8 are closed, this document adds no CD number and supersedes nothing.
**Read first:** that design — **CD3** above all (the local-state inventory, which this slice's remembered sort touches) and **CD7** (failure is a surface, because a search is the first thing in the app a sleeping Mac makes *unavailable* rather than *stale*) — then `../musaeum/docs/rest-api.md` → `GET /api/library` (the parameter table, the walk, and the 400 rule) and `GET /api/library/facets`, then `../musaeum/docs/invariants/library-views.md` → *Sorting & Search*, which is the Mac's behaviour this slice **mirrors rather than re-derives**.

---

## What this slice is

1. **A sort control** (3a) — the Mac's own eight curated options with its own wording, driving `sort` and `dir` on every request the library screen makes.
2. **A search field** (3a) — `q`, through the Mac's full-text path, debounced as you type, with the superseded request cancelled rather than raced.
3. **A remembered sort, and deliberately nothing else remembered** (3a) — the chosen sort survives a relaunch; the query and the filters do not.
4. **Filters** (3b) — the axes a text query cannot express (read status, format, a rating floor) plus the facet lists the Mac's sidebar draws from, on a sheet, with an active-filter indicator and one clear control.
5. **An empty state that discriminates** (3a) — "your library has no books in it" and "nothing matches that" are different screens, and this is the first slice where both are reachable.

**What the slice leans on rather than builds.** The wire half already exists and is already decided: `GET /api/library` accepts `sort`, `dir`, `q`, `authors`, `series`, `tags`, `formats`, `readStatus` and `minRating` (`../musaeum/docs/rest-api.md:71-79`), the order runs **server-side on the same stored sort keys the Mac sorts by** (`:125`), and `MusaeumClient.library(limit:offset:sort:direction:query:)` already composes three of them (`Musaeum/Core/API/MusaeumClient.swift:134-148`), decided by `ClientTests.testLibraryRequestCarriesSearchSortAndDirection` (`Tests/MusaeumTests/ClientTests.swift:50`). **No contract change, no Mac-repo slice, no new dependency.** What is missing is entirely the phone's own state and surface: `LibraryModel.start()` calls `client.library(limit:offset:)` and drops all three parameters (`LibraryScreen.swift:49`), and nothing in `Musaeum/` mentions `searchable`, a query or a sort.

**Explicitly not in this slice, and each for a stated reason:**

- **In-book search.** A different feature with a different engine (the Mac's own S1 search over foliate-js), and the phone already has Readium's. Not a debt this slice leaves — it was never in its scope.
- **The downloaded shelf's order.** The shelf is sorted by "most recently downloaded" (`DownloadStore.swift:60`), which is not a library sort; the shelf is small and works with the Mac asleep, which is the property that matters.
- **A local library cache.** CD3's line. A search still needs the Mac, and *that* is what this slice makes newly visible: with the Mac asleep the app can read, and cannot search.
- **Saved searches, search history, recent queries.** All are durable state (CD3) and none was asked for.

## The forks, and what was chosen

The owner settled these on 2026-09-23 in one batched form, recommendations listed first. Recorded here because the *reasons* are what a later session needs, not the outcomes.

| Fork | Chosen | The alternative it beat, as it was written |
| ---- | ------ | ------------------------------------------ |
| **Scope** | **All three** — sort, search and the filter chips (`facets`, `minRating`) — built in **two stages**, because the honest count runs past the house's ~10-file bound and the split is named here rather than discovered in the build | sort + search now, filters as their own follow-on slice |
| **Is the sort remembered?** | **Yes** — "preferably yes, just like the desktop: it's dissonant to come back to a reordered library" | session-only, every launch at Title A–Z, which keeps CD3's inventory at exactly the three kinds it enumerates |
| **Sort while searching** | **The active sort stays live** — the same query on both devices returns the same list in the same order | omit `sort` while `q` is present, so the server's relevance `rank` orders the results (the contract's own default, `:75`, and the thing the Mac deliberately overrides) |

The third one is worth its own sentence, because the contract hints at the same conclusion and this slice is agreeing with it rather than deciding freely: "*with `q` and no `sort` the order is relevance … because a search whose default were title order would disagree with the Mac's own results*" (`rest-api.md:75`). The Mac's renderer always passes the active sort, so relevance decides *which* books match and never their order (`library-views.md:24`, which names the trade-off as deliberate). The phone mirrors it, and the AC that decides it is a *pair*: with a sort chosen and a query active, the request carries both, and the order the server returns is the order shown.

## The readings this slice settles

Each is a rule the approved design left open, with the alternative it beats and the condition that would reverse it.

| Reading | The rule to build | The alternative it beat | Reversal condition |
| ------- | ----------------- | ----------------------- | ------------------ |
| **Which sort options** | the Mac's own eight curated field+direction pairs (`Toolbar.tsx:19-28`) with `sortLabel`'s exact wording (`book.types.ts:200-211`): Title A–Z, Title Z–A, Author A–Z, Series, Recently Added, Oldest First, Highest Rated, Read Status | all twelve field/direction pairs; or six fields with a separate direction toggle (a second control for a question the label already answers) | the owner wants a phone sort the Mac's dropdown does not offer — Author Z–A is the likely one, and it is one row in the list |
| **The direction is always sent explicitly** | every request carries `sort` *and* `dir`, never a bare `sort` | send only the field and let the contract's natural direction decide (its rule is the same rule, `:76`) — rejected because a request whose meaning depends on the *server's* default is a request whose meaning moves when the contract does | never; it costs one query parameter |
| **Whether the query is remembered** | **never** — and this is the Mac's rule, not a simplification: sorting is a preference, a query is a *narrowing*, and a library that opens looking much smaller than it is with the cause off screen is the failure both apps refuse (`library.store.ts:211-213`) | restore it, so you come back to your search | the owner asks for it |
| **Search timing** | debounced **150 ms** after the last keystroke, mirroring `SearchBar.tsx:11-15`, **and the in-flight request cancelled** when a newer keystroke supersedes it | submit-only (one request, explicit, and a phone keyboard makes you find the key while the Mac does not); or no debounce, which is one request per character per cover grid redraw | a search that feels laggy; or the cancellation turning out to lose a result the debounce would have settled |
| **A whitespace-only query is not a search** | the query is **trimmed** before it is judged, so `"   "` is the unfiltered library and `q` is absent from the request — the Mac's own rule (`library.store.ts:123`, `query.trim() ? … : …`) | send it and let the server decide — the contract refuses a malformed *parameter* with 400 (`:129`), and a `q` whose meaning is "whitespace" is exactly the kind of request a client should not compose | never; it is the same rule as "a query of one space is not a search" |
| **When the facets are fetched** (3b) | when the filter sheet is **opened**, not with each library page | with every page — a request per page for counts nobody has asked to see, on a screen whose whole cost model is "latency-bound" (the contract's own words, `:353`) | a filter sheet that feels slow to open |
| **Which facet values are offered** (3b) | the arrays the contract already returns, in the order it returns them (**count descending**), each list **narrowable by typing** | a client-side rank, or a top-N cut with no way to reach the tail — the real library's `authors` facet is **3,727 values**, so a list without a narrow field is a list nobody reaches the bottom of | the owner reports a facet he cannot reach |
| **What the filter sheet shows as "selected"** | the filters the *client* is applying, and the counts it shows are the contract's own: **not narrowed by the list route's filters** (`:170`), so a count stays still as you tick boxes | recompute counts against the current selection — that needs a request per tick and is what makes a facet count flicker | never; the contract's arrangement is the better one and this slice simply displays it |

**One thing the design already settled that this slice must not re-open:** the *sort* is a preference and goes in `UserDefaults` beside the base URL, so CD3's sentence — "the app holds exactly three kinds of local state, and no fourth" — stays true as written. A sort is not a fourth *kind*; it is a setting, and the owner chose the desktop's behaviour for it. **The query and the filters are not settings** and are not stored, which is what keeps the inventory honest: what is persisted is a *view preference*, never a narrowing of the library.

## Files

The count is honest rather than imagined, and the split is named here rather than discovered in the build.

**Stage 3a — sort and search (11 files: 4 code, 2 test, 4 documents, 1 script — over the ~10 house bound, which is why the stage exists)**

| # | Path | What changes |
| - | ---- | ------------ |
| 1 | `Musaeum/Core/API/LibraryQuery.swift` **(new)** | The pure heart, and the whole reason the sorting rule is testable without a view: the eight curated options, their labels, the wire `sort`/`dir` each produces, the guard against a stored preference from a build that no longer knows it, the query normalisation (trim) that decides "a search or the whole library", and the two "nothing to show" screens. **Landed under this name rather than the draft's `LibrarySort.swift`**, and the name is the point: the file carries the query and the empty state as well as the sort, so it is named for the concern — *what the screen is asking the Mac for* — rather than for one of its three parts |
| 2 | `Musaeum/Features/Library/LibraryScreen.swift` | The model gains `query`, `sort`, and a **generation counter** so a superseded response cannot land; every request — first page and every page after it — is composed from them; the empty state discriminates; the view gains `.searchable` (always shown, not revealed by scrolling) and the sort `Menu` in the toolbar |
| 3 | `Musaeum/Core/Store/SettingsStore.swift` | `librarySort` read at init and written on change, one `UserDefaults` key beside the base URL |
| 4 | `Musaeum/Core/Support/Probe.swift` | `MUSAEUM_PROBE_QUERY` and `MUSAEUM_PROBE_SORT`, so a search and a sort can be driven with no tap — the same seam `ACTION=write` gave slice 2 |
| 5 | `Tests/MusaeumTests/LibrarySortTests.swift` **(new)** | The pure rules: every option's wire pair is one the contract accepts; the default is Title A–Z; the guard refuses an unknown stored value and accepts a known one; the trim rule |
| 6 | `Tests/MusaeumTests/LibraryQueryTests.swift` **(new)** | The model's behaviour over a stubbed `URLProtocol`, where the discrimination lives: the query and sort ride on page 2 as well as page 1; a superseded response does not land; a whitespace-only query is not a search; the two empty states |
| 7 | `scripts/live-probe.sh` | `TAG=search` and `TAG=sort` recipes in the header and the seam they pass |
| 8 | `docs/plans/2026-09-23-slice3-search-sort-and-filters.md` | This annex |
| 9 | `docs/specs/2026-09-22-client-v1-design.md` | The revival recorded **in place** at the deferred entry, the slice table, and *Built — slice 3a/3b* on landing |
| 10 | `tasks.md` | A slice-3 section beside the other two, and the deferred bullet marked revived |
| 11 | `CHANGELOG.md` | User-facing: what you can now do on the phone |

**Stage 3b — filters (~6 files: 3 code, 1 test, 2 documents)**

| # | Path | What changes |
| - | ---- | ------------ |
| 12 | `Musaeum/Core/API/LibraryFilters.swift` **(new)** | The filter model and its wire composition: read status, format, rating floor, plus the author/series/tag selections — and the rule that an **empty** selection omits its parameter rather than sending an empty one (the contract refuses a bad *value* with 400 — `formats=docx` — but **not** `formats=`, which it reads as absent: measured 2026-09-23 against the probe server, it answers the whole 8-book library) |
| 13 | `Musaeum/Features/Library/FilterSheet.swift` **(new)** | The sheet: two segmented rows (read status, format), a rating row, and **one** reusable facet picker used by author, series and tags — a count-ordered list with a narrow-as-you-type field, because 3,727 authors is not a browsable list |
| 14 | `Musaeum/Features/Library/LibraryScreen.swift` | Facets fetched when the sheet opens; the active-filter state carried into every page request like the query; the toolbar gains the indicator and its clear control |
| 15 | `Tests/MusaeumTests/LibraryFilterTests.swift` **(new)** | The pure rules (empty omits, values are the contract's own, `minRating` is a whole number in range) plus the model half: filters ride on page 2, and clearing them restores the unfiltered library |
| 16-17 | `docs/specs/…-client-v1-design.md`, `tasks.md`, `CHANGELOG.md` | *Built — slice 3b* and the changelog entry |

**Files the budget row did not imagine, added because the criteria reach them:** the generation guard lives in the model (file 2), not in a file of its own; and `LibraryQueryTests` (file 6) is a second test file rather than a section of the first, because the pure rules and the model's behaviour fail for different reasons and one file would hide which.

## Acceptance criteria

Numbered `3.x`, following slice 2's `2.x`. Slice 1's 14 and slice 2's ten are **unchanged and unrenumbered**; where a criterion here sharpens one of theirs, it is named.

| # | Criterion | Decider |
| - | --------- | ------- |
| 3.1 | **The library screen offers the Mac's own eight sort options with the Mac's own wording and the Mac's default** (Title A–Z) | `LibrarySortTests`: the option list equals the eight field/direction pairs, each label equals `sortLabel`'s text for that pair, and the default is Title A–Z |
| 3.2 | **Every option produces a `sort`/`dir` pair the contract accepts** — so a typo cannot become a 400 the user sees as a broken library | `LibrarySortTests`: each option's `field` is in the contract's six and its `direction` is `asc`/`desc` |
| 3.3 | **Every library request carries the active sort and direction, and the query when there is one** — page 1 and page 2 alike | `LibraryQueryTests`: the stub records the requests; after a query and a sort are set, page 2's request carries the same `q`, `sort` and `dir` as page 1's |
| 3.4 | **A whitespace-only query is not a search** — `q` is absent and the library is unfiltered | `LibrarySortTests` for the normalisation rule, `LibraryQueryTests` for the request that results |
| 3.5 | **A superseded search does not land.** With two requests in flight, the older response must not replace the newer one's results | `LibraryQueryTests`: the stub holds the first response until the second has answered, then releases it; the books on screen are the second query's |
| 3.6 | **The two empty states are different screens.** A library with no books says so; a query that matched nothing says *that*, names the query, and offers to clear it | `LibraryQueryTests` over the model's own state, and the live probe's frame for the search that matches nothing |
| 3.7 | **The chosen sort survives a relaunch, and the query does not** | two deciders, because the halves fail for different reasons: `LibrarySortTests` over a scratch `UserDefaults` suite (a fresh store reads back the stored sort), and `LibraryQueryTests` for the funnel — after a search *and* a sort change, the whole container holds exactly one key, `musaeum.librarySort`. Asserted one field at a time, "the query is not remembered" would pass while a second key was written beside the first; comparing the container is what makes it a measurement rather than an absence |
| 3.8 | **A stored sort the current build does not know does not crash and does not leak into a request** — the guard falls back to the default | `LibrarySortTests`: an unknown stored value decodes to the default option |
| 3.9 | **Search and sort both work against the real library**, read off the app's own log with no tap | the **live probe**: a `sort=author:desc` run whose logged order is the reverse of the `title` run's, and a `QUERY=` run whose logged total is smaller than the library's own count and whose books all match |
| 3.10 | **The filter sheet offers read status, format and a rating floor, and the facet lists for author, series and tags** | the live probe's frame, plus `LibraryFilterTests` for the model the sheet binds to |
| 3.11 | **An empty selection omits its parameter** rather than sending an empty one | `LibraryFilterTests`: with every filter cleared, the composed query items contain no `formats`, no `readStatus`, no `minRating`, no `authors` |
| 3.12 | **Filters ride on every page, and clearing them restores the library** — the same trap as 3.3, one axis further | `LibraryFilterTests`: page 2 carries the same filters as page 1; clearing re-fetches with none |
| 3.13 | **A filter the user cannot see the cause of does not accumulate.** With a filter active, the library screen says so and offers one control that clears all of them | the live probe's frame; and the model's own `hasActiveFilters`. **This criterion is 3a's costliest lesson applied one control over:** a toolbar renders a `Label` **icon-only**, so the sort control shipped a bare ⇅ glyph through two builds — the second one adding `.labelStyle(.titleAndIcon)`, which did not override it — and only a committed frame caught it. An active-filter indicator built as a `Label` will vanish the same way, so decide this one in a **frame**, never by reading the view's source |
| 3.14 | **Nothing new carries the token, and no `file://` appears** | slice 1's AC13 source walk, re-run on this slice's tree |
| 3.15 | **Gates.** `xcodebuild build` and `xcodebuild test` both exit 0 on the slice's own tree, the count reported per file | the two commands |

**Two criteria are deliberately absent, and saying so is the point.** There is no criterion for *typing* in the search field or *tapping* a sort option: `simctl` can drive neither, so the claim that a tap opens the sort menu is **a claim for a human frame** — the same honest limit slice 2 recorded for the background door. What the probe *can* decide is that the app's own path from state to request to rendered order is right, through the same seam, and that is 3.9.

## What must not move

- **CD3's inventory.** The remembered sort is a setting beside the base URL; the **query and the filters are not stored at all**, and no local library cache arrives with them.
- **CD5's rule and slice 2's write.** The reader's opening position and the report path are untouched; nothing here reports or reads progress.
- **The token.** It stays in the Keychain and in the `Authorization` header, and no log line carries it (AC13's walk must still be clean here).
- **Slice 1 and 2's criteria.** All 61 cases stay green; anything this slice changes is **added**, never renumbered.
- **The contract.** Nothing in this slice changes a payload, a parameter or a status code. A field it needs and the document does not name would make this a Mac-repo slice; it needs none.

## Verification plan

1. `xcodegen generate` **first** — a file added since the last generate is absent from the target, the suite re-runs, the total does not move, and the criterion has no decider while everything reads pass (slice 1's trap 12). Read the **per-file** line, not the total.
2. The two gates, exit 0, with the count per file and the expected values quoted from the tree as built.
3. **A mutation campaign over the criteria that have a unit decider**, one mutation per criterion, each naming its file, its exact anchor and the one suite that must redden — `scripts/swift-campaign.py` in the `musaeum-ios-client` skill, with `--baseline` so a red row is known to mean an assertion failed. Budget ~8 minutes per row on this repo. The interesting rows, and the ones written down before the campaign so it cannot quietly become a count: the query dropped from **page 2 only** (the trap 3.3 exists for); the generation guard removed (3.5); the trim rule removed (3.4); the empty state collapsing its two cases (3.6); the stored sort written but never read (3.7); the guard removed (3.8); an empty selection *sent* rather than omitted (3.11); filters dropped from page 2 (3.12).
4. **The live probe**, as the app's own instrument: a library run (the control), a `SORT=` run and a `QUERY=` run for 3a, and a filtered run for 3b. The decider is the app's own log line — the total and the order — plus a frame per run, committed to `docs/evidence/slice3/`.
5. The AC13 source walk, re-run.
6. `../musaeum/scripts/api-smoke.sh` against the same server, because a client that agrees with a stub and not with the server is the expensive failure.

## The probe: what each run must read

Measured against the probe profile's own server on 2026-09-23, **before** the runs, so a frame that disagrees with this table is a finding rather than a judgement call. The profile holds 8 books. The decider is the **last** `library page` line in `probe.log`, because the seam applies `SORT` and then `QUERY`: a run that names either logs two or three of them, and only the last one describes where the screen settled.

| Run | the last `library page` line | the frame |
| --- | ---------------------------- | --------- |
| `TAG=library SORT=title:asc` | `count=8 total=8 … sort=title:asc q=- first=Caliban's war | Dragon Wing | The Hidden Palace` | `Caliban's war`, `Dragon Wing`, `The Hidden Palace`, `In Defense of Selfishness`, `Last Tango in Cyberspace`, `Negotiation Genius`, `Run`, `The Self-Driven Child` — the control |
| `TAG=sort SORT=author:desc` | `count=8 total=8 … sort=author:desc q=- first=The Self-Driven Child | Dragon Wing | The Hidden Palace` | `The Self-Driven Child`, `Dragon Wing`, `The Hidden Palace`, … — **a different first title**, which is the whole reason this run can decide anything |
| `TAG=kept` (no `SORT`) | `count=8 total=8 … sort=author:desc q=- first=The Self-Driven Child | Dragon Wing | The Hidden Palace` | unchanged from the run above, and this is the persistence: the only run that can decide it |
| `TAG=search QUERY=negotiation` | `count=1 total=1 … q=negotiation first=Negotiation Genius` | one cover, `Negotiation Genius`; a total **below** the library's own 8 |
| `TAG=nomatch QUERY=zzzz` | `count=0 total=0 … q=zzzz first=` (nothing), then `library empty kind=noMatches("zzzz") macBooks=8` | "Nothing matches" — two screens apart, and `macBooks=8` is what makes it *no matches* rather than *empty library* |

Two things this settles that no unit case can. The phone's two orders must be **the Mac's own**: the two lists above are what the Mac's own server returns for those parameters, so a phone rendering its own idea of "author Z–A" would show a different first title. And a search's total must be the **server's** `1`, not the phone's page length — which is what makes the difference between a search and a filter of the page in hand.

**What these runs cannot decide, said plainly:** none of them taps anything. `simctl` can neither open the sort menu nor type in the search field, so *the menu opens* and *the field accepts typing* are claims for a human frame — the same honest limit slice 2 recorded for the background door. What is decided is the app's own path, state → request → rendered order, through the same seam.

Also measured, and kept because it is why the guard in `LibrarySort.stored` is load-bearing rather than tidy: `GET /api/library?sort=athor` answers **400 `{"error":"bad request"}`**, and `?dir=sideways` likewise. The contract *refuses* rather than defaulting, so a stored preference this build no longer knows would reach the reader as a broken library instead of the wrong order.

**3b's own runs, measured the same way before they were taken** (filters are independent of a term and of a sort, so they run in any order; the decider is again the last `library page` line): `FILTERS='status=reading'` → `count=2 total=2 filters=status=reading`; `FILTERS='status=unread;format=epub'` → `count=6 total=6` (two axes **ANDed**); `FILTERS='status=read'` → `count=0 total=0` and then `library empty kind=noFilterMatches(1) macBooks=8`; `SHEET=1` → `facets authors=8 series=2 tags=27 formats=epub:8 statuses=unread:6,reading:2`. All five landed as written. Three things they settled that no unit case could, and the record of each is in *Built — slice 3b*:

- **The multi-value parameter is comma-separated, so a facet value containing a comma cannot be expressed through it.** The Authors row is the Mac's own list, and one of its eight values on this profile is `William Stixrud, PhD`. A filter naming it returns **0** (measured through the app: `count=0 … filters=author=William Stixrud, PhD`), where the comma-less `Steven Kotler` from the same list returns **1**. Left standing — the fix is an encoding the contract does not have — and worth knowing because it is the one place a filter the sheet *offers* is a filter that finds nothing.
- **A parameter *name* the server does not know is ignored, not refused**: `?status=reading` returns all 8 where `?readStatus=reading` returns 2. A typo in a name therefore cannot produce an error, only a request that quietly asks for less — which is why the probe seam reports the token it carried (`TAG=unknown FILTERS=nonsense=1` logs `probe: filters 'nonsense=1' carried nonsense=1, which this build does not know`).
- **An empty selection composes no parameter, but the server would not have punished one**: `formats=` answers the whole library. 3.11 is the client's own hygiene, not a rule the server enforces — the correction above.

And one reading that answers the question the slice started from: **`q` is not title-only.** It searches title, author, tags — the `series:` tags included — *and* description. Evidence, on the same 8 books: a word chosen to exist only in one description (`dragonlance`, from `Dragon Wing`) finds that book; `Kotler` (an author) finds one; `interplanetary` and `expanse` (tags) each find one; `zzzz` finds none. So descriptions are not something this slice builds — they are part of the path the phone was pointed at.

## Start here

```bash
git log --oneline -3
# the base this annex was written against: 7fcb29c (the Connect screen's settings row), one ahead of origin/main fe9a4e8
# 3a and 3b are built on top of it in the working tree (the owner commits this repo himself), so a "did
# my new case run?" check compares against **90/12**, not 61/9 — and reads the per-suite line, not the total

xcodegen generate     # first, always: a file added since the last generate is not in the target
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro, iOS 26.1 — an id, never a name
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD build   # exit 0
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" -derivedDataPath ./DD test    # 61/9 when this annex was written; **90 cases, 0 failures, 12 suites after 3a and 3b**

# the live probe (its header carries the server recipe; it refuses to run without base.txt + token.txt)
TAG=library ./scripts/live-probe.sh
TAG=search QUERY=negotiation ./scripts/live-probe.sh      # built by 3a
TAG=sort   SORT=author:desc  ./scripts/live-probe.sh      # built by 3a
TAG=filters      FILTERS='status=reading' ./scripts/live-probe.sh             # built by 3b: 2 of the 8
TAG=narrow       FILTERS='status=unread;format=epub' ./scripts/live-probe.sh  # two axes ANDed: 6
TAG=filter-empty FILTERS='status=read' ./scripts/live-probe.sh                # the card names the FILTER
TAG=sheet        SHEET=1 ./scripts/live-probe.sh                              # the sheet, with the Mac's counts
```

Then, in order: `Musaeum/Core/API/LibraryQuery.swift`, `Musaeum/Features/Library/LibraryScreen.swift` (the model above the view), `Musaeum/Core/Store/SettingsStore.swift`, then the two test files. 3b then adds `Musaeum/Core/API/LibraryFilters.swift`, `Musaeum/Features/Library/FilterSheet.swift` and `Tests/MusaeumTests/LibraryFilterTests.swift`, and edits `LibraryQuery.swift`, `MusaeumClient.swift` and `LibraryScreen.swift` again — a file that lands in a *later* stage of a slice is named here rather than left for the next session to grep for.

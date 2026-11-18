#!/usr/bin/env python3
"""stub-old-mac.py — the one Mac this machine cannot otherwise build.

The reading-queue wire landed on the Mac in one slice: a `kind: "queue"` entry on
`GET /api/shelves` **and** `PUT /api/shelves/{id}/books/{bookId}/position` arrived
together, so a Mac old enough to lack the route also has no queue to open — and the
phone's Move menu would be absent for a reason that decides nothing about the 404
reading. This stub is the state that *is* worth deciding: a Mac that serves a queue
and answers **404** to the place route, which is the contract's own sentence for a
build without it ("the move menu is absent, rather than failing, against a Mac that
answers 404 here").

It is a **server-side** stand-in, not a client change: the app under test is the
real build, and nothing in `Musaeum/` knows this thing exists.

What it serves, from the repo's own vendored contract fixtures (never a hand copy):

    GET  /api/health                       the health golden
    GET  /api/shelves                      the shelves golden — one manual shelf, one queue
    GET  /api/library[?shelf=<id>]         three books in the queue's order (b3, b1, b2)
    GET  /api/library/facets               an empty-but-well-formed facet payload
    PUT  /api/shelves/{id}/books/{id}/position   404, and nothing else
    anything else                          404

Usage (the probe reads a real Mac elsewhere; this one exists for AC16's second half):

    python3 scripts/stub-old-mac.py --port 8798 &
    TAG=stub BASE=http://127.0.0.1:8798 TOKEN=stub \\
      ACTION=shelf-move SHELF=<queue id> MOVE_BOOK=b2 TO=top ./scripts/live-probe.sh

`TOKEN` is accepted but not checked — this stub holds no library and no secret, and
saying so is better than pretending it authenticates.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(REPO, "Tests", "Fixtures", "contract")

QUEUE_BOOKS = [("b3", "Charlie"), ("b1", "Alpha"), ("b2", "Bravo")]


def fixture(name: str) -> dict:
    with open(os.path.join(FIXTURES, f"{name}.json"), encoding="utf-8") as handle:
        return json.load(handle)


def library_page(shelves: list[dict], shelf_id: str | None) -> dict:
    """The queue's own order, in the contract's `library` shape.

    The books are the golden's own book, re-identified — the decoder is strict, and a
    hand-typed book would be a second copy of the wire.
    """
    golden = fixture("library")
    template = golden["books"][0]
    books = []
    for index, (book_id, title) in enumerate(QUEUE_BOOKS):
        book = copy.deepcopy(template)
        book["id"] = book_id
        book["title"] = title
        book["shelves"] = [shelf_id] if shelf_id else []
        books.append(book)
    return {
        "books": books,
        "total": len(books),
        "limit": 100,
        "offset": 0,
        "nextOffset": len(books),
        "isLastPage": True,
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # one line per request, so a run's calls are legible
        sys.stderr.write("stub %s %s\n" % (self.command, self.path))

    def _send(self, status: int, payload: dict | bytes, content_type: str = "application/json"):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _route(self):
        url = urlparse(self.path)
        path, query = url.path, parse_qs(url.query)
        shelves = fixture("shelves")
        queue = next(s for s in shelves["shelves"] if s["kind"] == "queue")

        if path == "/api/health":
            return self._send(200, fixture("health"))
        if path == "/api/shelves":
            return self._send(200, shelves)
        if path == "/api/library/facets":
            return self._send(200, {"authors": [], "series": [], "tags": [], "formats": [], "readStatus": []})
        if path == "/api/library":
            shelf = (query.get("shelf") or [None])[0]
            return self._send(200, library_page(shelves["shelves"], shelf if shelf == queue["id"] else None))
        if path.endswith("/position"):
            # The one answer this stub exists for: a build without the route. The
            # contract's uniform 404, reason-free — and nothing is written, because
            # there is nothing here to write to.
            return self._send(404, {"error": "not found"})
        return self._send(404, {"error": "not found"})

    def do_GET(self):
        self._route()

    def do_HEAD(self):
        self._route()

    def do_PUT(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        self._route()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8798)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()

    queue = next(s for s in fixture("shelves")["shelves"] if s["kind"] == "queue")
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"stub-old-mac listening on http://{args.bind}:{args.port}", flush=True)
    print(f"  queue id {queue['id']} — serves a queue, answers 404 to /position", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

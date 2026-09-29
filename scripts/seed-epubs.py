#!/usr/bin/env python3
"""The probe profile's books: EPUBs with covers, written into
`{library_root}/imports/`, where the Mac's own watcher imports them.

**This is seeding, not an instrument.** Nothing it does decides anything about
this app; it exists so a probe profile can be rebuilt in one command when
`~/.hermes/profiles/dev/cache/scratch` is pruned, which is where the live probes
get their library from (`scripts/live-probe.sh`'s header has the rest of the
recipe).

The four parts of an EPUB are assembled the way `sidecar/tests/test_epub_metadata.py`'s
fixtures assemble them — the `mimetype` entry first and stored, then
`META-INF/container.xml`, the OPF, and a cover the OPF declares with
`<meta name="cover" …>` — so the Mac's extractor reads it exactly as it reads a
real book. Covers are generated rather than downloaded, so a run needs no network
and the frames show a grid that is *distinguishable* covers rather than eight
identical placeholders. The identifiers are real ISBNs, which is what makes the
Mac hydrate titles and authors through its own pass instead of leaving the
embedded ones.

    python3 seed-epubs.py <library_root>/imports
"""

import pathlib
import sys
import zipfile

from PIL import Image, ImageDraw

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

# Title, author, ISBN.
BOOKS = [
    ("The Partnership", "Philip Taubman", "9780805095770"),
    ("The Changing Face of Empire", "Nick Turse", "9780805089649"),
    ("Boss Rove", "Craig Unger", "9781439160957"),
    ("The Revolt Against the Masses", "Fred Siegel", "9781594036745"),
    ("The Prince", "Niccolo Machiavelli", "9780192807281"),
    ("The Divide", "Matt Taibbi", "9780812993434"),
    ("Shattered", "Jonathan Allen", "9780553447088"),
    ("Wickedness", "Mary Midgley", "9780415253987"),
]

PALETTE = [
    (32, 44, 68), (120, 44, 38), (28, 76, 60), (86, 60, 24),
    (58, 34, 82), (24, 66, 84), (104, 30, 66), (44, 48, 40),
]


def cover(initials: str, colour: tuple, path: pathlib.Path) -> None:
    """A 2:3 jacket: the Mac's own cover box, in a flat colour with a rule."""
    image = Image.new("RGB", (400, 600), colour)
    draw = ImageDraw.Draw(image)
    draw.rectangle([28, 28, 372, 572], outline=(232, 226, 210), width=4)
    draw.rectangle([70, 120, 330, 480], outline=(232, 226, 210), width=2)
    draw.text((150, 290), initials, fill=(238, 232, 216))
    image.save(path, "JPEG", quality=88)


def epub(title: str, author: str, isbn: str, initials: str, colour: tuple, out: pathlib.Path) -> None:
    opf = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>{title}</dc:title>
    <dc:creator opf:role="aut">{author}</dc:creator>
    <dc:identifier id="bookid" opf:scheme="ISBN">{isbn}</dc:identifier>
    <dc:language>en</dc:language>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg"/>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="content"/>
  </spine>
</package>
"""
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head>
<body><h1>{title}</h1><p>{author}</p><p>Seed copy for the client's live probe.</p></body></html>
"""
    tmp_cover = out.with_suffix(".jpg")
    cover(initials, colour, tmp_cover)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER)
        z.writestr("OEBPS/content.opf", opf)
        z.writestr("OEBPS/content.xhtml", body)
        z.writestr("OEBPS/images/cover.jpg", tmp_cover.read_bytes())
    tmp_cover.unlink()


def main() -> None:
    dest = pathlib.Path(sys.argv[1])
    dest.mkdir(parents=True, exist_ok=True)
    for i, (title, author, isbn) in enumerate(BOOKS):
        initials = "".join(word[0] for word in title.split()[:2]).upper()
        path = dest / f"{title} - {author}.epub"
        epub(title, author, isbn, initials, PALETTE[i % len(PALETTE)], path)
        print(f"seeded {path.name} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

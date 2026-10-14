#!/usr/bin/env python3
"""The Ask pass's test books: synthetic, multi-chapter EPUB 2s with numbered paragraphs, so the
true position of any paragraph in the extracted text is computable without reading a page.

    python3 -I make-test-book.py <out_dir>

Writes two books:
  * "The Ledger of Small Hours" (A. Fixture): five chapters of 12-60 thousand characters, curly
    quotes and em-dashes throughout and one emoji in chapter two (a UTF-16 surrogate pair).
    Not one section is over 200,000 UTF-16 units.
  * "The Long Appendix" (A. Fixture): a single ~230,000-unit chapter, to see the cap.

Also writes `<out_dir>/<slug>.sections.json`: per spine file, the pieces as the phone's extraction
should see them (heading, then each paragraph) so the true offset of a paragraph is a lookup.
Text is generated, not taken from any book.
"""
import json
import pathlib
import random
import sys
import zipfile

from PIL import Image, ImageDraw

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""

WORDS = ("harbour lantern ledger tide copper margin orchard vessel winter signal quarry meadow "
         "cipher timber archive bridge compass furnace garden harvest island journal kettle "
         "lattice mirror needle outpost pillar quiver ribbon saddle thistle umbrella valley "
         "weather yarrow zephyr anchor beacon cistern dovetail ember fathom gable hearth").split()


def sentence(rng, n):
    words = [rng.choice(WORDS) for _ in range(rng.randint(9, 17))]
    words[0] = words[0].capitalize()
    tail = "“quoted”" if rng.random() < 0.2 else ""
    dash = " — and then" if rng.random() < 0.15 else ""
    return " ".join(words) + dash + (" " + tail if tail else "") + "."


def paragraph(rng, chapter, n, emoji=False):
    body = " ".join(sentence(rng, n) for _ in range(rng.randint(3, 6)))
    face = " \U0001F4DA" if emoji else ""
    return f"Paragraph {n} of chapter {chapter}.{face} {body}"


def build(out_dir, slug, title, author, isbn, chapter_sizes, colour, seed):
    rng = random.Random(seed)
    spine, manifest, ncx, sections = [], [], [], []
    files = {}
    for ci, size in enumerate(chapter_sizes, start=1):
        heading = f"Chapter {ci}: {['The Quay','The Counting House','The Long Shelf','The Salt Road','The Last Lamp','The Tally','The Reckoning'][(ci-1) % 7]}"
        pieces = [heading]
        total = len(heading)
        n = 0
        while total < size:
            n += 1
            p = paragraph(rng, ci, n, emoji=(ci == 2 and n == 3))
            pieces.append(p)
            total += len(p) + 1
        html = ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><title>%s</title></head>\n<body><h1>%s</h1>\n%s\n</body></html>\n'
                % (heading, heading, "\n".join(f"<p>{p}</p>" for p in pieces[1:])))
        files[f"OEBPS/ch{ci}.xhtml"] = html
        manifest.append(f'<item id="ch{ci}" href="ch{ci}.xhtml" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="ch{ci}"/>')
        ncx.append(f'<navPoint id="n{ci}" playOrder="{ci}"><navLabel><text>{heading}</text></navLabel><content src="ch{ci}.xhtml"/></navPoint>')
        sections.append({"href": f"ch{ci}.xhtml", "heading": heading, "pieces": pieces})
    opf = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>{title}</dc:title><dc:creator opf:role="aut">{author}</dc:creator>
    <dc:identifier id="bookid" opf:scheme="ISBN">{isbn}</dc:identifier><dc:language>en</dc:language>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg"/>
    {''.join(manifest)}</manifest>
  <spine toc="ncx">{''.join(spine)}</spine>
</package>
"""
    toc = ('<?xml version="1.0" encoding="utf-8"?>\n<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/>'
           f'<docTitle><text>{title}</text></docTitle><navMap>{"".join(ncx)}</navMap></ncx>\n')
    img = Image.new("RGB", (400, 600), colour)
    d = ImageDraw.Draw(img)
    d.rectangle([28, 28, 372, 572], outline=(232, 226, 210), width=4)
    cover = out_dir / f"{slug}.cover.jpg"
    img.save(cover, "JPEG", quality=88)
    path = out_dir / f"{title} - {author}.epub"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER)
        z.writestr("OEBPS/content.opf", opf)
        z.writestr("OEBPS/toc.ncx", toc)
        z.writestr("OEBPS/images/cover.jpg", cover.read_bytes())
        for name, html in files.items():
            z.writestr(name, html)
    cover.unlink()
    (out_dir / f"{slug}.sections.json").write_text(json.dumps(sections, ensure_ascii=False))
    print(path.name, {s["href"]: sum(len(p.encode("utf-16-le")) // 2 for p in s["pieces"]) + len(s["pieces"]) - 1 for s in sections})


def main():
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    build(out, "ledger", "The Ledger of Small Hours", "A. Fixture", "9780000000001",
          [30000, 16000, 60000, 22000, 12000], (28, 76, 60), 7)
    build(out, "appendix", "The Long Appendix", "A. Fixture", "9780000000002",
          [230000], (120, 44, 38), 11)


main()

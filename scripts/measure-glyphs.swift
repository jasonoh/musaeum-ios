// measure-glyphs.swift — the glyph ink boxes in a probe frame.
//
// A claim about a glyph's size, or about two glyphs being level, is a claim about
// pixels, and this repo's rule is that such a claim is a *reading* rather than a
// source read. It has been measured three times now (the library bar's four
// controls, the cover box, the downloaded shelf's row) and the instrument has
// been rebuilt from scratch each time — this is it, so the fourth measurement is
// one command.
//
//   swift scripts/measure-glyphs.swift frame-downloads.png 380 620
//
// The frame comes off `scripts/live-probe.sh` (3× on this device, so **divide px
// by 3 for points**). The band is the row of glyphs you mean: a sheet of symbols
// on one line is one run per glyph, in x order, which is what makes "these two
// are the same size" and "these two are level" two numbers instead of an
// adjective. Ink is luminance above `threshold` (default 0.45), which is bright
// enough to skip this palette's near-black surfaces and dark enough to catch the
// muted glyphs; the gold read glyph and the muted share glyph both clear it.
//
// What each line gives you, in the order the questions get asked:
//   `w`  — the glyph's ink width, and `h` its ink height (the number two glyphs
//          in a row must share to read as one set)
//   `y`  — the ink's top and bottom, and `centreY` the line they sit on
//   `rgb` — the average colour of the ink, which is how the run list tells a
//          gold glyph from a muted one, and the artwork from the type
//
// One caveat worth knowing before trusting a run: a *thin* mark at the band's
// edge (a separator, a hairline border) is ink too. Read the runs against the
// frame, and give the band the row you mean rather than a generous slice of it.
import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: measure-glyphs.swift <png> [y0 y1] [threshold]\n".data(using: .utf8)!)
    exit(2)
}
let path = args[1]
let threshold = args.count > 4 ? Double(args[4])! : 0.45

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    exit(1)
}
let w = image.width, h = image.height
var buffer = [UInt8](repeating: 0, count: w * h * 4)
let context = CGContext(
    data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
// Row 0 of this buffer is the image's **top** row, verified against a known crop.

let y0 = args.count > 2 ? max(0, Int(args[2])!) : 0
let y1 = args.count > 3 ? min(h - 1, Int(args[3])!) : h - 1

func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let o = (y * w + x) * 4
    return (Int(buffer[o]), Int(buffer[o + 1]), Int(buffer[o + 2]))
}

func ink(_ x: Int, _ y: Int) -> Bool {
    let (r, g, b) = rgb(x, y)
    return 0.2126 * Double(r) / 255 + 0.7152 * Double(g) / 255 + 0.0722 * Double(b) / 255 > threshold
}

struct Run { var minX: Int; var maxX: Int; var minY: Int; var maxY: Int; var n: Int; var sr: Int; var sg: Int; var sb: Int }

print("measure \(w)x\(h) band y=[\(y0)…\(y1)] threshold \(threshold)")
var run: Run?
var runs: [Run] = []
for x in 0..<w {
    var minY = Int.max, maxY = -1, n = 0
    var sr = 0, sg = 0, sb = 0
    for y in y0...y1 where ink(x, y) {
        minY = min(minY, y); maxY = max(maxY, y); n += 1
        let (r, g, b) = rgb(x, y); sr += r; sg += g; sb += b
    }
    if n == 0 {
        if let r = run { runs.append(r); run = nil }
        continue
    }
    if var r = run {
        r.maxX = x; r.minY = min(r.minY, minY); r.maxY = max(r.maxY, maxY)
        r.n += n; r.sr += sr; r.sg += sg; r.sb += sb
        run = r
    } else {
        run = Run(minX: x, maxX: x, minY: minY, maxY: maxY, n: n, sr: sr, sg: sg, sb: sb)
    }
}
if let r = run { runs.append(r) }

// A one-pixel-wide run is a hairline or a period, not a glyph: it is reported
// (nothing is silently dropped) but flagged, because a glyph's ink is never that.
for r in runs where r.maxX - r.minX >= 1 {
    print(String(format: "x %4d…%4d (w %3d)  y %4d…%4d (h %3d)  px %5d  avg rgb %3d,%3d,%3d  centreY %.1f%@",
                 r.minX, r.maxX, r.maxX - r.minX + 1, r.minY, r.maxY, r.maxY - r.minY + 1, r.n,
                 r.sr / max(r.n, 1), r.sg / max(r.n, 1), r.sb / max(r.n, 1),
                 Double(r.minY + r.maxY) / 2, r.n < 12 ? "  (thin — check it against the frame)" : ""))
}

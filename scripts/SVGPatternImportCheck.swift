//
//  SVGPatternImportCheck.swift
//  EXP [design] — standalone verification for FEAT-062 (pattern import + render)
//  and BUG-060 (percentage lengths).
//
//  The regression these fixtures represent: a generated background whose entire
//  design hangs off `<rect fill='url(#p)' width='100%' height='100%'/>` imported
//  as ONE FLAT COLOUR — the carrier rect was dropped by a `guard w > 0` before
//  its fill was ever resolved, and the pattern behind it was unsupported anyway.
//
//  So the test that matters is not "did a PatternSource appear" but "does the
//  rendered artboard stop being flat". Both are asserted, plus the tile geometry
//  read straight out of each file, so a pattern that imports at the wrong size or
//  transform fails rather than passing on colour variety alone.
//

import AppKit
import Foundation

@main
enum SVGPatternImportCheck {

static var failures: [String] = []
static var checks = 0

static func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ok   \(label)")
    } else {
        let d = detail()
        print("  FAIL \(label)\(d.isEmpty ? "" : " — \(d)")")
        failures.append(label)
    }
}

/// Fraction of sampled pixels that are NOT the single most common colour.
///
/// Deliberately not a distinct-colour COUNT. A count of 8 sounded like proof and
/// was not: `hexline-weave-neon` rendered 99% flat background with a few faint
/// gradient shapes and still scored well above 8, so the check passed on an image
/// that was visibly broken. "How much of the picture is not the background" is
/// the thing actually being claimed.
static func nonDominantFraction(inPNG data: Data) -> Double {
    guard let rep = NSBitmapImageRep(data: data) else { return 0 }
    var histogram: [UInt32: Int] = [:]
    var total = 0
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let stepX = max(1, w / 96), stepY = max(1, h / 96)
    var y = 0
    while y < h {
        var x = 0
        while x < w {
            if let c = rep.colorAt(x: x, y: y) {
                let r = UInt32(max(0, min(255, c.redComponent * 255)))
                let g = UInt32(max(0, min(255, c.greenComponent * 255)))
                let b = UInt32(max(0, min(255, c.blueComponent * 255)))
                histogram[r << 16 | g << 8 | b, default: 0] += 1
                total += 1
            }
            x += stepX
        }
        y += stepY
    }
    guard total > 0, let dominant = histogram.values.max() else { return 0 }
    return 1 - Double(dominant) / Double(total)
}

static func distinctColors(inPNG data: Data) -> Int {
    guard let rep = NSBitmapImageRep(data: data) else { return 0 }
    var seen = Set<UInt32>()
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let stepX = max(1, w / 64), stepY = max(1, h / 64)
    var y = 0
    while y < h {
        var x = 0
        while x < w {
            if let c = rep.colorAt(x: x, y: y) {
                let r = UInt32(max(0, min(255, c.redComponent * 255)))
                let g = UInt32(max(0, min(255, c.greenComponent * 255)))
                let b = UInt32(max(0, min(255, c.blueComponent * 255)))
                seen.insert(r << 16 | g << 8 | b)
            }
            x += stepX
        }
        y += stepY
    }
    return seen.count
}

struct Expectation {
    let file: String
    let patternCount: Int
    let tileSizes: [CGSize]
    /// A known gap this suite can REPORT but cannot ASSERT. A pixel metric can
    /// tell "flat" from "not flat"; it cannot tell "complete" from "missing half
    /// its strokes", and pretending otherwise is how a green check starts lying.
    /// Printed with the results so the limitation stays visible.
    let limitation: String
}

static func main() {

// Read straight from the fixtures' own markup, so a wrong tile size fails here
// rather than silently rendering something plausible.
let expectations: [Expectation] = [
    Expectation(file: "quarter-orbs.svg", patternCount: 1,
                tileSizes: [CGSize(width: 1000, height: 1000)],
                limitation: ""),
    // Renders, but as DOTS rather than triangles: a 60-wide stroke over a
    // 1.25×1 triangle is all joins, and EXP strokes paths with a hardcoded
    // round join (CanvasView / ExportRenderer) where SVG's default is miter.
    // That is the open "Stroke fidelity — explicit line cap/join/miter" item in
    // WEB-SVG-FIDELITY-INVENTORY.md, not a pattern problem.
    Expectation(file: "spectrum-triangles.svg", patternCount: 1,
                tileSizes: [CGSize(width: 500, height: 100)],
                limitation: ""),
    Expectation(file: "gradient-diamonds.svg", patternCount: 2,
                tileSizes: [CGSize(width: 1000, height: 1000),
                            CGSize(width: 2000, height: 2000)],
                limitation: ""),
    // Imports its pattern correctly and still renders near-flat: every line is
    // stroked `url(#g)`, and `PathShape.stroke` is an `RGBAColor` — a gradient
    // stroke is not representable in the model at all. Pattern support cannot
    // fix this one.
    Expectation(file: "hexline-weave-neon.svg", patternCount: 1,
                tileSizes: [CGSize(width: 156.2, height: 270)],
                limitation: "neon lines are missing: every line is stroked "
                    + "url(#g) and PathShape.stroke is an RGBAColor, so a gradient "
                    + "stroke is not representable. Pattern support cannot fix it."),
]

let fixtureDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSString(string: "~/mnt/svg-backgrounds-export").expandingTildeInPath

print("SVGPatternImportCheck — fixtures at \(fixtureDir)\n")

for expectation in expectations {
    print("\(expectation.file):")
    let url = URL(fileURLWithPath: fixtureDir).appendingPathComponent(expectation.file)
    guard let data = try? Data(contentsOf: url) else {
        check("\(expectation.file) readable", false, "missing at \(url.path)")
        continue
    }
    guard let result = SVGImporter.importDocument(from: data) else {
        check("\(expectation.file) parses", false, "importDocument returned nil")
        continue
    }

    check("patterns imported", result.patterns.count == expectation.patternCount,
          "expected \(expectation.patternCount), got \(result.patterns.count)")

    let gotSizes = result.patterns.map(\.tileSize)
        .sorted { $0.width * $0.height < $1.width * $1.height }
    let wantSizes = expectation.tileSizes
        .sorted { $0.width * $0.height < $1.width * $1.height }
    let sizesMatch = gotSizes.count == wantSizes.count && zip(gotSizes, wantSizes).allSatisfy {
        abs($0.width - $1.width) < 0.05 && abs($0.height - $1.height) < 0.05
    }
    check("tile sizes match the markup", sizesMatch, "got \(gotSizes), want \(wantSizes)")

    check("every pattern has content", result.patterns.allSatisfy { !$0.children.isEmpty })
    check("patternUnits is userSpaceOnUse",
          result.patterns.allSatisfy { $0.units == .userSpaceOnUse })
    check("patternTransform survived",
          result.patterns.allSatisfy { $0.transform.cg != .identity },
          "every fixture uses a rotate/scale/translate patternTransform")

    // BUG-060: the percentage-sized carrier rect must exist AND carry the pattern.
    var carriers = 0
    func countCarriers(_ nodes: [Node]) {
        for node in nodes {
            switch node.content {
            case .rectangle(let s): if s.fill.isPattern { carriers += 1 }
            case .group(let kids):  countCarriers(kids)
            default: break
            }
        }
    }
    if case .group(let kids) = result.group.content { countCarriers(kids) }
    check("percentage-sized carrier rect survived with a pattern fill", carriers >= 1,
          "BUG-060: `width='100%'` parsed as 0 and the rect was dropped")

    // A tile must rasterise to something with actual structure in it.
    var document = Document(artboards: [], nodes: [])
    document.patterns = result.patterns
    for source in result.patterns {
        let image = ExportRenderView.patternTile(source, document: document, scale: 1)
        check("tile '\(source.name)' rasterises", image != nil)
        // A non-nil but BLANK tile is the failure mode that matters: it renders
        // as nothing and reads downstream as "the pattern worked".
        if let image {
            var opaque = 0, sampled = 0
            do {
                let rep = NSBitmapImageRep(cgImage: image)
                let stepX = max(1, rep.pixelsWide / 40), stepY = max(1, rep.pixelsHigh / 40)
                var y = 0
                while y < rep.pixelsHigh {
                    var x = 0
                    while x < rep.pixelsWide {
                        sampled += 1
                        if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.02 { opaque += 1 }
                        x += stepX
                    }
                    y += stepY
                }
            }
            check("tile '\(source.name)' has visible content", opaque > 0,
                  "\(opaque)/\(sampled) sampled pixels carry any alpha — "
                  + "tile \(Int(source.tileSize.width))×\(Int(source.tileSize.height)), "
                  + "\(source.children.count) child node(s), transform \(source.transform.cg)"
                  + " frames=" + source.children.map { "\($0.name)\($0.frame)" }.joined(separator: ","))
        }
    }

    // The regression itself: render the import and confirm it is not flat.
    let size = result.group.frame.size
    var board = Artboard(name: "check", frame: CGRect(origin: .zero, size: size))
    board.background = .solid(RGBAColor(r: 1, g: 1, b: 1, a: 1))
    var placed = result.group
    placed.frame = CGRect(origin: .zero, size: size)
    var renderDoc = Document(artboards: [board], nodes: [placed])
    renderDoc.patterns = result.patterns
    let renderer = ExportRenderer(document: renderDoc)
    if let png = renderer.data(for: board, format: .png, scale: 1) {
        // Optional second argument: a directory to drop the rendered PNG into, so
        // the result can be LOOKED at. A colour count proves "not flat"; it does
        // not prove the tiling landed in the right place at the right scale.
        if CommandLine.arguments.count > 2 {
            let out = URL(fileURLWithPath: CommandLine.arguments[2])
                .appendingPathComponent(expectation.file.replacingOccurrences(of: ".svg", with: ".png"))
            try? png.write(to: out)
        }
        let variety = nonDominantFraction(inPNG: png)
        check("render carries real artwork", variety >= 0.10,
              String(format: "only %.1f%% of sampled pixels differ from the "
                     + "dominant colour", variety * 100))
        if !expectation.limitation.isEmpty {
            print("  NOTE incomplete — \(expectation.limitation)")
        }
    } else {
        check("render produced a PNG", false)
    }

    // ── FEAT-062 Stage D: the round trip. Export the imported document back to
    // SVG and re-import THAT. This is the claim the whole document-level-source
    // architecture was chosen for, so it is asserted rather than assumed.
    let exported = renderer.svgString(for: board)
    if CommandLine.arguments.count > 2 {
        // Dump the export so it can be opened in an INDEPENDENT renderer. Our own
        // importer round-tripping it proves the two halves agree with each other,
        // not that the file is valid SVG anyone else will draw.
        let out = URL(fileURLWithPath: CommandLine.arguments[2])
            .appendingPathComponent(expectation.file.replacingOccurrences(
                of: ".svg", with: "-exported.svg"))
        try? Data(exported.utf8).write(to: out)
    }
    check("export emits a <pattern> def", exported.contains("<pattern "),
          "a pattern fill must not flatten to its fallback colour on export")
    check("one <pattern> def per source",
          exported.components(separatedBy: "<pattern ").count - 1 == result.patterns.count,
          "got \(exported.components(separatedBy: "<pattern ").count - 1), "
          + "expected \(result.patterns.count) — many fills must SHARE one def")
    check("export references the pattern by url()", exported.contains("fill=\"url(#pat"))

    if let roundTripped = SVGImporter.importDocument(from: Data(exported.utf8)) {
        check("round trip keeps the patterns",
              roundTripped.patterns.count == result.patterns.count,
              "re-importing the export produced \(roundTripped.patterns.count) "
              + "pattern(s), expected \(result.patterns.count)")
        let originalSizes = result.patterns.map(\.tileSize)
            .sorted { $0.width * $0.height < $1.width * $1.height }
        let trippedSizes = roundTripped.patterns.map(\.tileSize)
            .sorted { $0.width * $0.height < $1.width * $1.height }
        let sameTiles = originalSizes.count == trippedSizes.count
            && zip(originalSizes, trippedSizes).allSatisfy {
                abs($0.width - $1.width) < 0.5 && abs($0.height - $1.height) < 0.5
            }
        check("round trip keeps tile sizes", sameTiles,
              "got \(trippedSizes), expected \(originalSizes)")

        var tripDoc = Document(artboards: [board], nodes: [roundTripped.group])
        tripDoc.patterns = roundTripped.patterns
        if let tripPNG = ExportRenderer(document: tripDoc).data(for: board, format: .png, scale: 1) {
            let tripVariety = nonDominantFraction(inPNG: tripPNG)
            check("round-tripped render still carries artwork", tripVariety >= 0.10,
                  String(format: "only %.1f%% of pixels differ from the dominant "
                         + "colour after a round trip", tripVariety * 100))
        }
    } else {
        check("the exported SVG re-imports at all", false)
    }
    print("")
}

print("\(checks - failures.count)/\(checks) checks passed")
if failures.isEmpty {
    print("SVGPatternImportCheck: OK")
} else {
    print("SVGPatternImportCheck: \(failures.count) FAILED")
    exit(1)
}
}
}

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

/// FEAT-064. One objectBoundingBox pattern over an 800×600 board: tile =
/// 0.25 × 0.5 fractions (200 × 300 user units), fractional x/y of 0.1/0.1,
/// magenta tile content with a white circle. The carrier rect covers the whole
/// board, so if the renderer declines the OBB tile the ENTIRE render collapses
/// to the fallback magenta — a fallback that passes a "not flat" check on the
/// strength of one colour is exactly the failure this fixture exists to catch.
static func runOBBAnchoringFixture() {
    print("obb-anchor (embedded):")
    let obbSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" width="800" height="600" viewBox="0 0 800 600">
          <defs>
            <pattern id="obb" patternUnits="objectBoundingBox" x="0.1" y="0.1" width="0.25" height="0.5">
              <rect width="200" height="300" fill="#ff00ff"/>
              <circle cx="100" cy="150" r="60" fill="#ffffff"/>
            </pattern>
          </defs>
          <rect width="800" height="600" fill="#336633"/>
          <rect width="100%" height="100%" fill="url(#obb)"/>
        </svg>
        """

    guard let result = SVGImporter.importDocument(from: Data(obbSVG.utf8)) else {
        check("obb fixture parses", false, "importDocument returned nil")
        print("")
        return
    }
    guard let pattern = result.patterns.first else {
        check("obb pattern imported", false, "no patterns in the import")
        print("")
        return
    }

    check("obb pattern imported", result.patterns.count == 1)
    check("units are objectBoundingBox", pattern.units == .objectBoundingBox)
    check("tile size is the fractions from the file",
          abs(pattern.tileSize.width - 0.25) < 0.001 && abs(pattern.tileSize.height - 0.5) < 0.001,
          "got \(pattern.tileSize)")
    check("fractional x/y survived as tileOrigin",
          abs((pattern.tileOrigin?.x ?? -1) - 0.1) < 0.001
          && abs((pattern.tileOrigin?.y ?? -1) - 0.1) < 0.001,
          "got \(String(describing: pattern.tileOrigin))")

    // Render: the OBB tile must actually TILE — one tile per 200×300 user units,
    // anchored 80/60 in from the board corner by the fractional x/y.
    let size = result.group.frame.size
    var board = Artboard(name: "obb", frame: CGRect(origin: .zero, size: size))
    board.background = .solid(RGBAColor(r: 0.2, g: 0.4, b: 0.2, a: 1))
    var placed = result.group
    placed.frame = CGRect(origin: .zero, size: size)
    var renderDoc = Document(artboards: [board], nodes: [placed])
    renderDoc.patterns = result.patterns
    let renderer = ExportRenderer(document: renderDoc)
    if let png = renderer.data(for: board, format: .png, scale: 1) {
        let variety = nonDominantFraction(inPNG: png)
        check("obb render tiles rather than painting the fallback", variety >= 0.10,
              String(format: "only %.1f%% of sampled pixels differ from the dominant "
                     + "colour — the fallback would be flat magenta", variety * 100))
        check("obb render keeps the white circle (fraction-sized tile drew real content)",
              distinctColors(inPNG: png) >= 3,
              "expected background + magenta + white, got \(distinctColors(inPNG: png)) colours")
    } else {
        check("obb render produced a PNG", false)
    }

    // Export: the units, the fractions, and the x/y must all survive to the file.
    let exported = renderer.svgString(for: board)
    check("export keeps patternUnits=\"objectBoundingBox\"",
          exported.contains("patternUnits=\"objectBoundingBox\""))
    check("export keeps the fractional tile size",
          exported.contains("width=\"0.25") && exported.contains("height=\"0.5"),
          "fractions must not be written as absolute user units")
    check("export re-emits the fractional x/y",
          exported.contains("x=\"0.1") && exported.contains("y=\"0.1"),
          "a dropped x/y silently re-anchors the tile at the bounds corner")

    // Round trip: units, fractions, origin, and a live render.
    if let tripped = SVGImporter.importDocument(from: Data(exported.utf8)),
       let trippedPattern = tripped.patterns.first {
        check("obb round trip keeps objectBoundingBox",
              trippedPattern.units == .objectBoundingBox)
        check("obb round trip keeps the fractions",
              abs(trippedPattern.tileSize.width - 0.25) < 0.001
              && abs(trippedPattern.tileSize.height - 0.5) < 0.001,
              "got \(trippedPattern.tileSize)")
        check("obb round trip keeps the fractional x/y",
              abs((trippedPattern.tileOrigin?.x ?? -1) - 0.1) < 0.001
              && abs((trippedPattern.tileOrigin?.y ?? -1) - 0.1) < 0.001)
        var tripDoc = Document(artboards: [board], nodes: [tripped.group])
        tripDoc.patterns = tripped.patterns
        if let tripPNG = ExportRenderer(document: tripDoc).data(for: board, format: .png, scale: 1) {
            let tripVariety = nonDominantFraction(inPNG: tripPNG)
            check("obb round-tripped render still tiles", tripVariety >= 0.10,
                  String(format: "only %.1f%% differ from the dominant colour", tripVariety * 100))
        }
    } else {
        check("obb export re-imports", false)
    }

    // The inspector's flip, both directions, through the model helper the
    // canvas action calls. Reference = the fixture's own 800×600 board, so the
    // tile's appearance on that shape is what must survive the round flip.
    var flipDoc = Document(artboards: [], nodes: [])
    flipDoc.patterns = result.patterns
    let reference = CGSize(width: 800, height: 600)
    let toUser = flipDoc.settingPatternUnits(pattern.id, to: .userSpaceOnUse, reference: reference)
    check("flip to userSpace converts fractions to points",
          toUser.pattern(for: pattern.id)?.units == .userSpaceOnUse
          && abs((toUser.pattern(for: pattern.id)?.tileSize.width ?? 0) - 200) < 0.01
          && abs((toUser.pattern(for: pattern.id)?.tileSize.height ?? 0) - 300) < 0.01,
          "got \(String(describing: toUser.pattern(for: pattern.id)?.tileSize))")
    let back = toUser.settingPatternUnits(pattern.id, to: .objectBoundingBox, reference: reference)
    check("flip back to objectBoundingBox restores the fractions",
          abs((back.pattern(for: pattern.id)?.tileSize.width ?? 0) - 0.25) < 0.001
          && abs((back.pattern(for: pattern.id)?.tileSize.height ?? 0) - 0.5) < 0.001,
          "got \(String(describing: back.pattern(for: pattern.id)?.tileSize))")
    check("same-units flip is a no-op",
          back.settingPatternUnits(pattern.id, to: .objectBoundingBox, reference: reference)
              .patterns.first?.tileSize == back.patterns.first?.tileSize)
    print("")
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
    /// BUG-065: the minimum fraction of non-dominant pixels the render must
    /// carry. Defaults to the suite-wide bar; a fixture whose whole design IS
    /// its strokes (hexline) earns a higher one so "the lines went missing
    /// again" fails rather than limping past 10%.
    var minNonDominant: Double = 0.10
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
    // BUG-065 was this fixture's whole story: every line is stroked url(#g), a
    // gradient stroke was not representable in the model, and the neon lines
    // imported blank. Now they must import as gradient-stroke PAINTS, survive
    // the round trip, and carry the render past the suite-wide bar.
    Expectation(file: "hexline-weave-neon.svg", patternCount: 1,
                tileSizes: [CGSize(width: 156.2, height: 270)],
                limitation: "",
                minNonDominant: 0.30),
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

    // BUG-065: `stroke='url(#…)'` must import as a gradient-stroke PAINT. The
    // expected count is read straight from the file's own markup — the same
    // rule the tile sizes follow — so a single dropped line fails here.
    let strokeURLMarkers = (String(data: data, encoding: .utf8) ?? "")
        .components(separatedBy: "stroke=\"url(#").count - 1
    func countGradientStrokes(_ nodes: [Node]) -> Int {
        var n = 0
        for node in nodes {
            switch node.content {
            case .line(let s):      if s.stroke.isGradient { n += 1 }
            case .path(let s):      if s.stroke.isGradient { n += 1 }
            case .rectangle(let s): if s.stroke.isGradient { n += 1 }
            case .ellipse(let s):   if s.stroke.isGradient { n += 1 }
            case .polygon(let s):   if s.stroke.isGradient { n += 1 }
            case .group(let kids):  n += countGradientStrokes(kids)
            default: break
            }
        }
        return n
    }
    var importedGradientStrokes = 0
    if case .group(let kids) = result.group.content {
        importedGradientStrokes = countGradientStrokes(kids)
    }
    check("gradient strokes import as paints (file declares \(strokeURLMarkers))",
          importedGradientStrokes == strokeURLMarkers,
          "imported \(importedGradientStrokes) gradient-stroke layer(s), "
          + "the file declares \(strokeURLMarkers)")

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
    // Optional second argument: a directory to drop the rendered PNG into, so
    // the result can be LOOKED at. A colour count proves "not flat"; it does not
    // prove the tiling landed in the right place at the right scale. An EMPTY
    // string counts as absent — the wrapper used to pass "" through, which made
    // this dump to the repo root on every run.
    let dumpDirectory: String? = (CommandLine.arguments.count > 2 && !CommandLine.arguments[2].isEmpty)
        ? CommandLine.arguments[2] : nil

    if let png = renderer.data(for: board, format: .png, scale: 1) {
        if let dumpDirectory {
            let out = URL(fileURLWithPath: dumpDirectory)
                .appendingPathComponent(expectation.file.replacingOccurrences(of: ".svg", with: ".png"))
            try? png.write(to: out)
        }
        let variety = nonDominantFraction(inPNG: png)
        check("render carries real artwork", variety >= expectation.minNonDominant,
              String(format: "only %.1f%% of sampled pixels differ from the "
                     + "dominant colour (bar: %.0f%%)", variety * 100,
                     expectation.minNonDominant * 100))
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
    if let dumpDirectory {
        // Dump the export so it can be opened in an INDEPENDENT renderer. Our own
        // importer round-tripping it proves the two halves agree with each other,
        // not that the file is valid SVG anyone else will draw.
        let out = URL(fileURLWithPath: dumpDirectory)
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
        // BUG-065: the gradient strokes must come back through the export too —
        // stroke="url(#grad…)" re-importing as a flat colour would mean the
        // round trip flattened them.
        var trippedGradientStrokes = 0
        if case .group(let kids) = roundTripped.group.content {
            trippedGradientStrokes = countGradientStrokes(kids)
        }
        check("round trip keeps gradient strokes",
              trippedGradientStrokes >= importedGradientStrokes,
              "re-import produced \(trippedGradientStrokes) gradient-stroke "
              + "layer(s), imported \(importedGradientStrokes)")
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

// ── FEAT-064: objectBoundingBox anchoring. The owner fixtures are all
// userSpaceOnUse, so the bounds-relative mode gets its own EMBEDDED fixture —
// this half of the suite must not depend on a folder that happens to exist in
// someone's Dropbox. It exercises the fraction tile size, the fractional x/y
// origin (which cannot be baked into children because it differs per shape),
// the render path (which must tile rather than paint the fallback colour), the
// export re-emission, the round trip, and the inspector's unit-flip conversion.
runOBBAnchoringFixture()

print("\(checks - failures.count)/\(checks) checks passed")
if failures.isEmpty {
    print("SVGPatternImportCheck: OK")
} else {
    print("SVGPatternImportCheck: \(failures.count) FAILED")
    exit(1)
}
}
}

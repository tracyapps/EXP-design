import AppKit
import CoreImage
import WebKit

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}
private func require(_ value: Bool, _ message: String) {
    if !value { fail(message) }
}
private func rejects(_ name: String, _ body: () throws -> Void) {
    do { try body(); fail("accepted invalid \(name)") } catch { }
}
private let space = CGColorSpace(name: CGColorSpace.sRGB)!
private let sourcePixels: [[UInt8]] = [
    [0,0,0,255], [255,255,255,255], [128,128,128,255],
    [255,0,0,255], [0,255,0,255], [0,0,255,255],
    [0,0,0,0], [64,64,64,128], [128,0,0,128], [128,127,0,255]
]
private func image(_ pixels: [[UInt8]]) -> CGImage {
    CGImage(width: pixels.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.count * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: CGDataProvider(data: Data(pixels.flatMap { $0 }) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
private func pixels(_ image: CGImage) -> [Int] {
    let c = CGContext(data: nil, width: image.width, height: image.height,
                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    c.setBlendMode(.copy)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4)).map(Int.init)
}
private func expected(_ input: [UInt8], _ chain: [ColorMatrix]) -> [Int] {
    // Independent reference, not Core Image or production color helpers.
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    func gamma(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1/2.4) - 0.055 }
    let a = Double(input[3]) / 255
    var p = (0..<3).map { a == 0 ? 0 : Double(input[$0]) / 255 / a } + [a]
    for m in chain {
        if m.workingSpace == .linearRGB { for i in 0..<3 { p[i] = linear(p[i]) } }
        var out: [Double] = []
        for row in 0..<4 {
            var sum = m.values[row * 5 + 4]
            for column in 0..<4 { sum += m.values[row * 5 + column] * p[column] }
            out.append(min(1, max(0, sum)))
        }
        if m.workingSpace == .linearRGB { for i in 0..<3 { out[i] = gamma(out[i]) } }
        // Once a primitive erases alpha, RGB cannot survive premultiplication.
        p = out[3] == 0 ? [0,0,0,0] : out
    }
    return (0..<4).map { Int((255 * p[$0] * ($0 < 3 ? p[3] : 1)).rounded()) }
}

@MainActor
private final class Page: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    var completion: CheckedContinuation<Void, Error>?
    override init() { super.init(); web.navigationDelegate = self }
    func load() async throws {
        try await withCheckedThrowingContinuation { c in
            completion = c
            web.loadHTMLString("<!doctype html><html><body>Local SVG pixel check</body></html>", baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.completion?.resume(throwing: NSError(domain: "ColorMatrix.WebKitTimeout", code: 1))
                self?.completion = nil
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { completion?.resume(); completion = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { completion?.resume(throwing: error); completion = nil }
    func sample(_ svg: String, width: Int = 10, height: Int = 1) async throws -> [Int] {
        let result = try await web.callAsyncJavaScript("""
          const img = new Image();
          await Promise.race([
            new Promise((resolve, reject) => {
              img.onload = resolve; img.onerror = () => reject(new Error('SVG load failed'));
              img.src = 'data:image/svg+xml;base64,' + btoa(svg);
            }),
            new Promise((_, reject) => setTimeout(() => reject(new Error('SVG pixel timeout')), 15000))
          ]);
          const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
          const context = canvas.getContext('2d'); context.drawImage(img, 0, 0);
          return Array.from(context.getImageData(0,0,width,height).data);
          """, arguments: ["svg": svg, "width": width, "height": height], in: nil, contentWorld: .page)
        guard let values = result as? [NSNumber], values.count == width * height * 4 else { throw NSError(domain: "ColorMatrix.InvalidWebKitPixels", code: 1) }
        var p = values.map(\.intValue)
        for i in stride(from: 0, to: p.count, by: 4) {
            for ch in 0..<3 { p[i+ch] = Int((Double(p[i+ch]) * Double(p[i+3]) / 255).rounded()) }
        }
        return p
    }
}

@main
private enum ColorMatrixCheck {
    @MainActor static func main() async {
        do { try await runChecks() }
        catch { fail("matrix fixture: \(error)") }
    }
    @MainActor private static func runChecks() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let input = image(sourcePixels)
        let identity = ColorMatrix.identity
        require(try EffectsRender.colorMatrixImage(input, matrices: [identity]) === input, "identity must not allocate/quantize")
        rejects("wrong length") { _ = try ColorMatrix(values: [1,2]) }
        rejects("NaN") { _ = try identity.setting(3, to: .nan) }
        rejects("infinity") { _ = try identity.setting(5, to: .infinity) }
        rejects("invalid index") { _ = try identity.setting(20, to: 1) }
        rejects("invalid SVG token") { _ = try ColorMatrix(svgValues: identity.svgValues.replacingOccurrences(of: "1.0", with: "wat")) }
        rejects("repeated SVG comma") { _ = try ColorMatrix(svgValues: identity.svgValues.replacingOccurrences(of: " ", with: ",,")) }
        rejects("trailing SVG comma") { _ = try ColorMatrix(svgValues: identity.svgValues + ",") }
        rejects("hex SVG number") { _ = try ColorMatrix(svgValues: identity.svgValues.replacingOccurrences(of: "1.0", with: "0x1p0")) }
        require(try ColorMatrix(svgValues: identity.svgValues.replacingOccurrences(of: " ", with: ",\n"), workingSpace: .sRGB) == identity, "comma/whitespace SVG list must work")
        rejects("chain budget") { _ = try EffectsRender.colorMatrixImage(input, matrices: Array(repeating: identity, count: 33)) }
        rejects("invalid JSON matrix") {
            _ = try JSONDecoder().decode(ColorMatrix.self, from: Data(#"{"values":[1,2],"workingSpace":"sRGB"}"#.utf8))
        }
        let huge = try identity.setting(0, to: 1e100)
        require(try JSONDecoder().decode(ColorMatrix.self, from: JSONEncoder().encode(huge)) == huge, "finite values must survive even if backend cannot render them")
        rejects("backend coefficient overflow") { _ = try EffectsRender.colorMatrixImage(input, matrices: [huge]) }
        var scale = identity
        for index in [0,6,12] { scale = try scale.setting(index, to: 0.5) }
        var linear = scale; linear.workingSpace = .linearRGB
        let duotone = try ColorMatrix.duotone(shadows: RGBAColor(r: 0.08,g: 0.03,b: 0.26,a: 0),
                                             highlights: RGBAColor(r: 0.92,g: 1,b: 0.25,a: 0.2))
        require(try ColorMatrix.duotone(shadows: .black, highlights: .white, strength: 0) == identity, "strength zero must be identity")
        require(Array(duotone.values.suffix(5)) == [0,0,0,1,0], "duotone must preserve alpha")
        let swap = try ColorMatrix(values: [0,0,1,0,0, 0,1,0,0,0, 1,0,0,0,0, 0,0,0,1,0])
        let signed = try identity.setting(4, to: 0.1).setting(9, to: -0.1)
        let alpha = try identity.setting(18, to: 0.5)
        let boosted = try identity.setting(0, to: 3).setting(4, to: -0.3)
        let alphaBias = try identity.setting(19, to: 0.2)
        let reverse = try identity.setting(0, to: -1).setting(4, to: 1)
        let cancellation = try identity.setting(0, to: 4096).setting(1, to: -4096).setting(4, to: -16)
        let allChannels = try ColorMatrix(values: [
            0.45,0.15,-0.2,0.1,0.05, -0.1,0.6,0.2,0.05,0.1,
            0.2,-0.15,0.5,0.2,-0.02, 0.1,0.05,-0.1,0.8,0.02
        ])
        let cases: [(String,[ColorMatrix])] = [
            ("identity",[identity]), ("swap",[swap]), ("duotone",[duotone]),
            ("signed bias",[signed]), ("alpha scale",[alpha]), ("alpha bias",[alphaBias]),
            ("sRGB half",[scale]), ("linear half",[linear]),
            ("primitive clipping",[boosted,reverse]), ("mixed spaces",[linear,signed]), ("large coefficient cancellation",[cancellation]), ("intermediate precision",[swap,swap,cancellation]), ("all twenty coefficients",[allChannels])
        ]
        let png = NSBitmapImageRep(cgImage: input).representation(using: .png, properties: [:])!.base64EncodedString()
        let page = Page(); try await page.load()
        var receipts: [[String: Any]] = []
        for (name, chain) in cases {
            for m in chain {
                require(try ColorMatrix(svgValues: m.svgValues, workingSpace: m.workingSpace) == m, "SVG values changed")
                require(try JSONDecoder().decode(ColorMatrix.self, from: JSONEncoder().encode(m)) == m, "JSON changed")
            }
            let output = try EffectsRender.colorMatrixImage(input, matrices: chain, useCache: false)
            let native = pixels(output)
            let reference = sourcePixels.flatMap { expected($0, chain) }
            let cpuError = zip(native,reference).map { abs($0-$1) }.max()!
            require(cpuError <= 2, "\(name): native/reference max error \(cpuError); \(native) vs \(reference)")
            let primitives = chain.enumerated().map { i,m in
                "<feColorMatrix in=\"\(i == 0 ? "SourceGraphic" : "m\(i-1)")\" type=\"matrix\" values=\"\(m.svgValues)\" color-interpolation-filters=\"\(m.workingSpace.rawValue)\" result=\"m\(i)\"/>"
            }.joined()
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"1\"><defs><filter id=\"f\" x=\"0\" y=\"0\" width=\"100%\" height=\"100%\">\(primitives)</filter></defs><image width=\"10\" height=\"1\" href=\"data:image/png;base64,\(png)\" filter=\"url(#f)\"/></svg>"
            let browser = try await page.sample(svg)
            let svgError = zip(native,browser).map { abs($0-$1) }.max()!
            require(svgError <= 3, "\(name): native/WebKit SVG max error \(svgError); \(native) vs \(browser)")
            print("PASS: \(name), native/reference \(cpuError), native/WebKit SVG \(svgError) byte error")
            receipts.append(["case": name, "native": native, "reference": reference, "webkitSVG": browser, "maxCPUError": cpuError, "maxSVGError": svgError])
        }
        require(pixels(input) == sourcePixels.flatMap { $0.map(Int.init) }, "filtering changed source pixels")
        let cached = try EffectsRender.colorMatrixImage(input, matrices: [duotone])
        require(try EffectsRender.colorMatrixImage(input, matrices: [duotone]) === cached, "unchanged source/matrix must reuse cached output")
        let cachedSRGB = try EffectsRender.colorMatrixImage(input, matrices: [scale])
        let cachedLinear = try EffectsRender.colorMatrixImage(input, matrices: [linear])
        require(pixels(cachedSRGB) != pixels(cachedLinear), "cache key must include working space")
        require(try EffectsRender.colorMatrixImage(input, matrices: [signed]) !== cached, "cache key must include coefficients")
        let other = image(sourcePixels.reversed())
        require(try EffectsRender.colorMatrixImage(other, matrices: [duotone]) !== cached, "different source must not reuse output")
        let large = CGContext(data: nil, width: 4096, height: 1025, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        rejects("pixel budget") { _ = try EffectsRender.colorMatrixImage(large, matrices: [duotone]) }
        if CommandLine.arguments.count > 1 {
            try JSONSerialization.data(withJSONObject: receipts, options: [.prettyPrinted,.sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        try await integratedExportChecks(page)
        print("PASS: codec/validation/alpha/identity/cache/source distinction/resource guard")
    }
    @MainActor private static func integratedExportChecks(_ page: Page) async throws {
        let w = 64, h = 40
        var source: [UInt8] = []
        for y in 0..<h { for x in 0..<w {
            let p: [UInt8] = x < 16 ? [255,0,0,255] : x < 32 ? [0,128,0,128] : x < 48 ? [0,0,0,0] : (y < 20 ? [0,0,255,255] : [255,255,255,255])
            source += p
        }}
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4, space: space,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
                         provider: CGDataProvider(data: Data(source) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        let frame = CGRect(x: 16, y: 12, width: w, height: h)
        let board = Artboard(name: "Matrix fixture", frame: CGRect(x: 0,y: 0,width: 96,height: 64), background: .solid(.clear))
        var duo = Effect(kind: .colorMatrix); duo.duotone = DuotoneSettings()
        var linear = Effect(kind: .colorMatrix)
        var half = ColorMatrix.identity; half.workingSpace = .linearRGB
        for i in [0,6,12] { half = try half.setting(i, to: 0.5) }
        linear.colorMatrix = half
        var bias = Effect(kind: .colorMatrix); bias.colorMatrix = try ColorMatrix.identity.setting(4, to: 0.2).setting(19, to: 0.2)
        var identity = Effect(kind: .colorMatrix); identity.colorMatrix = .identity
        func make(_ effects: [Effect]) -> Document {
            Document(artboards: [board], nodes: [Node(name: "Matrix image", frame: frame, effects: effects,
                content: .image(ImageContent(data: png, naturalSize: CGSize(width: w,height: h))))])
        }
        for (name, effects) in [("identity",[identity]),("duotone",[duo]),("linear",[linear]),("alpha bias",[bias]),("stacked",[duo,linear])] {
            let doc = make(effects)
            let renderer = ExportRenderer(document: doc)
            guard let data = renderer.pngData(for: board, scale: 1, transparentBackground: true), let rep = NSBitmapImageRep(data: data), let nativeImage = rep.cgImage else { fail("integrated PNG failed") }
            let native = pixels(nativeImage)
            let svg = renderer.svgString(for: board)
            let browser = try await page.sample(svg, width: 96, height: 64)
            let error = zip(native,browser).map { abs($0-$1) }.max()!
            if error > 4 {
                let mismatch = zip(native,browser).enumerated().filter { abs($0.element.0-$0.element.1)>4 }.prefix(10).map { "x=\(($0.offset/4)%96) y=\(($0.offset/4)/96) ch=\($0.offset%4): \($0.element.0)/\($0.element.1)" }
                fail("integrated \(name): PNG/PDF vs actual SVG max error \(error); \(mismatch)")
            }
            let saved = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(doc))
            require(saved.nodes[0].effects[0].effectiveMatrix == effects[0].effectiveMatrix, "document matrix codec changed")
            guard let imported = SVGImporter.importDocument(from: Data(svg.utf8)) else { fail("actual exported SVG failed import") }
            require(imported.warnings.isEmpty, "own SVG import warnings: \(imported.warnings)")
            let back = ExportRenderer(document: Document(artboards: [board], nodes: [imported.group]))
            guard let roundtrip = back.pngData(for: board, scale: 1, transparentBackground: true), let roundImage = NSBitmapImageRep(data: roundtrip)?.cgImage else { fail("SVG roundtrip PNG failed") }
            let roundError = zip(native,pixels(roundImage)).map { abs($0-$1) }.max()!
            require(roundError <= 4, "integrated \(name): SVG import/native roundtrip max error \(roundError)")
            print("PASS: integrated \(name), native PNG/PDF vs actual exported WebKit SVG \(error), SVG re-import \(roundError)")
        }
        // Matrix runs after the older effect family, regardless of its row
        // position. Compare native composed pixels with filtering that baseline.
        let noise = Effect(kind: .noise, amount: 0.25)
        let base = ExportRenderer(document: make([noise]))
        let combined = ExportRenderer(document: make([duo,noise]))
        guard let baseData = base.pngData(for: board,scale: 1,transparentBackground: true),
              let baseImage = NSBitmapImageRep(data: baseData)?.cgImage,
              let combinedData = combined.pngData(for: board,scale: 1,transparentBackground: true),
              let combinedImage = NSBitmapImageRep(data: combinedData)?.cgImage else { fail("mixed matrix/noise PNG failed") }
        let expectedMixed = try EffectsRender.colorMatrixImage(baseImage,matrices: [duo.effectiveMatrix],useCache: false)
        let mixedError = zip(pixels(expectedMixed),pixels(combinedImage)).map { abs($0-$1) }.max()!
        require(mixedError <= 4, "matrix must follow noise; channel error \(mixedError)")
        var pasted = [Node(name: "Target",frame: frame,content: .rectangle(RectangleShape()))]
        let sourceNode = make([duo]).nodes[0]
        require(Node.pasteAppearance(NodeAppearanceStyle(effects: sourceNode.layerStyle),to: [pasted[0].id],in: &pasted), "matrix effects paste failed")
        require(pasted[0].effects[0].effectiveMatrix == duo.effectiveMatrix && pasted[0].effects[0].id != duo.id, "paste must retain coefficients with independent effect identity")
        print("PASS: matrix after noise (\(mixedError) bytes), effect copy/paste with independent identity")
        var invalid = duo; invalid.colorMatrix = try ColorMatrix.identity.setting(0, to: 1e100); invalid.duotone = nil
        require(ExportRenderer(document: make([invalid])).data(for: board, format: .pdf, scale: 1) == nil, "failed filter must not report PDF success")
        require(ExportRenderer(document: make([invalid])).pngData(for: board, scale: 1) == nil, "failed filter must not report PNG success")
        // A failed matrix inside a pattern must reach the outer export instead
        // of silently painting the pattern's representative fallback colour.
        var patternChild = make([invalid]).nodes[0]
        patternChild.frame = CGRect(x: 0,y: 0,width: 64,height: 40)
        var pattern = PatternSource(name: "Filtered tile",children: [patternChild],tileSize: CGSize(width: 64,height: 40))
        var patternDoc = Document(artboards: [board],nodes: [Node(name: "Pattern fill",frame: frame,
            content: .rectangle(RectangleShape(fill: .pattern(pattern.reference),strokeWidth: 0)))])
        patternDoc.patterns = [pattern]
        require(ExportRenderer(document: patternDoc).data(for: board,format: .pdf,scale: 1) == nil,
                "matrix failure in pattern must fail outer PDF")
        require(ExportRenderer(document: patternDoc).pngData(for: board,scale: 1) == nil,
                "matrix failure in pattern must fail outer PNG")
        // viewBox points may be much larger than the actual raster tile. Filter
        // capture density must follow that mapping, not assume one pixel/point.
        patternChild.effects = [duo]
        patternChild.frame = CGRect(x: 0,y: 0,width: 6000,height: 6000)
        patternChild.content = .rectangle(RectangleShape(fill: .solid(.black),strokeWidth: 0))
        pattern.children = [patternChild]
        pattern.viewBox = patternChild.frame
        pattern.tileSize = CGSize(width: 24,height: 24)
        patternDoc.patterns = [pattern]
        let patternRenderer = ExportRenderer(document: patternDoc)
        guard let patternData = patternRenderer.pngData(for: board,scale: 1,transparentBackground: true),
              let patternImage = NSBitmapImageRep(data: patternData)?.cgImage else {
            fail("small viewBox-mapped pattern must render at tile density")
        }
        let browserPattern = try await page.sample(patternRenderer.svgString(for: board),width: 96,height: 64)
        let patternError = zip(pixels(patternImage),browserPattern).map { abs($0-$1) }.max()!
        if patternError > 4 {
            try patternData.write(to: URL(fileURLWithPath: "/tmp/exp-matrix-pattern-native.png"))
            try patternRenderer.svgString(for: board).write(toFile: "/tmp/exp-matrix-pattern.svg",atomically: true,encoding: .utf8)
            let mismatch = zip(pixels(patternImage),browserPattern).enumerated().filter { abs($0.element.0-$0.element.1)>4 }.prefix(10).map { "x=\(($0.offset/4)%96) y=\(($0.offset/4)/96) ch=\($0.offset%4): \($0.element.0)/\($0.element.1)" }
            fail("viewBox pattern native/SVG channel error \(patternError); \(mismatch)")
        }
        require(patternError <= 4,"viewBox pattern native/SVG channel error \(patternError)")
        print("PASS: pattern matrix failures propagate; viewBox filter capture uses tile density, SVG error \(patternError)")
        let unsupported = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\"><defs><filter id=\"f\"><feOffset result=\"o\"/><feColorMatrix in=\"o\"/></filter></defs><rect width=\"20\" height=\"20\" filter=\"url(#f)\"/></svg>"
        require(!(SVGImporter.importDocument(from: Data(unsupported.utf8))?.warnings.isEmpty ?? true), "unsupported graph must report omission")
        rejects("invalid stored duotone strength") {
            _ = try JSONDecoder().decode(DuotoneSettings.self,from: Data(#"{"strength":1e100}"#.utf8))
        }
        let opacitySVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\"><defs><filter id=\"f\"><feColorMatrix values=\"\(ColorMatrix.identity.svgValues)\"/></filter></defs><g opacity=\"0.5\"><rect width=\"20\" height=\"20\" filter=\"url(#f)\"/></g></svg>"
        require(!(SVGImporter.importDocument(from: Data(opacitySVG.utf8))?.warnings.isEmpty ?? true), "opacity ordering outside the bounded importer must be reported")
        var huge = make([duo]); huge.nodes[0].frame.size = CGSize(width: 6000,height: 6000)
        require(ExportRenderer(document: huge).data(for: board, format: .pdf, scale: 1) == nil, "oversized matrix export must fail before allocating")
        for size in [CGSize(width: 1280,height: 32),CGSize(width: 32,height: 1280)] {
            let tileBoard = Artboard(name: "Tile seams", frame: CGRect(origin: .zero,size: size), background: .solid(.clear))
            let first = Node(name: "First", frame: CGRect(x: 0,y: 0,width: size.width,height: size.height/2), content: .rectangle(RectangleShape(fill: .solid(.black),strokeWidth: 0)))
            let second = Node(name: "Second", frame: CGRect(x: 0,y: size.height/2,width: size.width,height: size.height/2), content: .rectangle(RectangleShape(fill: .solid(.white),strokeWidth: 0)))
            let group = Node(name: "Group matrix", frame: tileBoard.frame, effects: [duo], content: .group(children: [first,second]))
            let renderer = ExportRenderer(document: Document(artboards: [tileBoard],nodes: [group]))
            guard let data = renderer.pngData(for: tileBoard,scale: 1,transparentBackground: true), let native = NSBitmapImageRep(data: data)?.cgImage else { fail("tile PNG failed") }
            let browser = try await page.sample(renderer.svgString(for: tileBoard),width: Int(size.width),height: Int(size.height))
            let error = zip(pixels(native),browser).map { abs($0-$1) }.max()!
            require(error <= 4, "2D tile orientation/seam error \(error) at \(size)")
        }
        if CommandLine.arguments.count > 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
            var fixture = make([duo])
            fixture.pages[0].artboards[0].frame.size = CGSize(width: 960,height: 640)
            fixture.pages[0].nodes[0].frame = CGRect(x: 160,y: 120,width: 640,height: 400)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            let fixtureURL = directory.appendingPathComponent("matrix-editor.design")
            if !FileManager.default.fileExists(atPath: fixtureURL.path) {
                try encoder.encode(fixture).write(to: fixtureURL)
            }
        }
        print("PASS: explicit raster-export failure, unsupported SVG graph reporting and 2D tile seams")
    }

}

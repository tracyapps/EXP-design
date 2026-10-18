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
    func sample(_ svg: String) async throws -> [Int] {
        let result = try await web.callAsyncJavaScript("""
          const img = new Image();
          await Promise.race([
            new Promise((resolve, reject) => {
              img.onload = resolve; img.onerror = () => reject(new Error('SVG load failed'));
              img.src = 'data:image/svg+xml;base64,' + btoa(svg);
            }),
            new Promise((_, reject) => setTimeout(() => reject(new Error('SVG pixel timeout')), 15000))
          ]);
          const canvas = document.createElement('canvas'); canvas.width = 10; canvas.height = 1;
          const context = canvas.getContext('2d'); context.drawImage(img, 0, 0);
          return Array.from(context.getImageData(0,0,10,1).data);
          """, arguments: ["svg": svg], in: nil, contentWorld: .page)
        guard let values = result as? [NSNumber], values.count == 40 else { throw NSError(domain: "ColorMatrix.InvalidWebKitPixels", code: 1) }
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
        print("PASS: codec/validation/alpha/identity/cache/source distinction/resource guard")
    }
}

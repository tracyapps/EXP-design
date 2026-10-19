import AppKit
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
private func pixels(_ image: CGImage) -> [Int] {
    let c = CGContext(data: nil, width: image.width, height: image.height,
                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    c.setBlendMode(.copy)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4)).map(Int.init)
}
@MainActor
private final class Page: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    var completion: CheckedContinuation<Void, Error>?
    var window: NSWindow?
    override init() { super.init(); web.navigationDelegate = self }
    func load() async throws {
        try await withCheckedThrowingContinuation { c in
            completion = c
            web.loadHTMLString("<!doctype html><html><body>Local SVG pixel check</body></html>", baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.completion?.resume(throwing: NSError(domain: "Mesh.WebKitTimeout", code: 1))
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
        guard let values = result as? [NSNumber], values.count == width * height * 4 else { throw NSError(domain: "Mesh.InvalidWebKitPixels", code: 1) }
        var p = values.map(\.intValue)
        for i in stride(from: 0, to: p.count, by: 4) {
            for ch in 0..<3 { p[i+ch] = Int((Double(p[i+ch]) * Double(p[i+3]) / 255).rounded()) }
        }
        return p
    }
    func cssPixels(_ mesh: MeshFill, width: Int, height: Int) async throws -> [Int] {
        web.frame.size = CGSize(width: width,height: height)
        if window == nil {
            let host = NSWindow(contentRect: web.frame,styleMask: [.borderless],backing: .buffered,defer: false)
            host.isReleasedWhenClosed = false; host.contentView = web; host.orderBack(nil)
            window = host
        }
        window?.setContentSize(CGSize(width: width,height: height))
        web.underPageBackgroundColor = .white
        let metadata = try await web.callAsyncJavaScript("""
          document.body.replaceChildren();
          document.documentElement.style.cssText='margin:0;background:white';
          document.body.style.cssText='margin:0;width:'+width+'px;height:'+height+'px;'+declarations;
          await new Promise(resolve => setTimeout(resolve,100));
          return getComputedStyle(document.body).getPropertyValue("--exp-mesh-v1").trim();
          """,arguments: ["declarations":try mesh.cssDeclarations(),"width":width,"height":height],in: nil,contentWorld: .page)
        let encoded = try mesh.metadata()
        require(metadata as? String == "\"\(encoded)\"","CSS must retain exact bounded metadata")
        require(try MeshFill.fromMetadata(encoded) == mesh,"CSS metadata must reconstruct point IDs/order")
        let config = WKSnapshotConfiguration(); config.rect = CGRect(x: 0,y: 0,width: width,height: height)
        let image = try await web.takeSnapshot(configuration: config)
        var rect = CGRect(x: 0,y: 0,width: width,height: height)
        guard let cg = image.cgImage(forProposedRect: &rect,context: nil,hints: nil) else { fail("CSS snapshot absent") }
        let ctx = CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: 0,
            space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(cg,in: CGRect(x: 0,y: 0,width: width,height: height))
        return pixels(ctx.makeImage()!)
    }

}


@MainActor private final class MeshPDFView: NSView {
    let mesh: MeshFill
    init(mesh: MeshFill,size: CGSize) { self.mesh = mesh; super.init(frame: CGRect(origin: .zero,size: size)) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        do { try PaintRender.drawMesh(mesh,in: bounds,ctx: NSGraphicsContext.current!.cgContext,pdfSafeAlpha: true) }
        catch { fail("PDF mesh rendering failed: \(error)") }
    }
    func raster() -> CGImage {
        guard let image = NSImage(data: dataWithPDF(inside: bounds)),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: Int(bounds.width),pixelsHigh: Int(bounds.height),
                bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0) else { fail("PDF raster unavailable") }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.cgContext.clear(bounds)
        image.draw(in: bounds)
        return rep.cgImage!
    }
}

@main private enum MeshFillCheck {
    @MainActor static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { fail("mesh fixture timed out") }
        do { try await checks() } catch { fail("mesh: \(error)") }
    }
    @MainActor static func checks() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let page = Page(); try await page.load()
        defer { page.window?.close() }
        let first = MeshPoint(position: CGPoint(x: 0.25,y: 0.4),radius: 0.65,color: RGBAColor(r: 0.9,g: 0.12,b: 0.3,a: 0.8),opacity: 0.7)
        let second = MeshPoint(position: CGPoint(x: 0.8,y: 0.7),radius: 0.55,color: RGBAColor(r: 0.1,g: 0.4,b: 1,a: 1),opacity: 0.6)
        let transparent = RGBAColor(r: 0.2,g: 0.1,b: 0.6,a: 0)
        let translucent = RGBAColor(r: 0.3,g: 0.6,b: 0.2,a: 0.45)
        var many: [MeshPoint] = []
        for i in 0..<MeshFill.maximumPoints {
            let position = CGPoint(x: Double(i%4)/3,y: Double(i/4)/3)
            let color = RGBAColor(r: Double(i%3)/2,g: Double((i+1)%5)/4,b: Double((i+2)%7)/6,a: 0.6)
            many.append(MeshPoint(position: position,radius: 0.75,color: color,opacity: 0.5))
        }
        let cases: [(String,MeshFill)] = [
            ("base only",MeshFill(base: translucent)),
            ("point limit",MeshFill(base: translucent,points: many)),
            ("transparent base",MeshFill(base: transparent,points: [first])),
            ("opaque base",MeshFill(base: .white,points: [first,second])),
            ("translucent base",MeshFill(base: translucent,points: [first,second])),
            ("reversed order",MeshFill(base: translucent,points: [second,first])),
            ("off-canvas",MeshFill(base: .clear,points: [MeshPoint(position: CGPoint(x: -0.1,y: 0.3),radius: 1.25,color: .white)]))
        ]
        var receipts: [[String:Any]] = []
        for size in [CGSize(width: 128,height: 80),CGSize(width: 48,height: 120)] {
            let w = Int(size.width), h = Int(size.height), rect = CGRect(origin: .zero,size: size)
            for (name,mesh) in cases {
                func native(_ pdfSafe: Bool, white: Bool = false) throws -> [Int] {
                    let ctx = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,
                        space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.translateBy(x: 0,y: CGFloat(h)); ctx.scaleBy(x: 1,y: -1)
                    if white { ctx.setFillColor(CGColor(srgbRed: 1,green: 1,blue: 1,alpha: 1)); ctx.fill(rect) }
                    try PaintRender.drawMesh(mesh,in: rect,ctx: ctx,pdfSafeAlpha: pdfSafe)
                    return pixels(ctx.makeImage()!)
                }
                let pattern = try mesh.svgPattern(id: UUID())
                let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\"><defs>\(pattern.definition)</defs><rect width=\"\(w)\" height=\"\(h)\" fill=\"url(#\(pattern.id))\"/></svg>"
                let browser = try await page.sample(svg,width: w,height: h)
                let direct = try native(false), masked = try native(true)
                let pdf = pixels(MeshPDFView(mesh: mesh,size: size).raster())
                let pdfError = zip(direct,pdf).map { abs($0-$1) }.max()!
                var reference: [Int] = []
                for y in 0..<h { for x in 0..<w {
                    var rgba = [mesh.base.r * mesh.base.a,mesh.base.g * mesh.base.a,mesh.base.b * mesh.base.a,mesh.base.a]
                    for point in mesh.points {
                        let d = hypot(((Double(x)+0.5)/Double(w)-point.position.x)/point.radius,
                                      ((Double(y)+0.5)/Double(h)-point.position.y)/point.radius)
                        let a = point.color.a * point.opacity * max(0,1-d)
                        for (ch,c) in [point.color.r,point.color.g,point.color.b,1].enumerated() { rgba[ch] = c*a+rgba[ch]*(1-a) }
                    }
                    reference += rgba.map { Int(($0*255).rounded()) }
                }}
                let directMath = zip(direct,reference).map { abs($0-$1) }.max()!
                let pdfMath = zip(pdf,reference).map { abs($0-$1) }.max()!
                require(directMath <= 4,"\(name) native/source-over reference error \(directMath)")
                require(pdfMath <= 5,"\(name) PDF/source-over reference error \(pdfMath)")
                let svgError = zip(direct,browser).map { abs($0-$1) }.max()!
                let maskError = zip(direct,masked).map { abs($0-$1) }.max()!
                let css = try await page.cssPixels(mesh,width: w,height: h)
                let white = try native(false,white: true)
                let cssError = zip(white,css).map { abs($0-$1) }.max()!
                // Independent source-over bounds above distinguish geometry/math
                // errors from opposing 8-bit rounding in the rendering backends.
                // Pairwise cap is 8/255; receipts retain actual maxima (not exact).
                require(svgError <= 8,"\(name) \(size) native/SVG error \(svgError)")
                require(pdfError <= 8,"\(name) actual PDF error \(pdfError)")
                require(maskError <= 8,"\(name) native/PDF-mask error \(maskError)")
                require(cssError <= 8,"\(name) native/CSS error \(cssError); native \(Array(white.prefix(8))) CSS \(Array(css.prefix(8)))")
                require(try MeshFill.fromMetadata(mesh.metadata()) == mesh,"metadata roundtrip must preserve point IDs/order/alpha")
                print("PASS: \(name) \(w)x\(h), SVG \(svgError), CSS \(cssError), PDF-mask \(maskError), actual PDF \(pdfError) byte error")
                receipts.append(["case":name,"width":w,"height":h,"svgError":svgError,"cssError":cssError,"maskError":maskError,"pdfError":pdfError,"nativeReferenceError":directMath,"pdfReferenceError":pdfMath])
            }
        }
        let benchSize = CGSize(width: 512,height: 320)
        let bench = CGContext(data: nil,width: 512,height: 320,bitsPerComponent: 8,bytesPerRow: 0,space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var times: [Double] = []
        for _ in 0..<25 {
            let start = CFAbsoluteTimeGetCurrent()
            bench.clear(CGRect(origin: .zero,size: benchSize))
            try PaintRender.drawMesh(MeshFill(base: translucent,points: many),in: CGRect(origin: .zero,size: benchSize),ctx: bench)
            times.append((CFAbsoluteTimeGetCurrent()-start)*1000)
        }
        times.sort()
        print("BENCH: 8 points at 512x320, median \(times[12]) ms, p95 \(times[23]) ms; isolated drawing, not app stress proof")
        receipts.append(["fixture":"native vector benchmark","points":many.count,"width":512,"height":320,"medianMs":times[12],"p95Ms":times[23]])
        rejects("invalid metadata") { _ = try MeshFill.fromMetadata("<script>alert(1)</script>") }
        rejects("oversized metadata") { _ = try MeshFill.fromMetadata(String(repeating: "A",count: 24_001)) }
        var invalid = cases[2].1
        invalid.points.append(invalid.points[0]); rejects("duplicate IDs") { try invalid.validate() }
        invalid = cases[2].1; invalid.points[0].radius = .nan; rejects("NaN radius") { try invalid.validate() }
        invalid = cases[2].1; invalid.points[0].opacity = 2; rejects("invalid opacity") { try invalid.validate() }
        invalid = cases[2].1; invalid.version = 2; rejects("unknown version") { try invalid.validate() }
        rejects("invalid encode must not emit corrupt JSON") { _ = try JSONEncoder().encode(invalid) }
        invalid = cases[2].1; invalid.base.r = 2; rejects("out-of-range RGB") { try invalid.validate() }
        invalid = cases[2].1; invalid.points[0].position.x = .infinity; rejects("infinite coordinate") { try invalid.validate() }
        invalid = cases[2].1; invalid.points[0].radius = 0; rejects("zero radius") { try invalid.validate() }
        invalid = MeshFill(base: .white,points: (0...MeshFill.maximumPoints).map { _ in MeshPoint(position: .zero,radius: 1,color: .black) })
        rejects("point budget") { try invalid.validate() }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cases[1].1)) as! [String:Any]
        var encodedPoints = object["points"] as! [[String:Any]]
        encodedPoints[1] = encodedPoints[0]; object["points"] = encodedPoints
        let duplicateMetadata = try JSONSerialization.data(withJSONObject: object).base64EncodedString()
        rejects("metadata duplicate IDs") { _ = try MeshFill.fromMetadata(duplicateMetadata) }
        rejects("nonfinite render bounds") {
            try PaintRender.drawMesh(cases[0].1,in: CGRect(x: 0,y: 0,width: CGFloat.infinity,height: 100),ctx: bench)
        }
        if CommandLine.arguments.count > 1 {
            let receipt = URL(fileURLWithPath: CommandLine.arguments[1])
            try JSONSerialization.data(withJSONObject: receipts,options: [.prettyPrinted,.sortedKeys]).write(to: receipt)
            let preview = MeshFill(base: RGBAColor(r: 0.08,g: 0.03,b: 0.18,a: 1),points: [
                MeshPoint(position: CGPoint(x: 0.2,y: 0.2),radius: 0.9,color: RGBAColor(r: 1,g: 0.05,b: 0.4,a: 1)),
                MeshPoint(position: CGPoint(x: 0.8,y: 0.5),radius: 0.85,color: RGBAColor(r: 0,g: 0.8,b: 1,a: 1)),
                MeshPoint(position: CGPoint(x: 0.25,y: 0.9),radius: 0.65,color: RGBAColor(r: 0.5,g: 1,b: 0.06,a: 1),opacity: 0.8)
            ])
            let previewRect = CGRect(x: 0,y: 0,width: 720,height: 450)
            let ctx = CGContext(data: nil,width: 720,height: 450,bitsPerComponent: 8,bytesPerRow: 0,space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0,y: 450); ctx.scaleBy(x: 1,y: -1)
            try PaintRender.drawMesh(preview,in: previewRect,ctx: ctx)
            let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png,properties: [:])!
            try png.write(to: receipt.deletingLastPathComponent().appendingPathComponent("mesh-preview.png"))
            let pattern = try preview.svgPattern(id: UUID())
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"450\"><defs>\(pattern.definition)</defs><rect width=\"720\" height=\"450\" fill=\"url(#\(pattern.id))\"/></svg>"
            try Data(svg.utf8).write(to: receipt.deletingLastPathComponent().appendingPathComponent("mesh-preview.svg"))
        }
        print("PASS: strict data-only mesh metadata, stable IDs, alpha/order/radius and bounded point count")
    }
}

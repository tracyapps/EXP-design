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
    func cssPixels(_ mesh: MeshFill, width: Int, height: Int,background: String? = nil) async throws -> [Int] {
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
          """,arguments: ["declarations":try background ?? mesh.cssDeclarations(),"width":width,"height":height],in: nil,contentWorld: .page)
        let encoded = try mesh.metadata()
        if background == nil { require(metadata as? String == "\"\(encoded)\"","CSS must retain exact bounded metadata") }
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
    @MainActor static func checkPatternScale(_ page: Page) async throws {
        let board = Artboard(name: "Pattern scale",frame: CGRect(x: 0,y: 0,width: 128,height: 80))
        var review: Document?
        for relative in [false,true] { for viewBox in [false,true] {
            let width = relative ? "0.125" : "16",height = relative ? "0.25" : "20"
            let units = relative ? "objectBoundingBox" : "userSpaceOnUse"
            let box = viewBox ? " viewBox=\"0 0 16 20\"" : ""
            let origin = relative ? " x=\"0.125\" y=\"0.25\"" : ""
            let input = """
            <svg xmlns="http://www.w3.org/2000/svg" width="128" height="80"><defs>
              <pattern id="p" patternUnits="\(units)" width="\(width)" height="\(height)"\(box)\(origin)>
                <rect width="16" height="20" fill="#dd2255"/>
                <rect width="8" height="10" fill="#2255dd"/>
              </pattern></defs><rect width="128" height="80" fill="url(#p)"/></svg>
            """
            guard let imported = SVGImporter.importDocument(from: Data(input.utf8)),let source = imported.patterns.first else { fail("pattern scale fixture import") }
            for scale: CGFloat in [0.5,1,1.75,2] {
                let ref = PatternRef(patternID: source.id,scale: scale)
                let node = Node(name: "Pattern shape",frame: board.frame,content: .rectangle(RectangleShape(fill: .pattern(ref),strokeWidth: 0)))
                var doc = Document(artboards: [board],nodes: [node]); doc.patterns = [source]
                let saved = try JSONDecoder().decode(Document.self,from: JSONEncoder().encode(doc))
                require(saved.nodes[0].layerPaintStyle?.fill?.patternValue == ref,"pattern scale save/reopen")
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                require(try encoder.encode(saved.patterns) == encoder.encode(doc.patterns),"scale must not modify shared tile")
                let renderer = ExportRenderer(document: doc),svg = renderer.svgString(for: board)
                let browser = try await page.sample(svg,width: 128,height: 80)
                guard let png = renderer.data(for: board,format: .png,scale: 1),let image = NSBitmapImageRep(data: png)?.cgImage else { fail("pattern PNG") }
                let native = pixels(image),mean = zip(native,browser).map { abs($0-$1) }.reduce(0,+)
                let difference = Double(mean)/Double(native.count)
                require(difference < 3,"pattern SVG/PNG drift at \(units), viewBox \(viewBox), scale \(scale): \(difference)")
                guard let pdf = renderer.data(for: board,format: .pdf,scale: 1),let pdfSource = NSImage(data: pdf) else { fail("scaled pattern PDF") }
                let pdfRep = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 128,pixelsHigh: 80,
                    bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,
                    colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
                pdfRep.size = board.frame.size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pdfRep)
                pdfSource.draw(in: board.frame)
                NSGraphicsContext.restoreGraphicsState()
                let pdfPixels = pixels(pdfRep.cgImage!)
                require(zip(native,pdfPixels).map { abs($0-$1) }.reduce(0,+) < native.count*3,"PDF must preserve pattern scale and orientation")
                guard let roundTrip = SVGImporter.importDocument(from: Data(svg.utf8)) else { fail("scaled pattern SVG import") }
                var importedDoc = Document(artboards: [board],nodes: [roundTrip.group]); importedDoc.patterns = roundTrip.patterns
                let importedPNG = ExportRenderer(document: importedDoc).data(for: board,format: .png,scale: 1)!
                let trip = pixels(NSBitmapImageRep(data: importedPNG)!.cgImage!)
                require(zip(native,trip).map { abs($0-$1) }.reduce(0,+) < native.count*3,"standard SVG scale must survive re-import")
                print("PASS: pattern scale \(scale), \(units), viewBox \(viewBox), SVG/PNG mean \(difference)")
                if !relative && !viewBox && scale == 1.75 { review = doc }
            }
        }}
        let id = UUID(),legacy = PatternRef(patternID: id)
        let legacyData = try JSONEncoder().encode(legacy)
        require(!String(decoding: legacyData,as: UTF8.self).contains("scale"),"default scale must preserve legacy encoding")
        require(try JSONDecoder().decode(PatternRef.self,from: legacyData).scale == 1,"missing scale defaults to 100 percent")
        var malformed = try JSONSerialization.jsonObject(with: legacyData) as! [String:Any]; malformed["scale"] = 0
        rejects("zero pattern scale") { _ = try JSONDecoder().decode(PatternRef.self,from: JSONSerialization.data(withJSONObject: malformed)) }
        if var doc = review,let source = doc.patterns.first {
            let small = Node(name: "Original scale",frame: CGRect(x: 0,y: 0,width: 64,height: 80),content: .rectangle(RectangleShape(fill: .pattern(source.reference),strokeWidth: 0)))
            let large = Node(name: "Double scale",frame: CGRect(x: 64,y: 0,width: 64,height: 80),content: .rectangle(RectangleShape(fill: .pattern(PatternRef(patternID: source.id,scale: 2)),strokeWidth: 0)))
            doc.nodes = [small,large]
            let svg = ExportRenderer(document: doc).svgString(for: board)
            require(svg.components(separatedBy: "<pattern ").count == 3,"two scales of same source need two SVG variants")
            let browser = try await page.sample(svg,width: 128,height: 80)
            let png = ExportRenderer(document: doc).data(for: board,format: .png,scale: 1)!
            let native = pixels(NSBitmapImageRep(data: png)!.cgImage!)
            require(zip(native,browser).map { abs($0-$1) }.reduce(0,+) < native.count*3,"shared-source SVG variants must retain distinct scales")
            print("PASS: shared source, distinct per-fill SVG variants, native codec and legacy defaults")
            if CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--") {
                let directory = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
                let fixture = directory.appendingPathComponent("pattern-editor.design")
                if !FileManager.default.fileExists(atPath: fixture.path) {
                    var gui = doc
                    gui.artboards[0].frame = CGRect(x: 0,y: 0,width: 720,height: 450)
                    gui.nodes[0].frame = CGRect(x: 30,y: 30,width: 300,height: 350)
                    gui.nodes[1].frame = CGRect(x: 380,y: 30,width: 300,height: 350)
                    try JSONEncoder().encode(gui).write(to: fixture)
                }
            }
        }
    }

    @MainActor static func checkFlipRendering(_ page: Page) async throws {
        let board = Artboard(name: "Bowtie flip",frame: CGRect(x: 0,y: 0,width: 128,height: 80))
        let frame = CGRect(x: 44,y: 12,width: 40,height: 56)
        let paint = Paint.gradient(GradientFill(kind: .linear,stops: [GradientStop(color: .black,position: 0),GradientStop(color: RGBAColor(r: 0.2,g: 0.6,b: 1,a: 1),position: 1)]))
        let polygon = PolygonShape(sides: 3,fill: paint,strokeWidth: 0,cornerRadius: 4)
        for content in [NodeContent.polygon(polygon),.path(polygon.outline(in: CGRect(origin: .zero,size: frame.size)))] {
            for angle in [23.0,90] {
                let base = Node(name: "Rotated triangle",frame: frame,rotation: angle,content: content)
                func raster(_ node: Node) -> [Int] {
                    let doc = Document(artboards: [board],nodes: [node])
                    let png = ExportRenderer(document: doc).pngData(for: board,scale: 1,transparentBackground: true)!
                    return pixels(NSBitmapImageRep(data: png)!.cgImage!)
                }
                let before = raster(base)
                for horizontal in [true,false] {
                    let after = SelectionTransform.flipped(base,horizontal: horizontal)
                    let native = raster(after)
                    var expected = before
                    for y in 0..<80 { for x in 0..<128 { for ch in 0..<4 {
                        let xx = horizontal ? 127-x : x, yy = horizontal ? y : 79-y
                        expected[(y*128+x)*4+ch] = before[(yy*128+xx)*4+ch]
                    }}}
                    let reflectionError = Double(zip(native,expected).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
                    require(reflectionError < 0.3,"rotated triangle must mirror both geometry and gradient on canvas axes: \(reflectionError)")
                    let doc = Document(artboards: [board],nodes: [after])
                    let svg = ExportRenderer(document: doc).svgString(for: board)
                    let browser = try await page.sample(svg,width: 128,height: 80)
                    let svgError = Double(zip(native,browser).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
                    require(svgError < 2,"canvas-axis Flip native/SVG appearance: \(svgError)")
                    let saved = try JSONDecoder().decode(Document.self,from: JSONEncoder().encode(doc))
                    require(saved.nodes[0].rotation == after.rotation && saved.nodes[0].flipH == after.flipH && saved.nodes[0].flipV == after.flipV,"flip save/reopen flags and rotation")
                    print("PASS: rotated polygon/path Flip \(angle), horizontal \(horizontal), PNG mirror mean \(reflectionError), SVG mean \(svgError)")
                }
            }
        }
    }

    @MainActor static func checks() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let page = Page(); try await page.load()
        try await checkPatternScale(page)
        try await checkFlipRendering(page)
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
        for size in (CommandLine.arguments.contains("--integration-only") ? [] : [CGSize(width: 128,height: 80),CGSize(width: 48,height: 120)]) {
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
        let integrationBoard = Artboard(name: "Mesh integration",frame: CGRect(x: 0,y: 0,width: 128,height: 80),background: .clear)
        let legacy = try JSONDecoder().decode(GradientFill.self,from: Data("{\"kind\":\"radial\"}".utf8))
        require(legacy.radial == nil,"old radial files must retain implicit geometry")
        rejects("negative radial radius") {
            _ = try JSONDecoder().decode(GradientFill.self,from: Data("{\"kind\":\"radial\",\"radial\":{\"center\":[0.5,0.5],\"radius\":[-1,0.5]}}".utf8))
        }
        for alpha in [1.0,0.4] {
            var radial = GradientFill(kind: .radial,stops: [GradientStop(color: RGBAColor(r: 1,g: 0.2,b: 0.4,a: alpha),position: 0),GradientStop(color: RGBAColor(r: 0.1,g: 0.5,b: 1,a: alpha),position: 1)])
            radial.radial = RadialGradientGeometry(center: CGPoint(x: 0.3,y: 0.6),radius: CGSize(width: 0.4,height: 0.7))
            require(try JSONDecoder().decode(GradientFill.self,from: JSONEncoder().encode(radial)) == radial,"radial geometry must survive save/reopen")
            let defaultRadial = GradientFill(kind: .radial).radialGeometry(in: integrationBoard.frame)
            require(abs(defaultRadial.radius.width*128-hypot(128,80)/2)<1e-8,"legacy radial must stay a circle to the corner")
            let node = Node(name: "Radial editing",frame: integrationBoard.frame,content: .rectangle(RectangleShape(fill: .gradient(radial),strokeWidth: 0)))
            let renderer = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [node]))
            let svg = renderer.svgString(for: integrationBoard)
            guard let data = renderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),let image = NSBitmapImageRep(data: data)?.cgImage else { fail("radial PNG missing") }
            let browser = try await page.sample(svg,width: 128,height: 80)
            let error = zip(pixels(image),browser).map { abs($0-$1) }.max()!
            require(error <= 8,"off-center elliptical radial native/PDF/SVG alpha \(alpha) error \(error)")
            let css = try await page.cssPixels(MeshFill(base: .white),width: 128,height: 80,background: "background: "+DesignLanguageIO.cssGradient(radial)+";")
            let native = pixels(image)
            var cssError = 0
            for pixel in 0..<(128*80) { for channel in 0..<3 {
                cssError = max(cssError,abs(native[pixel*4+channel]+255-native[pixel*4+3]-css[pixel*4+channel]))
            }}
            require(cssError <= 8,"radial CSS must match native geometry/alpha, error \(cssError)")
            guard let imported = SVGImporter.importDocument(from: Data(svg.utf8)),let roundtrip = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [imported.group])).pngData(for: integrationBoard,scale: 1,transparentBackground: true),let restored = NSBitmapImageRep(data: roundtrip)?.cgImage else { fail("radial SVG roundtrip missing") }
            require(zip(pixels(image),pixels(restored)).map { abs($0-$1) }.max()! <= 8,"radial SVG re-import must retain geometry")
            print("PASS: off-center elliptical radial codec/native/PDF/SVG/own import at alpha \(alpha), SVG error \(error), CSS \(cssError)")
        }

        for paint in [Paint.solid(.black),Paint.gradient(GradientFill(angle: 35)),Paint.mesh(cases[3].1)] {
            let polygon = PolygonShape(sides: 5,fill: paint,stroke: .black,strokeWidth: 2,cornerRadius: 9)
            let node = Node(name: "Rounded polygon",frame: CGRect(x: 14,y: 9,width: 100,height: 62),content: .polygon(polygon))
            let renderer = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [node]))
            guard let png = renderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),let image = NSBitmapImageRep(data: png)?.cgImage else { fail("rounded polygon native export missing") }
            let svg = renderer.svgString(for: integrationBoard)
            require(svg.contains("<path d=") && svg.contains("C"),"rounded polygon SVG must contain real cubic geometry")
            let browser = try await page.sample(svg,width: 128,height: 80),native = pixels(image)
            var interior = 0
            let outline = ExportRenderView.polygonPath(polygon,in: node.frame).cgPath
            let strokeEdge = outline.copy(strokingWithWidth: polygon.strokeWidth+4,lineCap: .butt,lineJoin: .miter,miterLimit: 4)
            // Filled pixels at the stroke's antialiased edge are still opaque;
            // exclude that narrow edge from color interpolation comparison.
            for pixel in 0..<(128*80) where native[pixel*4+3] == 255 && browser[pixel*4+3] == 255 {
                if strokeEdge.contains(CGPoint(x: Double(pixel%128)+0.5,y: Double(pixel/128)+0.5)) { continue }
                for channel in 0..<3 { interior = max(interior,abs(native[pixel*4+channel]-browser[pixel*4+channel])) }
            }
            let mean = Double(zip(native,browser).reduce(0) { $0+abs($1.0-$1.1) })/Double(native.count)
            require(interior <= 8 && mean <= 2,"rounded polygon native/SVG interior \(interior), mean \(mean)")
            print("PASS: rounded polygon native/PDF/SVG paint, interior \(interior), mean \(mean)")
        }
        let integrationMesh = cases[3].1
        var integrationNode = Node(name: "Mesh shape",frame: integrationBoard.frame,
            content: .rectangle(RectangleShape(fill: .mesh(integrationMesh),strokeWidth: 0)))
        for opacity in [1.0,0.5] {
            integrationNode.opacity = opacity
            let document = Document(artboards: [integrationBoard],nodes: [integrationNode])
            let renderer = ExportRenderer(document: document)
            guard let png = renderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),
                  let image = NSBitmapImageRep(data: png)?.cgImage else { fail("integrated Mesh PNG failed") }
            let svg = renderer.svgString(for: integrationBoard)
            let browser = try await page.sample(svg,width: 128,height: 80)
            let error = zip(pixels(image),browser).map { abs($0-$1) }.max()!
            if error > 8 {
                let mismatch = zip(pixels(image),browser).enumerated().filter { abs($0.element.0-$0.element.1)>8 }.prefix(10).map { "x=\(($0.offset/4)%128) y=\(($0.offset/4)/128) ch=\($0.offset%4): \($0.element.0)/\($0.element.1)" }
                fail("actual Mesh PNG/PDF vs SVG at opacity \(opacity): \(error), \(mismatch)")
            }
            require(renderer.svgString(for: integrationBoard) == svg,"Mesh export must be deterministic")
            guard let imported = SVGImporter.importDocument(from: Data(svg.utf8)) else { fail("own mesh SVG import failed") }
            func mesh(in node: Node) -> MeshFill? {
                if let m = node.layerPaintStyle?.fill?.meshValue { return m }
                if case .group(let children) = node.content { return children.compactMap { mesh(in: $0) }.first }
                return nil
            }
            require(mesh(in: imported.group) == integrationMesh,"own SVG must restore editable points; warnings \(imported.warnings)")
            let shifted = svg.replacingOccurrences(of: "patternUnits=\"userSpaceOnUse\" x=\"0.0\"",with: "patternUnits=\"userSpaceOnUse\" x=\"5.0\"")
            require(shifted != svg,"placement rejection fixture must change the pattern")
            let shiftedImport = SVGImporter.importDocument(from: Data(shifted.utf8))
            require(shiftedImport != nil && mesh(in: shiftedImport!.group) == nil && !shiftedImport!.warnings.isEmpty,"changed pattern placement must not collapse to old Mesh positions")
            let saved = try JSONDecoder().decode(Document.self,from: JSONEncoder().encode(document))
            require(saved.nodes[0].layerPaintStyle?.fill?.meshValue == integrationMesh,"document save/reopen mesh changed")
            let altered = svg.replacingOccurrences(of: "stop-opacity=\"0.8\"",with: "stop-opacity=\"0.1\"")
            // Modifying a visible position must invalidate metadata collapse.
            let tokenSVG = svg.replacingOccurrences(of: "<defs>",with: "<style>:root { --accent: #ff00ff; }</style><defs>")
            let tokenImport = SVGImporter.importDocument(from: Data(tokenSVG.utf8))
            require(tokenImport != nil && mesh(in: tokenImport!.group) == integrationMesh,"inert EXP color tokens must preserve Mesh collapse")
            let styled = svg.replacingOccurrences(of: "<defs>",with: "<style>stop { stop-color: red !important; }</style><defs>")
            let styledImport = SVGImporter.importDocument(from: Data(styled.utf8))
            require(styledImport != nil && mesh(in: styledImport!.group) == nil && !styledImport!.warnings.isEmpty,"stylesheet overrides must not be hidden by Mesh metadata")
            let changed = altered.replacingOccurrences(of: "cx=\"0.25\"",with: "cx=\"0.3\"")
            let untrusted = SVGImporter.importDocument(from: Data(changed.utf8))
            require(untrusted != nil && mesh(in: untrusted!.group) == nil && !untrusted!.warnings.isEmpty,"changed SVG visuals must not collapse from stale metadata")
            print("PASS: actual Mesh Paint / PNG / SVG / strict import / codec at opacity \(opacity), channel error \(error)")
        }
        integrationNode.opacity = 0.6; integrationNode.rotation = 25
        integrationNode.frame = CGRect(x: 18,y: 12,width: 92,height: 56)
        let rotatedDoc = Document(artboards: [integrationBoard],nodes: [integrationNode])
        let rotatedRenderer = ExportRenderer(document: rotatedDoc)
        let rotatedSVG = rotatedRenderer.svgString(for: integrationBoard)
        guard let rotatedImport = SVGImporter.importDocument(from: Data(rotatedSVG.utf8)),
              let first = rotatedRenderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),
              let second = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [rotatedImport.group])).pngData(for: integrationBoard,scale: 1,transparentBackground: true),
              let firstCG = NSBitmapImageRep(data: first)?.cgImage,let secondCG = NSBitmapImageRep(data: second)?.cgImage else { fail("rotated Mesh roundtrip unavailable") }
        let rotatedError = zip(pixels(firstCG),pixels(secondCG)).map { abs($0-$1) }.max()!
        require(rotatedError <= 8,"rotated non-square Mesh SVG re-import error \(rotatedError)")
        print("PASS: rotated non-square Mesh SVG/native roundtrip, channel error \(rotatedError)")
        _ = try await page.cssPixels(integrationMesh,width: 128,height: 80)
        let extraction = RenderedHTMLExtractionScript.source(sourceName: "Mesh CSS",sourceURL: "file:///mesh.html",
            viewport: RenderedHTMLViewport(name: "Mesh",width: 128,renderHeight: 80))
        guard let snapshot = try await page.web.evaluateJavaScript(extraction) as? String else { fail("real CSS snapshot missing") }
        let mapped = try RenderedHTMLImporter().read(snapshotData: [Data(snapshot.utf8)])
        require(mapped.payload.pages[0].artboards[0].background.meshValue == integrationMesh,"real CSS extraction/import must retain editable Mesh")
        _ = try await page.web.evaluateJavaScript("document.body.style.backgroundImage='none'")
        guard let changedSnapshot = try await page.web.evaluateJavaScript(extraction) as? String else { fail("changed CSS snapshot missing") }
        let changed = try RenderedHTMLImporter().read(snapshotData: [Data(changedSnapshot.utf8)])
        require(changed.payload.pages[0].artboards[0].background.meshValue == nil,"stale CSS metadata must not override changed visuals")
        print("PASS: actual production WebKit CSS extraction -> editable Mesh; changed visual invalidates stale metadata")
        let strokeFrame = CGRect(x: 24,y: 20,width: 80,height: 40)
        for opacity in [1.0,0.5] {
            let strokeNode = Node(name: "Mesh outline",frame: strokeFrame,opacity: opacity,
                content: .rectangle(RectangleShape(fill: .clear,stroke: .mesh(integrationMesh),strokeWidth: 8)))
            let renderer = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [strokeNode]))
            guard let png = renderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),
                  let cg = NSBitmapImageRep(data: png)?.cgImage else { fail("Mesh outline PNG missing") }
            let svg = try await page.sample(renderer.svgString(for: integrationBoard),width: 128,height: 80)
            let error = zip(pixels(cg),svg).map { abs($0-$1) }.max()!
            require(error <= 8,"Mesh outline native/SVG mismatch \(error), opacity \(opacity)")
            print("PASS: Mesh outline uses same tiled bbox paint as SVG, opacity \(opacity), channel error \(error)")
        }
        var curveStart = PathPoint(point: CGPoint(x: 0,y: 20)); curveStart.controlOut = CGPoint(x: 0,y: 0)
        var curveEnd = PathPoint(point: CGPoint(x: 80,y: 20)); curveEnd.controlIn = CGPoint(x: 80,y: 40)
        let curveNode = Node(name: "Mesh curve",frame: CGRect(x: 24,y: 20,width: 80,height: 40),content: .path(PathShape(points: [curveStart,curveEnd],closed: true,fill: .mesh(integrationMesh),strokeWidth: 0)))
        let curveRenderer = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [curveNode]))
        guard let curvePNG = curveRenderer.pngData(for: integrationBoard,scale: 1,transparentBackground: true),let curveCG = NSBitmapImageRep(data: curvePNG)?.cgImage else { fail("Mesh curve PNG absent") }
        let curveSVG = curveRenderer.svgString(for: integrationBoard)
        let curveBrowser = try await page.sample(curveSVG,width: 128,height: 80)
        // Compare solid interior pixels; vector edge antialiasing belongs to the
        // existing path rasterizers and must not mask a paint-space mismatch.
        let curveNative = pixels(curveCG)
        var logicalError = 0
        for pixel in 0..<(128*80) where curveNative[pixel*4+3] == 255 {
            let x = Double(pixel%128)+0.5, y = Double(pixel/128)+0.5
            var rgb = [integrationMesh.base.r,integrationMesh.base.g,integrationMesh.base.b]
            for point in integrationMesh.points {
                let distance = hypot(((x-24)/80-point.position.x)/point.radius,
                                     ((y-20)/40-point.position.y)/point.radius)
                let alpha = point.color.a * point.opacity * max(0,1-distance)
                for (channel,color) in [point.color.r,point.color.g,point.color.b].enumerated() {
                    rgb[channel] = color*alpha+rgb[channel]*(1-alpha)
                }
            }
            for channel in 0..<3 { logicalError = max(logicalError,abs(curveNative[pixel*4+channel]-Int((rgb[channel]*255).rounded()))) }
        }
        require(logicalError <= 4,"curved Mesh must follow editing-frame point coordinates: \(logicalError)")
        var curveError = 0
        for pixel in 0..<(128*80) where curveNative[pixel*4+3] == 255 && curveBrowser[pixel*4+3] == 255 {
            for ch in 0..<3 { curveError = max(curveError,abs(curveNative[pixel*4+ch]-curveBrowser[pixel*4+ch])) }
        }
        require(curveError <= 8,"curved Mesh paint must use logical frame, not SVG ink bounds: \(curveError)")
        guard let curveImport = SVGImporter.importDocument(from: Data(curveSVG.utf8)),
              let roundtrip = ExportRenderer(document: Document(artboards: [integrationBoard],nodes: [curveImport.group])).pngData(for: integrationBoard,scale: 1,transparentBackground: true),
              let roundtripCG = NSBitmapImageRep(data: roundtrip)?.cgImage else { fail("curved Mesh own SVG re-import missing") }
        let curveRoundtrip = zip(curveNative,pixels(roundtripCG)).map { abs($0-$1) }.max()!
        require(curveRoundtrip <= 8,"curved Mesh native SVG re-import changed paint: \(curveRoundtrip)")
        print("PASS: curved Mesh editing-frame math \(logicalError), native/SVG interior \(curveError), own re-import \(curveRoundtrip) channel error")
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
            let fixtureURL = receipt.deletingLastPathComponent().appendingPathComponent("mesh-editor.design")
            if !FileManager.default.fileExists(atPath: fixtureURL.path) {
                let board = Artboard(name: "Mesh review",frame: CGRect(x: 0,y: 0,width: 960,height: 640))
                let node = Node(name: "Mesh shape",frame: CGRect(x: 160,y: 120,width: 640,height: 400),content: .rectangle(RectangleShape(fill: .mesh(preview),strokeWidth: 0)))
                try JSONEncoder().encode(Document(artboards: [board],nodes: [node])).write(to: fixtureURL)
            }
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

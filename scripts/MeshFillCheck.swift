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
          const context = canvas.getContext('2d'); context.drawImage(img, 0, 0, width, height);
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
          """,arguments: ["declarations":try background ?? mesh.cssDeclarations(size: CGSize(width: width,height: height)),"width":width,"height":height],in: nil,contentWorld: .page)
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
    @MainActor static func checkEllipses(_ page: Page) async throws {
        let legacy = MeshFill(base: .white,points: [MeshPoint(position: CGPoint(x: 0.4,y: 0.5),radius: 0.6,color: .black)])
        let old = try legacy.metadata()
        require(!String(data: Data(base64Encoded: old)!,encoding: .utf8)!.contains("angle"),"legacy Mesh bytes must omit new default fields")
        require(try MeshFill.fromMetadata(old).metadata() == old,"legacy canonical Mesh metadata must stay byte stable")
        let oldRadial = try JSONDecoder().decode(RadialGradientGeometry.self,from: Data("{\"center\":[0.5,0.5],\"radius\":[0.4,0.6]}".utf8))
        require(oldRadial.angle == 0,"old radial geometry must default to zero angle")
        for angle in [33.0,127.0,298.0] { for size in [CGSize(width: 128,height: 80),CGSize(width: 60,height: 144)] {
            let rect = CGRect(origin: .zero,size: size),w = Int(size.width),h = Int(size.height)
            let geometry = RadialGradientGeometry(center: CGPoint(x: 0.42,y: 0.57),radius: CGSize(width: 0.56,height: 0.17),angle: angle)
            let a = angle * .pi/180
            let primary = geometry.unitPoint(CGPoint(x: 1,y: 0),in: size)
            let secondary = geometry.unitPoint(CGPoint(x: 0,y: 1),in: size)
            let dx = (primary.x-geometry.center.x)*size.width,dy = (primary.y-geometry.center.y)*size.height
            require(abs(dx-cos(a)*0.56*size.width) < 1e-8 && abs(dy-sin(a)*0.56*size.width) < 1e-8,"primary axis uses physical angle")
            require(abs(dx*(secondary.x-geometry.center.x)*size.width+dy*(secondary.y-geometry.center.y)*size.height) < 1e-8,"ellipse axes must stay perpendicular")
            var dragged = geometry
            dragged.movePrimary(to: primary,in: size,limit: 4); dragged.moveSecondary(to: secondary,in: size,limit: 4)
            require(abs(dragged.radius.width-geometry.radius.width)<1e-8 && abs(dragged.radius.height-geometry.radius.height)<1e-8 && abs(dragged.angle-angle)<1e-8,"axis drag geometry agrees with rendered handles")
            let halfway = CGPoint(x: (primary.x+geometry.center.x)/2,y: (primary.y+geometry.center.y)/2)
            require(abs(geometry.stopPosition(at: halfway,in: size)-0.5)<1e-8,"turned stop drag projects onto physical radius")
            let point = MeshPoint(position: geometry.center,radius: geometry.radius.width,color: RGBAColor(r: 0.9,g: 0.2,b: 0.4,a: 0.7),opacity: 0.6,radiusY: geometry.radius.height,angle: angle)
            let mesh = MeshFill(base: .white,points: [point])
            require(try JSONDecoder().decode(MeshFill.self,from: JSONEncoder().encode(mesh)) == mesh,"independent Mesh axes/angle/ID survive save")
            let ctx = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0,y: size.height); ctx.scaleBy(x: 1,y: -1)
            try PaintRender.drawMesh(mesh,in: rect,ctx: ctx)
            let direct = pixels(ctx.makeImage()!),pdf = pixels(MeshPDFView(mesh: mesh,size: size).raster())
            var expected: [Int] = []
            for y in 0..<h { for x in 0..<w {
                let x = Double(x)+0.5-geometry.center.x*size.width,y = Double(y)+0.5-geometry.center.y*size.height
                let u = (cos(a)*x+sin(a)*y)/(0.56*size.width),v = (-sin(a)*x+cos(a)*y)/(0.17*size.height)
                let opacity = max(0,1-hypot(u,v))*0.7*0.6
                expected += [0.9,0.2,0.4,1].map { Int((($0*opacity+1-opacity)*255).rounded()) }
            }}
            let mathError = zip(direct,expected).map { abs($0-$1) }.max()!
            let pdfError = zip(pdf,expected).map { abs($0-$1) }.max()!
            require(mathError<=4 && pdfError<=5,"turned Mesh independent analytic native/PDF error \(mathError)/\(pdfError)")
            let server = try mesh.svgPattern(name: "testEllipse",bounds: rect)
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\"><defs>\(server.definition)</defs><rect width=\"\(w)\" height=\"\(h)\" fill=\"url(#\(server.id))\"/></svg>"
            let browser = try await page.sample(svg,width: w,height: h)
            let svgError = zip(direct,browser).map { abs($0-$1) }.max()!
            let css = try await page.cssPixels(mesh,width: w,height: h)
            let cssError = zip(direct,css).map { abs($0-$1) }.max()!
            require(svgError<=8 && cssError<=8,"turned Mesh native/SVG/CSS errors \(svgError)/\(cssError)")
            let cssValue = try mesh.cssBackground(size: size)
            require(EllipseCSSBackground.verified(cssValue)?.paint == .mesh(mesh),"canonical Mesh vector CSS own import")
            let changed = try EllipseCSSBackground(paint: .mesh(mesh),size: size).svg().replacingOccurrences(of: "fill-opacity=\"1.0\"",with: "fill-opacity=\"0.2\"")
            require(EllipseCSSBackground.verified("url(\"data:image/svg+xml;base64,\(Data(changed.utf8).base64EncodedString())\")") == nil,"changed visual must invalidate ellipse metadata")
            let extraction = RenderedHTMLExtractionScript.source(sourceName: "Ellipse",sourceURL: "file:///ellipse.html",viewport: RenderedHTMLViewport(name: "Ellipse",width: CGFloat(w),renderHeight: CGFloat(h)))
            let snapshot = try await page.web.evaluateJavaScript(extraction) as! String
            let mapped = try RenderedHTMLImporter().read(snapshotData: [Data(snapshot.utf8)])
            require(mapped.payload.pages[0].artboards[0].background.meshValue == mesh,"real rotated Mesh CSS extraction/import retains axes/angle/ID")
            var radial = GradientFill(kind: .radial,stops: [GradientStop(color: RGBAColor(r: 1,g: 0.2,b: 0.4,a: 0.6),position: 0),GradientStop(color: RGBAColor(r: 0.1,g: 0.5,b: 1,a: 0.6),position: 1)])
            radial.radial = geometry
            let board = Artboard(name: "Ellipses",frame: rect,background: .clear)
            let radialNode = Node(name: "Radial",frame: rect,content: .rectangle(RectangleShape(fill: .gradient(radial),strokeWidth: 0)))
            let renderer = ExportRenderer(document: Document(artboards: [board],nodes: [radialNode]))
            let radialSVG = renderer.svgString(for: board)
            let image = NSBitmapImageRep(data: renderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!
            let radialBrowser = try await page.sample(radialSVG,width: w,height: h)
            let radialError = zip(pixels(image),radialBrowser).map { abs($0-$1) }.max()!
            require(radialError<=8,"turned radial native/SVG error \(radialError)")
            let radialCSS = DesignLanguageIO.cssGradient(radial,size: size)
            let radialCSSPixels = try await page.cssPixels(MeshFill(base: .white),width: w,height: h,background: "background: "+radialCSS+";")
            var radialCSSError = 0; let native = pixels(image)
            for pixel in 0..<(w*h) { for ch in 0..<3 { radialCSSError = max(radialCSSError,abs(native[pixel*4+ch]+255-native[pixel*4+3]-radialCSSPixels[pixel*4+ch])) }}
            require(radialCSSError<=8,"turned radial native/CSS error \(radialCSSError)")
            let imported = SVGImporter.importDocument(from: Data(radialSVG.utf8))!
            let roundtrip = NSBitmapImageRep(data: ExportRenderer(document: Document(artboards: [board],nodes: [imported.group])).pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!
            let roundtripError = zip(native,pixels(roundtrip)).map { abs($0-$1) }.max()!
            require(roundtripError<=8,"turned radial own SVG import error \(roundtripError)")
            let radialSnapshot = try await page.web.evaluateJavaScript(extraction) as! String
            let radialMapped = try RenderedHTMLImporter().read(snapshotData: [Data(radialSnapshot.utf8)])
            require(radialMapped.payload.pages[0].artboards[0].background == Paint.gradient(radial),"real radial vector CSS extraction/import retains stops/axes/angle")
            if angle == 33 && w == 128 {
                func allNodes(_ node: Node) -> [Node] {
                    if case .group(let children) = node.content { return [node]+children.flatMap(allNodes) }
                    return [node]
                }
                for fill in [Paint.mesh(mesh),Paint.gradient(radial)] {
                    let css = try fill.meshValue?.cssBackground(size: size) ?? DesignLanguageIO.cssGradient(radial,size: size)
                    _ = try await page.cssPixels(MeshFill(base: .white),width: w,height: h,background: "background: "+css+";")
                    _ = try await page.web.evaluateJavaScript("(()=>{ const child=document.createElement('div'); child.style.cssText=document.body.style.cssText; child.style.position='absolute'; child.style.left='0'; child.style.top='0'; document.body.style.background='transparent'; document.body.append(child); })()")
                    let childSnapshot = try await page.web.evaluateJavaScript(extraction) as! String
                    let childMapped = try RenderedHTMLImporter().read(snapshotData: [Data(childSnapshot.utf8)])
                    let nodes = childMapped.payload.pages[0].nodes.flatMap(allNodes)
                    let leaves = nodes.filter { if case .group = $0.content { return false }; return true }
                    require(leaves.filter { $0.layerPaintStyle?.fill == fill }.count == 1,"canonical ellipse element must create exactly one editable fill")
                    require(!nodes.contains { if case .image = $0.content { return true }; return false },"canonical ellipse must not duplicate its fill as an image")
                    _ = try await page.web.evaluateJavaScript("document.body.firstElementChild.style.backgroundSize='50% 50%'")
                    let staleSnapshot = try await page.web.evaluateJavaScript(extraction) as! String
                    let staleMapped = try RenderedHTMLImporter().read(snapshotData: [Data(staleSnapshot.utf8)])
                    require(!staleMapped.payload.pages[0].nodes.flatMap(allNodes).contains {
                        if case .group = $0.content { return false }
                        return $0.frame.size == size && $0.layerPaintStyle?.fill == fill
                    },"changed CSS placement must invalidate full-size editable ellipse collapse")
                }
                print("PASS: actual element ellipse CSS imports once; changed background size rejects stale geometry")
                let points = [PathPoint(point: CGPoint(x: 8,y: 14),controlOut: CGPoint(x: 22,y: -15)),
                    PathPoint(point: CGPoint(x: 111,y: 20),controlIn: CGPoint(x: 87,y: 45)),
                    PathPoint(point: CGPoint(x: 100,y: 65)),PathPoint(point: CGPoint(x: 12,y: 53))]
                for content in [NodeContent.path(PathShape(points: points,closed: true,fill: .gradient(radial),stroke: .gradient(radial),strokeWidth: 3)),
                                .polygon(PolygonShape(sides: 3,fill: .gradient(radial),stroke: .gradient(radial),strokeWidth: 3))] {
                    let node = Node(name: "Radial geometry bounds",frame: rect,content: content)
                    let renderer = ExportRenderer(document: Document(artboards: [board],nodes: [node]))
                    let svg = renderer.svgString(for: board)
                    let source = pixels(NSBitmapImageRep(data: renderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
                    let browser = try await page.sample(svg,width: w,height: h)
                    let imported = SVGImporter.importDocument(from: Data(svg.utf8))!
                    let restored = pixels(NSBitmapImageRep(data: ExportRenderer(document: Document(artboards: [board],nodes: [imported.group])).pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
                    let mean = Double(zip(source,browser).map { abs($0-$1) }.reduce(0,+))/Double(source.count)
                    let importMean = Double(zip(source,restored).map { abs($0-$1) }.reduce(0,+))/Double(source.count)
                    if importMean >= 1 {
                        for node in allNodes(imported.group) {
                            if case .path(let ps) = node.content { print("DEBUG radial path frame \(node.frame) fill \(String(describing: ps.fill.gradientValue?.radial)) stroke \(String(describing: ps.stroke.gradientValue?.radial))") }
                        }
                        print("DEBUG source SVG \(svg)")
                    }
                    require(mean < 1 && importMean < 1,"curved path/triangle radial fill/stroke must use actual paint bounds; SVG/import mean \(mean)/\(importMean)")
                    print("PASS: path/polygon turned radial fill/stroke SVG/import mean \(mean)/\(importMean)")
                }
                for fill in [Paint.mesh(mesh),Paint.gradient(radial)] {
                    let child = Node(name: "Ellipse child",frame: CGRect(x: 5,y: 4,width: 82,height: 48),rotation: 25,opacity: 0.65,content: .rectangle(RectangleShape(fill: fill,strokeWidth: 0)))
                    var group = Node(name: "Ellipse group",frame: CGRect(x: 13,y: 10,width: 100,height: 65),content: .group(children: [child])); group.flipH = true
                    let renderer = ExportRenderer(document: Document(artboards: [board],nodes: [group]))
                    let bytes = pixels(NSBitmapImageRep(data: renderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
                    let svg = renderer.svgString(for: board)
                    let browser = try await page.sample(svg,width: w,height: h)
                    let svgError = zip(bytes,browser).map { abs($0-$1) }.max()!
                    let imported = SVGImporter.importDocument(from: Data(svg.utf8))!
                    let restored = pixels(NSBitmapImageRep(data: ExportRenderer(document: Document(artboards: [board],nodes: [imported.group])).pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
                    let importError = zip(bytes,restored).map { abs($0-$1) }.max()!
                    // The independent backends antialias rotated silhouette edges
                    // differently. Measure interior paint separately; retain edge
                    // maxima/whole-image mean rather than hide those differences.
                    let fullAlpha = fill.isMesh ? 166 : 99
                    var interior = 0,interiorCount = 0
                    for pixel in 0..<(w*h) where abs(bytes[pixel*4+3]-fullAlpha)<=1 && abs(browser[pixel*4+3]-fullAlpha)<=1 {
                        interiorCount += 1
                        for ch in 0..<4 { interior = max(interior,abs(bytes[pixel*4+ch]-browser[pixel*4+ch])) }
                    }
                    let mean = Double(zip(bytes,browser).map { abs($0-$1) }.reduce(0,+))/Double(bytes.count)
                    require(interiorCount > 2000 && interior <= 8 && mean < 1 && importError <= 8,"nested flipped/rotated ellipse interior/mean/import errors \(interior)/\(mean)/\(importError), count \(interiorCount)")
                    print("PASS: nested/flipped/rotated \(fill.isMesh ? "Mesh" : "radial") carrier SVG interior/edge/mean/import \(interior)/\(svgError)/\(mean)/\(importError)")
                }
            }
            if angle == 33 && w == 128,let directory = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
                let folder = URL(fileURLWithPath: directory).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
                var meshNode = radialNode; meshNode.id = UUID(); meshNode.name = "Mesh"; meshNode.frame.origin.y = size.height+24
                meshNode.content = .rectangle(RectangleShape(fill: .mesh(mesh),strokeWidth: 0))
                let fixture = Document(artboards: [Artboard(name: "Ellipse controls",frame: CGRect(x: 0,y: 0,width: 200,height: 230))],nodes: [radialNode,meshNode])
                try JSONEncoder().encode(fixture).write(to: folder.appendingPathComponent("ellipse-controls.design"))
            }
            print("PASS: ellipse \(angle)° \(w)x\(h); Mesh math/PDF/SVG/CSS \(mathError)/\(pdfError)/\(svgError)/\(cssError); radial SVG/CSS/re-import \(radialError)/\(radialCSSError)/\(roundtripError)")
        }}
        for bad in [-0.1,4.1,Double.infinity] {
            var invalid = legacy; invalid.points[0].radiusY = bad
            rejects("invalid Mesh Y radius") { try invalid.validate() }
        }
        var invalid = legacy; invalid.points[0].angle = 361
        rejects("unbounded Mesh angle") { try invalid.validate() }
        print("PASS: legacy defaults/canonical metadata, bounded ellipse decoding, physical handles and stop projection")
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

    @MainActor static func checkPatternExportRegression(_ page: Page) async throws {
        var problems: [String] = []
        for (name,origin,tileSize,overlay) in [
            ("document-offset",CGPoint(x: 137,y: 211),CGSize(width: 16,height: 20),false),
            ("unequal-viewbox",CGPoint.zero,CGSize(width: 32,height: 20),false),
            ("mesh-over-pattern",CGPoint(x: 137,y: 211),CGSize(width: 32,height: 20),true)
        ] {
            let input = """
            <svg xmlns="http://www.w3.org/2000/svg" width="128" height="80"><defs>
            <pattern id="p" patternUnits="userSpaceOnUse" width="\(tileSize.width)" height="\(tileSize.height)" viewBox="0 0 16 20">
            <rect width="16" height="20" fill="#9955dd"/><rect width="8" height="10" fill="#22cc66"/>
            </pattern></defs><rect width="128" height="80" fill="url(#p)"/></svg>
            """
            let imported = SVGImporter.importDocument(from: Data(input.utf8))!,source = imported.patterns[0]
            let board = Artboard(name: name,frame: CGRect(origin: origin,size: CGSize(width: 128,height: 80)))
            var nodes = [Node(name: "Pattern",frame: board.frame,content: .rectangle(RectangleShape(fill: .pattern(source.reference),strokeWidth: 0)))]
            if overlay {
                let mesh = MeshFill(base: RGBAColor(r: 0.4,g: 0.1,b: 0.8,a: 0.8),points: [MeshPoint(position: CGPoint(x: 0.6,y: 0.3),radius: 0.85,color: RGBAColor(r: 1,g: 0.8,b: 0.1,a: 0.7))])
                nodes.append(Node(name: "Mesh overlay",frame: board.frame.insetBy(dx: 13,dy: 9),blendMode: .overlay,content: .ellipse(EllipseShape(fill: .mesh(mesh),strokeWidth: 0))))
            }
            var doc = Document(artboards: [board],nodes: nodes);doc.patterns = [source]
            let renderer = ExportRenderer(document: doc),svg = renderer.svgString(for: board)
            let browser = try await page.sample(svg,width: 128,height: 80)
            let native = pixels(NSBitmapImageRep(data: renderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
            let mean = Double(zip(native,browser).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
            print("PATTERN EXPORT \(name): mean channel difference \(mean)")
            if mean >= 3 { problems.append(name) }
        }
        // Neutral tiles isolate geometry from focus-context gamut clipping.
        // AppKit focus contexts carry an implicit axis mapping absent from
        // CGContext.ctm. Exercise it, rather than only fresh bitmap contexts.
        for pan in [CGPoint.zero,CGPoint(x: 19,y: 23),CGPoint(x: -13,y: -17)] {
            let source = PatternSource(name: "Pan probe",children: [
                Node(name: "base",frame: CGRect(x: 0,y: 0,width: 32,height: 40),content: .rectangle(RectangleShape(fill: .solid(RGBAColor(r: 0.8,g: 0.8,b: 0.8,a: 1)),strokeWidth: 0))),
                Node(name: "corner",frame: CGRect(x: 0,y: 0,width: 12,height: 12),content: .rectangle(RectangleShape(fill: .solid(RGBAColor(r: 0.2,g: 0.2,b: 0.2,a: 1)),strokeWidth: 0)))
            ],tileSize: CGSize(width: 32,height: 40))
            let frame = CGRect(x: 20,y: 20,width: 100,height: 100)
            var doc = Document(nodes: [Node(name: "carrier",frame: frame,content: .rectangle(RectangleShape(fill: .pattern(source.reference),strokeWidth: 0)))])
            doc.patterns = [source]
            let image = NSImage(size: CGSize(width: 160,height: 160)); image.lockFocusFlipped(true)
            let c = NSGraphicsContext.current!.cgContext,store = PatternTileStore()
            c.clear(CGRect(x: 0,y: 0,width: 160,height: 160))
            var nativeResolver = store.resolver(document: doc)
            nativeResolver.baseSpaceAdjustment = c.ctm.inverted().concatenating(CGAffineTransform(translationX: 0,y: 160).scaledBy(x: 1,y: -1))
            PaintRender.fillRect(.pattern(source.reference),rect: frame.offsetBy(dx: pan.x,dy: pan.y),in: c,patterns: nativeResolver,patternSpace: CGAffineTransform(translationX: pan.x,y: pan.y))
            image.unlockFocus()
            let nativeImage = image.cgImage(forProposedRect: nil,context: nil,hints: nil)!
            let board = Artboard(name: "camera",frame: CGRect(x: -pan.x,y: -pan.y,width: 160,height: 160))
            doc.artboards = [board]
            let expected = try await page.sample(ExportRenderer(document: doc).svgString(for: board),width: nativeImage.width,height: nativeImage.height)
            let native = pixels(nativeImage)
            let mean = Double(zip(native,expected).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
            print("APPKIT PATTERN PAN \(pan): mean \(mean)")
            if mean >= 3 { problems.append("AppKit-pan-\(pan)") }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--owner-pattern-file"),CommandLine.arguments.count > flag+1 {
            let file = URL(fileURLWithPath: CommandLine.arguments[flag+1])
            let doc = try JSONDecoder().decode(Document.self,from: Data(contentsOf: file))
            guard let board = doc.pages.flatMap(\.artboards).first(where: { $0.name == "a11ycat-square" }) else { fail("owner artboard missing") }
            let renderer = ExportRenderer(document: doc),svg = renderer.svgString(for: board)
            let png = renderer.pngData(for: board,scale: 0.5,transparentBackground: true)!
            let native = pixels(NSBitmapImageRep(data: png)!.cgImage!)
            let browser = try await page.sample(svg,width: 540,height: 540)
            let mean = Double(zip(native,browser).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
            print("OWNER PATTERN EXPORT: native/SVG mean channel difference \(mean)")
            // The black cat dominates the full-board average. Measure the bowtie
            // independently so a misplaced repeat cannot hide in that average.
            var bowtieDifference = 0, bowtieChannels = 0
            for y in 401..<540 { for x in 55..<479 { for channel in 0..<4 {
                let i = (y*540+x)*4+channel
                bowtieDifference += abs(native[i]-browser[i]); bowtieChannels += 1
            }}}
            let bowtieMean = Double(bowtieDifference)/Double(bowtieChannels)
            print("OWNER BOWTIE EXPORT: native/SVG mean channel difference \(bowtieMean)")
            if bowtieMean >= 3 { problems.append("owner-bowtie") }

            let directory = file.deletingLastPathComponent()
            try png.write(to: directory.appendingPathComponent("owner-current-native.png"))
            try Data(svg.utf8).write(to: directory.appendingPathComponent("owner-current.svg"))
            // Write the exact WebKit sample too, without screenshots/resizing.
            let ctx = CGContext(data: nil,width: 540,height: 540,bitsPerComponent: 8,bytesPerRow: 2160,space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
            for i in browser.indices { bytes[i] = UInt8(browser[i]) }
            let image = ctx.makeImage()!
            try NSBitmapImageRep(cgImage: image).representation(using: .png,properties: [:])!.write(to: directory.appendingPathComponent("owner-current-webkit.png"))
            if mean >= 3 { problems.append("owner-artwork") }
        }
        require(problems.isEmpty,"pattern export discrepancies: \(problems.joined(separator: ", "))")
    }

    @MainActor static func checkPatternPlacement(_ page: Page) async throws {
        for relative in [false,true] {
            let units = relative ? "objectBoundingBox" : "userSpaceOnUse"
            let input = """
            <svg xmlns="http://www.w3.org/2000/svg" width="80" height="90"><defs><pattern id="p" patternUnits="\(units)" width="\(relative ? "0.25" : "16")" height="\(relative ? "0.5" : "20")" viewBox="0 0 16 20"><rect width="16" height="20" fill="#9955dd" fill-opacity="0.5"/><rect width="8" height="10" fill="#22cc66" fill-opacity="0.5"/></pattern></defs><rect width="80" height="90" fill="url(#p)"/></svg>
            """
            let imported = SVGImporter.importDocument(from: Data(input.utf8))!
            let source = imported.patterns[0],legacy = source.reference
            let frame = CGRect(x: 154,y: 236,width: 80,height: 90)
            var local = legacy.anchored(.shape,source: source,reference: frame.size,origin: frame.origin)!
            require(local.tileGeometry(source: source,bounds: frame).origin == legacy.tileGeometry(source: source,bounds: frame).origin,"Document to Shape preserves the displayed tile phase")
            local.scale = 1.35
            let documentRef = local.anchored(.document,source: source,reference: frame.size,origin: frame.origin)!
            require(legacy.placement == nil && documentRef.placement?.anchor == .document && local.placement?.anchor == .shape,"placement applies to each independent paint")
            let base = local.tileGeometry(source: source,bounds: frame)
            let resize = local.tileGeometry(source: source,bounds: CGRect(x: frame.minX,y: frame.minY,width: 190,height: 31))
            require(base.size == resize.size && base.origin == resize.origin,"nonuniform layer resize must not stretch or shift the tile")
            let moved = local.tileGeometry(source: source,bounds: frame.offsetBy(dx: 7,dy: 11))
            require(moved.origin == CGPoint(x: base.origin.x+7,y: base.origin.y+11),"shape anchor follows layer movement")
            let global = documentRef.tileGeometry(source: source,bounds: frame)
            require(global.origin == documentRef.tileGeometry(source: source,bounds: frame.offsetBy(dx: 7,dy: 11)).origin,"document anchor keeps fixed phase")
            require(base.size == (relative ? CGSize(width: 20,height: 45) : CGSize(width: 16,height: 20)),"fixed conversion basis matches original physical tile")
            require(try JSONDecoder().decode(PatternRef.self,from: JSONEncoder().encode(local)) == local,"placement save/reopen")
            let board = Artboard(name: "Two anchors",frame: CGRect(x: 137,y: 211,width: 256,height: 160))
            let nodes = [Node(name: "Shape anchor",frame: frame,content: .rectangle(RectangleShape(fill: .pattern(local),strokeWidth: 0))),Node(name: "Document anchor",frame: CGRect(x: 260,y: 229,width: 109,height: 126),content: .rectangle(RectangleShape(fill: .pattern(documentRef),strokeWidth: 0)))]
            var doc = Document(artboards: [board],nodes: nodes);doc.patterns = [source]
            let store = PatternTileStore(),resolver = store.resolver(document: doc)
            let resolved = resolver.resolve(local,frame,1)!
            require(resolved.tileSize == CGSize(width: base.size.width * 1.35,height: base.size.height * 1.35),"scale combines with fixed placement size")
            var transformed = source
            transformed.transform = AffineValue(CGAffineTransform(rotationAngle: 0.17).scaledBy(x: 1.1,y: 0.9))
            var transformedDoc = doc; transformedDoc.patterns = [transformed]
            let transformedStore = PatternTileStore(),transformedResolver = transformedStore.resolver(document: transformedDoc)
            let atStart = transformedResolver.resolve(local,frame,1)!
            let atEnd = transformedResolver.resolve(local,frame.offsetBy(dx: 7,dy: 11),1)!
            let startOrigin = atStart.origin.applying(atStart.transform), endOrigin = atEnd.origin.applying(atEnd.transform)
            require(abs(endOrigin.x-startOrigin.x-7) < 0.000001 && abs(endOrigin.y-startOrigin.y-11) < 0.000001,"Shape placement follows document movement even with a rotated pattern transform")
            let transformedRenderer = ExportRenderer(document: transformedDoc)
            let transformedNative = pixels(NSBitmapImageRep(data: transformedRenderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
            let transformedBrowser = try await page.sample(transformedRenderer.svgString(for: board),width: 256,height: 160)
            let transformedMean = Double(zip(transformedNative,transformedBrowser).map { abs($0-$1) }.reduce(0,+))/Double(transformedNative.count)
            require(transformedMean < 3,"transformed per-fill native/SVG drift: \(transformedMean)")
            print("PASS: rotated lattice follows layer movement, native/SVG \(units), mean \(transformedMean)")
            let renderer = ExportRenderer(document: doc),svg = renderer.svgString(for: board)
            let native = pixels(NSBitmapImageRep(data: renderer.pngData(for: board,scale: 1,transparentBackground: true)!)!.cgImage!)
            let browser = try await page.sample(svg,width: 256,height: 160)
            let mean = Double(zip(native,browser).map { abs($0-$1) }.reduce(0,+))/Double(native.count)
            if mean >= 3 {
                let c = CGContext(data: nil,width: 256,height: 160,bitsPerComponent: 8,bytesPerRow: 1024,space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.translateBy(x: 0,y: 160); c.scaleBy(x: 1,y: -1)
                let old = NSGraphicsContext.current; NSGraphicsContext.current = NSGraphicsContext(cgContext: c,flipped: true)
                for node in nodes {
                    let r = node.frame.offsetBy(dx: -board.frame.minX,dy: -board.frame.minY)
                    PaintRender.fill(node.layerPaintStyle!.fill!,path: NSBezierPath(rect: r),bounds: r,in: c,patterns: resolver,patternSpace: CGAffineTransform(translationX: -board.frame.minX,y: -board.frame.minY))
                }
                NSGraphicsContext.current = old
                let direct = pixels(c.makeImage()!)
                let directMean = Double(zip(direct,browser).map { abs($0-$1) }.reduce(0,+))/Double(direct.count)
                print("FRACTIONAL DIAGNOSTIC direct bitmap/SVG mean \(directMean), PDF PNG/SVG \(mean), tile \(resolved.image.width)x\(resolved.image.height), period \(resolved.tileSize)")
            }
            require(mean < 3,"per-fill anchored native/SVG drift \(units): \(mean)")
            require(svg.components(separatedBy: "<pattern ").count == 2,"matching physical phases share a standard SVG definition")
            var shiftedDoc = doc; shiftedDoc.nodes[0].frame.origin.x += 7
            require(ExportRenderer(document: shiftedDoc).svgString(for: board).components(separatedBy: "<pattern ").count == 3,"moved Shape fill gets an independent phase definition")
            var styled = nodes[1]; _ = styled.applyPaintStyle(nodes[0].layerPaintStyle!)
            require(styled.layerPaintStyle?.fill?.patternValue == local,"appearance preserves fill anchor and frozen size")
            print("PASS: per-fill anchors, fixed-size resize/move, scale, appearance, codec and native/SVG \(units), mean \(mean)")
        }
    }

    @MainActor static func checks() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let page = Page(); try await page.load()
        try await checkEllipses(page)
        if CommandLine.arguments.contains("--ellipses-only") { return }
        try await checkPatternExportRegression(page)
        try await checkPatternPlacement(page)
        if CommandLine.arguments.contains("--pattern-regression-only") { return }
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

import Foundation
import CoreGraphics

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum SVGTokenBridgeCheck {
    static func main() {
        let artboard = Artboard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "SVG token bridge",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let action = RGBAColor(r: 0.12, g: 0.35, b: 0.82, a: 0.5)
        let shape = Node(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Action surface",
            frame: CGRect(x: 10, y: 10, width: 80, height: 80),
            effects: [Effect(kind: .layerBlur, blur: 3)],
            content: .rectangle(RectangleShape(
                fill: .solid(action), stroke: action, strokeWidth: 2)))
        let token = DesignAsset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            name: "Action", value: .solid(action))
        let document = Document(
            artboards: [artboard], nodes: [shape],
            designLanguage: DesignLanguage(assets: [token]))

        let svg = ExportRenderer(document: document).svgString(for: artboard)
        require(svg.contains("--action: #1F59D180;"),
                "standalone SVG does not declare the shared color token")
        require(svg.contains("fill=\"var(--action, #1F59D180)\""),
                "standalone SVG fill lost token identity or literal fallback")
        require(svg.contains("stroke=\"var(--action, #1F59D180)\""),
                "standalone SVG stroke lost token identity or literal fallback")
        require(!svg.contains("fill-opacity=\"0.5\"")
                    && !svg.contains("stroke-opacity=\"0.5\""),
                "linked alpha was applied twice")
        require(svg.contains("<feGaussianBlur in=\"SourceGraphic\" stdDeviation=\"3\""),
                "native layer blur did not round-trip as SVG feGaussianBlur")

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: 64, height: 64,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { require(false, "could not create layer-blur verification bitmap"); return }
        EffectsRender.drawLayerBlur([Effect(kind: .layerBlur, blur: 4)],
                                    bounds: CGRect(x: 16, y: 16, width: 32, height: 32),
                                    deviceScale: 1, in: bitmap) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        }
        guard let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else {
            require(false, "could not inspect layer-blur verification bitmap"); return
        }
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            pixels[y * bitmap.bytesPerRow + x * 4 + 3]
        }
        require(alpha(32, 32) > 100 && alpha(13, 32) > 0,
                "native layer blur did not soften editable vector pixels on raster render")

        print("ok: standalone SVG color token + fallback")
        print("ok: semi-transparent token alpha is applied exactly once")
        print("ok: native layer blur round-trips as SVG feGaussianBlur")
        print("ok: native layer blur softens vector pixels on raster render")
    }
}

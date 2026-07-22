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

        print("ok: standalone SVG color token + fallback")
        print("ok: semi-transparent token alpha is applied exactly once")
    }
}

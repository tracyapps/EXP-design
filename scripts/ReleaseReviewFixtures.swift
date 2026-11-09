import AppKit
import Foundation

@main private enum ReleaseReviewFixtures {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: output.path) else {
            fputs("Choose a new output folder; existing test results will not be overwritten.\n", stderr); exit(1)
        }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let ink = RGBAColor(r: 0.08, g: 0.12, b: 0.17)
        let teal = RGBAColor(r: 0.05, g: 0.48, b: 0.45)
        let violet = RGBAColor(r: 0.48, g: 0.22, b: 0.75)
        let blue = RGBAColor(r: 0.08, g: 0.3, b: 0.9)
        let pale = Paint.solid(RGBAColor(r: 0.97, g: 0.98, b: 0.99))
        let boards = (0..<3).map { index in
            Artboard(name: ["01 — Paint and popovers", "02 — Folders and empty path", "03 — Images and storage"][index],
                     frame: CGRect(x: index * 1120, y: 0, width: 1024, height: 680),
                     notes: "Use docs/TESTING-v2.8-RELEASE.md. Work on a copy. Save/reopen, Undo/Redo, appearance and keyboard checks are separate from automated passes.",
                     background: pale)
        }
        var nodes: [Node] = []
        func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 18) -> Node {
            Node(name: text, frame: CGRect(x: x, y: y, width: 900, height: size * 1.5),
                 content: .text(TextContent(string: text, fontSize: size, color: ink)))
        }
        func shape(_ name: String, _ x: CGFloat, _ y: CGFloat, _ paint: Paint) -> Node {
            Node(name: name, frame: CGRect(x: x, y: y, width: 210, height: 140),
                 content: .rectangle(RectangleShape(fill: paint, cornerRadius: 16)))
        }
        nodes.append(label("01  Paint, focus and popover checks", 32, 24, 28))
        nodes.append(label("Select Six shadows in Layers; focus a HEX field, then switch shadow swatches.", 32, 78))
        var shadowBox = shape("Six shadows — focus and swatch repro", 60, 150, .solid(teal))
        for i in 0..<6 {
            let color = RGBAColor(r: Double(i) / 8, g: 0.1, b: 0.4, a: 0.18)
            let shadow = Effect(color: color, dx: CGFloat(i * 3), dy: CGFloat(i * 3 + 2), blur: CGFloat(4 + i * 2))
            shadowBox.effects.append(shadow)
        }
        nodes.append(shadowBox)
        nodes.append(shape("Gradient — edit handles while picker stays open", 370, 150,
                           .gradient(GradientFill(stops: [GradientStop(color: teal, position: 0), GradientStop(color: violet, position: 1)]))))
        nodes.append(shape("Mesh — edit handles while picker stays open", 680, 150, .mesh(.seeded(base: teal))))
        nodes.append(label("Font field — change size, then open the font family picker", 60, 370, 24))
        nodes.append(label("Check light/dark, larger interface text, Reduce Motion, keyboard and VoiceOver.", 32, 570))

        let x: CGFloat = 1120
        nodes.append(label("02  Folder eyedropper and empty path", x + 32, 24, 28))
        nodes.append(label("Select Plain folder in Layers, press i, and sample the teal rectangle on board 01.", x + 32, 78))
        var locked = shape("Locked child — must stay blue", 270, 0, .solid(blue)); locked.isLocked = true
        var hidden = shape("Hidden child — must stay violet", 0, 180, .solid(violet)); hidden.isVisible = false
        let deep = Node(name: "Nested folder", frame: CGRect(x: 0, y: 180, width: 210, height: 140),
                        content: .group(children: [shape("Deep child — should recolor", 0, 0, .solid(violet))]))
        nodes.append(Node(name: "Plain folder — eyedropper target", frame: CGRect(x: x + 60, y: 150, width: 480, height: 320),
                          content: .group(children: [shape("Visible child — should recolor", 0, 0, .solid(violet)), locked, hidden, deep])))
        nodes.append(Node(name: "Empty path — select via Layers", frame: CGRect(x: x + 730, y: 160, width: 100, height: 100),
                          content: .path(PathShape(points: [], closed: true, fill: .gradient(GradientFill(kind: .radial))))))
        nodes.append(label("Empty path is intentionally invisible; select it in Layers and inspect Fill.", x + 32, 550))
        nodes.append(label("Undo the folder recolor. Locked and hidden children must remain unchanged.", x + 32, 590))

        // A deterministic, valid PNG shared by placements, a source and a pattern.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 1024, bitsPerPixel: 32)!
        for row in 0..<256 {
            for column in 0..<256 {
                let offset = row * 1024 + column * 4
                bitmap.bitmapData![offset] = UInt8(column)
                bitmap.bitmapData![offset + 1] = UInt8(row)
                bitmap.bitmapData![offset + 2] = UInt8((column * 13 + row * 7) % 256)
                bitmap.bitmapData![offset + 3] = 255
            }
        }
        let png = bitmap.representation(using: .png, properties: [:])!
        func image(_ name: String, _ point: CGPoint) -> Node {
            Node(name: name, frame: CGRect(origin: point, size: CGSize(width: 210, height: 210)),
                 content: .image(ImageContent(data: png, naturalSize: CGSize(width: 256, height: 256))))
        }
        let source = ComponentSource(name: "Image component — storage check", size: CGSize(width: 210, height: 210),
                                     children: [image("Source image", .zero)])
        let pattern = PatternSource(name: "Image tile — storage check", children: [image("Tile image", .zero)],
                                    tileSize: CGSize(width: 210, height: 210))
        let sx: CGFloat = 2240
        nodes.append(label("03  Save, reopen and storage checks", sx + 32, 24, 28))
        nodes.append(label("The same PNG appears in two placements, a component and a pattern.", sx + 32, 78))
        nodes.append(image("Image A", CGPoint(x: sx + 60, y: 150)))
        nodes.append(image("Image B — same bytes, different node", CGPoint(x: sx + 370, y: 150)))
        nodes.append(Node(name: "Image component instance", frame: CGRect(x: sx + 680, y: 150, width: 210, height: 210),
                          content: .instance(ComponentInstance(sourceID: source.id))))
        nodes.append(label("Use File → Save a Package Copy; open that copy to test repeated saves.", sx + 32, 450))
        nodes.append(label("Then Save a Legacy JSON Copy and open it separately. Images must match.", sx + 32, 490))
        var document = Document(artboards: boards, nodes: nodes, sources: [source])
        document.patterns = [pattern]
        document.codeBridges = [CodeBridgeManifest(connector: "release-review", source: CodeBridgeSource(displayName: "Review fixture"),
                                                    resources: [CodeBridgeResource(path: "image.png", role: "source", preservedData: png)])]
        document.reconcileArtboardOwnership(on: document.pages[0].id)
        let legacy = try NativeDocumentStorage.legacyData(document)
        try legacy.write(to: output.appendingPathComponent("EXP-release-review.design"))
        try NativeDocumentStorage.package(document).write(to: output.appendingPathComponent("EXP-release-review.designpkg"), options: .atomic, originalContentsURL: nil)
        var future = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        future["schemaVersion"] = 7
        future["writtenBy"] = ["appVersion": "99.0", "build": 999, "schemaVersion": 7]
        try JSONSerialization.data(withJSONObject: future, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Newer-version-warning.design"))
        for (index, board) in boards.enumerated() {
            guard let preview = ExportRenderer(document: document).pngData(for: board, scale: 1) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try preview.write(to: output.appendingPathComponent("Preview-\(index + 1).png"))
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try fm.copyItem(at: root.appendingPathComponent("spike/release-review/import"), to: output.appendingPathComponent("HTML-import"))
        try fm.copyItem(at: root.appendingPathComponent("spike/library-tokens/start-2"), to: output.appendingPathComponent("Token-library"))
        try fm.copyItem(at: root.appendingPathComponent("docs/TESTING-v2.8-RELEASE.md"), to: output.appendingPathComponent("README.md"))
        print(output.path)
    }
}

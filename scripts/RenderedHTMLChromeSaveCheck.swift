import AppKit
import Foundation

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? 20, height: 20)
    }
    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

private func descendants(_ node: Node) -> [Node] {
    if case .group(let children) = node.content {
        return [node] + children.flatMap(descendants)
    }
    return [node]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

@main
private enum RenderedHTMLChromeSaveCheck {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fail("usage: rendered-html-chrome-save-check /path/to/saved-page.html")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let html = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
                let result = try await RenderedHTMLWebKitCapture().readLocalFile(
                    from: html, scopedDirectory: html.deletingLastPathComponent(),
                    viewports: [
                        RenderedHTMLViewport(name: "Phone", width: 393,
                                             renderHeight: 852),
                        RenderedHTMLViewport(name: "Desktop", width: 1440,
                                             renderHeight: 1024)
                    ])
                let nodes = result.payload.pages.flatMap(\.nodes).flatMap(descendants)
                let images = nodes.filter { if case .image = $0.content { return true }; return false }
                let backgrounds = images.filter { $0.name == "Background image" }
                let editableSVGs = result.report.mappedCounts["Editable SVG"] ?? 0
                let editableSVGBackgrounds = result.report.mappedCounts["Editable SVG background"] ?? 0
                let placeholders = result.report.issues.filter { $0.category == "Placeholder" }
                guard images.count >= 20 else {
                    fail("expected a real Chrome save to embed its image assets; found \(images.count)\n\(result.report.detailedText)")
                }
                guard placeholders.isEmpty else {
                    fail("loaded local images must not remain placeholders: \(placeholders)")
                }
                guard editableSVGs > 0, editableSVGBackgrounds > 0 else {
                    fail("the Chrome save should retain inline/local SVG and SVG backgrounds as editable geometry")
                }
                let issueCounts = Dictionary(grouping: result.report.issues, by: \.category)
                    .mapValues(\.count)
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                print("ok: Chrome save mapped \(images.count) raster image nodes, \(editableSVGs) editable SVGs, and \(editableSVGBackgrounds) editable SVG background layers (plus \(backgrounds.count) raster CSS backgrounds) from its companion resource folder")
                print(result.report.summary)
                print("report categories: \(issueCounts)")
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        }
        app.run()
    }
}

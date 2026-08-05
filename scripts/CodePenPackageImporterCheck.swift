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

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

private func flatten(_ node: Node) -> [Node] {
    var result = [node]
    if case .group(let children) = node.content {
        result.append(contentsOf: children.flatMap(flatten))
    }
    return result
}

private func isGroup(_ node: Node) -> Bool {
    if case .group = node.content { return true }
    return false
}

@main
private enum CodePenPackageImporterCheck {
    static func main() {
        guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
            fail("usage: CodePenPackageImporterCheck <export.zip> [--live-opacity]")
        }
        for unsafe in ["../escape.html", "/absolute.html", "folder\\item.html",
                       "dist//index.html", "./dist/index.html"] {
            do {
                _ = try CodePenZipArchive.normalizedArchivePath(unsafe)
                fail("unsafe ZIP path was accepted: \(unsafe)")
            } catch { }
        }
        let opacityChild = Node(name: "Nested", frame: CGRect(x: 0, y: 0,
                                                               width: 10, height: 10),
                                content: .rectangle(RectangleShape()))
        let opacityGroup = Node(name: "Group", frame: CGRect(x: 0, y: 0,
                                                              width: 20, height: 20),
                                content: .group(children: [opacityChild]))
        var opacityTree = [opacityGroup]
        require(LayerOpacityMutation.apply(0.4, to: [opacityGroup.id],
                                           in: &opacityTree)
                && opacityTree[0].opacity == 0.4,
                "shared opacity mutation should reach a selected group")
        require(LayerOpacityMutation.apply(0.7, to: [opacityChild.id],
                                           in: &opacityTree),
                "shared opacity mutation should recurse to a selected nested layer")
        guard case .group(let opacityChildren) = opacityTree[0].content else {
            fail("opacity test group was lost")
        }
        require(opacityChildren[0].opacity == 0.7,
                "nested opacity mutation did not persist")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let zip = URL(fileURLWithPath: CommandLine.arguments[1])
                let result = try await CodePenPackageImporter().read(
                    from: zip,
                    viewports: [
                        RenderedHTMLViewport(name: "Phone", width: 393,
                                             renderHeight: 852),
                        RenderedHTMLViewport(name: "Desktop", width: 1440,
                                             renderHeight: 1024)
                    ])
                require(result.report.format == .codePen,
                        "report should identify CodePen 2.0")
                require(result.payload.pages.count == 1,
                        "one exported Pen should produce one canvas page")
                let page = result.payload.pages[0]
                require(page.name == zip.deletingPathExtension().lastPathComponent,
                        "canvas page should use the export name")
                require(page.artboards.count == 2,
                        "two requested viewports should produce two artboards")
                require(page.artboards.allSatisfy {
                    $0.notes.contains("dist/index.html")
                        && !$0.notes.contains("EXP-CodePen-Import-")
                }, "artboard notes should retain only the relative package entry")

                let nodes = page.nodes.flatMap(flatten)
                if CommandLine.arguments.last == "--live-opacity" {
                    let sections = nodes.filter { $0.name == "section.section" }
                    require(!sections.isEmpty,
                            "the live opacity probe found no section.section groups")
                    require(sections.allSatisfy { $0.opacity > 0.999 },
                            "live finite entrance-animation sections were not stabilized: \(sections.map(\.opacity))")
                    print("ok: live CodePen export has \(sections.count) section groups at final visible opacity")
                    app.terminate(nil)
                    return
                }
                let cards = nodes.filter { $0.name == "main.card" }
                require(cards.count == 2 && cards.allSatisfy { $0.opacity == 1 },
                        "finite entrance animations should be sampled at their final visible state")
                require(nodes.contains {
                    $0.name == "Editable geometric mark" && isGroup($0)
                }, "the dist SVG should remain editable native vector artwork")

                guard result.codeBridges.count == 1 else {
                    fail("CodePen import should create one provenance manifest")
                }
                let bridge = result.codeBridges[0]
                require(bridge.connector == "codepen-2-zip",
                        "manifest connector should identify the CodePen ZIP boundary")
                require(bridge.source.entryPath == "dist/index.html",
                        "manifest should bind the last successful build entry")
                require(bridge.source.stableID?.hasPrefix("codepen-export:") == true,
                        "manifest should carry a content-addressed package identity")
                require(bridge.metadata["buildExecution"] == "never"
                        && bridge.metadata["renderedJavaScriptPolicy"] == "isolated-browser-only"
                        && bridge.metadata["sourceScriptPolicy"] == "preserve-opaque-no-execute"
                        && bridge.metadata["sourceWritePolicy"] == "receipt-only",
                        "manifest must distinguish isolated render JS from source/build execution and write-back")
                require(bridge.bindings.allSatisfy {
                    $0.sourcePath == "dist/index.html" && $0.writableProperties.isEmpty
                }, "all imported bindings should remain receipt-only")

                let paths = Set(bridge.resources.map(\.path))
                for path in ["dist/index.html", "dist/style.css", "dist/script.js",
                             "dist/mark.svg", "src/index.html", "src/style.scss",
                             "src/script.ts", "src/.codepen/pen.config.json", "LICENSE"] {
                    require(paths.contains(path), "missing package receipt: \(path)")
                }
                guard let config = bridge.resources.first(where: {
                    $0.path == "src/.codepen/pen.config.json"
                }), let configData = config.preservedData else {
                    fail("CodePen configuration should be retained as bounded source")
                }
                require(String(decoding: configData, as: UTF8.self).contains("typescript"),
                        "Block configuration bytes should survive unchanged")
                require(config.metadata["packageSection"] == "codepen-configuration",
                        "protected CodePen configuration should be classified explicitly")
                guard let authoredScript = bridge.resources.first(where: {
                    $0.path == "src/script.ts"
                }) else { fail("authored TypeScript receipt is missing") }
                require(authoredScript.preservedData != nil
                        && authoredScript.metadata["executedAsBuildInput"] == "false",
                        "authored source should be preserved but never executed as build input")
                require(bridge.resources.allSatisfy {
                    $0.sha256?.count == 64 && ($0.byteCount ?? -1) >= 0
                }, "every package file should carry size and SHA-256 receipt")
                require(result.report.detailedText.contains("did not run a package manager")
                        && result.report.detailedText.contains("Browser-ready JavaScript")
                        && result.report.detailedText.contains("advanced 1 finite animation")
                        && result.report.detailedText.contains("Block/processor"),
                        "import report should state the execution and configuration boundaries")

                print("ok: CodePen ZIP shape and traversal guard")
                print("ok: last successful dist build imported at two viewports")
                print("ok: SVG remains editable and no private temp path is retained")
                print("ok: src/config/Block bytes, paths, sizes, and hashes preserved")
                print("ok: all source bindings remain receipt-only")
                print("ok: shared canvas/Layers opacity mutation reaches groups and nested layers")
                app.terminate(nil)
            } catch {
                fail(String(reflecting: error))
            }
        }
        app.run()
    }
}

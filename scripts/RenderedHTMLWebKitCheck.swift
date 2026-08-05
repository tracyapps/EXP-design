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

private struct FlatNode {
    var node: Node
    var frame: CGRect
}

private func flatten(_ node: Node, parentOrigin: CGPoint = .zero) -> [FlatNode] {
    let frame = node.frame.offsetBy(dx: parentOrigin.x, dy: parentOrigin.y)
    var result = [FlatNode(node: node, frame: frame)]
    if case .group(let children) = node.content {
        result.append(contentsOf: children.flatMap { flatten($0, parentOrigin: frame.origin) })
    }
    return result
}

/// Mirrors the canvas' finite TextKit container closely enough to catch the
/// importer handing it browser ink bounds instead of full CSS line boxes.
private func textOverflows(_ node: Node) -> Bool {
    guard case .text(let text) = node.content, !text.isEmpty else { return false }
    let paragraph = NSMutableParagraphStyle()
    switch text.align {
    case .left: paragraph.alignment = .left
    case .center: paragraph.alignment = .center
    case .right: paragraph.alignment = .right
    }
    switch text.lineHeightUnit {
    case .auto: paragraph.lineHeightMultiple = 0
    case .multiple: paragraph.lineHeightMultiple = text.lineHeight
    case .px:
        paragraph.minimumLineHeight = text.lineHeight
        paragraph.maximumLineHeight = text.lineHeight
    case .em:
        let height = text.lineHeight * text.firstRun.fontSize
        paragraph.minimumLineHeight = height
        paragraph.maximumLineHeight = height
    }
    let attributed = NSMutableAttributedString()
    for run in text.runs {
        var font = NSFont(name: run.fontName, size: run.fontSize)
            ?? NSFont.systemFont(ofSize: run.fontSize)
        if run.fontName.lowercased().contains("bold") {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        attributed.append(NSAttributedString(
            string: text.textCase.apply(run.string),
            attributes: [.font: font, .paragraphStyle: paragraph,
                         .kern: text.tracking]))
    }
    let storage = NSTextStorage(attributedString: attributed)
    let layout = NSLayoutManager()
    layout.usesFontLeading = true
    let container = NSTextContainer(containerSize: node.frame.size)
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let glyphs = layout.glyphRange(for: container)
    let characters = layout.characterRange(forGlyphRange: glyphs,
                                            actualGlyphRange: nil)
    let end = min(storage.length, NSMaxRange(characters))
    guard end < storage.length else { return false }
    let remainder = (storage.string as NSString).substring(
        with: NSRange(location: end, length: storage.length - end))
    return remainder.rangeOfCharacter(
        from: CharacterSet.whitespacesAndNewlines.inverted) != nil
}

private func naturalTextWidth(_ text: TextContent) -> CGFloat {
    text.runs.reduce(0) { total, run in
        var font = NSFont(name: run.fontName, size: run.fontSize)
            ?? NSFont.systemFont(ofSize: run.fontSize)
        if run.fontName.lowercased().contains("bold") {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        let string = text.textCase.apply(run.string)
        return total + NSAttributedString(
            string: string, attributes: [.font: font, .kern: text.tracking]).size().width
    }
}

@main
private enum RenderedHTMLWebKitCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
          do {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent("spike/html-import/fixture2-handwritten/index.html")
        let viewports = [
            RenderedHTMLViewport(name: "Phone", width: 393, renderHeight: 852),
            RenderedHTMLViewport(name: "Desktop", width: 1440, renderHeight: 1024)
        ]
        let result = try await RenderedHTMLWebKitCapture().readLocalFile(
            from: fixture, viewports: viewports)
        require(result.payload.pages.count == 1,
                "one local document at two widths should produce one canvas page")
        let page = result.payload.pages[0]
        require(page.artboards.count == 2,
                "the real WebKit render should produce two viewport artboards")
        require(page.artboards.map(\.frame.width) == [393, 1440],
                "artboard widths should equal the selected CSS viewports")
        require(page.artboards.allSatisfy { $0.frame.height > 0 },
                "measured document heights must remain finite and positive")
        require(page.artboards[0].notes.contains("max-width: 768px) => true")
                && page.artboards[1].notes.contains("max-width: 768px) => false"),
                "the real CSS media query should resolve differently at Phone and Desktop; notes were \(page.artboards.map(\.notes)); report was \(result.report.detailedText)")

        let flat = page.nodes.flatMap { flatten($0) }
        let cards = flat.filter { $0.node.name == "article.card" }
        require(cards.count == 4, "two cards should map at each of two viewports")
        let phoneCards = cards.filter { $0.frame.minX < 393 }
        let desktopOrigin = page.artboards[1].frame.minX
        let desktopCards = cards.filter { $0.frame.minX >= desktopOrigin }
        require(phoneCards.count == 2 && desktopCards.count == 2,
                "each viewport should retain both article boxes")
        require(abs(phoneCards[0].frame.minX - phoneCards[1].frame.minX) < 1,
                "the phone media query should stack cards at one x coordinate")
        require(abs(desktopCards[0].frame.minX - desktopCards[1].frame.minX) > 20,
                "the desktop layout should place cards at distinct x coordinates")
        require(flat.contains { if case .text = $0.node.content { return true }; return false },
                "WebKit text rects should reach editable EXP text nodes")
        let editableSwatches = flat.filter {
            guard $0.node.name == "A blue rounded swatch" else { return false }
            if case .group = $0.node.content { return true }
            return false
        }
        require(editableSwatches.count == 4,
                "the two local SVG swatches at each viewport should remain editable vector groups")
        require(!result.report.issues.contains { $0.category == "Placeholder" },
                "successfully decoded local images must not leave placeholder warnings")
        let clippedText = flat.filter { textOverflows($0.node) }.map {
            guard case .text(let text) = $0.node.content else { return $0.node.name }
            return "\($0.node.name) [\($0.node.frame.width)×\($0.node.frame.height), natural width \(naturalTextWidth(text)), line \(text.lineHeight), font \(text.firstRun.fontName) \(text.firstRun.fontSize)]"
        }
        require(clippedText.isEmpty,
                "the production importer should provide full TextKit line boxes; clipped: \(clippedText)")
        let expectedInlineParagraph = "An external link that must map to a link role, and bold plus italic runs inside one paragraph so text-run splitting is exercised."
        let inlineParagraphs: [TextContent] = flat.compactMap {
            guard case .text(let text) = $0.node.content,
                  text.plainString.contains("An external link") else { return nil }
            return text
        }
        require(inlineParagraphs.count == 2,
                "mixed inline content should produce one rich text box per viewport, not overlapping DOM-fragment boxes")
        require(inlineParagraphs.allSatisfy { $0.plainString == expectedInlineParagraph },
                "inline DOM order and collapsed boundary whitespace must survive in one paragraph")
        require(inlineParagraphs.allSatisfy { text in
            text.runs.contains {
                $0.string.contains("An external link") && $0.underline
                    && $0.linkURL == "https://example.com/somewhere"
            }
                && text.runs.contains { $0.string.contains("bold") && $0.fontName.lowercased().contains("bold") }
                && text.runs.contains {
                    $0.string.contains("italic")
                        && ($0.fontName.lowercased().contains("italic")
                            || $0.fontName.lowercased().contains("oblique"))
                }
        }, "link destination, bold, and italic inline styles should remain distinct runs in the merged EXP text box")
        require(flat.contains { node in
            guard case .rectangle(let shape) = node.node.content else { return false }
            return shape.fill.isGradient
        }, "the live accent-card gradient should remain editable")
        require(result.report.issues.contains { $0.category == "Sources" },
                "the local-only source receipt should be present")
        require(result.codeBridges.count == 1,
                "the live local import should produce one source bridge")
        let bridge = result.codeBridges[0]
        require(bridge.source.entryPath == "index.html"
                && bridge.source.stableID?.hasSuffix("/index.html") == true,
                "the bridge should retain a relative, non-secret local source identity")
        let entryResource = bridge.resources.first { $0.path == "index.html" }
        let styleResource = bridge.resources.first { $0.path == "style.css" }
        let svgResource = bridge.resources.first { $0.path == "swatch.svg" }
        let scriptResource = bridge.resources.first { $0.path == "behavior.js" }
        require(entryResource?.sha256?.count == 64
                && entryResource?.preservedData != nil,
                "the used HTML entry should be hashed and retained byte-for-byte")
        require(styleResource?.role == "stylesheet"
                && styleResource?.preservedData != nil,
                "used CSS should be retained as opaque source")
        require(svgResource?.role == "image"
                && svgResource?.preservedData != nil,
                "used text SVG source should remain available for editable re-import/handoff")
        require(scriptResource?.role == "script"
                && scriptResource?.preservedData != nil,
                "used JavaScript should remain byte-for-byte opaque source, not editable canvas behavior")
        require(bridge.bindings.contains { $0.expNodeID != nil }
                && bridge.bindings.allSatisfy { $0.writableProperties.isEmpty },
                "DOM bindings should exist but remain receipt-only until a source contract grants writes")
        require(result.report.issues.contains { $0.category == "Source provenance" },
                "bounded source retention should be visible in the import report")

        var cappedLimits = RenderedHTMLWebKitCapture.Limits()
        cappedLimits.maximumNodes = 12
        let capped = try await RenderedHTMLWebKitCapture(limits: cappedLimits)
            .readLocalFile(from: fixture, viewports: viewports)
        require(capped.payload.pages[0].artboards.count == 1,
                "the import-wide node cap should omit later viewports after the first partial capture")
        require(capped.report.issues.contains {
            $0.category == "Limits" && $0.fidelity == .unsupported
        }, "an import-wide node cap must be visible in the fidelity report")

        // A symlink inside the chosen folder must not turn into permission to
        // read its target outside that folder. If escaped.css loads, this box is
        // forced to 37px; blocked local CSS leaves the normal block width.
        let safetyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("exp-html-symlink-\(UUID().uuidString)")
        let safetyRoot = safetyBase.appendingPathComponent("allowed")
        try FileManager.default.createDirectory(at: safetyRoot,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: safetyBase) }
        let outsideCSS = safetyBase.appendingPathComponent("outside.css")
        try Data("#target { width: 37px; }".utf8).write(to: outsideCSS)
        try FileManager.default.createSymbolicLink(
            at: safetyRoot.appendingPathComponent("escaped.css"),
            withDestinationURL: outsideCSS)
        let safetyHTML = safetyRoot.appendingPathComponent("index.html")
        try Data("""
        <!doctype html><html><head><link rel="stylesheet" href="escaped.css"></head>
        <body><div id="target" style="height:20px;background:red"></div></body></html>
        """.utf8).write(to: safetyHTML)
        let safety = try await RenderedHTMLWebKitCapture().readLocalFile(
            from: safetyHTML, scopedDirectory: safetyRoot,
            viewports: [RenderedHTMLViewport(name: "Safety", width: 320,
                                              renderHeight: 240)])
        let safetyNodes = safety.payload.pages[0].nodes.flatMap { flatten($0) }
        let target = safetyNodes.first { $0.node.name == "div#target" }
        require((target?.frame.width ?? 0) > 100,
                "a local symlink must not load CSS from outside the selected folder")

        // Framework portals often mount under a zero-size absolute wrapper,
        // while icon systems reference symbols in a same-folder SVG sprite.
        // Both must survive the browser-to-native boundary as editable nodes.
        let sprite = safetyRoot.appendingPathComponent("sprite.svg")
        try Data("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <symbol id="mark" viewBox="0 0 24 24">
            <defs><linearGradient id="tone"><stop stop-color="#36c"/><stop offset="1" stop-color="#8cf"/></linearGradient></defs>
            <path d="M2 12 L9 19 L22 4" fill="none" stroke="url(#tone)" stroke-width="3"/>
          </symbol>
        </svg>
        """.utf8).write(to: sprite)
        let portalHTML = safetyRoot.appendingPathComponent("portal.html")
        try Data("""
        <!doctype html><html><head><style>
        body{margin:0;height:40px}.hidden-shell{display:none}
        .portal{position:absolute;width:0;height:0}
        .dialog{position:fixed;inset:0;background:#eef;display:grid;place-items:center}
        </style></head><body>
        <div class="hidden-shell"><p>Not rendered</p></div>
        <main>Normal content</main>
        <div class="portal"><section class="dialog" role="dialog" aria-label="Portal dialog">
          <h1>Portal title</h1><svg width="48" height="48"><use href="sprite.svg#mark"/></svg>
        </section></div>
        </body></html>
        """.utf8).write(to: portalHTML)
        let portal = try await RenderedHTMLWebKitCapture().readLocalFile(
            from: portalHTML, scopedDirectory: safetyRoot,
            viewports: [RenderedHTMLViewport(name: "Portal", width: 320,
                                              renderHeight: 240)])
        let portalPage = portal.payload.pages[0]
        let portalNodes = portalPage.nodes.flatMap { flatten($0) }
        require(abs(portalPage.artboards[0].frame.height - 240) < 1,
                "a visible fixed portal should extend the artboard to its viewport")
        require(portalNodes.contains { node in
            guard case .text(let text) = node.node.content else { return false }
            return text.plainString == "Portal title"
        }, "a zero-size portal wrapper must not discard visible descendants")
        require((portal.report.mappedCounts["Editable SVG"] ?? 0) == 1
                && portal.report.mappedCounts["Raster SVG fallback"] == nil,
                "same-folder SVG sprite symbols should be inlined and remain editable")
        require(!portalNodes.contains { node in
            guard case .text(let text) = node.node.content else { return false }
            return text.plainString.contains("Not rendered")
        }, "display:none preparation shells should stay outside the rendered snapshot")

        let cancelled = InteropCancellationToken()
        cancelled.cancel()
        do {
            _ = try await RenderedHTMLWebKitCapture().readLocalFile(
                from: fixture, viewports: [viewports[0]],
                context: InteropContext(cancellation: cancelled))
            fail("a pre-cancelled render should not produce an import")
        } catch InteropCodecError.cancelled {
            // Expected: no payload means the document layer has nothing to mutate.
        }

            print("ok: real WKWebView fixture produces responsive editable artboards, unclipped rich text runs, portal overlays, local SVG sprites, media-query notes, import-wide limits, folder confinement, source receipt, and cancellation")
            exit(0)
          } catch {
            fail(error.localizedDescription)
          }
        }
        app.run()
    }
}

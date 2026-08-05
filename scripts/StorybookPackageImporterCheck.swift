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

private func descendants(_ node: Node) -> [Node] {
    if case .group(let children) = node.content {
        return [node] + children.flatMap(descendants)
    }
    return [node]
}

private struct FlatNode {
    var node: Node
    var frame: CGRect
}

private func flatten(_ node: Node, parentOrigin: CGPoint = .zero) -> [FlatNode] {
    let frame = node.frame.offsetBy(dx: parentOrigin.x, dy: parentOrigin.y)
    var result = [FlatNode(node: node, frame: frame)]
    if case .group(let children) = node.content {
        result.append(contentsOf: children.flatMap {
            flatten($0, parentOrigin: frame.origin)
        })
    }
    return result
}

/// Mirrors the canvas' finite TextKit container so a corpus pass fails when an
/// imported native text box would show EXP's red overflow badge.
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
        let lower = run.fontName.lowercased()
        let reloadable = !run.fontName.hasPrefix(".")
            ? NSFont(name: run.fontName, size: run.fontSize) : nil
        var font = reloadable ?? NSFont.systemFont(ofSize: run.fontSize)
        if reloadable == nil {
            if lower.contains("bold") {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if lower.contains("italic") || lower.contains("oblique") {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
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

@main
private enum StorybookPackageImporterCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("EXP-Storybook-Fixture-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: root,
                                                        withIntermediateDirectories: true)
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("icons"),
                    withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let index = #"""
                {"v":5,"entries":{
                  "controls-button--primary":{"id":"controls-button--primary","title":"Controls/Button","name":"Primary","type":"story","importPath":"./src/Button.stories.tsx","tags":["autodocs"]},
                  "controls-button--danger":{"id":"controls-button--danger","title":"Controls/Button","name":"Danger","type":"story","importPath":"./src/Button.stories.tsx","tags":[]},
                  "controls-button--docs":{"id":"controls-button--docs","title":"Controls/Button","name":"Docs","type":"docs"}
                }}
                """#
                let html = #"""
                <!doctype html><html><head><style>
                body{margin:0;font:16px system-ui;background:#fff}
                main{padding:24px}.card{padding:20px;border:1px solid #bbb;border-radius:10px}
                .sr-only{position:absolute;width:1px;height:1px;overflow:hidden}
                .danger{background:#fee;color:#900}.primary{background:#eef4ff;color:#124}
                .generated::after{content:"Generated label";display:inline-block;width:112px;height:20px}
                .masked::after{content:"";display:block;width:20px;height:20px;background:#1d2c3b;
                  -webkit-mask-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 20 20' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M3 7l7 7 7-7z'/%3E%3C/svg%3E")}
                .local-masked{display:block;width:20px;height:20px;background:#2456a6;
                  -webkit-mask-image:url('/icons/caret.svg')}
                </style></head><body class="sb-main-padded sb-show-main"><main id="storybook-root"></main>
                <script src="/root-ready.js"></script><script>
                const id = new URLSearchParams(location.search).get('id');
                const danger = id.endsWith('danger');
                window.__STORYBOOK_PREVIEW__ = {currentRender: {id, phase: 'completed',
                  story: {id, initialArgs: {label: danger ? 'Delete' : 'Continue', destructive: danger}}}};
                document.querySelector('#storybook-root').innerHTML = `<section class="card ${danger?'danger':'primary'}" aria-label="Story result"><h1>${danger?'Danger story':'Primary story'}</h1><p>${window.rootAssetLabel}</p><button aria-pressed="${danger}">${danger?'Delete':'Continue'}<span class="sr-only">Hidden action description</span></button><span class="generated"></span><i class="masked"></i><i class="local-masked"></i><div style="height:0;overflow:hidden"><p>Collapsed body must stay clipped</p></div></section>`;
                </script></body></html>
                """#
                let project = #"""
                {"framework":{"name":"@storybook/vue3-vite"},
                 "builder":"@storybook/builder-vite","renderer":"@storybook/vue3",
                 "storybookVersion":"8.6.0","language":"typescript",
                 "packageManager":{"type":"pnpm","version":"9.1.0"},
                 "storybookPackages":{"@storybook/vue3-vite":{"version":"8.6.0"},
                   "@storybook/builder-vite":{"version":"8.6.0"}}}
                """#
                try Data(index.utf8).write(to: root.appendingPathComponent("index.json"))
                try Data(html.utf8).write(to: root.appendingPathComponent("iframe.html"))
                try Data(project.utf8).write(to: root.appendingPathComponent("project.json"))
                try Data("window.rootAssetLabel = 'Root asset loaded';".utf8)
                    .write(to: root.appendingPathComponent("root-ready.js"))
                try Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><path fill="#111" d="M3 7l7 7 7-7z"/></svg>"##.utf8)
                    .write(to: root.appendingPathComponent("icons/caret.svg"))

                var selectionLimits = StorybookPackageImporter.Limits()
                selectionLimits.maximumStories = 1
                let selectionImporter = StorybookPackageImporter(limits: selectionLimits)
                let discovery = try selectionImporter.discover(from: root)
                require(discovery.stories.count == 2,
                        "catalog discovery must not reject a build merely because it exceeds the render-selection limit")
                let selectedResult = try await selectionImporter.read(
                    from: root, storyIDs: ["controls-button--danger"],
                    viewports: [RenderedHTMLViewport(name: "Desktop", width: 800,
                                                      renderHeight: 600)])
                require(selectedResult.payload.pages[0].artboards.count == 1
                        && selectedResult.payload.pages[0].artboards[0].name.contains("Danger"),
                        "a large catalog should render only the selected story ids")

                let result = try await StorybookPackageImporter().read(
                    from: root,
                    viewports: [RenderedHTMLViewport(name: "Desktop", width: 800,
                                                      renderHeight: 600)])
                require(result.payload.pages.count == 1,
                        "one Storybook build should create one EXP page")
                let page = result.payload.pages[0]
                require(page.artboards.count == 2,
                        "docs entries should be skipped and both story entries rendered")
                require(page.artboards[0].name.contains("Danger")
                        && page.artboards[1].name.contains("Primary"),
                        "story artboards should use deterministic title/name ordering")
                let text = page.nodes.flatMap(descendants).compactMap { node -> String? in
                    guard case .text(let content) = node.content else { return nil }
                    return content.plainString
                }
                require(text.contains("Danger story") && text.contains("Primary story")
                        && text.contains("Generated label") && text.contains("Root asset loaded"),
                        "iframe query ids, root-level assets, and generated pseudo-element text should render into editable story content; imported: \(text)")
                require(!text.contains("Collapsed body must stay clipped"),
                        "fully overflow-clipped descendants must not become editable story content")
                require(page.nodes.flatMap(descendants).contains { node in
                    guard node.name == "i::after" else { return false }
                    if case .group = node.content { return true }
                    return false
                }, "a bounded data-SVG CSS mask should become editable vector geometry")
                require(page.nodes.flatMap(descendants).contains { node in
                    guard node.name == "i.local-masked" else { return false }
                    if case .group = node.content { return true }
                    return false
                }, "a same-folder SVG CSS mask should become editable vector geometry; imported: \(page.nodes.flatMap(descendants).map(\.name)) / \(result.report.issues)")
                let hiddenAccessibilityNodes = page.nodes.flatMap(descendants).filter {
                    !$0.isVisible && $0.name.hasPrefix("Visually hidden:")
                }
                require(hiddenAccessibilityNodes.count == 2,
                        "1×1 clipped accessibility text should remain as hidden layers")
                require(result.codeBridges.count == 1,
                        "Storybook should produce one hidden package bridge")
                let bridge = result.codeBridges[0]
                require(bridge.connector == "storybook-static"
                        && bridge.behaviorContracts.count == 2,
                        "story ids and index metadata should remain structured contracts")
                require(bridge.source.framework == "@storybook/vue3-vite"
                        && bridge.source.frameworkVersion == "8.6.0"
                        && bridge.source.buildTool == "@storybook/builder-vite"
                        && bridge.source.buildToolVersion == "8.6.0"
                        && bridge.source.metadata["packageManager"] == "pnpm",
                        "published Storybook project metadata should remain structured provenance")
                let dangerContract = bridge.behaviorContracts.first {
                    $0.externalID == "controls-button--danger"
                }
                require(dangerContract?.payload["initialArgsJSON"]?.contains(
                    "\"destructive\":true") == true,
                        "bounded JSON-safe initial args should remain on the story contract")
                require(bridge.resources.contains { $0.path == "index.json" && $0.sha256?.count == 64 }
                        && bridge.resources.contains { $0.path == "project.json" && $0.sha256?.count == 64 }
                        && bridge.resources.contains { $0.path == "icons/caret.svg" && $0.sha256?.count == 64 }
                        && bridge.bindings.allSatisfy { $0.writableProperties.isEmpty },
                        "index/project and DOM receipts should be hashed and receipt-only")
                let bridgeJSON = String(data: try JSONEncoder().encode(bridge),
                                        encoding: .utf8) ?? ""
                require(!bridgeJSON.contains(root.path),
                        "private local Storybook paths must not enter the document")
                require(result.report.format == .storybook
                        && result.report.mappedCounts["Story"] == 2,
                        "the report should identify and count Storybook stories")
                if let livePath = ProcessInfo.processInfo.environment["EXP_STORYBOOK_FIXTURE"],
                   !livePath.isEmpty {
                    let liveRoot = URL(fileURLWithPath: livePath, isDirectory: true)
                    let liveImporter = StorybookPackageImporter()
                    let liveCatalog = try liveImporter.discover(from: liveRoot)
                    let accordionID = "base-accordion--default"
                    let tabsID = "base-tabs--with-counter-badges"
                    let defaultCorpusIDs: Set<String> = [
                        accordionID,
                        tabsID,
                        "base-toggle--default",
                        "base-modal--default",
                        "base-illustration--default",
                        "base-table-table-lite--default",
                        "charts-bar-chart--default",
                        "base-button--button-with-badge"
                    ]
                    let diagnosticStoryID = ProcessInfo.processInfo.environment[
                        "EXP_STORYBOOK_STORY_ID"]?.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    let corpusIDs = diagnosticStoryID?.isEmpty == false
                        ? Set([diagnosticStoryID!]) : defaultCorpusIDs
                    require(corpusIDs.allSatisfy { id in
                        liveCatalog.stories.contains { $0.id == id }
                    },
                            "the live Storybook fixture should contain the diagnostic stories")
                    let liveResult = try await liveImporter.read(
                        from: liveRoot, storyIDs: corpusIDs,
                        viewports: [RenderedHTMLViewport(
                            name: "Desktop", width: 1_440, renderHeight: 1_024)])
                    let livePage = liveResult.payload.pages[0]
                    print("live corpus artboards: " + livePage.artboards.map {
                        "\($0.name)=\(Int($0.frame.width))×\(Int($0.frame.height))"
                    }.joined(separator: ", "))
                    require(livePage.artboards.count == corpusIDs.count
                            && livePage.artboards.allSatisfy { $0.frame.height > 1 },
                            "the production Storybook runtime must finish before capture")
                    require(livePage.artboards.allSatisfy { artboard in
                        livePage.nodes.contains { $0.frame.intersects(artboard.frame) }
                    }, "every corpus artboard should contain mapped top-level artwork")
                    let liveText = livePage.nodes.flatMap(descendants)
                        .compactMap { node -> String? in
                            guard case .text(let content) = node.content else { return nil }
                            return content.plainString
                        }.joined(separator: " ")
                    if diagnosticStoryID?.isEmpty != false {
                        require(liveText.contains("Item 1") && liveText.contains("Item 2"),
                                "the live Storybook DOM should map visible story text")
                        for expected in ["Label", "Example title", "First column",
                                         "Pushes per day", "primary default"] {
                            require(liveText.contains(expected),
                                    "the live corpus should retain visible text: \(expected)")
                        }
                    }
                    let liveHidden = livePage.nodes.flatMap(descendants).filter {
                        !$0.isVisible && $0.name.hasPrefix("Visually hidden:")
                    }
                    if diagnosticStoryID?.isEmpty != false {
                        require(liveHidden.contains { $0.name.contains("42 issues") }
                                && liveHidden.contains { $0.name.contains("15 open issues") }
                                && liveHidden.contains { $0.name.contains("1 closed issue") },
                                "GitLab tab screen-reader labels should remain hidden on canvas")
                    }
                    let mapped = liveResult.report.mappedCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    require((liveResult.report.mappedCounts["Editable SVG"] ?? 0) > 0,
                            "same-folder SVG sprite references should remain editable")
                    let liveBridge = liveResult.codeBridges[0]
                    require(liveBridge.source.framework == "@storybook/vue-webpack5"
                            && liveBridge.source.frameworkVersion == "7.6.24"
                            && liveBridge.source.buildTool == "@storybook/builder-webpack5"
                            && liveBridge.source.metadata["packageManager"] == "yarn",
                            "the live project.json should identify its Storybook framework/build stack")
                    require(liveBridge.behaviorContracts.first {
                        $0.externalID == "base-toggle--default"
                    }?.payload["initialArgsJSON"]?.isEmpty == false,
                            "the live runtime should retain the toggle story's published initial args")
                    let issues = liveResult.report.issues
                        .map { "\($0.category)=\($0.occurrences)" }.joined(separator: ", ")
                    print("live corpus mapped: \(mapped)")
                    print("live corpus report: \(issues)")
                    print("ok: live Storybook ES-module runtime renders through isolated loopback HTTP")
                }
                if let reactVitePath = ProcessInfo.processInfo.environment[
                    "EXP_STORYBOOK_REACT_VITE_FIXTURE"],
                   !reactVitePath.isEmpty {
                    let reactViteRoot = URL(fileURLWithPath: reactVitePath,
                                            isDirectory: true)
                    let reactViteImporter = StorybookPackageImporter()
                    let catalog = try reactViteImporter.discover(from: reactViteRoot)
                    let defaultCorpusIDs: Set<String> = [
                        "components-accordion--default",
                        "components-buttons-button--default",
                        "components-dialog--default",
                        "components-inputs-inputtoggle--default",
                        "components-table-precomposedtable--default",
                        "components-tabs--default",
                        "data-viz-heatmapchart--default",
                        "data-viz-stackedbarchart--default"
                    ]
                    let diagnosticStoryID = ProcessInfo.processInfo.environment[
                        "EXP_STORYBOOK_REACT_VITE_STORY_ID"]?.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    let corpusIDs = diagnosticStoryID?.isEmpty == false
                        ? Set([diagnosticStoryID!]) : defaultCorpusIDs
                    require(catalog.version == "5" && catalog.stories.count >= 200,
                            "the React + Vite fixture should retain its index-v5 catalog")
                    require(corpusIDs.allSatisfy { id in
                        catalog.stories.contains { $0.id == id }
                    }, "the React + Vite fixture should contain the representative corpus")
                    let reactViteResult = try await reactViteImporter.read(
                        from: reactViteRoot, storyIDs: corpusIDs,
                        viewports: [
                            RenderedHTMLViewport(name: "Phone", width: 393,
                                                 renderHeight: 852),
                            RenderedHTMLViewport(name: "Web 1280", width: 1_280,
                                                 renderHeight: 800)
                        ])
                    let reactVitePage = reactViteResult.payload.pages[0]
                    print("React + Vite corpus artboards: " + reactVitePage.artboards.map {
                        "\($0.name)=\(Int($0.frame.width))×\(Int($0.frame.height))"
                    }.joined(separator: ", "))
                    let phoneArtboards = reactVitePage.artboards.filter {
                        $0.name.hasSuffix("— Phone")
                    }
                    let webArtboards = reactVitePage.artboards.filter {
                        $0.name.hasSuffix("— Web 1280")
                    }
                    require(reactVitePage.artboards.count == corpusIDs.count * 2
                            && phoneArtboards.count == corpusIDs.count
                            && webArtboards.count == corpusIDs.count,
                            "the Storybook 10 React + Vite runtime must render every story at both acceptance viewports")
                    require(phoneArtboards.allSatisfy {
                        $0.frame.width == 393 && $0.frame.height >= 852
                    } && webArtboards.allSatisfy {
                        $0.frame.width == 1_280 && $0.frame.height >= 800
                    }, "visible viewport-sized descendants must not be cropped by shrink-wrapped Storybook bodies")
                    require(reactVitePage.artboards.allSatisfy {
                        $0.background.representativeColor.a > 0.999
                    }, "transparent Storybook bodies should retain the browser's opaque canvas backdrop")
                    require(reactVitePage.artboards.allSatisfy { artboard in
                        reactVitePage.nodes.contains { $0.frame.intersects(artboard.frame) }
                    }, "every React + Vite corpus artboard should contain mapped artwork")
                    let reactViteBridge = reactViteResult.codeBridges[0]
                    require(reactViteBridge.source.framework == "@storybook/react-vite"
                            && reactViteBridge.source.frameworkVersion == "10.5.2"
                            && reactViteBridge.source.buildTool == "@storybook/builder-vite"
                            && reactViteBridge.source.buildToolVersion == "10.5.2"
                            && reactViteBridge.source.metadata["renderer"] == "@storybook/react"
                            && reactViteBridge.source.metadata["packageManager"] == "yarn",
                            "the published React + Vite project contract should remain structured provenance")
                    require(reactViteBridge.behaviorContracts.count == corpusIDs.count
                            && reactViteBridge.behaviorContracts.allSatisfy {
                                $0.payload["initialArgsJSON"]?.isEmpty == false
                            }, "Storybook 10 should expose bounded initial args for every selected story")
                    let importedNodes = reactVitePage.nodes.flatMap(descendants)
                    let importedText = importedNodes.compactMap { node -> String? in
                        guard case .text(let content) = node.content else { return nil }
                        return content.plainString
                    }
                    if corpusIDs.contains("components-inputs-inputtoggle--default") {
                        require(importedText.contains("Off"),
                                "generated InputToggle ::after text should remain editable")
                    }
                    let clippedText = importedNodes.filter(textOverflows).map { node in
                        "\(node.name) [\(Int(node.frame.width))×\(Int(node.frame.height))]"
                    }
                    require(clippedText.isEmpty,
                            "the exact Phone/Web corpus should not create native text overflow badges: \(clippedText)")

                    // Owner visual acceptance exposed failures outside the
                    // original eight-story corpus: ContentCard's multiline
                    // fallback font wrapped into an excluded sixth line, while
                    // InputToggle's flex pseudo label and CSS outline disappeared
                    // at the app's real Tablet preset.
                    let tabletResult = try await reactViteImporter.read(
                        from: reactViteRoot,
                        storyIDs: ["components-buttons-button--default",
                                   "components-contentcard--default",
                                   "components-inputs-inputtoggle--default"],
                        viewports: [RenderedHTMLViewport(
                            name: "Tablet", width: 834, renderHeight: 1_194)])
                    let tabletPage = tabletResult.payload.pages[0]
                    require(tabletPage.artboards.count == 3
                            && tabletPage.artboards.allSatisfy {
                                $0.frame.width == 834 && $0.frame.height >= 1_194
                            }, "the real Tablet acceptance stories should retain the selected viewport")
                    let tabletNodes = tabletPage.nodes.flatMap { flatten($0) }
                    let tabletClippedText = tabletNodes.filter {
                        textOverflows($0.node)
                    }.map { "\($0.node.name) [\(Int($0.node.frame.width))×\(Int($0.node.frame.height))]" }
                    require(tabletClippedText.isEmpty,
                            "ContentCard Tablet text should not show native overflow badges: \(tabletClippedText)")
                    guard let paragraph = tabletNodes.first(where: { flat in
                        guard case .text(let content) = flat.node.content else { return false }
                        return content.plainString.hasPrefix("Lorem ipsum dolor sit amet")
                    }) else {
                        fail("ContentCard Tablet should retain its multiline paragraph")
                    }
                    if case .text(let paragraphText) = paragraph.node.content {
                        require(paragraphText.lineHeightUnit == .px
                                && paragraphText.lineHeight == 24,
                                "ContentCard should retain its authored 24px CSS line height")
                    }
                    guard let label = tabletNodes.first(where: { flat in
                        guard case .text(let content) = flat.node.content else { return false }
                        return content.plainString == "Label"
                    }), let button = tabletNodes.first(where: { flat in
                        flat.node.name == "button.MuiButtonBase-root"
                            && flat.frame.contains(CGPoint(x: label.frame.midX,
                                                         y: label.frame.midY))
                    }) else {
                        fail("Button Tablet should retain its Label and button box")
                    }
                    if case .text(let labelText) = label.node.content {
                        require(labelText.lineHeightUnit == .px
                                && labelText.lineHeight == 24,
                                "Button should retain its authored 24px CSS line height")
                    }
                    require(abs(label.frame.midY - button.frame.midY) <= 1.5
                            && label.frame.maxY <= button.frame.maxY + 1,
                            "browser inline ink must be translated back to its centered CSS line box; label=\(label.frame), button=\(button.frame)")
                    guard let off = tabletNodes.first(where: { flat in
                        guard case .text(let content) = flat.node.content else { return false }
                        return content.plainString == "Off"
                    }), let thumb = tabletNodes.first(where: {
                        $0.node.name == "span.MuiSwitch-thumb"
                    }) else {
                        fail("InputToggle Tablet should retain both thumb and generated Off label")
                    }
                    require(off.frame.minX >= thumb.frame.maxX + 1
                            && abs(off.frame.midY - thumb.frame.midY) <= 4,
                            "the generated Off label should occupy its flex position beside the thumb; off=\(off.frame), thumb=\(thumb.frame)")
                    if case .rectangle(let thumbShape) = thumb.node.content {
                        require(abs(thumbShape.cornerRadius - 8) < 0.001,
                                "InputToggle's 16px thumb with 50% CSS radius should remain circular")
                    } else {
                        fail("InputToggle thumb should remain an editable rectangle surface")
                    }
                    require(tabletNodes.contains { flat in
                        guard case .rectangle(let shape) = flat.node.content else { return false }
                        return abs(flat.frame.width - 62) < 1
                            && abs(flat.frame.height - 24) < 1
                            && shape.strokeWidth > 0
                            && shape.strokeAlignment == .outside
                            && abs(shape.effectiveRadii.clamped(
                                to: flat.frame.size).topLeft - 12) < 0.001
                    }, "InputToggle's authored CSS outline should remain an editable outside stroke")
                    if corpusIDs.contains("data-viz-stackedbarchart--default") {
                        require(reactViteResult.report.issues.contains {
                            $0.category == "Viewport overflow"
                        }, "the fixed-width phone chart should be reported as authored viewport overflow, not claimed as responsive")
                        require(reactViteBridge.behaviorContracts.first {
                            $0.externalID == "data-viz-stackedbarchart--default"
                        }?.payload["initialArgsJSON"]?.contains("\"width\":\"360px\"") == true,
                                "the chart's published fixed 360px width should remain explicit provenance")
                    }
                    print("React + Vite Tablet acceptance: paragraph=\(paragraph.node.frame), label=\(label.frame), button=\(button.frame), Off=\(off.frame), thumb=\(thumb.frame), zero text overflows")
                    let mapped = reactViteResult.report.mappedCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    let issues = reactViteResult.report.issues
                        .map { "\($0.category)=\($0.occurrences)" }.joined(separator: ", ")
                    print("React + Vite corpus mapped: \(mapped)")
                    print("React + Vite corpus report: \(issues)")
                    for issue in reactViteResult.report.issues {
                        print("React + Vite issue: \(issue.category) "
                            + "[\(issue.fidelity.rawValue)] ×\(issue.occurrences): "
                            + issue.message)
                    }
                    print("ok: published Storybook 10 React + Vite corpus renders through the framework-neutral seam")
                }
                if let angularWebpackPath = ProcessInfo.processInfo.environment[
                    "EXP_STORYBOOK_ANGULAR_WEBPACK_FIXTURE"],
                   !angularWebpackPath.isEmpty {
                    let angularWebpackRoot = URL(
                        fileURLWithPath: angularWebpackPath, isDirectory: true)
                    let angularWebpackImporter = StorybookPackageImporter()
                    let catalog = try angularWebpackImporter.discover(
                        from: angularWebpackRoot)
                    let defaultCorpusIDs: Set<String> = [
                        "components-accordion--overview",
                        "components-button--overview",
                        "components-card--metrics-card",
                        "components-modal--overview",
                        "components-switch--overview",
                        "patterns-sign-in--overview"
                    ]
                    let diagnosticStoryID = ProcessInfo.processInfo.environment[
                        "EXP_STORYBOOK_ANGULAR_WEBPACK_STORY_ID"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let corpusIDs = diagnosticStoryID?.isEmpty == false
                        ? Set([diagnosticStoryID!]) : defaultCorpusIDs
                    require(catalog.version == "5" && catalog.stories.count >= 46,
                            "the Angular + webpack fixture should retain its index-v5 catalog")
                    require(corpusIDs.allSatisfy { id in
                        catalog.stories.contains { $0.id == id }
                    }, "the Angular + webpack fixture should contain the representative corpus")
                    let angularWebpackResult = try await angularWebpackImporter.read(
                        from: angularWebpackRoot, storyIDs: corpusIDs,
                        viewports: [
                            RenderedHTMLViewport(name: "Phone", width: 393,
                                                 renderHeight: 852),
                            RenderedHTMLViewport(name: "Web 1280", width: 1_280,
                                                 renderHeight: 800)
                        ])
                    let angularWebpackPage = angularWebpackResult.payload.pages[0]
                    print("Angular + webpack corpus artboards: "
                        + angularWebpackPage.artboards.map {
                            "\($0.name)=\(Int($0.frame.width))×\(Int($0.frame.height))"
                        }.joined(separator: ", "))
                    let phoneArtboards = angularWebpackPage.artboards.filter {
                        $0.name.hasSuffix("— Phone")
                    }
                    let webArtboards = angularWebpackPage.artboards.filter {
                        $0.name.hasSuffix("— Web 1280")
                    }
                    require(angularWebpackPage.artboards.count == corpusIDs.count * 2
                            && phoneArtboards.count == corpusIDs.count
                            && webArtboards.count == corpusIDs.count,
                            "the Storybook 8 Angular + webpack runtime must render every story at both acceptance viewports")
                    require(phoneArtboards.allSatisfy {
                        $0.frame.width == 393 && $0.frame.height >= 852
                    } && webArtboards.allSatisfy {
                        $0.frame.width == 1_280 && $0.frame.height >= 800
                    }, "the Angular corpus should retain both requested viewport canvases")
                    require(angularWebpackPage.artboards.allSatisfy {
                        $0.background.representativeColor.a > 0.999
                    }, "the Angular corpus should retain the browser's opaque canvas backdrop")
                    require(angularWebpackPage.artboards.allSatisfy { artboard in
                        angularWebpackPage.nodes.contains {
                            $0.frame.intersects(artboard.frame)
                        }
                    }, "every Angular + webpack corpus artboard should contain mapped artwork")
                    let angularWebpackBridge = angularWebpackResult.codeBridges[0]
                    require(angularWebpackBridge.source.framework == "@storybook/angular"
                            && angularWebpackBridge.source.frameworkVersion == "8.6.18"
                            && angularWebpackBridge.source.buildTool == "@storybook/builder-webpack5"
                            && angularWebpackBridge.source.buildToolVersion == "8.6.18"
                            && angularWebpackBridge.source.metadata["renderer"] == "@storybook/angular"
                            && angularWebpackBridge.source.metadata["packageManager"] == "npm",
                            "the published Angular + webpack project contract should remain structured provenance")
                    require(angularWebpackBridge.resources.first {
                        $0.path == "index.json"
                    }?.sha256 == "9dd74882d46ec3efd0fd3543f2aa47783db802eda00cac7ed983a92c17d0a00b"
                            && angularWebpackBridge.resources.first {
                                $0.path == "project.json"
                            }?.sha256 == "eebc54b6353ffdb0c96754e769e33768948f7558f865f5c9c631bd79a26d2fd1",
                            "the Angular regression should remain pinned to the measured v3.0.1 deployment receipts")
                    require(angularWebpackBridge.behaviorContracts.count == corpusIDs.count
                            && angularWebpackBridge.behaviorContracts.allSatisfy {
                                $0.payload["initialArgsJSON"]?.isEmpty == false
                            }, "every selected Angular story should retain its published initial args")
                    let importedNodes = angularWebpackPage.nodes.flatMap(descendants)
                    let importedText = importedNodes.compactMap { node -> String? in
                        guard case .text(let text) = node.content else { return nil }
                        return text.plainString
                    }
                    let hiddenAccessibilityNodes = importedNodes.filter {
                        !$0.isVisible && $0.name.hasPrefix("Visually hidden:")
                    }
                    require(!importedText.contains("404 Not Found"),
                            "root-relative files present in the selected static build must not import the loopback server's 404 body")
                    if corpusIDs.contains("components-accordion--overview") {
                        require(importedText.contains("How long does delivery take?")
                                && importedText.contains("Can I cancel my order after placing it?")
                                && importedText.contains("What payment methods are accepted?"),
                                "the collapsed accordion headings should remain editable")
                        require(!importedText.contains(where: {
                            $0.contains("Delivery times vary based on your location")
                                || $0.contains("Once shipped, you will need to request a return")
                                || $0.contains("We accept credit cards, debit cards")
                        }), "overflow-clipped collapsed accordion bodies must not be resurrected as editable text")
                        let editableCarets = importedNodes.filter { node in
                            guard node.name == "span::after" else { return false }
                            if case .group = node.content { return true }
                            return false
                        }
                        require(editableCarets.count == 6,
                                "the three data-SVG accordion carets at both viewports should remain editable vectors")
                    }
                    if corpusIDs.contains("components-switch--overview") {
                        let switchArtboards = angularWebpackPage.artboards.filter {
                            $0.name.hasPrefix("Components/Switch / Overview")
                        }
                        require(switchArtboards.allSatisfy { artboard in
                            let switchNodes = angularWebpackPage.nodes.filter {
                                $0.frame.intersects(artboard.frame)
                            }.flatMap { flatten($0) }
                            guard let control = switchNodes.first(where: {
                                $0.node.name.hasPrefix("input.")
                                    && abs($0.frame.width - 40) < 0.6
                                    && abs($0.frame.height - 24) < 0.6
                            }), let thumb = switchNodes.first(where: {
                                $0.node.name == "input::before"
                            }) else { return false }
                            return abs(thumb.frame.midY - control.frame.midY) < 0.6
                                && thumb.frame.minX >= control.frame.minX
                                && thumb.frame.maxX <= control.frame.maxX
                        },
                                "the transformed switch thumb should stay centered inside its control")
                    }
                    if diagnosticStoryID?.isEmpty != false {
                        require(angularWebpackResult.report.mappedCounts["Text"] == 52
                                && angularWebpackResult.report.mappedCounts["Semantic role"] == 32
                                && angularWebpackResult.report.mappedCounts["ARIA attribute"] == 32
                                && hiddenAccessibilityNodes.count == 2,
                                "the measured Angular corpus should retain only painted text and authored accessibility semantics")
                    }
                    let clippedText = importedNodes.filter(textOverflows).map { node in
                        "\(node.name) [\(Int(node.frame.width))×\(Int(node.frame.height))]"
                    }
                    require(clippedText.isEmpty,
                            "the exact Angular corpus should not create native text overflow badges: \(clippedText)")
                    let mapped = angularWebpackResult.report.mappedCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    let issues = angularWebpackResult.report.issues
                        .map { "\($0.category)=\($0.occurrences)" }
                        .joined(separator: ", ")
                    print("Angular + webpack corpus mapped: \(mapped)")
                    print("Angular + webpack corpus report: \(issues)")
                    for issue in angularWebpackResult.report.issues {
                        print("Angular + webpack issue: \(issue.category) "
                            + "[\(issue.fidelity.rawValue)] ×\(issue.occurrences): "
                            + issue.message)
                    }
                    print("ok: published Storybook 8 Angular + webpack corpus renders through the framework-neutral seam")
                }
                if let svelteVitePath = ProcessInfo.processInfo.environment[
                    "EXP_STORYBOOK_SVELTE_VITE_FIXTURE"],
                   !svelteVitePath.isEmpty {
                    let svelteViteRoot = URL(
                        fileURLWithPath: svelteVitePath, isDirectory: true)
                    let svelteViteImporter = StorybookPackageImporter()
                    let catalog = try svelteViteImporter.discover(from: svelteViteRoot)
                    let defaultCorpusIDs: Set<String> = [
                        "components-alert--default-alert",
                        "components-button--filled",
                        "components-checkbox--primary",
                        "components-dialog--default",
                        "components-input--character-count",
                        "components-segmentedcontrol--default",
                        "components-tabs--with-icons",
                        "components-toggle--default"
                    ]
                    let diagnosticStoryID = ProcessInfo.processInfo.environment[
                        "EXP_STORYBOOK_SVELTE_VITE_STORY_ID"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let corpusIDs = diagnosticStoryID?.isEmpty == false
                        ? Set([diagnosticStoryID!]) : defaultCorpusIDs
                    require(catalog.version == "5" && catalog.stories.count >= 104,
                            "the Svelte + Vite fixture should retain its index-v5 catalog")
                    require(corpusIDs.allSatisfy { id in
                        catalog.stories.contains { $0.id == id }
                    }, "the Svelte + Vite fixture should contain the representative corpus")
                    let svelteViteResult = try await svelteViteImporter.read(
                        from: svelteViteRoot, storyIDs: corpusIDs,
                        viewports: [
                            RenderedHTMLViewport(name: "Phone", width: 393,
                                                 renderHeight: 852),
                            RenderedHTMLViewport(name: "Web 1280", width: 1_280,
                                                 renderHeight: 800)
                        ])
                    let svelteVitePage = svelteViteResult.payload.pages[0]
                    print("Svelte + Vite corpus artboards: "
                        + svelteVitePage.artboards.map {
                            "\($0.name)=\(Int($0.frame.width))×\(Int($0.frame.height))"
                        }.joined(separator: ", "))
                    let phoneArtboards = svelteVitePage.artboards.filter {
                        $0.name.hasSuffix("— Phone")
                    }
                    let webArtboards = svelteVitePage.artboards.filter {
                        $0.name.hasSuffix("— Web 1280")
                    }
                    require(svelteVitePage.artboards.count == corpusIDs.count * 2
                            && phoneArtboards.count == corpusIDs.count
                            && webArtboards.count == corpusIDs.count,
                            "the Storybook 8 Svelte + Vite runtime must render every story at both acceptance viewports")
                    require(phoneArtboards.allSatisfy {
                        $0.frame.width == 393 && $0.frame.height >= 852
                    } && webArtboards.allSatisfy {
                        $0.frame.width == 1_280 && $0.frame.height >= 800
                    }, "the Svelte corpus should retain both requested viewport canvases")
                    require(svelteVitePage.artboards.allSatisfy {
                        $0.background.representativeColor.a > 0.999
                    }, "the Svelte corpus should retain the browser's opaque canvas backdrop")
                    require(svelteVitePage.artboards.allSatisfy { artboard in
                        svelteVitePage.nodes.contains {
                            $0.frame.intersects(artboard.frame)
                        }
                    }, "every Svelte + Vite corpus artboard should contain mapped artwork")
                    let svelteViteBridge = svelteViteResult.codeBridges[0]
                    require(svelteViteBridge.source.framework == "@storybook/svelte-vite"
                            && svelteViteBridge.source.frameworkVersion == "8.6.18"
                            && svelteViteBridge.source.buildTool == "@storybook/builder-vite"
                            && svelteViteBridge.source.buildToolVersion == "8.6.14"
                            && svelteViteBridge.source.metadata["renderer"] == "@storybook/svelte"
                            && svelteViteBridge.source.metadata["packageManager"] == "pnpm",
                            "the published Svelte + Vite project contract should remain structured provenance")
                    require(svelteViteBridge.resources.first {
                        $0.path == "index.json"
                    }?.sha256 == "c4d1029e385fb55a55c6a62b9b62e95a553bc2e5db8b3563636ffa36ad691ae5"
                            && svelteViteBridge.resources.first {
                                $0.path == "project.json"
                            }?.sha256 == "c4f2dc4f0b7c9afb25598e621835987021c27314d48b8cff25a604ae2ef54e28",
                            "the Svelte regression should remain pinned to the measured Leo deployment receipts")
                    require(svelteViteBridge.behaviorContracts.count == corpusIDs.count
                            && svelteViteBridge.behaviorContracts.allSatisfy {
                                $0.payload["initialArgsJSON"]?.isEmpty == false
                            }, "every selected Svelte story should retain its published initial args")
                    let importedNodes = svelteVitePage.nodes.flatMap(descendants)
                    let importedText = importedNodes.compactMap { node -> String? in
                        guard case .text(let text) = node.content else { return nil }
                        return text.plainString
                    }
                    require(!importedText.contains("404 Not Found"),
                            "missing local Svelte artifact resources must not become editable error text")
                    if diagnosticStoryID?.isEmpty != false {
                        require(svelteViteResult.report.mappedCounts["Text"] == 32
                                && svelteViteResult.report.mappedCounts["Semantic role"] == 28
                                && svelteViteResult.report.mappedCounts["ARIA attribute"] == 14
                                && svelteViteResult.report.mappedCounts["Editable SVG mask"] == 18
                                && svelteViteResult.report.mappedCounts["Shadow"] == 2,
                                "the measured Svelte corpus should retain its painted text, semantics, editable SVG masks, and shadows")
                    }
                    let clippedText = importedNodes.filter(textOverflows).map { node in
                        "\(node.name) [\(Int(node.frame.width))×\(Int(node.frame.height))]"
                    }
                    require(clippedText.isEmpty,
                            "the exact Svelte corpus should not create native text overflow badges: \(clippedText)")
                    let mapped = svelteViteResult.report.mappedCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    let issues = svelteViteResult.report.issues
                        .map { "\($0.category)=\($0.occurrences)" }
                        .joined(separator: ", ")
                    print("Svelte + Vite corpus mapped: \(mapped)")
                    print("Svelte + Vite corpus report: \(issues)")
                    for issue in svelteViteResult.report.issues {
                        print("Svelte + Vite issue: \(issue.category) "
                            + "[\(issue.fidelity.rawValue)] ×\(issue.occurrences): "
                            + issue.message)
                    }
                    print("ok: published Storybook 8 Svelte + Vite corpus renders through the framework-neutral seam")
                }
                if let webComponentsVitePath = ProcessInfo.processInfo.environment[
                    "EXP_STORYBOOK_WEB_COMPONENTS_VITE_FIXTURE"],
                   !webComponentsVitePath.isEmpty {
                    let webComponentsViteRoot = URL(
                        fileURLWithPath: webComponentsVitePath, isDirectory: true)
                    let webComponentsViteImporter = StorybookPackageImporter()
                    let catalog = try webComponentsViteImporter.discover(
                        from: webComponentsViteRoot)
                    let defaultCorpusIDs: Set<String> = [
                        "desktop-button--base",
                        "desktop-checkbox--base",
                        "desktop-dialog--base",
                        "desktop-dropdown--base",
                        "desktop-readonly-table--base",
                        "desktop-switch--base",
                        "desktop-tabs--base",
                        "desktop-text--base"
                    ]
                    let diagnosticStoryID = ProcessInfo.processInfo.environment[
                        "EXP_STORYBOOK_WEB_COMPONENTS_VITE_STORY_ID"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let corpusIDs = diagnosticStoryID?.isEmpty == false
                        ? Set([diagnosticStoryID!]) : defaultCorpusIDs
                    require(catalog.version == "5" && catalog.stories.count == 106,
                            "the Web Components + Vite fixture should retain its 106-story index-v5 catalog")
                    require(corpusIDs.allSatisfy { id in
                        catalog.stories.contains { $0.id == id }
                    }, "the Web Components + Vite fixture should contain the representative corpus")
                    let webComponentsViteResult = try await webComponentsViteImporter.read(
                        from: webComponentsViteRoot, storyIDs: corpusIDs,
                        viewports: [
                            RenderedHTMLViewport(name: "Phone", width: 393,
                                                 renderHeight: 852),
                            RenderedHTMLViewport(name: "Web 1280", width: 1_280,
                                                 renderHeight: 800)
                        ])
                    let webComponentsVitePage = webComponentsViteResult.payload.pages[0]
                    print("Web Components + Vite corpus artboards: "
                        + webComponentsVitePage.artboards.map {
                            "\($0.name)=\(Int($0.frame.width))×\(Int($0.frame.height))"
                        }.joined(separator: ", "))
                    let phoneArtboards = webComponentsVitePage.artboards.filter {
                        $0.name.hasSuffix("— Phone")
                    }
                    let webArtboards = webComponentsVitePage.artboards.filter {
                        $0.name.hasSuffix("— Web 1280")
                    }
                    require(webComponentsVitePage.artboards.count == corpusIDs.count * 2
                            && phoneArtboards.count == corpusIDs.count
                            && webArtboards.count == corpusIDs.count,
                            "the Storybook 10 Web Components + Vite runtime must render every story at both acceptance viewports")
                    require(phoneArtboards.allSatisfy {
                        $0.frame.width == 393 && $0.frame.height >= 852
                    } && webArtboards.allSatisfy {
                        $0.frame.width == 1_280 && $0.frame.height >= 800
                    }, "the Web Components corpus should retain both requested viewport canvases")
                    require(webComponentsVitePage.artboards.allSatisfy {
                        $0.background.representativeColor.a > 0.999
                    }, "the Web Components corpus should retain the browser's opaque canvas backdrop")
                    require(webComponentsVitePage.artboards.allSatisfy { artboard in
                        webComponentsVitePage.nodes.contains {
                            $0.frame.intersects(artboard.frame)
                        }
                    }, "every Web Components + Vite corpus artboard should contain mapped artwork")
                    let webComponentsViteBridge = webComponentsViteResult.codeBridges[0]
                    require(webComponentsViteBridge.source.framework
                            == "@storybook/web-components-vite"
                            && webComponentsViteBridge.source.frameworkVersion == "10.3.5"
                            && webComponentsViteBridge.source.buildTool
                                == "@storybook/builder-vite"
                            && webComponentsViteBridge.source.buildToolVersion == "10.3.5"
                            && webComponentsViteBridge.source.metadata["renderer"]
                                == "@storybook/web-components"
                            && webComponentsViteBridge.source.metadata["packageManager"]
                                == "pnpm",
                            "the published Web Components + Vite project contract should remain structured provenance")
                    require(webComponentsViteBridge.resources.first {
                        $0.path == "index.json"
                    }?.sha256 == "6bf58b1074e970ef44f201c23f30b55e698dab333bcfcfafe0df04a6885b0788"
                            && webComponentsViteBridge.resources.first {
                                $0.path == "project.json"
                            }?.sha256 == "1f480f3f74e2d07a5e565c8158c5cd0415a778e36911a03484d742ac110c6c9d",
                            "the Web Components regression should remain pinned to the measured Kintone deployment receipts")
                    require(webComponentsViteBridge.behaviorContracts.count
                            == corpusIDs.count
                            && webComponentsViteBridge.behaviorContracts.allSatisfy {
                                $0.payload["initialArgsJSON"]?.isEmpty == false
                            }, "every selected Web Components story should retain its published initial args")
                    let importedNodes = webComponentsVitePage.nodes.flatMap(descendants)
                    let importedText = importedNodes.compactMap { node -> String? in
                        guard case .text(let text) = node.content else { return nil }
                        return text.plainString
                    }
                    require(importedNodes.contains { $0.name.hasPrefix("kuc-") },
                            "the Web Components corpus should retain its custom-element hosts as editable groups")
                    require(!importedText.contains("404 Not Found"),
                            "missing Web Components artifact resources must not become editable error text")
                    if diagnosticStoryID?.isEmpty != false {
                        require(webComponentsViteResult.report.mappedCounts["Text"] == 113
                                && webComponentsViteResult.report.mappedCounts["Editable SVG"] == 18
                                && webComponentsViteResult.report.mappedCounts["Semantic role"] == 134
                                && webComponentsViteResult.report.mappedCounts["ARIA attribute"] == 78
                                && webComponentsViteResult.report.mappedCounts["Shadow"] == 6,
                                "the measured Web Components corpus should retain its light-DOM custom-element paint and semantics")
                    }
                    let clippedText = importedNodes.filter(textOverflows).map { node in
                        "\(node.name) [\(Int(node.frame.width))×\(Int(node.frame.height))]"
                    }
                    require(clippedText.isEmpty,
                            "the exact Web Components corpus should not create native text overflow badges: \(clippedText)")
                    let mapped = webComponentsViteResult.report.mappedCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    let issues = webComponentsViteResult.report.issues
                        .map { "\($0.category)=\($0.occurrences)" }
                        .joined(separator: ", ")
                    print("Web Components + Vite corpus mapped: \(mapped)")
                    print("Web Components + Vite corpus report: \(issues)")
                    for issue in webComponentsViteResult.report.issues {
                        print("Web Components + Vite issue: \(issue.category) "
                            + "[\(issue.fidelity.rawValue)] ×\(issue.occurrences): "
                            + issue.message)
                    }
                    print("ok: published Storybook 10 Web Components + Vite corpus renders through the framework-neutral seam")
                }
                print("ok: static Storybook index discovery renders isolated stories and preserves receipt-only provenance")
                exit(0)
            } catch {
                fail(String(reflecting: error))
            }
        }
        app.run()
    }
}

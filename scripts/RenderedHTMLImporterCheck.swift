import Foundation
import CoreGraphics

private let measuredParagraphText = "Five measured browser lines must keep their final line visible."

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? 20, height: 20)
    }
    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func descendants(_ node: Node) -> [Node] {
    if case .group(let children) = node.content {
        return [node] + children.flatMap(descendants)
    }
    return [node]
}

private func style(backgroundColor: String = "rgba(0, 0, 0, 0)",
                   backgroundImage: String = "none",
                   color: String = "rgb(20, 33, 61)",
                   fontSize: String = "16px") -> RenderedHTMLComputedStyle {
    var result = RenderedHTMLComputedStyle()
    result.backgroundColor = backgroundColor
    result.backgroundImage = backgroundImage
    result.color = color
    result.fontFamily = #""Definitely Not Installed", Helvetica, Arial, sans-serif"#
    result.fontSize = fontSize
    result.lineHeight = "24px"
    return result
}

private func snapshot(width: CGFloat, renderHeight: CGFloat, documentHeight: CGFloat,
                      phone: Bool) -> RenderedHTMLSnapshot {
    var bodyStyle = style(backgroundColor: "rgb(251, 251, 254)")
    bodyStyle.fontSize = "16px"

    var headingStyle = style(fontSize: phone ? "28px" : "40px")
    headingStyle.fontWeight = "700"
    headingStyle.lineHeight = phone ? "32.2px" : "46px"
    let heading = RenderedHTMLElement(
        tagName: "h1", path: "0.0.0",
        rect: CGRect(x: phone ? 16 : 24, y: 24, width: width - (phone ? 32 : 48), height: 92),
        style: headingStyle,
        textFragments: [RenderedHTMLTextFragment(
            text: "A page the importer has never seen",
            rects: [CGRect(x: phone ? 16 : 24, y: 24, width: phone ? 330 : 690, height: phone ? 64.4 : 46)],
            style: headingStyle)])

    let paragraph = RenderedHTMLElement(
        tagName: "p", path: "0.0.2",
        rect: CGRect(x: 16, y: 500, width: 320, height: 120),
        style: style(),
        textFragments: [RenderedHTMLTextFragment(
            text: measuredParagraphText,
            rects: (0..<5).map {
                CGRect(x: 16, y: 503 + CGFloat($0) * 24,
                       width: 300, height: 18)
            }, style: style())])

    let semanticToggle = RenderedHTMLElement(
        tagName: "button", path: "0.0.3",
        rect: CGRect(x: 16, y: 640, width: 160, height: 40),
        style: style(),
        attributes: ["id": "semantic-toggle", "role": "switch",
                     "aria-checked": "true", "aria-label": "Motion"],
        textFragments: [RenderedHTMLTextFragment(
            text: "Motion", rects: [CGRect(x: 24, y: 648, width: 54, height: 20)],
            style: style())])
    let invalidHostRole = RenderedHTMLElement(
        tagName: "button", path: "0.0.4",
        rect: CGRect(x: 184, y: 640, width: 160, height: 40),
        style: style(),
        attributes: ["id": "invalid-role", "role": "heading", "aria-level": "2"],
        textFragments: [RenderedHTMLTextFragment(
            text: "Still a button", rects: [CGRect(x: 192, y: 648, width: 104, height: 20)],
            style: style())])

    var avatarStyle = style(backgroundColor: "rgb(43, 89, 195)")
    avatarStyle.borderTopLeftRadius = "50%"
    avatarStyle.borderTopRightRadius = "50%"
    avatarStyle.borderBottomRightRadius = "50%"
    avatarStyle.borderBottomLeftRadius = "50%"
    let avatar = RenderedHTMLElement(
        tagName: "span", path: "0.0.5",
        rect: CGRect(x: 16, y: 700, width: 20, height: 20),
        style: avatarStyle, attributes: ["class": "avatar"])

    var normalTextStyle = style()
    normalTextStyle.lineHeight = "normal"
    let normalText = RenderedHTMLElement(
        tagName: "span", path: "0.0.6",
        rect: CGRect(x: 48, y: 700, width: 88, height: 20),
        style: normalTextStyle,
        textFragments: [RenderedHTMLTextFragment(
            text: "Native line", rects: [CGRect(x: 48, y: 700, width: 88, height: 20)],
            style: normalTextStyle)])

    var cardStyle = style(
        backgroundImage: "linear-gradient(160deg, rgb(255, 255, 255) 0%, rgb(230, 236, 251) 100%)")
    cardStyle.borderTopWidth = "1px"
    cardStyle.borderRightWidth = "1px"
    cardStyle.borderBottomWidth = "1px"
    cardStyle.borderLeftWidth = "1px"
    cardStyle.borderTopColor = "rgb(43, 89, 195)"
    cardStyle.borderRightColor = "rgb(43, 89, 195)"
    cardStyle.borderBottomColor = "rgb(43, 89, 195)"
    cardStyle.borderLeftColor = "rgb(43, 89, 195)"
    cardStyle.borderTopLeftRadius = "12px"
    cardStyle.borderTopRightRadius = "12px"
    cardStyle.borderBottomRightRadius = "12px"
    cardStyle.borderBottomLeftRadius = "12px"
    cardStyle.boxShadow = "rgba(20, 33, 61, 0.12) 0px 2px 8px 0px"

    var cardHeadingStyle = style(fontSize: "18px")
    cardHeadingStyle.fontWeight = "700"
    let cardX: CGFloat = phone ? 16 : 744
    let cardY: CGFloat = phone ? 180 : 160
    let cardWidth: CGFloat = phone ? 361 : 672
    let cardHeading = RenderedHTMLElement(
        tagName: "h3", path: "0.0.1.0",
        rect: CGRect(x: cardX + (phone ? 16 : 24), y: cardY + 100,
                     width: cardWidth - (phone ? 32 : 48), height: 24),
        style: cardHeadingStyle,
        textFragments: [RenderedHTMLTextFragment(
            text: "Gradient, radius, shadow",
            rects: [CGRect(x: cardX + (phone ? 16 : 24), y: cardY + 100,
                           width: 230, height: 24)], style: cardHeadingStyle)])
    let card = RenderedHTMLElement(
        tagName: "article", path: "0.0.1",
        rect: CGRect(x: cardX, y: cardY, width: cardWidth, height: 280),
        style: cardStyle,
        attributes: ["class": "card card--accent"],
        children: [cardHeading])
    let main = RenderedHTMLElement(
        tagName: "main", path: "0.0",
        rect: CGRect(x: 0, y: 0, width: width, height: documentHeight - 80),
        style: style(), children: [heading, card, paragraph, semanticToggle,
                                   invalidHostRole, avatar, normalText])
    let root = RenderedHTMLElement(
        tagName: "body", path: "0",
        rect: CGRect(x: 0, y: 0, width: width, height: documentHeight),
        style: bodyStyle, children: [main])

    return RenderedHTMLSnapshot(
        sourceName: "Fixture 2", sourceURL: "file:///fixture2/index.html",
        title: "Fixture 2 — hand-written",
        viewport: RenderedHTMLViewport(name: phone ? "Phone" : "Desktop",
                                       width: width, renderHeight: renderHeight),
        documentHeight: documentHeight, root: root,
        mediaQueryMatches: ["(max-width: 768px) => \(phone)"])
}

@main
private enum RenderedHTMLImporterCheck {
    @MainActor
    static func main() throws {
        let phone = snapshot(width: 393, renderHeight: 852, documentHeight: 1120, phone: true)
        let desktop = snapshot(width: 1440, renderHeight: 1024, documentHeight: 760, phone: false)
        let encoded = try [phone, desktop].map { try JSONEncoder().encode($0) }
        let result = try RenderedHTMLImporter().read(snapshotData: encoded)

        require(result.payload.pages.count == 1,
                "one source imported at two viewports should create one EXP page")
        let page = result.payload.pages[0]
        require(page.artboards.count == 2, "two browser snapshots should create two artboards")
        require(page.artboards[0].frame.size == CGSize(width: 393, height: 1120),
                "phone artboard must use viewport width and measured content height")
        require(page.artboards[1].frame.origin.x == 393 + RenderedHTMLImporter.artboardGap,
                "responsive artboards should be separated by the standard import gap")
        require(page.artboards[1].frame.height == 760,
                "desktop artboard must not be clamped up to render height")
        require(page.artboards[0].notes.contains("393 × 852")
                && page.artboards[0].notes.contains("max-width: 768px"),
                "artboard notes should retain render height and resolved media query context")

        let phoneNodes = page.nodes.first.map(descendants) ?? []
        let phoneHeading = phoneNodes.first { node in
            if case .text(let text) = node.content { return text.plainString.hasPrefix("A page") }
            return false
        }
        if case .text(let text)? = phoneHeading?.content {
            require(phoneHeading?.frame.minX == 0 && phoneHeading?.frame.minY == 0
                    && phoneHeading?.frame.height == 66
                    && (phoneHeading?.frame.width ?? 0) >= 332,
                    "text should retain measured placement and widen only when native fallback metrics require it")
            require(text.box == .fixed && text.firstRun.fontSize == 28,
                    "browser text should remain a fixed measured box at resolved size")
            require(text.firstRun.fontName.lowercased().contains("helvetica"),
                    "an unavailable primary CSS family should advance to the installed Helvetica fallback")
            require(text.contentRole == .heading1,
                    "heading markup should survive as text content hierarchy")
        } else {
            require(false, "phone heading should map to editable text")
        }
        let paragraphNode = phoneNodes.first { node in
            if case .text(let text) = node.content { return text.plainString == measuredParagraphText }
            return false
        }
        require(paragraphNode?.frame.height == 121,
                "five 18px ink rectangles spaced on 24px lines need a full 120px TextKit box")

        let main = phoneNodes.first { $0.name == "main" }
        require(main?.semantics?.role == .main,
                "native HTML landmarks should map to curated EXP roles")
        require(phoneHeading?.semantics?.role == .heading
                && phoneHeading?.semantics?.headingLevel == 1,
                "native headings should retain both role and level; got \(String(describing: phoneHeading?.semantics))")
        let semanticToggle = phoneNodes.first { $0.name == "button#semantic-toggle" }
        require(semanticToggle?.semantics?.role == .switch
                && semanticToggle?.semantics?.ariaAttributes["aria-checked"] == "true"
                && semanticToggle?.semantics?.explicitRoleConformsToHost == true,
                "allowed explicit roles and authored ARIA state should survive as structured semantics")
        let invalidRole = phoneNodes.first { $0.name == "button#invalid-role" }
        require(invalidRole?.semantics?.role == .button
                && invalidRole?.semantics?.authoredRole == "heading"
                && invalidRole?.semantics?.explicitRoleConformsToHost == false,
                "a role prohibited on its HTML host should be retained as source data while EXP uses the host's implicit role")
        require(result.report.issues.contains {
                    $0.category == "Semantics" && $0.message.contains("not allowed on <button>")
                },
                "invalid explicit host-role combinations should be visible in the import report")

        guard let avatar = phoneNodes.first(where: { $0.name == "span.avatar" }) else {
            require(false, "percentage-radius surface should remain editable")
            return
        }
        let avatarShape: RectangleShape?
        switch avatar.content {
        case .rectangle(let shape): avatarShape = shape
        case .group(let children):
            avatarShape = children.compactMap { child in
                guard child.name == "Background",
                      case .rectangle(let shape) = child.content else { return nil }
                return shape
            }.first
        default: avatarShape = nil
        }
        guard let avatarShape else {
            require(false, "percentage-radius surface should remain an editable rectangle")
            return
        }
        require(avatarShape.cornerRadius == 10,
                "a 50% radius on a 20px square should import as a 10px circle")
        guard let normalLine = phoneNodes.first(where: { node in
            guard case .text(let text) = node.content else { return false }
            return text.plainString == "Native line"
        }), case .text(let normalLineText) = normalLine.content else {
            require(false, "normal-line-height fixture text should remain editable")
            return
        }
        require(normalLineText.lineHeightUnit == .auto,
                "CSS line-height normal should remain font-native Auto, not an invented px value")
        var legacyTextObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(normalLineText)) as! [String: Any]
        legacyTextObject.removeValue(forKey: "centersFixedLineHeightLeading")
        let legacyText = try JSONDecoder().decode(
            TextContent.self,
            from: JSONSerialization.data(withJSONObject: legacyTextObject))
        require(!legacyText.centersFixedLineHeightLeading,
                "pre-v2.2 text should retain legacy baseline placement until its fixed line-height is edited")

        let card = phoneNodes.first { $0.name == "article.card" }
        guard let card, case .group(let cardChildren) = card.content,
              let background = cardChildren.first(where: { $0.name == "Background" }),
              case .rectangle(let rectangle) = background.content else {
            require(false, "accent card should map to an editable group and surface")
            return
        }
        require(card.frame == CGRect(x: 16, y: 180, width: 361, height: 280),
                "responsive card geometry should use the phone render")
        require(rectangle.strokeAlignment == .inside && rectangle.strokeWidth == 1,
                "CSS border should map to an inside EXP stroke")
        require(rectangle.cornerRadius == 12,
                "uniform CSS radius should remain one editable corner value")
        if case .gradient(let gradient) = rectangle.fill {
            require(gradient.stops.count == 2 && gradient.angle == 70,
                    "CSS linear gradient should reverse into EXP angle space")
        } else {
            require(false, "accent card gradient should remain editable")
        }
        require(background.effects.first?.kind == .dropShadow
                && background.effects.first?.blur == 8,
                "first CSS box shadow should remain editable")
        require(result.report.mappedCounts["Artboard"] == 2,
                "report should count both viewport artboards")
        require(result.codeBridges.count == 1,
                "one rendered source should produce one hidden bridge manifest")
        let bridge = result.codeBridges[0]
        require(bridge.connector == "local-html"
                && bridge.source.entryPath == "index.html",
                "the bridge should retain connector and relative entry identity")
        require(bridge.bindings.filter { $0.externalKind == "rendered-viewport" }.count == 2,
                "each imported viewport should have an artboard binding")
        require(bridge.bindings.contains {
                    $0.expNodeID != nil && $0.externalKind == "dom-path"
                        && $0.metadata["domPath"] == "0.0.1"
                },
                "editable nodes should retain their measured DOM-path identity")
        require(bridge.bindings.allSatisfy { $0.writableProperties.isEmpty },
                "rendered identity alone must not grant source write-back authority")

        let bridgeDocument = Document(artboards: [], nodes: [],
                                      codeBridges: result.codeBridges)
        let bridgeData = try JSONEncoder().encode(bridgeDocument)
        let decodedBridgeDocument = try JSONDecoder().decode(Document.self,
                                                             from: bridgeData)
        require(decodedBridgeDocument.schemaVersion == Document.currentSchemaVersion
                && decodedBridgeDocument.codeBridges == result.codeBridges,
                "bridge manifests should round-trip through the .design document")
        let semanticDocument = Document(artboards: page.artboards, nodes: page.nodes)
        let semanticData = try JSONEncoder().encode(semanticDocument)
        let decodedSemanticDocument = try JSONDecoder().decode(Document.self,
                                                               from: semanticData)
        let decodedNodes = decodedSemanticDocument.nodes.first.map(descendants) ?? []
        require(decodedNodes.first { $0.name == "button#semantic-toggle" }?
                    .semantics?.ariaAttributes["aria-checked"] == "true",
                "imported role/state receipts should persist through the .design file")
        var bridgeJSON = try JSONSerialization.jsonObject(with: bridgeData)
            as! [String: Any]
        var sparseBridges = bridgeJSON["codeBridges"] as! [[String: Any]]
        sparseBridges[0].removeValue(forKey: "resources")
        sparseBridges[0].removeValue(forKey: "bindings")
        sparseBridges[0].removeValue(forKey: "behaviorContracts")
        sparseBridges[0].removeValue(forKey: "metadata")
        bridgeJSON["codeBridges"] = sparseBridges
        let sparseData = try JSONSerialization.data(withJSONObject: bridgeJSON)
        let sparseDocument = try JSONDecoder().decode(Document.self, from: sparseData)
        require(sparseDocument.codeBridges[0].resources.isEmpty
                && sparseDocument.codeBridges[0].bindings.isEmpty,
                "additive/missing bridge fields should decode with safe defaults")

        let script = RenderedHTMLExtractionScript.source(
            sourceName: "Fixture \"2\"", sourceURL: "file:///fixture2/index.html",
            viewport: RenderedHTMLViewport(name: "Phone", width: 393, renderHeight: 852))
        require(script.contains(#""sourceName":"Fixture \"2\"""#)
                && script.contains("getBoundingClientRect"),
                "extraction metadata must be JSON-escaped and use measured browser geometry")

        // Original SVG bytes must cross the HTML seam into native vector nodes.
        // This fixture covers the common logo/texture combination of defs,
        // symbol/use, gradients, and a standalone Gaussian filter.
        let svg = Data(#"""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
          <defs>
            <linearGradient id="g"><stop offset="0" stop-color="#ff00aa"/><stop offset="1" stop-color="#330099"/></linearGradient>
            <filter id="soft"><feGaussianBlur in="SourceGraphic" stdDeviation="3"/></filter>
            <filter id="future"><feColorMatrix in="SourceGraphic" type="matrix" values="1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0 0 1 0"/></filter>
            <symbol id="mark"><rect x="4" y="4" width="32" height="32" rx="6" fill="url(#g)" filter="url(#soft)"/></symbol>
          </defs>
          <use href="#mark"/>
        </svg>
        """#.utf8)
        let svgElement = RenderedHTMLElement(
            tagName: "img", path: "0.0", rect: CGRect(x: 20, y: 20, width: 80, height: 80),
            style: style(), attributes: ["alt": "Editable logo"],
            renderedAsset: RenderedHTMLAsset(mimeType: "image/svg+xml", data: svg,
                                             naturalWidth: 40, naturalHeight: 40,
                                             sourceURL: "file:///fixture/logo.svg"))
        let svgRoot = RenderedHTMLElement(
            tagName: "body", path: "0", rect: CGRect(x: 0, y: 0, width: 200, height: 140),
            style: style(backgroundColor: "rgb(255, 255, 255)"), children: [svgElement])
        let svgSnapshot = RenderedHTMLSnapshot(
            sourceName: "SVG fixture", sourceURL: "file:///fixture/index.html", title: "SVG fixture",
            viewport: RenderedHTMLViewport(name: "Desktop", width: 200, renderHeight: 140),
            documentHeight: 140, root: svgRoot)
        let svgResult = try RenderedHTMLImporter().read(snapshotData: [JSONEncoder().encode(svgSnapshot)])
        let svgNodes = svgResult.payload.pages[0].nodes.flatMap(descendants)
        require(svgNodes.contains(where: { node in
                    guard node.name == "Editable logo" else { return false }
                    if case .group = node.content { return true }
                    return false
                }),
                "local SVG img should map to one editable native group")
        require(svgNodes.contains(where: { node in
                    if case .rectangle = node.content {
                        return node.effects.contains { $0.kind == .layerBlur && $0.blur == 3 }
                    }
                    return false
                }),
                "symbol/use geometry and standalone feGaussianBlur should remain editable")
        require(svgResult.report.issues.contains(where: {
                    $0.category == "SVG filter" && $0.message.contains("feColorMatrix")
                }),
                "general feColorMatrix should be named as a native-effect gap without flattening geometry\n\(svgResult.report.detailedText)")

        print("ok: rendered HTML snapshots map responsive geometry, text, paint, and editable SVG symbol/use + layer blur")
    }
}

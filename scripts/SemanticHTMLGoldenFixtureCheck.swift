import Foundation
import CoreGraphics

// The headless contract check does not render text. These deterministic metrics
// satisfy Document/AutoLayoutEngine without pulling AppKit into the fixture.
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        let count = runs.reduce(0) { $0 + $1.string.count }
        return CGSize(width: maxWidth ?? max(20, CGFloat(count) * firstRun.fontSize * 0.6),
                      height: max(1, firstRun.fontSize * 1.3))
    }

    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

enum Fixture {
    static func id(_ value: String) -> UUID { UUID(uuidString: value)! }

    static let artboardID = id("00000000-0000-0000-0000-000000000001")
    static let sourceID = id("00000000-0000-0000-0000-000000000010")
    static let backgroundID = id("00000000-0000-0000-0000-000000000011")
    static let labelID = id("00000000-0000-0000-0000-000000000012")
    static let descriptionID = id("00000000-0000-0000-0000-000000000013")
    static let hoverID = id("00000000-0000-0000-0000-000000000014")
    static let openID = id("00000000-0000-0000-0000-000000000015")
    static let instanceID = id("00000000-0000-0000-0000-000000000020")
    static let secondInstanceID = id("00000000-0000-0000-0000-000000000021")
    static let freeNodeID = id("00000000-0000-0000-0000-000000000030")
    static let autoGroupID = id("00000000-0000-0000-0000-000000000040")
    static let autoFirstID = id("00000000-0000-0000-0000-000000000041")
    static let autoSecondID = id("00000000-0000-0000-0000-000000000042")
    static let wallNodeID = id("00000000-0000-0000-0000-000000000043")
    static let categoryID = id("00000000-0000-0000-0000-000000000050")
    static let colorID = id("00000000-0000-0000-0000-000000000051")
    static let typeStyleID = id("00000000-0000-0000-0000-000000000052")
    static let headingSourceID = id("00000000-0000-0000-0000-000000000060")
    static let headingLabelID = id("00000000-0000-0000-0000-000000000061")
    static let headingInstanceID = id("00000000-0000-0000-0000-000000000062")
    static let vectorPathID = id("00000000-0000-0000-0000-000000000063")

    static func document() -> Document {
        let brand = RGBAColor(r: 0.12, g: 0.35, b: 0.82, a: 1)
        let hover = RGBAColor(r: 0.08, g: 0.24, b: 0.62, a: 1)
        let fixtureFont = "Fixture Sans\"; } body { color: red"

        let background = Node(
            id: backgroundID,
            name: "Button surface",
            frame: CGRect(x: 0, y: 0, width: 132, height: 44),
            publicProps: PublicOverrideProps(fill: true),
            content: .rectangle(RectangleShape(fill: .solid(brand), cornerRadius: 8))
        )
        let label = Node(
            id: labelID,
            name: "Button label",
            frame: CGRect(x: 28, y: 11, width: 76, height: 22),
            relationships: [NodeRelationship(kind: .describedby, targetID: descriptionID)],
            publicProps: PublicOverrideProps(text: true),
            content: .text(TextContent(
                runs: [TextRun(string: "Continue", fontName: fixtureFont,
                               fontSize: 16, color: .white)],
                lineHeight: 1.3, lineHeightUnit: .multiple))
        )
        let description = Node(
            id: descriptionID,
            name: "Button description",
            frame: CGRect(x: 0, y: 48, width: 180, height: 18),
            isVisible: false,
            content: .text(TextContent(string: "Moves to the next step", fontSize: 13))
        )

        let hoverState = ComponentState(
            id: hoverID,
            name: "hover",
            overrides: [InstanceOverride(targetNodeID: backgroundID, value: .fill(.solid(hover)))]
        )
        let openState = ComponentState(id: openID, name: "menu open")
        let source = ComponentSource(
            id: sourceID,
            name: "Continue Button",
            size: CGSize(width: 180, height: 66),
            children: [background, label, description],
            a11y: A11ySemantics(role: .button, accessibleNameLayerID: labelID),
            states: [hoverState, openState]
        )

        var layout = AutoLayout()
        layout.direction = .horizontal
        layout.gap = 12
        layout.cross = .center
        let first = Node(id: autoFirstID, name: "First item",
                         frame: CGRect(x: 0, y: 0, width: 80, height: 24),
                         content: .text(TextContent(
                            runs: [TextRun(string: "First", fontSize: 16)],
                            contentRole: .paragraph)))
        let second = Node(id: autoSecondID, name: "Second item",
                          frame: CGRect(x: 92, y: 0, width: 80, height: 24),
                          content: .text(TextContent(
                            runs: [TextRun(string: "Second", fontSize: 16)],
                            contentRole: .heading3)))
        let autoGroup = Node(id: autoGroupID, name: "Auto row",
                             frame: CGRect(x: 80, y: 220, width: 172, height: 24),
                             autoLayout: layout,
                             content: .group(children: [first, second]))

        let pageGradient = GradientFill(
            kind: .linear,
            stops: [GradientStop(color: brand, position: 0),
                    GradientStop(color: hover, position: 1)],
            angle: 90)
        let freeNode = Node(
            id: freeNodeID,
            name: "Free-positioned card",
            frame: CGRect(x: 64, y: 64, width: 360, height: 120),
            content: .rectangle(RectangleShape(fill: .gradient(pageGradient), cornerRadius: 16))
        )
        let vectorPath = Node(
            id: vectorPathID,
            name: "Complex vector path",
            frame: CGRect(x: 500, y: 80, width: 120, height: 100),
            content: .path(PathShape(
                points: [
                    PathPoint(point: CGPoint(x: 0, y: 80),
                              controlOut: CGPoint(x: 20, y: 10)),
                    PathPoint(point: CGPoint(x: 60, y: 0),
                              controlIn: CGPoint(x: 30, y: 0),
                              controlOut: CGPoint(x: 90, y: 0)),
                    PathPoint(point: CGPoint(x: 120, y: 80),
                              controlIn: CGPoint(x: 100, y: 10))
                ],
                closed: true, fill: .solid(brand), stroke: hover, strokeWidth: 2))
        )
        let instance = Node(
            id: instanceID,
            name: "Continue Button",
            frame: CGRect(x: 80, y: 300, width: 180, height: 66),
            content: .instance(ComponentInstance(sourceID: sourceID,
                                                  activeStateID: hoverID))
        )
        let secondInstance = Node(
            id: secondInstanceID,
            name: "Continue Button duplicate",
            frame: CGRect(x: 300, y: 300, width: 180, height: 66),
            content: .instance(ComponentInstance(sourceID: sourceID,
                                                  activeStateID: openID))
        )
        let headingLabel = Node(
            id: headingLabelID,
            name: "Heading label",
            frame: CGRect(x: 0, y: 0, width: 240, height: 36),
            content: .text(TextContent(
                runs: [TextRun(string: "Fixture heading", fontSize: 28)],
                contentRole: .heading2))
        )
        let headingSource = ComponentSource(
            id: headingSourceID,
            name: "Section Heading",
            size: CGSize(width: 240, height: 36),
            children: [headingLabel],
            a11y: A11ySemantics(role: .heading)
        )
        let headingInstance = Node(
            id: headingInstanceID,
            name: "Section Heading",
            frame: CGRect(x: 80, y: 410, width: 240, height: 36),
            content: .instance(ComponentInstance(sourceID: headingSourceID))
        )
        let wallNode = Node(
            id: wallNodeID,
            name: "Wall-only reference",
            frame: CGRect(x: 900, y: 40, width: 80, height: 80),
            content: .rectangle(RectangleShape(fill: .solid(brand)))
        )

        let category = DLCategory(id: categoryID, name: "Brand")
        let color = DesignAsset(id: colorID, name: "Action", categoryID: categoryID,
                                value: .solid(brand), notes: "Primary action color")
        let type = TypeStyle(id: typeStyleID, name: "Button Label", categoryID: categoryID,
                             fontName: fixtureFont, fontSize: 16, lineHeight: 1.3,
                             lineHeightUnit: .multiple)
        let language = DesignLanguage(categories: [category], assets: [color], typeStyles: [type])

        return Document(
            artboards: [Artboard(id: artboardID, name: "Handoff Fixture",
                                 frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                 notes: "Test <markup> & comment -- safety-")],
            nodes: [freeNode, autoGroup, instance, secondInstance, vectorPath,
                    headingInstance, wallNode],
            sources: [source, headingSource],
            designLanguage: language
        )
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

#if SEMANTIC_CONTRACT_CHECK
@main
private enum SemanticHTMLGoldenFixtureCheck {
    static func main() throws {
        let document = Fixture.document()

        // Every curated role must have a complete deterministic mapping.
        require(!AriaRole.allCases.isEmpty, "role list is empty")
        for role in AriaRole.allCases {
            let mapping = role.semanticHTMLMapping
            require(!mapping.tag.isEmpty, "\(role.rawValue) has no host tag")
            require(mapping.fixedAttributes.keys.allSatisfy { !$0.isEmpty },
                    "\(role.rawValue) has an empty fixed attribute")
        }
        require(AriaRole.button.semanticHTMLMapping.tag == "button", "button is not native")
        require(AriaRole.navigation.semanticHTMLMapping.tag == "nav", "navigation is not native")
        require(AriaRole.link.semanticHTMLMapping.requirements.contains(.href),
                "link does not report missing href")
        require(AriaRole.heading.semanticHTMLMapping.requirements.contains(.headingLevel),
                "heading does not report missing level")

        // Repeated instances must never duplicate DOM ids.
        let first = SemanticHTMLIdentity.nodeDOMID(Fixture.labelID, instanceID: Fixture.instanceID)
        let second = SemanticHTMLIdentity.nodeDOMID(Fixture.labelID, instanceID: Fixture.secondInstanceID)
        require(first != second, "repeated source layers produced duplicate DOM ids")
        require(first.contains(Fixture.labelID.uuidString.lowercased()), "source id missing from DOM id")
        require(first.contains(Fixture.instanceID.uuidString.lowercased()), "instance id missing from DOM id")
        require(SemanticHTMLIdentity.artboardFilename(name: "Handoff Fixture", id: Fixture.artboardID)
                    == "handoff-fixture--00000000-0000-0000-0000-000000000001.html",
                "artboard filename is not deterministic")

        // State and escaping rules are executable rather than prose-only.
        require(SemanticHTMLStateSelector.forName("hover") == .pseudoClass(":hover"),
                "hover selector mismatch")
        require(SemanticHTMLStateSelector.forName("focus") == .pseudoClass(":focus-visible"),
                "focus selector mismatch")
        require(SemanticHTMLStateSelector.forName("menu open") == .dataState("menu open"),
                "custom state selector mismatch")
        require(SemanticHTMLEscape.text("<&>") == "&lt;&amp;&gt;", "text escaping failed")
        require(SemanticHTMLEscape.attribute("\"'&") == "&quot;&#39;&amp;",
                "attribute escaping failed")
        let comment = SemanticHTMLEscape.comment(document.artboards[0].notes)
        require(!comment.contains("--") && !comment.hasSuffix("-"), "comment escaping failed")

        // The shared fixed-id fixture covers every B0 contract seam and survives
        // the real public Document codec used by `.design` and `.exph`.
        require(document.artboards[0].notes.contains("--"), "fixture lacks hostile notes")
        require(document.designLanguage.assets.count == 1, "fixture lacks color token")
        require(document.designLanguage.typeStyles.count == 1, "fixture lacks type style")
        require(DesignLanguageIO.firstAssetBinding(
            matching: .solid(RGBAColor(r: 0.12, g: 0.35, b: 0.82, a: 1)),
            in: document.designLanguage)?.variableName == "action",
                "fixture color token does not have stable CSS identity")
        guard let label = document.sources.first?.children.first(where: { $0.id == Fixture.labelID }),
              case .text(let labelText) = label.content else {
            require(false, "fixture label text missing"); return
        }
        require(DesignLanguageIO.firstTypeStyleBinding(
            matching: labelText, in: document.designLanguage)?.className == "type-button-label",
                "fixture text does not retain its type-style identity")
        require(document.nodes.contains { $0.autoLayout != nil }, "fixture lacks auto-layout")
        guard let source = document.sources.first else {
            require(false, "fixture lacks component source"); return
        }
        require(source.a11y.role == .button, "fixture component is not categorized")
        require(source.a11y.accessibleNameLayerID == Fixture.labelID,
                "fixture lacks accessible-name source")
        require(source.states.contains { $0.name == "hover" }, "fixture lacks conventional state")
        require(source.states.contains { $0.name == "menu open" }, "fixture lacks custom state")
        require(source.children.contains { !$0.relationships.isEmpty }, "fixture lacks relationship")
        require(document.nodes.contains {
            if case .instance(let instance) = $0.content { return instance.activeStateID == Fixture.hoverID }
            return false
        }, "fixture lacks active-state instance")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: encoded)
        require(decoded.artboards.first?.id == Fixture.artboardID, "document round-trip lost artboard id")
        require(decoded.sources.first?.states.count == 2, "document round-trip lost states")
        guard case .group(let decodedAutoChildren) = decoded.nodes.first(where: {
            $0.id == Fixture.autoGroupID
        })?.content else {
            require(false, "document round-trip lost semantic text fixture"); return
        }
        require(decodedAutoChildren.first?.textContentRole == .paragraph,
                "document round-trip lost paragraph content role")

        let headingText = TextContent(
            runs: [TextRun(string: "Future-safe")], contentRole: .heading4)
        let encodedHeading = try JSONEncoder().encode(headingText)
        let unknownRoleData = Data(String(decoding: encodedHeading, as: UTF8.self)
            .replacingOccurrences(of: "heading4", with: "futureHeading")
            .utf8)
        let tolerant = try JSONDecoder().decode(TextContent.self, from: unknownRoleData)
        require(tolerant.contentRole == .plain,
                "unknown future text content role did not decode safely")

        print("ok: \(AriaRole.allCases.count) semantic role mappings")
        print("ok: stable artboard/node/component identity")
        print("ok: state selectors and HTML escaping")
        print("ok: B0 golden fixture document round-trip (\(encoded.count) bytes)")
    }
}

private extension Node {
    var textContentRole: TextContentRole? {
        guard case .text(let text) = content else { return nil }
        return text.contentRole
    }
}
#endif

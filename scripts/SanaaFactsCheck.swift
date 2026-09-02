import Foundation
import CoreGraphics

// The production app supplies TextKit-backed measurement. This calculation-only
// gate needs deterministic dimensions solely so component override/reflow code can
// compile and run without AppKit.
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? max(1, CGFloat(plainString.count) * firstRun.fontSize * 0.5),
               height: max(1, firstRun.fontSize * 1.3))
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

private func text(_ name: String, frame: CGRect, color: RGBAColor,
                  size: CGFloat, font: String = "Inter-Regular",
                  rotation: Double = 0) -> Node {
    Node(name: name, frame: frame, rotation: rotation,
         content: .text(TextContent(runs: [
            TextRun(string: name, fontName: font, fontSize: size, color: color)
         ])))
}

private func role(_ value: AriaRole) -> NodeSemantics {
    NodeSemantics(role: value)
}

@main
private enum SanaaFactsCheck {
    static func main() throws {
        let board = Artboard(
            name: "Facts fixture",
            frame: CGRect(x: 0, y: 0, width: 800, height: 700),
            background: .solid(.white))

        var buttonPadding = AutoPadding()
        buttonPadding.fill = .solid(.black)
        var buttonLayout = AutoLayout()
        buttonLayout.gap = 8
        let normal = text("Normal white", frame: CGRect(x: 12, y: 12, width: 120, height: 22),
                          color: .white, size: 16)
        let large = text("Large regular", frame: CGRect(x: 140, y: 12, width: 120, height: 28),
                         color: .white, size: 18)
        let bold = text("Large bold", frame: CGRect(x: 268, y: 12, width: 120, height: 24),
                        color: .white, size: 14, font: "Inter-Bold")
        let alpha = text("Alpha text", frame: CGRect(x: 396, y: 12, width: 120, height: 22),
                         color: RGBAColor(r: 1, g: 1, b: 1, a: 0.5), size: 16)
        var button = Node(name: "Measured button",
                          frame: CGRect(x: 20, y: 20, width: 540, height: 56),
                          autoLayout: buttonLayout, autoPadding: buttonPadding,
                          semantics: role(.button),
                          content: .group(children: [normal, large, bold, alpha]))
        button.artboardID = board.id

        let grey = RGBAColor(r: 118.0 / 255.0, g: 118.0 / 255.0,
                             b: 118.0 / 255.0, a: 1)
        var smallTarget = Node(name: "Small control",
                               frame: CGRect(x: 20, y: 100, width: 20, height: 20),
                               semantics: role(.button),
                               content: .rectangle(RectangleShape(fill: .solid(grey))))
        smallTarget.artboardID = board.id

        let gradient = GradientFill(kind: .linear, stops: [
            GradientStop(color: .black, position: 0),
            GradientStop(color: .white, position: 1)
        ])
        var gradientCard = Node(name: "Gradient card",
                                frame: CGRect(x: 20, y: 150, width: 220, height: 80),
                                content: .rectangle(RectangleShape(fill: .gradient(gradient))))
        gradientCard.artboardID = board.id
        var gradientText = text("Gradient text", frame: CGRect(x: 40, y: 170, width: 160, height: 24),
                                color: .black, size: 16)
        gradientText.artboardID = board.id

        var rotated = text("Rotated", frame: CGRect(x: 280, y: 160, width: 100, height: 24),
                           color: .black, size: 16, rotation: 12)
        rotated.artboardID = board.id

        let sourceText = text("Source label", frame: CGRect(x: 8, y: 8, width: 100, height: 22),
                              color: .black, size: 15)
        var sourcePadding = AutoPadding()
        sourcePadding.fill = .solid(.white)
        let sourceRoot = Node(name: "Source surface",
                              frame: CGRect(x: 0, y: 0, width: 116, height: 38),
                              autoPadding: sourcePadding,
                              content: .group(children: [sourceText]))
        let source = ComponentSource(name: "Button source", size: sourceRoot.frame.size,
                                     children: [sourceRoot],
                                     a11y: A11ySemantics(role: .button))
        var instance = Node(name: "Resolved instance",
                            frame: CGRect(x: 20, y: 260, width: 116, height: 38),
                            content: .instance(ComponentInstance(
                                sourceID: source.id,
                                overrides: [InstanceOverride(
                                    targetNodeID: sourceText.id,
                                    value: .textStyle(TextStyleOverride(fontSize: 18))) ])))
        instance.artboardID = board.id

        let controlledLayer = Node(name: "Controlled panel",
                                   frame: CGRect(x: 0, y: 0, width: 90, height: 24),
                                   content: .rectangle(RectangleShape(fill: .solid(grey))))
        let relationshipSource = ComponentSource(
            name: "Relationship source", size: controlledLayer.frame.size,
            children: [controlledLayer],
            a11y: A11ySemantics(rootRelationships: [
                NodeRelationship(kind: .controls, targetID: controlledLayer.id)
            ]))
        var relationshipInstance = Node(
            name: "Relationship instance",
            frame: CGRect(x: 20, y: 320, width: 90, height: 24),
            content: .instance(ComponentInstance(sourceID: relationshipSource.id)))
        relationshipInstance.artboardID = board.id

        let packedA = Node(name: "Packed A", frame: CGRect(x: 0, y: 0, width: 30, height: 20),
                           content: .rectangle(RectangleShape()))
        let packedB = Node(name: "Packed B", frame: CGRect(x: 38, y: 0, width: 30, height: 20),
                           content: .rectangle(RectangleShape()))
        var spacingLayout = AutoLayout()
        spacingLayout.gap = 8
        var spacing = Node(name: "Spacing group",
                           frame: CGRect(x: 200, y: 260, width: 68, height: 20),
                           autoLayout: spacingLayout,
                           content: .group(children: [packedA, packedB]))
        spacing.artboardID = board.id

        var document = Document(artboards: [], nodes: [],
                                sources: [source, relationshipSource])
        document.pages = [CanvasPage(name: "Page", artboards: [board],
                                     nodes: [button, smallTarget, gradientCard,
                                             gradientText, rotated, instance,
                                             relationshipInstance, spacing])]

        let stableEncoder = JSONEncoder()
        stableEncoder.outputFormatting = [.sortedKeys]
        let before = try stableEncoder.encode(document)
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sanaa-facts-\(UUID().uuidString).design")
        try before.write(to: fixtureURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let reopened = try JSONDecoder().decode(Document.self,
                                                from: Data(contentsOf: fixtureURL))
        let report = try SanaaFacts.report(document: reopened, artboardID: board.id,
                                           selectedNodeIDs: [], selectedArtboardIDs: [])
        let after = try Data(contentsOf: fixtureURL)

        require(before == after, "facts calculation mutated the saved document")
        require(report.scope.kind == "artboard" && report.scope.artboardIDs == [board.id.uuidString],
                "artboard scope was not reported")
        require(report.colorSpace == "sRGB", "color space disclosure is missing")
        require(report.interpretation == "measured facts, not verdicts",
                "facts/verdict boundary is missing")
        require(report.schemaVersion == 2, "gradient contrast schema revision is missing")

        let normalPair = report.colorPairs.first { $0.nodeID == normal.id.uuidString }
        require(abs((normalPair?.ratio ?? 0) - 21) < 0.000001,
                "known black/white text ratio is wrong")
        require(normalPair?.threshold == 4.5 && normalPair?.largeText == false,
                "normal-text threshold/classification is wrong")
        require(report.colorPairs.first { $0.nodeID == large.id.uuidString }?.threshold == 3,
                "18pt regular was not classified as large text")
        let boldPair = report.colorPairs.first { $0.nodeID == bold.id.uuidString }
        require(boldPair?.threshold == 3 && boldPair?.largeTextClassification.contains("heuristic") == true,
                "14pt bold heuristic was not disclosed")
        require(report.colorPairs.first { $0.nodeID == alpha.id.uuidString }?.estimated == true,
                "alpha text pair was not labeled estimated")

        let nonText = report.nonTextContrast.first { $0.nodeID == smallTarget.id.uuidString }
        require(abs((nonText?.ratio ?? 0) - 4.5422249596) < 0.00001,
                "known #767676/white non-text ratio is wrong")
        require(nonText?.threshold == 3 && nonText?.criterion == "WCAG 2.2 SC 1.4.11",
                "non-text criterion metadata is wrong")

        let gradientPair = report.gradientColorPairs.first {
            $0.nodeID == gradientText.id.uuidString
        }
        require(gradientPair?.gradientKind == "linear"
                && gradientPair?.sampleCount == 60
                && gradientPair?.sampleGridColumns == 20
                && gradientPair?.sampleGridRows == 3,
                "native-gradient text did not report its deterministic sample geometry")
        require((gradientPair?.minimumRatio ?? 99) < 4.5
                && (gradientPair?.medianRatio ?? 0) > (gradientPair?.minimumRatio ?? 99)
                && (gradientPair?.maximumRatio ?? 0) > 4.5,
                "native-gradient contrast range did not preserve its weakest and strongest samples")
        require(abs((gradientPair?.meetingThresholdFraction ?? 0) - (1.0 / 3.0)) < 0.000001,
                "gradient threshold coverage fraction is wrong")
        require(gradientPair?.estimated == true
                && gradientPair?.estimateReason.contains("text-frame grid") == true,
                "gradient frame-sampling limitation was not disclosed")
        require(!report.notAssessed.contains { $0.nodeID == gradientText.id.uuidString },
                "supported native-gradient text was incorrectly left unassessed")
        require(report.notAssessed.contains { $0.nodeID == rotated.id.uuidString && $0.reason.contains("rotated") },
                "rotated text was not explicitly unassessed")
        require(report.targetSizes.contains { $0.nodeID == smallTarget.id.uuidString && $0.width == 20 && $0.height == 20 },
                "heuristic target size is missing")
        require(report.targetSizeReference.exceptions == ["spacing", "equivalent", "inline", "userAgentControl", "essential"],
                "SC 2.5.8 exception list is incomplete or reordered")
        require(report.spacingInventory.autoLayoutGaps.contains { $0.nodeID == spacing.id.uuidString && $0.gap == 8 },
                "auto-layout gap is missing")
        require(report.spacingInventory.siblingDeltas.contains { $0.parentNodeID == spacing.id.uuidString && $0.edgeGapX == 8 },
                "sibling-frame delta is missing")
        require(report.textSizes.contains { $0.nodeID == sourceText.id.uuidString && $0.fontSize == 18 },
                "component instance override/reflow did not resolve into facts")
        require(report.targetSizes.contains { $0.nodeID == instance.id.uuidString },
                "component-source role did not classify the instance target")
        require(report.targetSizes.contains {
            $0.nodeID == relationshipInstance.id.uuidString
                && $0.role == nil
                && $0.classification.contains("control relationship")
        }, "component-root control relationship did not classify the instance target")
        require(report.fontInventory.contains { $0.fontName == "Inter-Regular" && $0.sizes.contains(18) },
                "font inventory did not include resolved instance typography")
        require(report.smallestText?.fontSize == 14,
                "smallest text summary is wrong")
        require(report.heuristics.contains { $0.contains("fontName") }
                && report.heuristics.contains { $0.lowercased().contains("interactive") },
                "heuristic disclosures are incomplete")
        require(!report.truncated, "ordinary fixture was unexpectedly truncated")

        let selection = try SanaaFacts.report(document: reopened, artboardID: nil,
                                              selectedNodeIDs: [smallTarget.id],
                                              selectedArtboardIDs: [])
        require(selection.scope.kind == "selection" && selection.scope.nodeIDs == [smallTarget.id.uuidString],
                "selection scope was not reported")
        require(selection.targetSizes.count == 1,
                "selection scope leaked unselected targets")

        var many = document
        many.pages[0].nodes = (0..<(SanaaFacts.Limits.maxNodes + 5)).map { index in
            var node = Node(name: "Node \(index)",
                            frame: CGRect(x: index, y: 400, width: 1, height: 1),
                            content: .rectangle(RectangleShape()))
            node.artboardID = board.id
            return node
        }
        let bounded = try SanaaFacts.report(document: many, artboardID: board.id,
                                            selectedNodeIDs: [], selectedArtboardIDs: [])
        require(bounded.truncated && bounded.counts.nodesVisited == SanaaFacts.Limits.maxNodes,
                "oversized artboard did not set an explicit node-cap truncation")

        let encoded = try JSONEncoder().encode(report)
        require(encoded.count < SanaaFacts.Limits.maxEncodedBytes,
                "ordinary facts response exceeded the byte budget")
        let lower = String(decoding: encoded, as: UTF8.self).lowercased()
        require(!lower.contains("non-compliant") && !lower.contains("fails ada"),
                "facts response contains forbidden verdict language")

        print("ok: Sanaa facts report measured contrast, text/target sizes, spacing, fonts, resolved instances, honesty omissions, caps, selection scope, and no writes")
    }
}

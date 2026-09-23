import Foundation
import CryptoKit

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private enum SemanticHTMLPackageCheck {
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let source = URL(fileURLWithPath: CommandLine.arguments[1])
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: source))
            try HandoffPackageWriter(document: document, sourceURL: source).write(to: output)
            let css = try String(contentsOf: output.appendingPathComponent("html/styles.css"),
                                 encoding: .utf8)
            require(!css.contains(" / 1;"), "real-document CSS contains an unclosed rgb()")
            let htmlFiles = try FileManager.default.contentsOfDirectory(
                at: output.appendingPathComponent("html"),
                includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "html" }
            require(htmlFiles.count == document.allArtboards.count,
                    "real-document artboard page count mismatch")
            print("ok: real document smoke export (\(document.allArtboards.count) artboard page(s), \(css.utf8.count) CSS bytes)")
            return
        }
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: semantic-html-package-check OUTPUT.exph [or SOURCE.design OUTPUT.exph]\n", stderr)
            exit(2)
        }

        let document = Fixture.document()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = HandoffPackageWriter(
            document: document,
            sourceURL: URL(fileURLWithPath: "/fixture/Handoff.design"),
            generatedAt: generatedAt
        )
        try writer.write(to: output)

        let pageName = SemanticHTMLIdentity.artboardFilename(
            name: document.artboards[0].name, id: Fixture.artboardID)
        let expected = [
            "design.json", "tokens.json", "manifest.json", "README.llm.md",
            "html/styles.css", "html/\(pageName)"
        ]
        for path in expected {
            require(FileManager.default.fileExists(atPath: output.appendingPathComponent(path).path),
                    "missing package file \(path)")
        }

        let repeatOutput = output.deletingLastPathComponent()
            .appendingPathComponent(output.lastPathComponent + "-repeat", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repeatOutput) }
        try writer.write(to: repeatOutput)
        for path in expected {
            let first = try Data(contentsOf: output.appendingPathComponent(path))
            let second = try Data(contentsOf: repeatOutput.appendingPathComponent(path))
            require(first == second, "fixed-input export is not deterministic for \(path)")
        }

        let manifestData = try Data(contentsOf: output.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let entries = manifest["entries"] as? [[String: Any]],
              let summary = manifest["summary"] as? [String: Any] else {
            require(false, "manifest shape is invalid"); return
        }
        require(entries.count == 5, "manifest does not list every non-manifest package file")
        require(summary["semanticHTMLPages"] as? Int == 1, "HTML page count mismatch")
        let emittedCount = summary["semanticHTMLNodes"] as? Int
        require(emittedCount == 15, "emitted HTML node count mismatch: \(emittedCount.map(String.init) ?? "missing")")
        require(summary["semanticHTMLOmittedWallNodes"] as? Int == 1,
                "wall omission count mismatch")

        for entry in entries {
            guard let path = entry["path"] as? String,
                  let bytes = entry["bytes"] as? Int,
                  let digest = entry["sha256"] as? String else {
                require(false, "manifest entry is incomplete"); return
            }
            let data = try Data(contentsOf: output.appendingPathComponent(path))
            require(data.count == bytes, "byte count mismatch for \(path)")
            require(sha256(data) == digest, "SHA-256 mismatch for \(path)")
        }

        let html = try String(contentsOf: output.appendingPathComponent("html/\(pageName)"),
                              encoding: .utf8)
        let css = try String(contentsOf: output.appendingPathComponent("html/styles.css"),
                             encoding: .utf8)
        let readme = try String(contentsOf: output.appendingPathComponent("README.llm.md"),
                                encoding: .utf8)

        // Fixed-input golden digests make intentional exporter changes visible.
        // Update these only after reviewing the complete generated artifacts.
        require(sha256(Data(css.utf8)) == "974ec908be2368343d87fd71704bc11c0907f96c293a23ce99ecbc2ebf2e0b88",
                "semantic stylesheet no longer matches the reviewed golden")
        require(sha256(Data(html.utf8)) == "bdbe933a027de5c815fa23bbe36b2b0ffc8cebc5dd2d0638d9ba36765a5a07ad",
                "semantic HTML page no longer matches the reviewed golden")
        // Re-reviewed for Xcode 26.3 / Swift 6.2 before v2.4. Foundation's
        // deterministic JSON key ordering changed the manifest bytes while all
        // entry digests, HTML, CSS, README, fidelity rows, and counts stayed
        // byte-for-byte correct.
        // Re-minted again 2026-09-23 for BUG-062: BUG-065 had left this
        // fixture source un-compilable (a bare `RGBAColor` passed where stroke
        // became a `Paint`), so the check had not run since that commit. The
        // first re-run showed the same class of drift — manifest bytes only,
        // while every embedded digest above still matches — verified by
        // generating from pre-BUG-062 code and comparing bytes.
        require(sha256(manifestData) == "e3f688827dcef7beae741deed9b23e68f1061cb5b8982f4882ec540a92990877",
                "handoff manifest no longer matches the reviewed golden")
        require(sha256(Data(readme.utf8)) == "0aca4002dc6c9c9e57c4b9b5bf9f922c3ed8c79b3b20331698a967cdcff8637f",
                "handoff README no longer matches the reviewed golden")

        require(html.contains("<!doctype html>"), "page is not a standalone HTML document")
        require(html.contains("<html lang=\"und\">"),
                "page does not honestly declare its undetermined language")
        require(html.contains("href=\"styles.css\""), "page does not link shared CSS")
        require(html.contains("Test <markup> & comment — safety- "),
                "artboard note comment was not safely preserved")
        require(!html.contains("comment -- safety"), "unsafe comment delimiter survived")
        require(html.contains("data-exp-id=\"\(Fixture.freeNodeID.uuidString.lowercased())\""),
                "ordinary node identity is missing")
        require(!html.contains(Fixture.wallNodeID.uuidString.lowercased()),
                "wall-only node leaked into an artboard page")

        let firstResolvedID = SemanticHTMLIdentity.nodeDOMID(Fixture.labelID,
                                                              instanceID: Fixture.instanceID)
        let secondResolvedID = SemanticHTMLIdentity.nodeDOMID(Fixture.labelID,
                                                               instanceID: Fixture.secondInstanceID)
        require(firstResolvedID != secondResolvedID, "resolved instance ids collide")
        require(html.contains("id=\"\(firstResolvedID)\""), "first resolved child id missing")
        require(html.contains("id=\"\(secondResolvedID)\""), "second resolved child id missing")
        require(html.contains("<button") && html.contains("type=\"button\""),
                "button component did not use a native host")
        guard let buttonStart = html.range(of: "<button"),
              let buttonEnd = html.range(of: "</button>", range: buttonStart.upperBound..<html.endIndex) else {
            require(false, "button component markup is incomplete"); return
        }
        let buttonMarkup = String(html[buttonStart.lowerBound..<buttonEnd.upperBound])
        require(!buttonMarkup.contains("<div") && !buttonMarkup.contains("<p ")
                    && !buttonMarkup.contains("<h1 ") && !buttonMarkup.contains("<h2 ")
                    && !buttonMarkup.contains("<h3 "),
                "native button contains non-phrasing visual markup")
        require(html.contains("aria-labelledby=\"\(firstResolvedID)\""),
                "component accessible-name relationship is missing")
        let describedTarget = SemanticHTMLIdentity.nodeDOMID(Fixture.descriptionID,
                                                               instanceID: Fixture.instanceID)
        require(html.contains("aria-describedby=\"\(describedTarget)\""),
                "typed relationship did not resolve inside the instance")
        require(html.contains("data-state=\"menu open\""),
                "active custom state is not represented")
        require(html.contains("role=\"heading\""),
                "explicit heading role is missing")
        require(html.contains("role=\"heading\" aria-level=\"2\""),
                "heading component did not resolve its authored level")
        require(html.contains("<p ") && html.contains(">First</span></p>"),
                "paragraph content role did not emit a native p element")
        require(html.contains("<h3 ") && html.contains(">Second</span></h3>"),
                "heading content role did not emit a native h3 element")
        require(!html.contains("<h2 id=\"(SemanticHTMLIdentity.nodeDOMID(Fixture.headingLabelID, instanceID: Fixture.headingInstanceID))\""),
                "heading component emitted a duplicate nested native heading")
        require(html.contains("class=\"exp-node exp-text type-button-label\""),
                "exact text style match did not emit its reusable class")
        require(!html.lowercased().contains("<script"), "semantic export generated JavaScript")
        require(html.contains("class=\"exp-path-svg\""),
                "vector path did not emit inline SVG geometry")
        require(html.contains("<path class=\"exp-path-shape\" d=\"M 0 80 C"),
                "vector path data is missing or flattened")

        let secondPosition = html.range(of: Fixture.secondInstanceID.uuidString.lowercased())?.lowerBound
        let firstPosition = html.range(of: Fixture.instanceID.uuidString.lowercased())?.lowerBound
        let freePosition = html.range(of: Fixture.freeNodeID.uuidString.lowercased())?.lowerBound
        require(secondPosition != nil && firstPosition != nil && freePosition != nil,
                "fixture nodes missing from DOM")
        require(secondPosition! < firstPosition! && firstPosition! < freePosition!,
                "DOM reading order is not frontmost-first")
        let autoFirstPosition = html.range(of: ">First</span>")?.lowerBound
        let autoSecondPosition = html.range(of: ">Second</span>")?.lowerBound
        require(autoFirstPosition != nil && autoSecondPosition != nil
                    && autoFirstPosition! < autoSecondPosition!,
                "auto-layout DOM order does not follow the visual primary axis")

        require(css.contains("#\(SemanticHTMLIdentity.artboardDOMID(Fixture.artboardID))"),
                "artboard CSS rule missing")
        require(css.contains("left: 64px;"), "absolute geometry missing")
        require(css.contains("rgb(255 255 255 / 1);"), "generated rgb() is not syntactically closed")
        require(css.contains("linear-gradient(180deg"),
                "EXP’s 90-degree gradient was not converted to CSS coordinates")
        require(css.contains("--action: #1F59D1;"),
                "Design Language color custom property is missing")
        require(css.contains("var(--action, rgb(31 89 209 / 1))"),
                "exact paint match did not retain its token with a literal fallback")
        require(css.contains(".type-button-label {"),
                "Design Language type-style class is missing")
        let autoGroupDOMID = SemanticHTMLIdentity.nodeDOMID(Fixture.autoGroupID)
        require(css.contains("#\(autoGroupDOMID) {\n  left: 80px;\n  top: 220px;\n  width: 172px;\n  height: 24px;\n  z-index: 2;\n  display: flex;\n  flex-direction: row;\n  justify-content: flex-start;\n  gap: 12px;\n  align-items: center;"),
                "managed row did not map to flexbox")
        let autoFirstDOMID = SemanticHTMLIdentity.nodeDOMID(Fixture.autoFirstID)
        require(css.contains("#\(autoFirstDOMID) {\n  position: relative;"),
                "auto-layout child did not become a flex item")
        let vectorDOMID = SemanticHTMLIdentity.nodeDOMID(Fixture.vectorPathID)
        require(!css.contains("#\(vectorDOMID) {\n  left: 500px;\n  top: 80px;\n  width: 120px;\n  height: 100px;\n  z-index: 5;\n  background:"),
                "vector path regressed to a rectangular CSS background")
        require(css.contains("\\22 "), "font name was not CSS-string escaped")
        require(!css.contains("Fixture Sans\"; } body"), "raw CSS injection text survived")
        require(css.contains("#\(Fixture.instanceID.uuidString.lowercased()):hover") == false,
                "state selector lost the EXP DOM-id prefix")
        let instanceDOMID = SemanticHTMLIdentity.nodeDOMID(Fixture.instanceID)
        require(css.contains("#\(instanceDOMID):hover"), "hover state selector is missing")
        let secondDOMID = SemanticHTMLIdentity.nodeDOMID(Fixture.secondInstanceID)
        require(css.contains("#\(secondDOMID)[data-state=\"menu open\"]"),
                "custom data-state selector is missing")
        require(css.contains(".exp-instance:focus-visible")
                    && css.contains("@media (prefers-contrast: more)"),
                "keyboard focus or increased-contrast CSS is missing")
        require(readme.contains("html/\(pageName)"), "README lacks HTML entry point")
        require(readme.contains("> Test <markup> & comment -- safety-"),
                "README does not include the full artboard note")
        require(!readme.contains("**headingLevel**"),
                "README still reports a heading level that was explicitly authored")
        require(readme.contains("1 wall-only node(s) were omitted"),
                "README lacks wall omission disclosure")
        guard let fidelity = manifest["fidelity"] as? [String: Any],
              let semanticIssues = fidelity["semanticHTMLRequirements"] as? [[String: Any]] else {
            require(false, "manifest lacks structured semantic requirements"); return
        }
        require(!semanticIssues.contains { $0["requirement"] as? String == "headingLevel" },
                "manifest still reports a heading level that was explicitly authored")
        require(semanticIssues.contains {
            $0["category"] as? String == "semanticRequirement"
                && $0["requirement"] as? String == "unresolvedRelationship"
        }, "broken relationship was not reported structurally")
        let effectIssues = semanticIssues.filter {
            $0["category"] as? String == "visualFallback"
                && $0["requirement"] as? String == "unsupportedEffect"
        }
        require(effectIssues.count == 3,
                "enabled unsupported effects were not reported for every exported instance")
        let effectInstances = Set(effectIssues.compactMap { $0["instanceID"] as? String })
        require(effectInstances == Set([
            Fixture.instanceID.uuidString.uppercased(),
            Fixture.secondInstanceID.uuidString.uppercased()
        ]), "component effect fallbacks lack instance-qualified identity")
        require(readme.contains("Visual fallback") && readme.contains("**unsupportedEffect**"),
                "README does not surface visual fallbacks")

        let rolesDocument = Fixture.allRolesDocument()
        let rolesBundle = SemanticHTMLExporter(document: rolesDocument).makeBundle()
        guard let rolesArtifact = rolesBundle.artifacts.first(where: { $0.mediaType == "text/html" }) else {
            require(false, "all-roles smoke export produced no HTML"); return
        }
        let rolesHTML = String(decoding: rolesArtifact.data, as: UTF8.self)
        require(rolesBundle.emittedNodeCount == AriaRole.allCases.count * 2,
                "all-roles smoke export lost nodes")
        for role in AriaRole.allCases {
            require(rolesHTML.contains("data-exp-name=\"Role smoke: \(role.rawValue)\""),
                    "all-roles export omitted \(role.rawValue)")
            let mapping = role.semanticHTMLMapping
            if let explicitRole = mapping.explicitRole {
                require(rolesHTML.contains("role=\"\(explicitRole.rawValue)\""),
                        "all-roles export omitted explicit \(explicitRole.rawValue) role")
            } else {
                require(rolesHTML.contains("<\(mapping.tag)"),
                        "all-roles export omitted native \(mapping.tag) host")
            }
        }

        // BUG-018 — nested landmarks keep the role the designer authored.
        let nestedDocument = Fixture.nestedLandmarksDocument()
        let nestedBundle = SemanticHTMLExporter(document: nestedDocument).makeBundle()
        guard let nestedArtifact = nestedBundle.artifacts.first(where: { $0.mediaType == "text/html" }) else {
            require(false, "nested-landmark export produced no HTML"); return
        }
        let nestedHTML = String(decoding: nestedArtifact.data, as: UTF8.self)
        func occurrences(_ needle: String, in haystack: String) -> Int {
            haystack.components(separatedBy: needle).count - 1
        }
        // Inside a `region` (→ <section>, sectioning content) each of the three
        // rescoped landmarks must state its role explicitly, or HTML-AAM
        // computes sectionheader / sectionfooter / generic instead.
        for role in ["banner", "contentinfo", "complementary"] {
            require(occurrences("role=\"\(role)\"", in: nestedHTML) == 1,
                    "nested \(role) did not emit exactly one explicit role "
                    + "(BUG-018: expected 1 inside the region host, 0 inside the toolbar host)")
        }
        // And the negative: the banner inside a `toolbar` (→ <div>) is still
        // scoped to body, so a second role="banner" would be the redundant
        // attribute ARIA in HTML calls NOT RECOMMENDED.
        require(occurrences("<header", in: nestedHTML) == 2,
                "nested-landmark fixture should export two <header> hosts")

        // BUG-062 — mask groups clip through their authored silhouette
        // (clip-path: path(...) from the SAME shared silhouette the SVG and
        // raster exporters clip with), and mask-shape layers stop being DOM
        // elements instead of rendering as real shapes over the content.
        let maskDocument = Fixture.maskGroupDocument()
        let maskBundle = SemanticHTMLExporter(document: maskDocument).makeBundle()
        guard let maskHTMLArtifact = maskBundle.artifacts.first(where: { $0.mediaType == "text/html" }),
              let maskCSSArtifact = maskBundle.artifacts.first(where: { $0.mediaType == "text/css" }) else {
            require(false, "mask export produced no HTML/CSS"); return
        }
        let maskHTML = String(decoding: maskHTMLArtifact.data, as: UTF8.self)
        let maskCSS = String(decoding: maskCSSArtifact.data, as: UTF8.self)
        func maskRule(_ nodeUUID: String) -> Substring? {
            let selector = "#" + SemanticHTMLIdentity.nodeDOMID(Fixture.id(nodeUUID), chain: [])
            guard let start = maskCSS.range(of: selector + " {"),
                  let end = maskCSS.range(of: "\n}", range: start.upperBound..<maskCSS.endIndex) else {
                return nil
            }
            return maskCSS[start.lowerBound..<end.upperBound]
        }

        // The diamond's four vertices, in the GROUP's local space — the exact
        // string proves the clip is the authored silhouette (not the bounds
        // rectangle, not artboard-absolute coordinates, not y-flipped). The
        // trailing `M 60 0` is NSBezierPath→CGPath's empty final move-to after
        // the close — the same bytes the SVG half emits, kept identical by
        // design (one serializer, no drift).
        let diamond = maskRule("00000000-0000-0000-0000-000000000111")
        require(diamond?.contains("clip-path: path(\"M 60 0 L 120 60 L 60 120 L 0 60 Z M 60 0\")") == true,
                "diamond mask group does not carry its exact silhouette as clip-path")
        require(diamond?.contains("overflow") == false,
                "mask group still falls back to rectangular overflow clipping")
        // The text mask cannot contribute an outline, so the shared helper's
        // bounds-rectangle fallback is the clip — asserted verbatim so a
        // coordinate-space regression cannot hide behind a contains-check.
        let textMask = maskRule("00000000-0000-0000-0000-000000000121")
        require(textMask?.contains("clip-path: path(\"M 0 20 L 160 20 L 160 100 L 0 100 Z\")") == true,
                "text mask group does not clip to the layer's bounds rectangle")
        // The ellipse mask contributes curves; the auto-padding background
        // shares the same element here (the drift the fidelity report states).
        let padded = maskRule("00000000-0000-0000-0000-000000000131")
        require(padded?.contains("clip-path: path(") == true && padded?.contains(" C ") == true,
                "ellipse mask silhouette lost its curves")
        require(padded?.contains("background:") == true,
                "padded mask group lost its background box")

        // Mask shapes are not elements: no HTML node, no CSS rule.
        for shapeUUID in ["00000000-0000-0000-0000-000000000112",
                          "00000000-0000-0000-0000-000000000122",
                          "00000000-0000-0000-0000-000000000132"] {
            require(!maskHTML.contains("data-exp-id=\"\(Fixture.id(shapeUUID).uuidString.lowercased())\""),
                    "mask shape leaked into the DOM as an element")
            require(maskRule(shapeUUID) == nil, "mask shape earned a CSS rule with no element")
        }
        // The masked content and the ORPHANED mask flag stay ordinary layers.
        for contentUUID in ["00000000-0000-0000-0000-000000000113",
                            "00000000-0000-0000-0000-000000000123",
                            "00000000-0000-0000-0000-000000000133",
                            "00000000-0000-0000-0000-000000000141"] {
            require(maskHTML.contains("data-exp-id=\"\(Fixture.id(contentUUID).uuidString.lowercased())\""),
                    "content layer went missing from the mask export")
        }
        require(maskBundle.emittedNodeCount == 7,
                "mask export emitted \(maskBundle.emittedNodeCount) nodes, expected 7 (3 groups + 3 contents + orphan)")

        // Fidelity: exact silhouettes, the disclosed bounds fallback, the
        // orphan flag, the auto-padding drift, and the relationship that can
        // no longer resolve to an element which no longer exists.
        let maskShapeIssues = maskBundle.fidelityIssues.filter { $0.requirement == "maskShape" }
        require(maskShapeIssues.count == 4,
                "expected 4 maskShape fidelity entries (2 exact, 1 bounds, 1 orphan), got \(maskShapeIssues.count)")
        require(maskShapeIssues.filter { $0.detail.contains("exact outline") }.count == 2,
                "exact mask silhouettes were not reported as exact")
        require(maskShapeIssues.filter { $0.detail.contains("bounds rectangle") }.count == 1,
                "the text mask's bounds-rectangle fallback was not disclosed")
        require(maskShapeIssues.filter { $0.detail.contains("outside any mask group") }.count == 1,
                "the orphaned mask flag was not reported")
        require(maskBundle.fidelityIssues.contains { $0.requirement == "maskAutoPadding" },
                "the auto-padding mask divergence was not reported")
        require(maskBundle.fidelityIssues.contains { $0.requirement == "unresolvedRelationship" },
                "a relationship aimed at a mask shape must be reported unresolvable, not dangle")

        let codePen = try CodePenPrefillExporter(document: document)
            .makePackage(artboardID: Fixture.artboardID)
        guard let codePenPayload = try JSONSerialization.jsonObject(
            with: codePen.payloadJSON) as? [String: Any],
              let codePenHTML = codePenPayload["html"] as? String,
              let codePenCSS = codePenPayload["css"] as? String,
              let codePenJS = codePenPayload["js"] as? String else {
            require(false, "CodePen prefill payload is not valid JSON"); return
        }
        require(codePenPayload["title"] as? String == document.artboards[0].name,
                "CodePen prefill should name the selected artboard")
        require(Set(codePenPayload.keys) == Set([
                    "title", "description", "layout",
                    "html", "html_pre_processor",
                    "css", "css_pre_processor",
                    "js", "js_pre_processor"
                ]),
                "CodePen prefill should contain only the current documented fields")
        require(!codePenHTML.contains("<!doctype html>")
                && !codePenHTML.contains("<head>")
                && !codePenHTML.contains("href=\"styles.css\"")
                && codePenHTML.contains("class=\"exp-artboard\""),
                "CodePen should receive the semantic body fragment without a nested document or package-relative stylesheet link")
        require(codePenCSS == css && codePenJS.isEmpty,
                "CodePen should receive the reviewed semantic CSS and no unproven JavaScript")
        let launcher = String(decoding: codePen.launcherHTML, as: UTF8.self)
        require(launcher.contains(CodePenPrefillExporter.endpoint.absoluteString)
                && launcher.contains("name=\"data\"")
                && launcher.contains("target=\"_blank\"")
                && launcher.contains("&quot;"),
                "the local CodePen review page should contain an escaped form POST")
        require(launcher.contains("nothing is transmitted") == false
                && launcher.contains("only after you press the button"),
                "the CodePen review page should state the transmission boundary plainly")

        print("ok: standalone stylesheet + artboard page")
        print("ok: deterministic fixed-input package bytes")
        print("ok: manifest byte counts and SHA-256 hashes")
        print("ok: absolute geometry, reading order, and stable instance identity")
        print("ok: hostile HTML/CSS text escaped and wall omission reported")
        print("ok: all 40 native/ARIA hosts, relationships, states, and fidelity reporting")
        print("ok: nested landmarks keep their authored role (BUG-018)")
        print("ok: mask groups clip via their authored silhouette; mask shapes leave the DOM (BUG-062)")
        print("ok: one-artboard CodePen prefill stays static, bounded, and user-confirmed")
    }
}

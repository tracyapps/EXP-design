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
        require(sha256(manifestData) == "7c2645f30fdd44e93ed36e7df5b83ee32d0aef689154876ab9f9fef810c95b49",
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

        print("ok: standalone stylesheet + artboard page")
        print("ok: deterministic fixed-input package bytes")
        print("ok: manifest byte counts and SHA-256 hashes")
        print("ok: absolute geometry, reading order, and stable instance identity")
        print("ok: hostile HTML/CSS text escaped and wall omission reported")
        print("ok: all 40 native/ARIA hosts, relationships, states, and fidelity reporting")
    }
}

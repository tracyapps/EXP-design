import Foundation

// FEAT-083 groundwork check: Custom Elements Manifest → component contracts.
// Usage: ComponentManifestCheck [path/to/custom-elements.json or library folder]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}
private func require(_ condition: Bool, _ message: String) { if !condition { fail(message) } }

@main
private enum ComponentManifestCheck {
    static func main() throws {
        let synthetic = #"""
        {"schemaVersion": "1.0.0", "modules": [
          {"kind": "javascript-module", "path": "src/x-card.js", "declarations": [
            {"kind": "class", "name": "XCard", "customElement": true, "tagName": "x-card",
             "summary": "A card.",
             "attributes": [
               {"name": "variant", "type": {"text": "'plain' | \"raised\" | undefined"}, "default": "'plain'", "fieldName": "variant"},
               {"name": "open", "type": {"text": "boolean"}, "default": "false"},
               {"name": "count", "type": {"text": "number"}},
               {"name": "mixed", "type": {"text": "'a' | string"}},
               {"name": "nested", "type": {"text": "Array<'a' | 'b'>"}},
               {"name": "old", "type": {"text": "string"}, "deprecated": true}
             ],
             "members": [
               {"kind": "field", "name": "variant", "type": {"text": "string"}},
               {"kind": "field", "name": "label", "type": {"text": "string"}, "privacy": "public"},
               {"kind": "field", "name": "secret", "privacy": "private"},
               {"kind": "field", "name": "_internal"},
               {"kind": "field", "name": "styles", "static": true},
               {"kind": "method", "name": "show"}
             ],
             "slots": [{"name": "", "description": "Body"}, {"name": "header"}],
             "events": [{"name": "x-toggle", "type": {"text": "CustomEvent"}}],
             "cssParts": [{"name": "base"}],
             "cssProperties": [{"name": "--x-pad", "default": "1rem", "syntax": "<length>"}],
             "cssStates": [{"name": "open"}]},
            {"kind": "class", "name": "Helper"},
            {"kind": "class", "name": "Dupe", "tagName": "x-card"}
          ]}]}
        """#
        let manifest = try ComponentManifestReader.parse(Data(synthetic.utf8))
        require(manifest.components.count == 1, "one element (non-elements and duplicates skipped)")
        require(manifest.warnings.contains { $0.contains("x-card") }, "duplicate warned")
        let card = manifest.contract("x-card")!
        require(card.id == "cem:x-card" && card.className == "XCard" && card.modulePath == "src/x-card.js", "identity")
        func prop(_ id: String) -> ComponentProp? { card.props.first { $0.id == id } }
        require(prop("variant")?.kind == .enumeration && prop("variant")?.options == ["plain", "raised"],
                "union with undefined → enumeration: \(String(describing: prop("variant")))")
        require(prop("variant")?.defaultValue == "plain", "default unquoted")
        require(prop("open")?.kind == .boolean && prop("count")?.kind == .number, "scalars")
        require(prop("mixed")?.kind == .other && prop("nested")?.kind == .other, "non-closed types are other")
        require(prop("old")?.deprecated == true, "deprecated")
        require(prop("label")?.field == "label" && prop("label")?.attribute == nil, "public field without attribute")
        require(card.props.filter { $0.field == "variant" }.count == 1, "field merged with its attribute")
        require(prop("secret") == nil && prop("_internal") == nil && prop("styles") == nil && prop("show") == nil,
                "private/static/methods excluded")
        require(card.variantAxes.map(\.id) == ["variant"], "variant axes")
        require(card.slots.map(\.name) == ["", "header"] && card.slots[0].id == "(default)", "slots")
        require(card.events.first?.typeText == "CustomEvent", "events")
        require(card.cssProperties.first?.defaultValue == "1rem" && card.cssStates.first?.name == "open", "css")
        do { _ = try ComponentManifestReader.parse(Data("{\"modules\": []}".utf8)); fail("empty accepted") }
        catch ComponentManifestError.noComponents {}
        do { _ = try ComponentManifestReader.parse(Data("nope".utf8)); fail("garbage accepted") }
        catch ComponentManifestError.notJSON {}
        print("  ok  synthetic manifest (16 assertions)")

        let args = CommandLine.arguments
        if args.count >= 2 {
            var url = URL(fileURLWithPath: args[1])
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                guard let found = ComponentManifestReader.locate(in: url) else { fail("no manifest in \(url.path)") }
                url = found
            }
            let live = try ComponentManifestReader.read(url)
            print("  live: \(live.components.count) elements, schema \(live.schemaVersion ?? "?")")
            if let details = live.contract("wa-details") {
                require(details.slots.contains { $0.name.isEmpty } && details.slots.contains { $0.name == "summary" },
                        "wa-details slots")
                let appearance = details.props.first { $0.attribute == "appearance" }
                require(appearance?.kind == .enumeration && appearance?.options.count == 4
                        && appearance?.defaultValue == "outlined", "wa-details appearance \(String(describing: appearance))")
                require(details.cssProperties.contains { $0.name == "--spacing" }, "wa-details --spacing")
                require(details.events.contains { $0.name == "wa-show" }, "wa-details events")
                print("  ok  wa-details: \(details.props.count) props, axes \(details.variantAxes.map { "\($0.id)(\($0.options.count))" }), \(details.slots.count) slots, \(details.cssParts.count) parts, \(details.cssProperties.count) css props")
            }
            if let button = live.contract("wa-button") {
                print("  ok  wa-button axes: \(button.variantAxes.map { "\($0.id)=\($0.options.joined(separator: "/"))" }.joined(separator: "; "))")
            }
            let axes = live.components.reduce(0) { $0 + $1.variantAxes.count }
            print("  live totals: \(axes) variant axes, \(live.components.reduce(0) { $0 + $1.slots.count }) slots, \(live.warnings.count) warnings")
        }
        print("PASS")
    }
}

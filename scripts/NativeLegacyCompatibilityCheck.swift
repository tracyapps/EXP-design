import Foundation

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { CGSize(width: maxWidth ?? 20, height: 20) }
    func measuredSize(boxWidth: CGFloat) -> CGSize { CGSize(width: boxWidth, height: 20) }
}

// Compiled against the immutable v2.7 sources, not the current model.
@main private enum NativeLegacyCompatibilityCheck {
    static func main() throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let oldDocument = try JSONDecoder().decode(Document.self, from: input)
        let output = try JSONEncoder().encode(oldDocument)
        var before = try JSONSerialization.jsonObject(with: input) as! [String: Any]
        var after = try JSONSerialization.jsonObject(with: output) as! [String: Any]
        // This additive writer receipt was introduced after v2.7; it is not artwork.
        before.removeValue(forKey: "writtenBy"); after.removeValue(forKey: "writtenBy")
        // v2.7 predates editable modes and bindings. Compare all artwork and
        // resolved fields after excluding just this newer authoring metadata.
        if var language = before["designLanguage"] as? [String: Any] {
            language.removeValue(forKey: "modeSets")
            if let assets = language["assets"] as? [[String: Any]] {
                language["assets"] = assets.map { asset in
                    var value = asset
                    value.removeValue(forKey: "modeValues")
                    return value
                }
            }
            before["designLanguage"] = language
        }
        for (container, layers) in [("pages", "nodes"), ("sources", "children"), ("patterns", "children")] {
            if let roots = before[container] as? [[String: Any]] {
                before[container] = roots.map { root in
                    var value = root
                    if let nodes = value[layers] as? [[String: Any]] {
                        value[layers] = nodes.map(withoutBindingMetadata)
                    }
                    return value
                }
            }
        }
        guard NSDictionary(dictionary: before).isEqual(to: after) else {
            fputs("FAIL: v2.7 dropped supported data from legacy JSON export\n", stderr); exit(1)
        }
        print("PASS: immutable v2.7 decoder preserves legacy-export model, images and bridge payloads")
    }

    private static func withoutBindingMetadata(_ node: [String: Any]) -> [String: Any] {
        var value = node
        value.removeValue(forKey: "tokenBindings")
        if var content = value["content"] as? [String: Any],
           var group = content["group"] as? [String: Any],
           let children = group["children"] as? [[String: Any]] {
            group["children"] = children.map(withoutBindingMetadata)
            content["group"] = group
            value["content"] = content
        }
        return value
    }
}

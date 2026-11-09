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
        guard NSDictionary(dictionary: before).isEqual(to: after) else {
            fputs("FAIL: v2.7 dropped supported data from legacy JSON export\n", stderr); exit(1)
        }
        print("PASS: immutable v2.7 decoder preserves legacy-export model, images and bridge payloads")
    }
}

import Foundation

/// Native design-language data for editing in place. Interchange exports can
/// flatten a palette for other tools. This snapshot keeps IDs and sparse modes.
enum DesignLanguageCode {
    struct Content: Codable, Equatable {
        var categories: [DLCategory]
        var assets: [DesignAsset]
        var typeStyles: [TypeStyle]
        var tokens: [DLToken]
        var modeSets: [DLModeSet]
        var settings: DLSettings

        init(_ language: DesignLanguage) {
            categories = language.categories
            assets = language.assets
            typeStyles = language.typeStyles
            tokens = language.tokens
            modeSets = language.modeSets
            settings = language.settings
        }

        func language(recents: [Paint] = []) -> DesignLanguage {
            DesignLanguage(categories: categories, assets: assets, typeStyles: typeStyles,
                           recents: recents, tokens: tokens, modeSets: modeSets, settings: settings)
        }
    }

    struct Change: Identifiable {
        enum Action: String { case add = "Add", update = "Update", remove = "Remove", reorder = "Reorder" }
        let id = UUID()
        let action: Action
        let kind: String
        let title: String
        var detail: String? = nil
    }

    struct Preview: Identifiable {
        let id = UUID()
        let baseline: Content
        let proposed: Content
        let changes: [Change]
        fileprivate let removedIDs: Set<UUID>

        func affectedLinkCount(in document: Document) -> Int {
            let uses = document.tokenUseCounts()
            return removedIDs.reduce(0) { $0 + (uses[$1] ?? 0) }
        }

        /// The caller commits through the normal undo and propagation funnel.
        func applying(to document: Document) throws -> Document {
            guard Content(document.designLanguage) == baseline else { throw Issue.stale }
            try DesignLanguageCode.validate(proposed, from: baseline, in: document)
            var updated = document
            updated.designLanguage = proposed.language(recents: document.designLanguage.recents)
            updated.removeBindingReferences(to: removedIDs)
            return updated
        }
    }

    struct Issue: LocalizedError {
        let text: String
        var errorDescription: String? { text }

        static let stale = Issue(text: "Design Language changed since this draft started. Copy your edits before reloading the document JSON.")
    }

    static func encode(_ content: Content) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(content), as: UTF8.self) + "\n"
    }

    static func preview(_ text: String, from baseline: Content, in document: Document) throws -> Preview {
        guard Content(document.designLanguage) == baseline else { throw Issue.stale }
        let proposed = try decode(text)
        try validate(proposed, from: baseline, in: document)
        let changes = compare(baseline.categories, proposed.categories, kind: "Category", title: \.name)
            + compare(baseline.assets, proposed.assets, kind: "Swatch", title: swatchName, value: {
                DesignLanguageIO.css(for: $0.value)
            })
            + compare(baseline.typeStyles, proposed.typeStyles, kind: "Type Style", title: styleName, value: \.fallbackLabel)
            + compare(baseline.tokens, proposed.tokens, kind: "Token", title: \.name, value: {
                $0.value.authoredText
            })
            + compare(baseline.modeSets, proposed.modeSets, kind: "Mode Set", title: \.name)
            + (baseline.settings == proposed.settings ? [] : [
                Change(action: .update, kind: "Settings", title: "Points per rem",
                       detail: "\(baseline.settings.remBase) → \(proposed.settings.remBase)")
            ])
        return Preview(baseline: baseline, proposed: proposed, changes: changes,
                       removedIDs: bindableIDs(baseline).subtracting(bindableIDs(proposed)))
    }

    private static func decode(_ text: String) throws -> Content {
        let data = Data(text.utf8)
        var parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch let error as NSError {
            let message = error.userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            throw Issue(text: "Invalid JSON. \(message)")
        }
        guard var root = parsed as? [String: Any] else {
            throw Issue(text: "Design Language JSON must start with an object.")
        }

        // A short HEX literal is convenient for authoring a new swatch. Convert
        // it before decoding. Existing colors retain their exact component precision.
        if var assets = root["assets"] as? [[String: Any]] {
            for index in assets.indices {
                if let input = assets[index]["value"] as? String {
                    assets[index]["value"] = try hexObject(input, path: "assets[\(index)].value")
                }
                if var modes = assets[index]["modeValues"] as? [String: Any] {
                    for (id, input) in modes {
                        if let input = input as? String {
                            modes[id] = ["color": try hexObject(input, path: "assets[\(index)].modeValues.\(id)")]
                        }
                    }
                    assets[index]["modeValues"] = modes
                }
            }
            root["assets"] = assets
        }

        let normalized = try JSONSerialization.data(withJSONObject: root)
        let decoder = JSONDecoder()
        let result: Content
        do {
            result = try decoder.decode(Content.self, from: normalized)
        } catch let error as DecodingError {
            throw Issue(text: describe(error))
        }

        // The document codec deliberately accepts older or partially damaged
        // entries. Verify the editable fields survive that tolerant decode.
        let supplied = try decoder.decode(DLJSON.self, from: normalized)
        let encoded = try decoder.decode(DLJSON.self, from: Data(encode(result).utf8))
        if let mismatch = mismatchedPath(supplied, encoded, path: "") {
            throw Issue(text: "\(mismatch) contains an unknown field or an invalid value.")
        }
        return result
    }

    private static func hexObject(_ input: String, path: String) throws -> [String: Double] {
        guard let color = ColorMath.parseHex(input) else {
            throw Issue(text: "\(path) needs a HEX color such as #336699.")
        }
        return ["r": color.r, "g": color.g, "b": color.b, "a": color.a]
    }

    private static func describe(_ error: DecodingError) -> String {
        let keys: [CodingKey]
        let description: String
        switch error {
        case .keyNotFound(let key, let context):
            keys = context.codingPath + [key]
            description = "This field is required."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            keys = context.codingPath
            description = context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
        let path = keys.reduce("") { prefix, key in
            if let index = key.intValue { return "\(prefix)[\(index)]" }
            return pathByAppending(key.stringValue, to: prefix)
        }
        return "\(path.isEmpty ? "Draft" : path). \(description)"
    }

    private static func pathByAppending(_ key: String, to path: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    private static func mismatchedPath(_ input: DLJSON, _ output: DLJSON, path: String) -> String? {
        if input == output { return nil }
        switch (input, output) {
        case (.object(let entries), .object(let saved)):
            for key in entries.keys.sorted() {
                guard let value = entries[key] else { continue }
                let field = pathByAppending(key, to: path)
                // UUID dictionary keys, like UUID values, are case insensitive.
                let roundTripped = saved[key] ?? UUID(uuidString: key).flatMap { saved[$0.uuidString] }
                if let roundTripped {
                    if let mismatch = mismatchedPath(value, roundTripped, path: field) { return mismatch }
                } else if !isOmittedDefault(value, key: key) {
                    return field
                }
            }
            return nil
        case (.array(let inputs), .array(let outputs)) where inputs.count == outputs.count:
            for i in inputs.indices {
                if let mismatch = mismatchedPath(inputs[i], outputs[i], path: "\(path)[\(i)]") { return mismatch }
            }
            return nil
        case (.string(let a), .string(let b)) where UUID(uuidString: a) != nil && UUID(uuidString: a) == UUID(uuidString: b):
            return nil
        default:
            return path.isEmpty ? "Draft" : path
        }
    }

    private static func isOmittedDefault(_ value: DLJSON, key: String) -> Bool {
        switch key {
        case "modeValues": value == .object([:])
        case "notes", "group", "provenance": value == .string("")
        case "categoryID", "deprecated", "externalID", "defaultModeID", "activeModeID",
             "libraryKey", "iconSymbol", "backgroundColor", "foregroundColor", "start", "end", "radial":
            value == .null
        case "angle": value == .number(0)
        case "scale": value == .number(1)
        default: false
        }
    }

    private static func validate(_ proposed: Content, from baseline: Content, in document: Document) throws {
        let priorIssues = Set(referenceIssues(in: baseline, document: document))
        if let issue = referenceIssues(in: proposed, document: document).first(where: { !priorIssues.contains($0) }) {
            throw Issue(text: issue)
        }

        try checkLibraryAssets(proposed, in: document)
    }

    private static func checkLibraryAssets(_ candidate: Content, in document: Document) throws {
        let links = document.libraryTokenLinks
        let proposed = index(candidate.assets)
        for asset in document.designLanguage.assets {
            guard let link = links[asset.id] else { continue }
            if !link.writable && proposed[asset.id] != asset {
                throw Issue(text: "“\(link.token)” is read-only in its source library.")
            }
            if let updated = proposed[asset.id], updated.tags != asset.tags || updated.provenance != asset.provenance {
                throw Issue(text: "“\(link.token)” must keep its library tags and provenance.")
            }
        }
    }

    private static func referenceIssues(in content: Content, document: Document) -> [String] {
        var issues: [String] = []
        let categories = Set(content.categories.map(\.id))
        let modes = content.modeSets.flatMap(\.modes)
        let modeKeys = Set(modes.map { $0.id.uuidString })
        let allIDs = content.assets.map(\.id) + content.tokens.map(\.id) + content.typeStyles.map(\.id)
            + content.categories.map(\.id) + content.modeSets.map(\.id) + modes.map(\.id)
        var seen = Set<UUID>()
        for id in allIDs where !seen.insert(id).inserted {
            issues.append("ID \(id.uuidString) appears more than once. Keep existing IDs and omit the ID when adding a new entry.")
        }

        func checkCategory(_ category: UUID?, name: String) {
            if let category, !categories.contains(category) {
                issues.append("“\(name)” refers to a missing category. Set a valid categoryID or remove it.")
            }
        }
        func checkModeKeys(_ ids: Dictionary<String, DLTokenValue>.Keys, name: String) {
            for id in ids.sorted() where !modeKeys.contains(id) {
                issues.append("“\(name)” has a value for an unknown mode \(id).")
            }
        }

        let pageOverrides = document.pages.flatMap { page in
            [(page.name, page.modeOverrides)] + page.artboards.map { ($0.name, $0.modeOverrides) }
        }
        let modeSets = index(content.modeSets)
        for (name, overrides) in pageOverrides {
            for (setID, modeID) in (overrides ?? [:]).sorted(by: { $0.key < $1.key })
            where UUID(uuidString: setID).flatMap({ modeSets[$0] })?.modes.contains(where: { $0.id == modeID }) != true {
                issues.append("“\(name)” uses mode \(modeID.uuidString). Clear its mode override before removing that mode.")
            }
        }
        for set in content.modeSets {
            if set.modes.isEmpty {
                issues.append("Mode set “\(set.name)” needs at least one mode.")
            }
            for id in [set.defaultModeID, set.activeModeID].compactMap({ $0 })
            where !set.modes.contains(where: { $0.id == id }) {
                issues.append("“\(set.name)” refers to a default or active mode outside its mode set.")
            }
        }

        let patternIDs = Set(document.patterns.map(\.id))
        let solids = Dictionary(content.assets.compactMap { asset -> (UUID, DesignAsset)? in
            if case .solid = asset.value { return (asset.id, asset) }
            return nil
        }, uniquingKeysWith: { first, _ in first })
        for asset in content.assets {
            let name = swatchName(asset)
            checkCategory(asset.categoryID, name: name)
            checkModeKeys(asset.modeValues.keys, name: name)
            if !validColor(asset.value.representativeColor) {
                issues.append("“\(name)” needs color components between 0 and 1.")
            }
            if let pattern = asset.value.patternValue, !patternIDs.contains(pattern.patternID) {
                issues.append("“\(name)” refers to a missing pattern.")
            }
            if let gradient = asset.value.gradientValue,
               !gradient.stops.allSatisfy({ validColor($0.color) && (0...1).contains($0.position) }) {
                issues.append("“\(name)” needs gradient colors and stop positions between 0 and 1.")
            }
            for (mode, value) in asset.modeValues.sorted(by: { $0.key < $1.key }) {
                switch value {
                case .color(let color) where validColor(color):
                    if solids[asset.id] == nil { issues.append("“\(name)” has a mode override on a non-solid swatch.") }
                case .alias:
                    if solids[asset.id] == nil || !validAlias(start: asset.id, value: { solids[$0]?.modeValues[mode] }, exists: {
                        solids[$0] != nil
                    }) {
                        issues.append("“\(name)” has a missing or circular swatch alias in mode \(mode).")
                    }
                default:
                    issues.append("“\(name)” needs a solid color or swatch alias in mode \(mode).")
                }
            }
        }
        for style in content.typeStyles {
            checkCategory(style.categoryID, name: styleName(style))
            if !(0 < style.fontSize && style.fontSize < CGFloat(Int.max / 2)) ||
                !(0 < style.lineHeight && style.lineHeight < CGFloat(Int.max / 2)) {
                issues.append("“\(styleName(style))” needs a positive font size and line height within the supported range.")
            }
        }
        let tokens = index(content.tokens)
        let active = content.modeSets.compactMap(\.resolvedActiveModeID)
        let contexts: [[UUID]] = [[]] + modes.map { [$0.id] } + [active]
        for token in content.tokens {
            checkCategory(token.categoryID, name: token.name)
            checkModeKeys(token.modeValues.keys, name: token.name)
            let values = [token.value] + token.modeValues.values
            for value in values {
                if case .preserved(.object(let fields)) = value,
                   !Set(fields.keys).isDisjoint(with: ["number", "dimension", "color", "alias", "raw"]) {
                    issues.append("“\(token.name)” contains an invalid token value. Check the value type.")
                }
            }
            for ids in contexts where !validAlias(start: token.id, value: { tokens[$0]?.value(inModes: ids) }, exists: {
                tokens[$0] != nil
            }) {
                let names = ids.compactMap { id in modes.first { $0.id == id }?.name }
                let context = names.isEmpty ? "Base" : names.joined(separator: ", ")
                issues.append("“\(token.name)” has a missing or circular token alias in \(context).")
            }
        }
        return issues
    }

    private static func validColor(_ color: RGBAColor) -> Bool {
        [color.r, color.g, color.b, color.a].allSatisfy { (0...1).contains($0) }
    }

    private static func validAlias(start: UUID, value: (UUID) -> DLTokenValue?, exists: (UUID) -> Bool) -> Bool {
        var seen = Set<UUID>()
        var id = start
        while seen.insert(id).inserted {
            guard exists(id) else { return false }
            guard let target = value(id)?.aliasTarget else { return true }
            id = target
        }
        return false
    }

    private static func bindableIDs(_ content: Content) -> Set<UUID> {
        Set(content.assets.map(\.id) + content.tokens.map(\.id) + content.typeStyles.map(\.id))
    }

    private static func index<T: Identifiable>(_ items: [T]) -> [T.ID: T] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func swatchName(_ asset: DesignAsset) -> String {
        asset.name.isEmpty ? "Unnamed Swatch" : asset.name
    }

    private static func styleName(_ style: TypeStyle) -> String {
        style.name.isEmpty ? "Unnamed Type Style" : style.name
    }

    private static func compare<T: Identifiable & Equatable>(
        _ before: [T], _ after: [T], kind: String, title: (T) -> String,
        value: (T) -> String = { _ in "" }
    ) -> [Change] {
        let old = index(before)
        let new = index(after)
        var changes = before.filter { new[$0.id] == nil }.map { Change(action: .remove, kind: kind, title: title($0)) }
        for item in after {
            if let previous = old[item.id] {
                guard previous != item else { continue }
                let names = (title(previous), title(item))
                let values = (value(previous), value(item))
                let detail = names.0 != names.1 ? "\(names.0) → \(names.1)"
                    : values.0 != values.1 && !values.0.isEmpty && !values.1.isEmpty ? "\(values.0) → \(values.1)" : nil
                changes.append(Change(action: .update, kind: kind, title: names.1, detail: detail))
            } else {
                changes.append(Change(action: .add, kind: kind, title: title(item)))
            }
        }
        if before.map(\.id).filter({ new[$0] != nil }) != after.map(\.id).filter({ old[$0] != nil }) {
            changes.append(Change(action: .reorder, kind: kind, title: "Display order"))
        }
        return changes
    }
}

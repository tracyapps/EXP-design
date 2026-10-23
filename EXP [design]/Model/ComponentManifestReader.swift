//
//  ComponentManifestReader.swift
//  EXP [design]
//
//  FEAT-083 groundwork (v2.8): read a library's Custom Elements Manifest
//  (`custom-elements.json`, schema 1.x) into typed component contracts — props
//  with types and defaults, variant axes from string-literal unions, slots,
//  events, CSS parts, CSS custom properties and CSS states.
//
//  Read-only and document-independent: nothing here creates components or
//  changes a document. Turning contracts into EXP component sources (with
//  rendered visuals) is the FEAT-083 slice proper, which starts after FEAT-082
//  owner verification (ROADMAP sequencing rule). Spec:
//  https://github.com/webcomponents/custom-elements-manifest
//

import Foundation

struct ComponentContract: Codable, Equatable, Sendable, Identifiable {
    /// Stable ID: `cem:<tag-name>`.
    var id: String { "cem:\(tagName)" }
    var tagName: String
    var className: String?
    var summary: String?
    /// Module path inside the package (`components/details/details.js`).
    var modulePath: String?
    var props: [ComponentProp]
    var slots: [ComponentNamedItem]
    var events: [ComponentNamedItem]
    var cssParts: [ComponentNamedItem]
    var cssProperties: [ComponentCSSProperty]
    var cssStates: [ComponentNamedItem]

    /// Props whose type is a closed set of string literals: the named variants a
    /// designer can switch between (`appearance`: filled / outlined / …).
    var variantAxes: [ComponentProp] { props.filter { $0.kind == .enumeration } }
}

struct ComponentProp: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case boolean, string, number, enumeration, other }
    var id: String { attribute ?? field ?? "?" }
    /// HTML attribute name, when the prop is reflected to one.
    var attribute: String?
    /// JS property name, when the manifest names it.
    var field: String?
    /// The manifest's type text, verbatim (`'s' | 'm' | 'l'`).
    var typeText: String?
    var kind: Kind
    /// Enumeration values, in manifest order.
    var options: [String]
    /// Default, unquoted when it was a string literal.
    var defaultValue: String?
    var summary: String?
    var deprecated: Bool
}

struct ComponentNamedItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { name.isEmpty ? "(default)" : name }
    /// Empty string = the default slot.
    var name: String
    var summary: String?
    var typeText: String?
}

struct ComponentCSSProperty: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var syntax: String?
    var defaultValue: String?
    var summary: String?
}

struct ComponentManifest: Equatable, Sendable {
    var schemaVersion: String?
    var components: [ComponentContract]
    var warnings: [String]

    func contract(_ tagName: String) -> ComponentContract? { components.first { $0.tagName == tagName } }
}

enum ComponentManifestError: LocalizedError {
    case notJSON
    case noComponents
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "custom-elements.json isn't valid JSON."
        case .noComponents: return "The manifest doesn't declare any custom elements."
        case .tooLarge(let bytes): return "The manifest is \(bytes / 1_048_576) MB; EXP reads manifests up to 32 MB."
        }
    }
}

enum ComponentManifestReader {
    static let maximumBytes = 32 * 1_024 * 1_024

    /// Common locations, checked in order, relative to a library folder.
    static let candidatePaths = ["custom-elements.json", "dist/custom-elements.json",
                                 "dist-cdn/custom-elements.json", "build/custom-elements.json"]

    /// Finds a manifest in a library folder: the candidate paths, then the
    /// `customElements` field of package.json (the CEM-recommended pointer).
    static func locate(in root: URL) -> URL? {
        let fm = FileManager.default
        let package = root.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: package),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pointer = object["customElements"] as? String,
           !pointer.hasPrefix("/"), !pointer.contains("..") {
            let url = root.appendingPathComponent(pointer)
            if fm.fileExists(atPath: url.path) { return url }
        }
        for path in candidatePaths {
            let url = root.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func read(_ url: URL) throws -> ComponentManifest {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maximumBytes else { throw ComponentManifestError.tooLarge(size) }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> ComponentManifest {
        guard data.count <= maximumBytes else { throw ComponentManifestError.tooLarge(data.count) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComponentManifestError.notJSON
        }
        var warnings: [String] = []
        let schema = root["schemaVersion"] as? String
        if let schema, !schema.hasPrefix("1.") && !schema.hasPrefix("2.") {
            warnings.append("Manifest schema \(schema) is newer than EXP has tested; reading the fields it knows.")
        }
        var components: [ComponentContract] = []
        var seen = Set<String>()
        for module in root["modules"] as? [[String: Any]] ?? [] {
            let path = module["path"] as? String
            for declaration in module["declarations"] as? [[String: Any]] ?? [] {
                guard let tag = declaration["tagName"] as? String, !tag.isEmpty,
                      (declaration["customElement"] as? Bool) ?? true else { continue }
                guard seen.insert(tag).inserted else {
                    warnings.append("<\(tag)> is declared more than once; kept the first.")
                    continue
                }
                components.append(contract(declaration, tag: tag, modulePath: path))
            }
        }
        guard !components.isEmpty else { throw ComponentManifestError.noComponents }
        return ComponentManifest(schemaVersion: schema,
                                 components: components.sorted { $0.tagName < $1.tagName },
                                 warnings: warnings)
    }

    // MARK: Declarations

    private static func contract(_ d: [String: Any], tag: String, modulePath: String?) -> ComponentContract {
        ComponentContract(
            tagName: tag,
            className: d["name"] as? String,
            summary: text(d["summary"]) ?? text(d["description"]),
            modulePath: modulePath,
            props: props(d),
            slots: named(d["slots"]),
            events: named(d["events"]),
            cssParts: named(d["cssParts"]),
            cssProperties: (d["cssProperties"] as? [[String: Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                return ComponentCSSProperty(name: name, syntax: item["syntax"] as? String,
                                            defaultValue: item["default"] as? String,
                                            summary: text(item["description"]))
            },
            cssStates: named(d["cssStates"]))
    }

    /// Attributes first (what markup and Gutenberg wrappers use), then public,
    /// non-static fields that have no attribute. Private/protected members and
    /// methods are never props.
    private static func props(_ d: [String: Any]) -> [ComponentProp] {
        var out: [ComponentProp] = []
        var fieldsWithAttribute = Set<String>()
        for attribute in d["attributes"] as? [[String: Any]] ?? [] {
            guard let name = attribute["name"] as? String else { continue }
            let field = attribute["fieldName"] as? String
            if let field { fieldsWithAttribute.insert(field) }
            out.append(prop(attribute: name, field: field, typeText: typeText(attribute["type"]),
                            defaultValue: attribute["default"] as? String,
                            summary: text(attribute["description"]),
                            deprecated: attribute["deprecated"] != nil))
        }
        for member in d["members"] as? [[String: Any]] ?? [] {
            guard (member["kind"] as? String) == "field",
                  (member["privacy"] as? String ?? "public") == "public",
                  (member["static"] as? Bool) != true,
                  (member["readonly"] as? Bool) != true,
                  let name = member["name"] as? String,
                  !name.hasPrefix("_"), !fieldsWithAttribute.contains(name) else { continue }
            out.append(prop(attribute: member["attribute"] as? String, field: name,
                            typeText: typeText(member["type"]),
                            defaultValue: member["default"] as? String,
                            summary: text(member["description"]),
                            deprecated: member["deprecated"] != nil))
        }
        return out
    }

    private static func prop(attribute: String?, field: String?, typeText: String?,
                             defaultValue: String?, summary: String?, deprecated: Bool) -> ComponentProp {
        let (kind, options) = classify(typeText)
        return ComponentProp(attribute: attribute, field: field, typeText: typeText, kind: kind,
                             options: options, defaultValue: defaultValue.map(unquote),
                             summary: summary, deprecated: deprecated)
    }

    /// `boolean`, `string`, `number`, or a union of string literals (optionally
    /// with `undefined`/`null`, which only mean "unset"). Anything else is `other`.
    static func classify(_ typeText: String?) -> (ComponentProp.Kind, [String]) {
        guard let raw = typeText?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return (.other, []) }
        let parts = splitUnion(raw).filter { $0 != "undefined" && $0 != "null" }
        if parts.count == 1 {
            switch parts[0] {
            case "boolean": return (.boolean, [])
            case "string": return (.string, [])
            case "number": return (.number, [])
            default: break
            }
        }
        let literals = parts.compactMap(stringLiteral)
        if !parts.isEmpty, literals.count == parts.count { return (.enumeration, literals) }
        return (.other, [])
    }

    private static func splitUnion(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var depth = 0
        for ch in raw {
            if let q = quote {
                current.append(ch); if ch == q { quote = nil }; continue
            }
            switch ch {
            case "'", "\"", "`": quote = ch; current.append(ch)
            case "(", "<", "[", "{": depth += 1; current.append(ch)
            case ")", ">", "]", "}": depth -= 1; current.append(ch)
            case "|" where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(ch)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    private static func stringLiteral(_ part: String) -> String? {
        guard part.count >= 2, let first = part.first, let last = part.last,
              first == last, "'\"`".contains(first) else { return nil }
        let inner = part.dropFirst().dropLast()
        return inner.contains(first) ? nil : String(inner)
    }

    private static func unquote(_ value: String) -> String { stringLiteral(value) ?? value }

    private static func typeText(_ value: Any?) -> String? {
        (value as? [String: Any])?["text"] as? String
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func named(_ value: Any?) -> [ComponentNamedItem] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return ComponentNamedItem(name: name, summary: text(item["description"]) ?? text(item["summary"]),
                                      typeText: typeText(item["type"]))
        }
    }
}

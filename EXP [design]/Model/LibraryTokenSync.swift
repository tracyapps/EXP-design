//
//  LibraryTokenSync.swift
//  EXP [design]
//
//  FEAT-082 (v2.8): bring a code library's design tokens into the Design Language
//  with their REAL names, stable IDs, aliases and light/dark modes.
//
//  Contract: docs/COMPONENT-SYNC-v2.8.md. The user points EXP at a library folder;
//  EXP auto-detects token sources (DTCG token files, root-scoped CSS custom
//  properties, a WordPress theme.json) and reads them. Nothing in the library is
//  executed or changed.
//
//  Storage is deliberately old-version-safe: the typed snapshot rides inside an
//  existing `CodeBridgeManifest` resource (`preservedData`) and the token ↔ asset
//  links are ordinary `CodeBridgeBinding`s. EXP v2.7 already decodes and re-encodes
//  both, so opening and saving a v2.8 file in v2.7 keeps the library link intact.
//  No document schema bump is needed for this slice.
//

import CryptoKit
import Foundation

// MARK: - Snapshot model

/// One scan of one library: what was found, where, and every token's value per
/// mode. Encoded as JSON inside the bridge manifest. Fields only ever get added.
struct LibraryTokenSnapshot: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let connector = "expsync-library"
    static let resourceRole = "expsync-token-snapshot"

    var formatVersion: Int = Self.currentFormatVersion
    /// Stable library identity (`npm:<name>`, `wp-theme:<folder>`, `folder:<name>`,
    /// or the `libraryID` an `.expsync/expsync.json` declares).
    var libraryID: String
    var displayName: String
    /// Source-control revision when readable, else nil.
    var revision: String?
    /// SHA-256 over the selected sources' digests — the content identity.
    var contentDigest: String
    var scannedAt: Date
    var sources: [LibraryTokenSource]
    var tokens: [LibraryToken]
    var warnings: [String]

    func token(_ id: String) -> LibraryToken? { tokens.first { $0.id == id } }
}

struct LibraryTokenSource: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case designTokens = "dtcg"
        case cssCustomProperties = "css"
        case wordPressThemeJSON = "wp-theme-json"
    }
    var id: String { path }
    /// Path relative to the library root.
    var path: String
    var kind: Kind
    var sha256: String
    var byteCount: Int
    var tokenCount: Int
    /// Sources EXP read but did not adopt (e.g. theme.json when CSS variables exist).
    var selected: Bool
}

/// DTCG-aligned type names; `expression` and `unknown` are EXP's honest buckets
/// for values it preserves but cannot represent or edit.
enum LibraryTokenType: String, Codable, Sendable, CaseIterable {
    case color, dimension, duration, fontFamily, fontWeight, number, shadow
    case expression, unknown
}

struct LibraryTokenValue: Codable, Equatable, Sendable {
    /// Exactly as written in the source.
    var raw: String
    /// Token ID this value points at (`var(--x)` / `{group.token}`), if an alias.
    var aliasOf: String?
}

struct LibraryToken: Codable, Equatable, Sendable, Identifiable {
    /// Stable ID: `css:--color-accent`, `wp:color.palette.accent`, `dtcg:color.accent`.
    var id: String
    /// The name a developer writes: `--color-accent`, `{color.accent}`.
    var name: String
    var type: LibraryTokenType
    /// Mode → value. `base` always present; `dark` / `light` when declared.
    var modes: [String: LibraryTokenValue]
    var sourcePath: String
    /// Default editable vocabulary (COMPONENT-SYNC-v2.8 → "can't safely infer"):
    /// literal values of representable types only. Aliases edit their target.
    var editable: Bool
    var note: String?

    var baseValue: LibraryTokenValue? { modes[LibraryTokenMode.base] }
    var isAlias: Bool { baseValue?.aliasOf != nil }
}

enum LibraryTokenMode {
    static let base = "base"
    static let light = "light"
    static let dark = "dark"
}

// MARK: - Scanner

enum LibraryTokenScanError: LocalizedError {
    case notAFolder
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .notAFolder: return "Choose a folder that contains the library's code."
        case .nothingFound:
            return "No design tokens were found. EXP looks for design token JSON files, CSS custom properties declared on :root, and a WordPress theme.json."
        }
    }
}

struct LibraryTokenScanner {
    struct Limits: Sendable {
        var maximumFiles = 400
        var maximumFileBytes = 2 * 1_024 * 1_024
        var maximumDepth = 8
        var maximumTokens = 2_000
    }

    /// Folders that are never a library's own token source.
    static let excludedDirectories: Set<String> = [
        "node_modules", ".git", "vendor", "bower_components", ".expsync", ".svn",
        ".hg", ".cache", ".next", ".nuxt", "coverage"
    ]
    /// Generated output, used only when the library has no other source.
    static let generatedDirectories: Set<String> = ["dist", "build", "out", "public"]

    var limits = Limits()

    func scan(root: URL, now: Date = Date()) throws -> LibraryTokenSnapshot {
        try scanWithSources(root: root, now: now).snapshot
    }

    /// The snapshot plus the exact bytes of every SELECTED source file, keyed by
    /// relative path. Adoption keeps those bytes as the write-back baseline.
    func scanWithSources(root: URL, now: Date = Date()) throws
        -> (snapshot: LibraryTokenSnapshot, sourceFiles: [String: Data]) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw LibraryTokenScanError.notAFolder }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var warnings: [String] = []

        let files = candidateFiles(root: root, warnings: &warnings)
        var sources: [LibraryTokenSource] = []
        var parsed: [(source: LibraryTokenSource, tokens: [LibraryToken])] = []
        var contents: [String: Data] = [:]

        func read(_ url: URL) -> Data? {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize, size <= limits.maximumFileBytes else {
                warnings.append("Skipped \(relative(url, root)): larger than \(limits.maximumFileBytes / 1_048_576) MB.")
                return nil
            }
            return try? Data(contentsOf: url)
        }

        for url in files.dtcg {
            guard let data = read(url) else { continue }
            let path = relative(url, root)
            let mode = Self.modeHint(fromFileName: url.lastPathComponent)
            guard let tokens = LibraryDTCGParser.parse(data, sourcePath: path, mode: mode) else { continue }
            contents[path] = data
            let src = LibraryTokenSource(path: path, kind: .designTokens, sha256: Self.sha256(data),
                                         byteCount: data.count, tokenCount: tokens.count, selected: true)
            parsed.append((src, tokens))
        }
        for url in files.css {
            guard let data = read(url), let text = String(data: data, encoding: .utf8) else { continue }
            let path = relative(url, root)
            let result = LibraryCSSVariableParser.parse(text, sourcePath: path)
            guard !result.tokens.isEmpty else { continue }
            if result.skippedScopedDeclarations > 0 {
                warnings.append("\(path): \(result.skippedScopedDeclarations) custom properties are declared under a component selector or a media condition other than light/dark (e.g. reduced motion, widths). Kept for component import; not adopted as tokens.")
            }
            contents[path] = data
            let src = LibraryTokenSource(path: path, kind: .cssCustomProperties, sha256: Self.sha256(data),
                                         byteCount: data.count, tokenCount: result.tokens.count, selected: true)
            parsed.append((src, result.tokens))
        }
        if let url = files.themeJSON, let data = read(url) {
            let path = relative(url, root)
            if let tokens = LibraryThemeJSONParser.parse(data, sourcePath: path), !tokens.isEmpty {
                contents[path] = data
                let src = LibraryTokenSource(path: path, kind: .wordPressThemeJSON, sha256: Self.sha256(data),
                                             byteCount: data.count, tokenCount: tokens.count, selected: true)
                parsed.append((src, tokens))
            }
        }
        guard !parsed.isEmpty else { throw LibraryTokenScanError.nothingFound }

        // Selection rule: design-token files are the most explicit source. With
        // none, CSS custom properties are what the code actually uses. theme.json
        // presets are a separate WordPress namespace; adopt them only when they are
        // the sole source, so one palette doesn't appear twice.
        let kinds = Set(parsed.map(\.source.kind))
        let preferred: LibraryTokenSource.Kind = kinds.contains(.designTokens) ? .designTokens
            : kinds.contains(.cssCustomProperties) ? .cssCustomProperties : .wordPressThemeJSON
        var tokens: [LibraryToken] = []
        var seen = Set<String>()
        for entry in parsed {
            var source = entry.source
            source.selected = (source.kind == preferred)
            sources.append(source)
            guard source.selected else {
                warnings.append("Read \(source.path) (\(source.tokenCount) tokens) but did not adopt it: \(Self.label(preferred)) take priority, so the same palette isn't added twice.")
                continue
            }
            for token in entry.tokens {
                if let existing = tokens.firstIndex(where: { $0.id == token.id }) {
                    // Same token declared in another file/mode file: merge modes.
                    for (mode, value) in token.modes where tokens[existing].modes[mode] == nil {
                        tokens[existing].modes[mode] = value
                    }
                    continue
                }
                guard seen.insert(token.id).inserted else { continue }
                tokens.append(token)
            }
        }
        if tokens.count > limits.maximumTokens {
            warnings.append("Kept the first \(limits.maximumTokens) of \(tokens.count) tokens.")
            tokens = Array(tokens.prefix(limits.maximumTokens))
        }
        LibraryTokenResolver.markUnresolvedAliases(&tokens, warnings: &warnings)

        let identity = Self.identity(root: root)
        let digest = Self.sha256(Data(sources.filter(\.selected).map(\.sha256).joined(separator: "\n").utf8))
        let selectedPaths = Set(sources.filter(\.selected).map(\.path))
        let snapshot = LibraryTokenSnapshot(libraryID: identity.id, displayName: identity.name,
                                    revision: Self.gitRevision(near: root),
                                    contentDigest: digest,
                                    // Whole seconds: the snapshot is stored as ISO-8601 JSON.
                                    scannedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
                                    sources: sources, tokens: tokens, warnings: warnings)
        return (snapshot, contents.filter { selectedPaths.contains($0.key) })
    }

    // MARK: Discovery

    private struct Candidates { var dtcg: [URL] = []; var css: [URL] = []; var themeJSON: URL? }

    private func candidateFiles(root: URL, warnings: inout [String]) -> Candidates {
        var primary = Candidates()
        var generated = Candidates()
        let theme = root.appendingPathComponent("theme.json")
        if FileManager.default.fileExists(atPath: theme.path) { primary.themeJSON = theme }

        var visited = 0
        func walk(_ dir: URL, depth: Int, inGenerated: Bool) {
            guard depth <= limits.maximumDepth, visited < limits.maximumFiles,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]) else { return }
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard visited < limits.maximumFiles else {
                    warnings.append("Stopped after \(limits.maximumFiles) files; choose a narrower folder if tokens are missing.")
                    return
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }   // never follow links out of the library
                let name = url.lastPathComponent
                if values?.isDirectory == true {
                    if Self.excludedDirectories.contains(name.lowercased()) { continue }
                    walk(url, depth: depth + 1,
                         inGenerated: inGenerated || Self.generatedDirectories.contains(name.lowercased()))
                    continue
                }
                let lower = name.lowercased()
                if lower.hasSuffix(".css") || lower.hasSuffix(".scss") {
                    visited += 1
                    if inGenerated { generated.css.append(url) } else { primary.css.append(url) }
                } else if lower.hasSuffix(".tokens.json") || lower.hasSuffix(".tokens")
                            || (lower.hasSuffix(".json") && lower.contains("token")) {
                    visited += 1
                    if inGenerated { generated.dtcg.append(url) } else { primary.dtcg.append(url) }
                }
            }
        }
        walk(root, depth: 0, inGenerated: false)
        if primary.dtcg.isEmpty && primary.css.isEmpty {
            primary.dtcg = generated.dtcg
            primary.css = generated.css
        }
        return primary
    }

    // MARK: Identity

    static func identity(root: URL) -> (id: String, name: String) {
        let folder = root.lastPathComponent
        let expsync = root.appendingPathComponent(".expsync/expsync.json")
        if let data = try? Data(contentsOf: expsync),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = object["libraryID"] as? String, !id.isEmpty {
            return (id, (object["displayName"] as? String) ?? folder)
        }
        let style = root.appendingPathComponent("style.css")
        if let data = try? Data(contentsOf: style), data.count < 512 * 1024,
           let text = String(data: data, encoding: .utf8),
           let range = text.range(of: "Theme Name:") {
            let line = text[range.upperBound...].prefix { $0 != "\n" && $0 != "\r" && $0 != "*" }
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return ("wp-theme:\(folder)", name) }
        }
        let package = root.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: package),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["name"] as? String, !name.isEmpty {
            return ("npm:\(name)", name)
        }
        return ("folder:\(folder)", folder)
    }

    /// Reads `.git/HEAD` in the library folder (no git process is run). Sandboxed
    /// EXP can only read inside the folder the user chose, so a library nested in
    /// a larger repository usually reports nil; the content digest still identifies it.
    static func gitRevision(near root: URL) -> String? {
        let git = root.appendingPathComponent(".git")
        guard let head = try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ref: ") else { return trimmed.isEmpty ? nil : trimmed }
        let ref = String(trimmed.dropFirst(5))
        if let sha = try? String(contentsOf: git.appendingPathComponent(ref), encoding: .utf8) {
            let value = sha.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        if let packed = try? String(contentsOf: git.appendingPathComponent("packed-refs"), encoding: .utf8) {
            for line in packed.split(separator: "\n") where line.hasSuffix(" " + ref) {
                return String(line.prefix { $0 != " " })
            }
        }
        return nil
    }

    // MARK: Helpers

    static func modeHint(fromFileName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("dark") { return LibraryTokenMode.dark }
        if lower.contains("light") { return LibraryTokenMode.base }
        return LibraryTokenMode.base
    }

    static func label(_ kind: LibraryTokenSource.Kind) -> String {
        switch kind {
        case .designTokens: return "design token files"
        case .cssCustomProperties: return "CSS custom properties"
        case .wordPressThemeJSON: return "theme.json presets"
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func relative(_ url: URL, _ root: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
    }
}

// MARK: - Value classification (shared by every parser)

enum LibraryTokenClassifier {
    /// Infers a token type from its raw value, using the name only to break ties
    /// (a bare family list and a keyword look the same to a value parser).
    static func classify(name: String, raw: String) -> LibraryTokenType {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = name.lowercased()
        if value.isEmpty { return .unknown }
        if value.contains("#{") || value.contains("$") { return .expression } // SCSS interpolation
        if isColorLiteral(value) { return .color }
        let lower = value.lowercased()
        let functions = ["color-mix(", "calc(", "clamp(", "min(", "max(", "env(", "light-dark("]
        if functions.contains(where: { lower.contains($0) }) { return .expression }
        if isDuration(lower) { return .duration }
        if isDimension(lower) { return .dimension }
        if lowerName.contains("shadow"), lower.contains("rgb") || lower.contains("#") { return .shadow }
        if lowerName.contains("weight"), Double(lower) != nil { return .fontWeight }
        if Double(lower) != nil { return .number }
        if lowerName.contains("font") || lowerName.contains("family") { return .fontFamily }
        return .unknown
    }

    static func isColorLiteral(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("#") {
            let hex = v.dropFirst()
            return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy(\.isHexDigit)
        }
        let lower = v.lowercased()
        for fn in ["rgb(", "rgba(", "hsl(", "hsla(", "oklch("] where lower.hasPrefix(fn) {
            // One function call only — `rgb(...) 0 1px` is a shadow, not a color.
            return lower.hasSuffix(")") && lower.filter({ $0 == "(" }).count == 1
        }
        return false
    }

    static func color(from value: String) -> RGBAColor? {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard isColorLiteral(v) else { return nil }
        if v.hasPrefix("#") {
            var hex = String(v.dropFirst())
            if hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }   // #rgba
            return ColorMath.parseHex(hex)
        }
        let lower = v.lowercased()
        if lower.hasPrefix("rgb") { return ColorMath.parse(v, .rgba, currentAlpha: 1) }
        if lower.hasPrefix("hsl") { return ColorMath.parse(v, .hsl, currentAlpha: 1) }
        if lower.hasPrefix("oklch") { return ColorMath.parse(v, .oklch, currentAlpha: 1) }
        return nil
    }

    private static func isDimension(_ v: String) -> Bool {
        let units = ["px", "rem", "em", "%", "vw", "vh", "vmin", "vmax", "ch", "ex", "pt", "dvh", "svh", "lvh"]
        guard let unit = units.sorted(by: { $0.count > $1.count }).first(where: { v.hasSuffix($0) })
        else { return v == "0" }
        return Double(v.dropLast(unit.count)) != nil
    }

    private static func isDuration(_ v: String) -> Bool {
        if v.hasSuffix("ms") { return Double(v.dropLast(2)) != nil }
        if v.hasSuffix("s") { return Double(v.dropLast(1)) != nil }
        return false
    }
}

// MARK: - CSS custom properties

enum LibraryCSSVariableParser {
    struct Result { var tokens: [LibraryToken]; var skippedScopedDeclarations: Int }

    static func parse(_ css: String, sourcePath: String) -> Result {
        let text = stripComments(css)
        var tokens: [LibraryToken] = []
        var index: [String: Int] = [:]
        var skipped = 0

        func record(name: String, raw: String, mode: String) {
            let id = "css:\(name)"
            let value = LibraryTokenValue(raw: raw, aliasOf: alias(in: raw))
            if let at = index[id] {
                // Later declarations in the same mode win, matching the cascade.
                tokens[at].modes[mode] = value
                if mode == LibraryTokenMode.base { refreshType(&tokens[at]) }
                return
            }
            var token = LibraryToken(id: id, name: name, type: .unknown,
                                     modes: [mode: value], sourcePath: sourcePath,
                                     editable: false)
            refreshType(&token)
            index[id] = tokens.count
            tokens.append(token)
        }

        walk(Substring(text), media: []) { selector, media, declarations in
            guard let mode = mode(selector: selector, media: media) else {
                skipped += declarations.count
                return
            }
            for (name, raw) in declarations { record(name: name, raw: raw, mode: mode) }
        }
        // A token only declared under a mode (no base) adopts that value as base so
        // it still has a value to show; the original mode entry is kept.
        for i in tokens.indices where tokens[i].modes[LibraryTokenMode.base] == nil {
            if let light = tokens[i].modes[LibraryTokenMode.light] {
                tokens[i].modes[LibraryTokenMode.base] = light
            } else if let first = tokens[i].modes.sorted(by: { $0.key < $1.key }).first?.value {
                tokens[i].modes[LibraryTokenMode.base] = first
                tokens[i].note = "Declared only inside a mode; base value copied from it."
            }
            refreshType(&tokens[i])
        }
        return Result(tokens: tokens, skippedScopedDeclarations: skipped)
    }

    private static func refreshType(_ token: inout LibraryToken) {
        let raw = token.modes[LibraryTokenMode.base]?.raw ?? token.modes.values.first?.raw ?? ""
        token.type = alias(in: raw) != nil ? .unknown : LibraryTokenClassifier.classify(name: token.name, raw: raw)
        token.editable = alias(in: raw) == nil && editableTypes.contains(token.type)
    }

    static let editableTypes: Set<LibraryTokenType> = [.color, .dimension, .duration, .fontFamily, .fontWeight, .number]

    /// `var(--x)` or `var(--x, fallback)` as the WHOLE value → alias of `css:--x`.
    static func alias(in raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("var("), v.hasSuffix(")") else { return nil }
        let inner = v.dropFirst(4).dropLast()
        // Reject `var(--a) var(--b)` and nested calls in the target position.
        var depth = 0
        for ch in inner {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1; if depth < 0 { return nil } }
        }
        let name = inner.prefix { $0 != "," && $0 != ")" }.trimmingCharacters(in: .whitespaces)
        guard name.hasPrefix("--"), !name.contains(" ") else { return nil }
        return "css:\(name)"
    }

    /// nil = not a root-level token scope (component-scoped; skipped).
    static func mode(selector: String, media: [String]) -> String? {
        var mediaMode: String?
        for query in media {
            let q = query.lowercased().replacingOccurrences(of: " ", with: "")
            if q.contains("prefers-color-scheme:dark") { mediaMode = LibraryTokenMode.dark }
            else if q.contains("prefers-color-scheme:light") { mediaMode = LibraryTokenMode.light }
            else { return nil }   // width/print/etc. variants are not modes EXP models yet
        }
        var result: String?
        for part in selector.split(separator: ",") {
            guard let m = selectorMode(String(part)) else { return nil }
            result = result ?? m
        }
        guard let resolved = result else { return nil }
        if let mediaMode { return resolved == LibraryTokenMode.base ? mediaMode : resolved }
        return resolved
    }

    private static func selectorMode(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // `:not(...)` only narrows when a mode applies; it never selects one.
        while let range = s.range(of: ":not(") {
            var depth = 1
            var end = range.upperBound
            while end < s.endIndex, depth > 0 {
                if s[end] == "(" { depth += 1 }
                if s[end] == ")" { depth -= 1 }
                end = s.index(after: end)
            }
            s.removeSubrange(range.lowerBound..<end)
        }
        let rootish = [":root", "html", ":host"]
        var rest = s
        for prefix in rootish where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)); break
        }
        // `:root .dark` is a descendant element, not a mode on the root.
        if rest != s, rest.first?.isWhitespace == true { return nil }
        rest = rest.trimmingCharacters(in: .whitespaces)
        let wasRoot = rest != s || s.isEmpty
        if rest.isEmpty { return wasRoot ? LibraryTokenMode.base : nil }
        // Mode markers on the root: [data-theme="dark"], .dark, .wa-dark, .theme-dark …
        let isMarker = (rest.hasPrefix("[") && rest.hasSuffix("]") && !rest.contains(" "))
            || (rest.hasPrefix(".") && !rest.contains(" ") && rest.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        guard isMarker else { return nil }
        if rest.contains("dark") { return LibraryTokenMode.dark }
        if rest.contains("light") { return LibraryTokenMode.light }
        return nil
    }

    // MARK: Block walker

    /// Calls `visit(selector, media, declarations)` for every style rule that
    /// declares custom properties, descending into @media/@supports/@layer and
    /// CSS nesting. Strings and parentheses are respected when splitting.
    static func walk(_ text: Substring, media: [String],
                     visit: (String, [String], [(String, String)]) -> Void) {
        var i = text.startIndex
        while i < text.endIndex {
            guard let open = indexOfTopLevel("{", in: text, from: i) else { return }
            let prelude = text[i..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let close = matchingBrace(in: text, open: open) else { return }
            let body = text[text.index(after: open)..<close]
            // A prelude can carry stray top-level declarations/at-statements before
            // it (`@import …;`); keep only the part after the last `;`.
            let header = prelude.split(separator: ";", omittingEmptySubsequences: false).last
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? prelude
            if header.hasPrefix("@media") {
                walk(body, media: media + [String(header.dropFirst(6))], visit: visit)
            } else if header.hasPrefix("@supports") || header.hasPrefix("@layer") || header.hasPrefix("@container") {
                walk(body, media: media, visit: visit)
            } else if header.hasPrefix("@") {
                // @font-face, @keyframes, @property … carry no root tokens.
            } else {
                let declarations = customProperties(in: body)
                if !declarations.isEmpty { visit(header, media, declarations) }
                if indexOfTopLevel("{", in: body, from: body.startIndex) != nil {
                    walk(nestedRules(body), media: media) { selector, m, d in
                        // Nested `&[data-theme=dark]` under :root, or `.x` under :root.
                        let combined = selector.hasPrefix("&")
                            ? header + selector.dropFirst()
                            : header + " " + selector
                        visit(combined, m, d)
                    }
                }
            }
            i = text.index(after: close)
        }
    }

    private static func nestedRules(_ body: Substring) -> Substring {
        // Remove top-level declarations so the walker sees only nested rules.
        var out = ""
        var i = body.startIndex
        while i < body.endIndex {
            guard let open = indexOfTopLevel("{", in: body, from: i),
                  let close = matchingBrace(in: body, open: open) else { break }
            let prelude = body[i..<open]
            let header = prelude.split(separator: ";", omittingEmptySubsequences: false).last ?? prelude
            out += header + body[open...close]
            i = body.index(after: close)
        }
        return Substring(out)
    }

    static func customProperties(in body: Substring) -> [(String, String)] {
        var out: [(String, String)] = []
        var depthBraces = 0, depthParens = 0
        var quote: Character?
        var start = body.startIndex
        var i = body.startIndex
        func flush(_ end: String.Index) {
            let decl = body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if decl.hasPrefix("--"), let colon = decl.firstIndex(of: ":") {
                let name = decl[..<colon].trimmingCharacters(in: .whitespaces)
                var value = decl[decl.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.lowercased().hasSuffix("!important") {
                    value = String(value.dropLast(10)).trimmingCharacters(in: .whitespaces)
                }
                if !name.isEmpty, !name.contains(" ") { out.append((name, value)) }
            }
        }
        while i < body.endIndex {
            let ch = body[i]
            if let q = quote { if ch == q { quote = nil } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "(" { depthParens += 1 }
            else if ch == ")" { depthParens = max(0, depthParens - 1) }
            else if ch == "{" { depthBraces += 1 }
            else if ch == "}" { depthBraces = max(0, depthBraces - 1); if depthBraces == 0 { start = body.index(after: i) } }
            else if ch == ";", depthBraces == 0, depthParens == 0 {
                flush(i); start = body.index(after: i)
            }
            i = body.index(after: i)
        }
        if depthBraces == 0 { flush(body.endIndex) }
        return out
    }

    private static func indexOfTopLevel(_ target: Character, in text: Substring,
                                        from: String.Index) -> String.Index? {
        var quote: Character?
        var parens = 0
        var i = from
        while i < text.endIndex {
            let ch = text[i]
            if let q = quote { if ch == q { quote = nil } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "(" { parens += 1 }
            else if ch == ")" { parens = max(0, parens - 1) }
            else if ch == target, parens == 0 { return i }
            i = text.index(after: i)
        }
        return nil
    }

    private static func matchingBrace(in text: Substring, open: String.Index) -> String.Index? {
        var depth = 0
        var quote: Character?
        var i = open
        while i < text.endIndex {
            let ch = text[i]
            if let q = quote { if ch == q { quote = nil } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1; if depth == 0 { return i } }
            i = text.index(after: i)
        }
        return nil
    }

    static func stripComments(_ css: String) -> String {
        var out = ""
        out.reserveCapacity(css.count)
        var i = css.startIndex
        var quote: Character?
        while i < css.endIndex {
            let ch = css[i]
            let next = css.index(after: i)
            if let q = quote {
                out.append(ch); if ch == q { quote = nil }; i = next; continue
            }
            if ch == "\"" || ch == "'" { quote = ch; out.append(ch); i = next; continue }
            if ch == "/", next < css.endIndex, css[next] == "*" {
                if let end = css.range(of: "*/", range: css.index(after: next)..<css.endIndex) {
                    i = end.upperBound; out.append(" "); continue
                }
                break
            }
            if ch == "/", next < css.endIndex, css[next] == "/" {
                // SCSS line comment — only at a line start / after whitespace, so
                // `url(https://…)` is untouched.
                let prev = out.last
                if prev == nil || prev == "\n" || prev == " " || prev == "\t" || prev == ";" || prev == "{" {
                    while i < css.endIndex, css[i] != "\n" { i = css.index(after: i) }
                    continue
                }
            }
            out.append(ch); i = next
        }
        return out
    }
}

// MARK: - WordPress theme.json presets

enum LibraryThemeJSONParser {
    static func parse(_ data: Data, sourcePath: String) -> [LibraryToken]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["settings"] as? [String: Any] else { return nil }
        var tokens: [LibraryToken] = []
        func add(path: [String], slug: String, raw: String, type: LibraryTokenType) {
            let css = "--wp--preset--\(path.first ?? "x")--\(slug)"
            tokens.append(LibraryToken(
                id: "wp:\((path + [slug]).joined(separator: "."))", name: css, type: type,
                modes: [LibraryTokenMode.base: LibraryTokenValue(raw: raw)],
                sourcePath: sourcePath,
                editable: LibraryCSSVariableParser.editableTypes.contains(type)))
        }
        func presets(_ object: Any?, valueKey: String) -> [(String, String)] {
            (object as? [[String: Any]] ?? []).compactMap { item -> (String, String)? in
                guard let slug = item["slug"] as? String, let value = item[valueKey] as? String else { return nil }
                return (slug, value)
            }
        }
        if let color = settings["color"] as? [String: Any] {
            for (slug, value) in presets(color["palette"], valueKey: "color") {
                let type = LibraryTokenClassifier.classify(name: "color", raw: value)
                add(path: ["color", "palette"], slug: slug, raw: value, type: type == .color ? .color : .expression)
            }
        }
        if let spacing = settings["spacing"] as? [String: Any] {
            for (slug, value) in presets(spacing["spacingSizes"], valueKey: "size") {
                add(path: ["spacing", "spacingSizes"], slug: slug, raw: value,
                    type: LibraryTokenClassifier.classify(name: "spacing", raw: value))
            }
        }
        if let type = settings["typography"] as? [String: Any] {
            for (slug, value) in presets(type["fontFamilies"], valueKey: "fontFamily") {
                add(path: ["font-family", "fontFamilies"], slug: slug, raw: value, type: .fontFamily)
            }
            for (slug, value) in presets(type["fontSizes"], valueKey: "size") {
                add(path: ["font-size", "fontSizes"], slug: slug, raw: value,
                    type: LibraryTokenClassifier.classify(name: "size", raw: value))
            }
        }
        // `--wp--preset--color--…` is WordPress's own generated name; fix the
        // prefix for the non-color groups to match core's output.
        for i in tokens.indices {
            let parts = tokens[i].id.dropFirst(3).split(separator: ".")
            guard parts.count == 3 else { continue }
            let group: String
            switch parts[0] {
            case "spacing": group = "spacing"
            case "font-family": group = "font-family"
            case "font-size": group = "font-size"
            default: group = "color"
            }
            tokens[i].name = "--wp--preset--\(group)--\(parts[2])"
        }
        if let custom = settings["custom"] as? [String: Any] {
            func walk(_ object: [String: Any], path: [String]) {
                for key in object.keys.sorted() {
                    if let child = object[key] as? [String: Any] { walk(child, path: path + [key]) }
                    else if let raw = scalar(object[key]) {
                        let parts = path + [key]
                        let css = "--wp--custom--" + parts.map(kebab).joined(separator: "--")
                        let type = LibraryTokenClassifier.classify(name: parts.joined(separator: "-"), raw: raw)
                        tokens.append(LibraryToken(
                            id: "wp:custom." + parts.joined(separator: "."), name: css, type: type,
                            modes: [LibraryTokenMode.base: LibraryTokenValue(raw: raw)],
                            sourcePath: sourcePath,
                            editable: LibraryCSSVariableParser.editableTypes.contains(type)))
                    }
                }
            }
            walk(custom, path: [])
        }
        return tokens
    }

    private static func scalar(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// WordPress converts camelCase custom keys to kebab-case in variable names.
    static func kebab(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase { if !out.isEmpty { out.append("-") }; out.append(Character(ch.lowercased())) }
            else { out.append(ch) }
        }
        return out
    }
}

// MARK: - DTCG token files

enum LibraryDTCGParser {
    static func parse(_ data: Data, sourcePath: String, mode: String) -> [LibraryToken]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var tokens: [LibraryToken] = []
        func walk(_ object: [String: Any], path: [String], inheritedType: String?) {
            let groupType = (object["$type"] as? String) ?? inheritedType
            if object.keys.contains("$value") {
                let raw = stringValue(object["$value"])
                let name = path.joined(separator: ".")
                let declared = groupType.flatMap { LibraryTokenType(rawValue: $0) }
                let alias = aliasTarget(raw)
                let type: LibraryTokenType = alias != nil ? .unknown
                    : declared ?? (groupType == nil ? LibraryTokenClassifier.classify(name: name, raw: raw) : .unknown)
                var note: String?
                if declared == nil, let groupType { note = "Type \"\(groupType)\" is preserved but not editable in EXP yet." }
                let editable = alias == nil && LibraryCSSVariableParser.editableTypes.contains(type)
                    && !(object["$value"] is [String: Any]) && !(object["$value"] is [Any])
                tokens.append(LibraryToken(
                    id: "dtcg:\(name)", name: "{\(name)}", type: type,
                    modes: [mode: LibraryTokenValue(raw: raw, aliasOf: alias)],
                    sourcePath: sourcePath, editable: editable, note: note))
                return
            }
            for key in object.keys.sorted() where !key.hasPrefix("$") {
                if let child = object[key] as? [String: Any] {
                    walk(child, path: path + [key], inheritedType: groupType)
                }
            }
        }
        walk(root, path: [], inheritedType: nil)
        // Mode-only files still need a base so they have something to show.
        if mode != LibraryTokenMode.base {
            for i in tokens.indices { tokens[i].modes[LibraryTokenMode.base] = nil }
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// Composite values (shadow objects, typography) are preserved as compact JSON.
    private static func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let value { return canonicalJSON(value) }
        return ""
    }

    /// Compact, key-sorted JSON with shortest round-trip numbers (`0.2`, not
    /// `0.20000000000000001`). Exact source bytes are kept separately in the
    /// bridge's source resources; this is the per-token readable form.
    static func canonicalJSON(_ value: Any) -> String {
        switch value {
        case let s as String:
            let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
            return String(String(data: data, encoding: .utf8)?.dropFirst().dropLast() ?? "\"\"")
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            if CFNumberIsFloatType(n as CFNumber) {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : "\(d)"
            }
            return n.stringValue
        case let array as [Any]:
            return "[" + array.map(canonicalJSON).joined(separator: ",") + "]"
        case let object as [String: Any]:
            return "{" + object.keys.sorted().map { canonicalJSON($0) + ":" + canonicalJSON(object[$0]!) }
                .joined(separator: ",") + "}"
        case is NSNull:
            return "null"
        default:
            return "null"
        }
    }

    static func aliasTarget(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("{"), v.hasSuffix("}"), !v.dropFirst().dropLast().contains("{") else { return nil }
        return "dtcg:\(v.dropFirst().dropLast())"
    }
}

// MARK: - Alias resolution

enum LibraryTokenResolver {
    /// Follows aliases to a literal value for `mode`, falling back to `base` on each
    /// hop. Cycles and dangling references resolve to nil, never loop.
    static func resolvedRaw(_ id: String, mode: String, in tokens: [LibraryToken]) -> String? {
        let byID = Dictionary(tokens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var visited = Set<String>()
        var current = id
        while visited.insert(current).inserted, let token = byID[current] {
            guard let value = token.modes[mode] ?? token.modes[LibraryTokenMode.base] else { return nil }
            guard let next = value.aliasOf else { return value.raw }
            if byID[next] == nil {
                // `var(--undefined, fallback)` — the fallback is what the browser uses.
                return cssFallback(value.raw)
            }
            current = next
        }
        return nil
    }

    static func resolvedType(_ token: LibraryToken, in tokens: [LibraryToken]) -> LibraryTokenType {
        guard token.isAlias,
              let raw = resolvedRaw(token.id, mode: LibraryTokenMode.base, in: tokens) else { return token.type }
        return LibraryTokenClassifier.classify(name: token.name, raw: raw)
    }

    static func resolvedColor(_ id: String, mode: String, in tokens: [LibraryToken]) -> RGBAColor? {
        resolvedRaw(id, mode: mode, in: tokens).flatMap(LibraryTokenClassifier.color(from:))
    }

    static func cssFallback(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("var("), let comma = v.firstIndex(of: ",") else { return nil }
        let fallback = v[v.index(after: comma)...].dropLast().trimmingCharacters(in: .whitespaces)
        return fallback.isEmpty ? nil : fallback
    }

    static func markUnresolvedAliases(_ tokens: inout [LibraryToken], warnings: inout [String]) {
        let ids = Set(tokens.map(\.id))
        var dangling = 0
        for i in tokens.indices {
            guard let target = tokens[i].baseValue?.aliasOf, !ids.contains(target) else { continue }
            if cssFallback(tokens[i].baseValue?.raw ?? "") == nil { dangling += 1 }
            tokens[i].note = tokens[i].note
                ?? "Points at \(target.split(separator: ":").last ?? ""), which this library doesn't define (often supplied by WordPress or a vendor theme)."
        }
        for i in tokens.indices where tokens[i].isAlias {
            if resolvedRaw(tokens[i].id, mode: LibraryTokenMode.base, in: tokens) == nil, tokens[i].note == nil {
                tokens[i].note = "Alias could not be resolved (circular or missing)."
            }
        }
        if dangling > 0 { warnings.append("\(dangling) aliases point at tokens outside this library and have no fallback.") }
    }
}

// MARK: - Adoption into the document

struct LibraryTokenAdoptionReport: Equatable, Sendable {
    var libraryName: String
    var tokenCount = 0
    var addedColors = 0
    var updatedColors = 0
    var keptLocalEdits: [String] = []
    var keptDeleted: [String] = []
    var readOnlyCount = 0
    var nonColorCount = 0
    var warnings: [String] = []

    var summary: String {
        var lines = ["\(tokenCount) tokens from \(libraryName)."]
        lines.append("\(addedColors) colors added, \(updatedColors) updated in the Design Language.")
        if nonColorCount > 0 {
            lines.append("\(nonColorCount) spacing, type and other tokens are kept with the library and listed in the Design Language; components will use them.")
        }
        if readOnlyCount > 0 {
            lines.append("\(readOnlyCount) tokens are read-only here (aliases, expressions or types EXP can't edit yet). Their values are preserved exactly.")
        }
        if !keptLocalEdits.isEmpty {
            lines.append("Kept your edits to: \(keptLocalEdits.joined(separator: ", ")).")
        }
        if !keptDeleted.isEmpty {
            lines.append("Not re-added (you deleted them in EXP): \(keptDeleted.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}

enum LibraryTokenBindingKey {
    static let assetID = "designAssetID"
    static let tokenName = "tokenName"
    static let darkHex = "mode.dark"
}

enum LibraryTokenAdoption {
    /// Applies a scan to a document. Re-importing the same library updates by
    /// token ID: an asset still equal to its last-imported value takes the new
    /// value; one the designer changed keeps the designer's edit (reported);
    /// one the designer deleted stays deleted (reported). Pure function; the
    /// caller owns undo.
    /// Total source bytes preserved per library. Larger libraries keep digests only.
    static let maximumPreservedSourceBytes = 4 * 1_024 * 1_024
    static let sourceRole = "expsync-token-source"

    static func adopt(_ snapshot: LibraryTokenSnapshot, sourceFiles: [String: Data] = [:],
                      into document: Document) -> (Document, LibraryTokenAdoptionReport) {
        var doc = document
        var report = LibraryTokenAdoptionReport(libraryName: snapshot.displayName)
        report.tokenCount = snapshot.tokens.count
        report.warnings = snapshot.warnings

        let bridgeIndex = doc.codeBridges.firstIndex {
            $0.connector == LibraryTokenSnapshot.connector
                && $0.source.stableID == snapshot.libraryID
        }
        let previous = bridgeIndex.map { doc.codeBridges[$0] }
        var oldBindings: [String: CodeBridgeBinding] = [:]
        for binding in previous?.bindings ?? [] { oldBindings[binding.externalID] = binding }

        // One category per library, reused on refresh.
        let categoryName = snapshot.displayName
        let category: DLCategory
        if let existing = doc.designLanguage.categories.first(where: { $0.name == categoryName }) {
            category = existing
        } else {
            category = DLCategory(name: categoryName)
            doc.designLanguage.categories.append(category)
        }

        var bindings: [CodeBridgeBinding] = []
        for token in snapshot.tokens {
            let type = LibraryTokenResolver.resolvedType(token, in: snapshot.tokens)
            if !token.editable { report.readOnlyCount += 1 }
            guard type == .color,
                  let color = LibraryTokenResolver.resolvedColor(token.id, mode: LibraryTokenMode.base,
                                                                 in: snapshot.tokens) else {
                report.nonColorCount += 1
                continue
            }
            let paint = Paint.solid(color)
            let digest = hex(color)
            var metadata: [String: String] = [LibraryTokenBindingKey.tokenName: token.name]
            if let dark = LibraryTokenResolver.resolvedColor(token.id, mode: LibraryTokenMode.dark,
                                                              in: snapshot.tokens),
               token.modes[LibraryTokenMode.dark] != nil || isDarkThroughAlias(token, snapshot.tokens) {
                metadata[LibraryTokenBindingKey.darkHex] = hex(dark)
            }

            let displayName = String(token.name.drop { $0 == "-" || $0 == "{" }).replacingOccurrences(of: "}", with: "")
            let provenance = "library: \(snapshot.displayName) · \(token.sourcePath) · \(token.name)"
            var assetID: UUID?

            if let old = oldBindings[token.id],
               let idString = old.metadata[LibraryTokenBindingKey.assetID],
               let id = UUID(uuidString: idString) {
                if let index = doc.designLanguage.assets.firstIndex(where: { $0.id == id }) {
                    assetID = id
                    let current = doc.designLanguage.assets[index].value
                    if case .solid(let c) = current, hex(c) == old.baselineDigest {
                        if hex(c) != digest {
                            doc.designLanguage.assets[index].value = paint
                            report.updatedColors += 1
                        }
                        doc.designLanguage.assets[index].provenance = provenance
                    } else {
                        report.keptLocalEdits.append(token.name)
                    }
                } else {
                    report.keptDeleted.append(token.name)
                    // Keep the binding so the deletion stays a deliberate choice.
                    var kept = old
                    kept.metadata = old.metadata.merging(metadata) { _, new in new }
                    kept.metadata[LibraryTokenBindingKey.assetID] = idString
                    kept.baselineDigest = digest
                    kept.writableProperties = token.editable ? ["value"] : []
                    bindings.append(kept)
                    continue
                }
            } else {
                // `token:--name` makes CSS export emit the library's exact variable
                // name (DesignLanguageIO.cssAssetBindings) instead of a fresh slug.
                var tags = ["library-token"]
                if token.name.hasPrefix("--") { tags.append("token:\(token.name)") }
                let asset = DesignAsset(name: displayName, categoryID: category.id, value: paint,
                                        notes: token.note ?? "", tags: tags,
                                        provenance: provenance)
                doc.designLanguage.assets.append(asset)
                assetID = asset.id
                report.addedColors += 1
            }
            guard let assetID else { continue }
            metadata[LibraryTokenBindingKey.assetID] = assetID.uuidString
            bindings.append(CodeBridgeBinding(
                id: oldBindings[token.id]?.id ?? UUID(),
                externalID: token.id, externalKind: "token.\(type.rawValue)",
                sourcePath: token.sourcePath, confidence: 1, ownership: "source",
                observedProperties: ["value"], writableProperties: token.editable ? ["value"] : [],
                baselineDigest: digest, metadata: metadata))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = (try? encoder.encode(snapshot)) ?? Data()
        let resource = CodeBridgeResource(
            path: ".expsync/token-snapshot.json", role: LibraryTokenSnapshot.resourceRole,
            mimeType: "application/json", byteCount: payload.count,
            sha256: LibraryTokenScanner.sha256(payload), preservedData: payload,
            metadata: ["formatVersion": String(LibraryTokenSnapshot.currentFormatVersion)])
        let manifest = CodeBridgeManifest(
            id: previous?.id ?? UUID(), connector: LibraryTokenSnapshot.connector,
            source: CodeBridgeSource(displayName: snapshot.displayName, stableID: snapshot.libraryID,
                                     revision: snapshot.revision,
                                     metadata: ["contentDigest": snapshot.contentDigest]),
            resources: [resource] + sourceResources(snapshot, sourceFiles: sourceFiles, previous: previous),
            bindings: bindings,
            baseline: CodeBridgeBaseline(importedAt: snapshot.scannedAt,
                                         sourceRevision: snapshot.revision,
                                         sourceDigest: snapshot.contentDigest,
                                         snapshotVersion: LibraryTokenSnapshot.currentFormatVersion),
            metadata: ["feature": "FEAT-082", "buildExecution": "never"])
        if let bridgeIndex { doc.codeBridges[bridgeIndex] = manifest } else { doc.codeBridges.append(manifest) }
        return (doc, report)
    }

    /// The exact bytes of each selected source — the baseline a later changeset
    /// (FEAT-084) diffs against. Without new bytes (a snapshot-only refresh) the
    /// previous baseline is kept only when its digest still matches.
    private static func sourceResources(_ snapshot: LibraryTokenSnapshot, sourceFiles: [String: Data],
                                        previous: CodeBridgeManifest?) -> [CodeBridgeResource] {
        var budget = maximumPreservedSourceBytes
        let old = Dictionary((previous?.resources ?? []).filter { $0.role == sourceRole }.map { ($0.path, $0) },
                             uniquingKeysWith: { first, _ in first })
        return snapshot.sources.filter(\.selected).map { source in
            var data = sourceFiles[source.path]
            if data == nil, let kept = old[source.path], kept.sha256 == source.sha256 { data = kept.preservedData }
            let keep = data.map { $0.count <= budget } ?? false
            if keep, let data { budget -= data.count }
            return CodeBridgeResource(
                path: source.path, role: sourceRole,
                mimeType: source.kind == .cssCustomProperties ? "text/css" : "application/json",
                byteCount: source.byteCount, sha256: source.sha256,
                preservedData: keep ? data : nil,
                metadata: ["kind": source.kind.rawValue, "preserved": keep ? "true" : "false"])
        }
    }

    private static func isDarkThroughAlias(_ token: LibraryToken, _ tokens: [LibraryToken]) -> Bool {
        guard let target = token.baseValue?.aliasOf,
              let next = tokens.first(where: { $0.id == target }) else { return false }
        return next.modes[LibraryTokenMode.dark] != nil
    }

    static func hex(_ c: RGBAColor) -> String {
        func byte(_ v: Double) -> String { String(format: "%02x", Int((min(1, max(0, v)) * 255).rounded())) }
        return "#" + byte(c.r) + byte(c.g) + byte(c.b) + (c.a < 0.999 ? byte(c.a) : "")
    }
}

// MARK: - Reading back

/// What the Design Language shows for an asset that came from a library.
struct LibraryTokenLink: Equatable, Sendable {
    var token: String
    var tokenID: String
    var library: String
    var darkHex: String?
    var writable: Bool
}

/// Decoded snapshots keyed by their resource digest. Panels re-render on every
/// model change (ExpDocument.model is @Published), so decoding JSON per render
/// would put library size on the hot path; the digest only changes on re-import.
enum LibraryTokenSnapshotCache {
    nonisolated(unsafe) private static var decoded: [String: LibraryTokenSnapshot] = [:]

    static func snapshot(for resource: CodeBridgeResource) -> LibraryTokenSnapshot? {
        guard let data = resource.preservedData else { return nil }
        let key = resource.sha256 ?? LibraryTokenScanner.sha256(data)
        if let hit = decoded[key] { return hit }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(LibraryTokenSnapshot.self, from: data) else { return nil }
        if decoded.count > 32 { decoded.removeAll() }
        decoded[key] = value
        return value
    }
}

extension Document {
    /// Every library linked to this document, decoded from its bridge receipts.
    /// A damaged snapshot is skipped, never thrown — the artwork stays primary.
    var librarySnapshots: [LibraryTokenSnapshot] {
        codeBridges.filter { $0.connector == LibraryTokenSnapshot.connector }.compactMap { bridge in
            bridge.resources.first(where: { $0.role == LibraryTokenSnapshot.resourceRole })
                .flatMap(LibraryTokenSnapshotCache.snapshot(for:))
        }
    }

    /// Asset ID → library link, built once per call. Callers rendering many rows
    /// should take this dictionary once rather than looking up per row.
    var libraryTokenLinks: [UUID: LibraryTokenLink] {
        var out: [UUID: LibraryTokenLink] = [:]
        for bridge in codeBridges where bridge.connector == LibraryTokenSnapshot.connector {
            for binding in bridge.bindings {
                guard let raw = binding.metadata[LibraryTokenBindingKey.assetID],
                      let id = UUID(uuidString: raw) else { continue }
                out[id] = LibraryTokenLink(
                    token: binding.metadata[LibraryTokenBindingKey.tokenName] ?? binding.externalID,
                    tokenID: binding.externalID, library: bridge.source.displayName,
                    darkHex: binding.metadata[LibraryTokenBindingKey.darkHex],
                    writable: !binding.writableProperties.isEmpty)
            }
        }
        return out
    }

    func libraryTokenLink(forAsset id: UUID) -> LibraryTokenLink? { libraryTokenLinks[id] }
}

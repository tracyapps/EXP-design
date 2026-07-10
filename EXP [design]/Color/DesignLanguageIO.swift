//
//  DesignLanguageIO.swift
//  EXP [design]
//
//  Phase 18e — serialize / parse the document's design language for sharing.
//  Pure and UI-free (Foundation only) so it's testable and reusable by the panel,
//  menu commands, and any future automation.
//
//  Three surfaces:
//   • Canonical EXP JSON — a small, versioned envelope for document-to-document
//     sharing. Decoding is tolerant (envelope, bare array, or a whole
//     DesignLanguage all work) so hand-edited or older files still import.
//   • CSS custom properties — a developer/design hand-off format.
//   • Palette paste — best-effort import from HEX lists, CSS variables, and
//     Coolors share URLs. This only PARSES text the user pastes or a file they
//     pick; it never fetches a URL or scrapes a private endpoint.
//

import Foundation

/// The on-the-wire shape of an exported design language. `expDesignLanguage` is a
/// schema version so future changes stay legible and back-compatible.
struct EXPDesignLanguageFile: Codable {
    var expDesignLanguage: Int
    var categories: [DLCategory]
    var assets: [DesignAsset]
    var typeStyles: [TypeStyle]

    init(expDesignLanguage: Int, categories: [DLCategory], assets: [DesignAsset],
         typeStyles: [TypeStyle] = []) {
        self.expDesignLanguage = expDesignLanguage
        self.categories = categories
        self.assets = assets
        self.typeStyles = typeStyles
    }

    enum CodingKeys: String, CodingKey { case expDesignLanguage, categories, assets, typeStyles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expDesignLanguage = try c.decodeIfPresent(Int.self, forKey: .expDesignLanguage) ?? 1
        categories = try c.decodeIfPresent([DLCategory].self, forKey: .categories) ?? []
        // `assets` stays required-with-fallback: a type-styles-only file is valid.
        assets = try c.decodeIfPresent([DesignAsset].self, forKey: .assets) ?? []
        typeStyles = try c.decodeIfPresent([TypeStyle].self, forKey: .typeStyles) ?? []
    }
}

enum DesignLanguageIO {

    static let schemaVersion = 1

    // MARK: Canonical EXP JSON

    static func exportJSON(_ dl: DesignLanguage) throws -> Data {
        let file = EXPDesignLanguageFile(expDesignLanguage: schemaVersion,
                                        categories: dl.categories, assets: dl.assets,
                                        typeStyles: dl.typeStyles)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(file)
    }

    /// Tolerant import: accept the versioned envelope, a bare `[DesignAsset]`, or a
    /// full `DesignLanguage` object. Returns the entries plus any categories they
    /// reference; nil only if none of those decode.
    static func parseJSON(_ data: Data) -> (assets: [DesignAsset], categories: [DLCategory], typeStyles: [TypeStyle])? {
        let dec = JSONDecoder()
        if let f = try? dec.decode(EXPDesignLanguageFile.self, from: data),
           !f.assets.isEmpty || !f.typeStyles.isEmpty {
            return (f.assets, f.categories, f.typeStyles)
        }
        if let a = try? dec.decode([DesignAsset].self, from: data) { return (a, [], []) }
        if let dl = try? dec.decode(DesignLanguage.self, from: data) { return (dl.assets, dl.categories, dl.typeStyles) }
        return nil
    }

    // MARK: CSS custom properties

    /// A `:root { … }` block of custom properties for every non-archived entry.
    /// Slugs are made unique so no two lines collide.
    static func exportCSS(_ dl: DesignLanguage) -> String {
        let entries = dl.assets
        var used = Set<String>()
        var lines: [String] = []
        for a in entries {
            var name = slug(a.name, fallback: a.representativeColor)
            var n = 2
            while used.contains(name) { name = slug(a.name, fallback: a.representativeColor) + "-\(n)"; n += 1 }
            used.insert(name)
            lines.append("  --\(name): \(css(for: a.value));")
        }
        let root = lines.isEmpty ? ":root {\n}\n"
            : ":root {\n" + lines.joined(separator: "\n") + "\n}\n"
        let type = cssTypeStyles(dl)
        return type.isEmpty ? root : root + "\n" + type
    }

    /// Type styles as CSS classes (SCSS-friendly): one `.type-<slug>` block per
    /// style with honest `font-*` properties. Color is intentionally absent —
    /// EXP type styles don't own color (pair them with the custom properties).
    static func cssTypeStyles(_ dl: DesignLanguage) -> String {
        guard !dl.typeStyles.isEmpty else { return "" }
        var used = Set<String>()
        var blocks: [String] = []
        for t in dl.typeStyles {
            let base = t.name.isEmpty ? t.fallbackLabel : t.name
            var name = slug(base, fallback: .black)
            var n = 2
            while used.contains(name) { name = slug(base, fallback: .black) + "-\(n)"; n += 1 }
            used.insert(name)
            var props: [String] = []
            if !t.fontName.isEmpty { props.append("  font-family: \"\(t.fontName)\";") }
            props.append("  font-size: \(Int(t.fontSize.rounded()))px;")
            switch t.lineHeightUnit {
            case .auto:     props.append("  line-height: normal;")
            case .multiple: props.append("  line-height: \(t.lineHeight);")
            case .px:       props.append("  line-height: \(Int(t.lineHeight.rounded()))px;")
            case .em:       props.append("  line-height: \(t.lineHeight)em;")
            }
            if t.tracking != 0 { props.append("  letter-spacing: \(t.tracking)px;") }
            if t.align != .left { props.append("  text-align: \(t.align.rawValue);") }
            if t.underline { props.append("  text-decoration: underline;") }
            switch t.textCase {
            case .none: break
            case .upper:    props.append("  text-transform: uppercase;")
            case .lower:    props.append("  text-transform: lowercase;")
            case .title:    props.append("  text-transform: capitalize;")
            case .sentence: props.append("  /* text-transform: sentence-case (no CSS equivalent) */")
            }
            blocks.append(".type-\(name) {\n" + props.joined(separator: "\n") + "\n}")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// A single CSS custom-property declaration for one paint.
    static func cssVariable(name: String, paint: Paint) -> String {
        "--\(slug(name, fallback: paint.representativeColor)): \(css(for: paint));"
    }

    /// The CSS value for a paint: hex for a solid, a gradient function otherwise.
    static func css(for paint: Paint) -> String {
        switch paint {
        case .solid(let c):    return ColorMath.string(c, .hex)
        case .gradient(let g): return cssGradient(g)
        }
    }

    /// Convenience CSS gradient string. Approximate: CSS angles differ from the
    /// model's y-down degrees — this is a copy-out helper, not a renderer.
    static func cssGradient(_ g: GradientFill) -> String {
        let stops = g.sortedStops
            .map { "\(ColorMath.string($0.color, .hex)) \(Int(($0.position * 100).rounded()))%" }
            .joined(separator: ", ")
        switch g.kind {
        case .linear: return "linear-gradient(\(Int(g.angle.rounded()))deg, \(stops))"
        case .radial: return "radial-gradient(circle, \(stops))"
        }
    }

    /// A CSS-safe slug from a name; falls back to the color's hex when unnamed.
    static func slug(_ name: String, fallback color: RGBAColor) -> String {
        let base = name.isEmpty
            ? ColorMath.string(color, .hex).replacingOccurrences(of: "#", with: "color-")
            : name
        var out = ""
        for ch in base.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: Palette paste (HEX lists, CSS vars, Coolors URLs)

    /// Best-effort parse of pasted palette text into candidate solids. Named CSS
    /// custom properties keep their names; everything else lands unnamed. Values
    /// are de-duplicated by hex so a named entry isn't re-added by the loose pass.
    static func parsePalette(_ text: String) -> [DesignAsset] {
        let provenance = text.lowercased().contains("coolors.co") ? "import: coolors" : "import: pasted"
        var seen = Set<String>()
        var out: [DesignAsset] = []

        func add(_ color: RGBAColor, name: String) {
            let hex = ColorMath.string(color, .hex).uppercased()
            guard seen.insert(hex).inserted else { return }
            out.append(DesignAsset(name: name, value: .solid(color), provenance: provenance))
        }

        // 1) Named CSS custom properties: `--name: <color>;`
        for chunkSub in text.split(whereSeparator: { $0 == "\n" || $0 == ";" }) {
            let chunk = String(chunkSub)
            guard let r = chunk.range(of: "--") else { continue }
            let rest = chunk[r.upperBound...]
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let name = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(rest[rest.index(after: colon)...])
            if let color = parseColorToken(valuePart) { add(color, name: name) }
        }

        // 2) Any remaining hex tokens (hashed anywhere, or bare in lists / URLs).
        for token in hexTokens(in: text) {
            if let color = ColorMath.parseHex(token) { add(color, name: "") }
        }
        return out
    }

    /// Pull the first usable color out of a fragment (hex, rgb(), or hsl()).
    static func parseColorToken(_ s: String) -> RGBAColor? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let hashIdx = t.firstIndex(of: "#") {
            let hexPart = t[t.index(after: hashIdx)...].prefix { $0.isHexDigit }
            if let c = ColorMath.parseHex(String(hexPart)) { return c }
        }
        let lower = t.lowercased()
        if lower.contains("rgb") { return ColorMath.parse(t, .rgba, currentAlpha: 1) }
        if lower.contains("hsl") { return ColorMath.parse(t, .hsl, currentAlpha: 1) }
        return nil
    }

    /// Extract candidate hex tokens: split on common palette separators (and URL
    /// path bits), keep 3- or 6-digit all-hex tokens. Handles "#a1b2c3", bare
    /// "a1b2c3" comma/newline lists, and Coolors dash-joined URLs.
    static func hexTokens(in text: String) -> [String] {
        let separators = CharacterSet(charactersIn: " \t\n\r,;/|\\-").union(.whitespacesAndNewlines)
        var out: [String] = []
        for raw in text.components(separatedBy: separators) {
            var t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { t = String(t.dropFirst()) }
            guard t.count == 6 || t.count == 3 else { continue }
            if t.allSatisfy({ $0.isHexDigit }) { out.append("#" + t) }
        }
        return out
    }
}

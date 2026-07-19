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
//   • CSS custom properties + W3C Design Tokens — developer/design hand-off
//     formats.
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

    /// Tolerant import for W3C Design Tokens JSON (`$type` / `$value`). Accepts
    /// nested groups, group-level `$type`, and the common color/gradient/
    /// typography shapes used by Style Dictionary, Tokens Studio, and our own
    /// exporter. Unknown token types are skipped, not treated as corruption.
    static func parseDesignTokensJSON(_ data: Data) -> (assets: [DesignAsset], categories: [DLCategory], typeStyles: [TypeStyle])? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out = DTCGParseState()
        walkDesignTokens(root, path: [], inheritedType: nil, state: &out)
        guard !out.assets.isEmpty || !out.typeStyles.isEmpty else { return nil }
        return (out.assets, out.categories, out.typeStyles)
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
        if lower.contains("oklch") { return ColorMath.parse(t, .oklch, currentAlpha: 1) }
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

    // MARK: Forgiving variable paste (v1.3 transfer sheet — CSS + SCSS, mixed)

    /// What a pasted blob parsed into: named colors/gradients + type styles.
    struct ParsedVariables {
        var assets: [DesignAsset] = []
        var typeStyles: [TypeStyle] = []
        var isEmpty: Bool { assets.isEmpty && typeStyles.isEmpty }
    }

    /// Parse pasted CSS/SCSS **deliberately forgivingly** — paste from other
    /// apps arrives with stray prose, smart quotes, `:root {` wrappers,
    /// `!default` flags, whatever. Picks up BOTH kinds of declaration in one
    /// mixed paste:
    ///   • `--name: <color>` / `$name: <color>`  → named color (hex, rgb[a],
    ///     hsl[a], oklch)
    ///   • `--name: <font shorthand or family>` / `$name: …` → type style
    ///     (CSS font shorthand `[weight] size[/line-height] family` or a bare
    ///     family list)
    ///   • `.type-x { font-*: …; }` class blocks — round-trips our own CSS
    ///     export losslessly.
    /// Falls back to the loose hex-list/Coolors scan when nothing declared.
    static func parseVariables(_ text: String) -> ParsedVariables {
        if let data = text.data(using: .utf8),
           let parsed = parseDesignTokensJSON(data) ?? parseJSON(data),
           !parsed.assets.isEmpty || !parsed.typeStyles.isEmpty {
            return ParsedVariables(assets: parsed.assets, typeStyles: parsed.typeStyles)
        }

        var out = ParsedVariables()
        // Normalize smart quotes; strip /* */ and // comments.
        var clean = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        clean = removing(clean, pattern: "/\\*[\\s\\S]*?\\*/")
        clean = removing(clean, pattern: "(?m)//[^\\n]*$")

        var seenColorKeys = Set<String>()
        var seenStyleNames = Set<String>()

        // 1. `.type-x { … }` blocks (our own CSS export round-trip) — parsed
        //    FIRST and their ranges skipped by the variable pass below.
        var blockRanges: [Range<String.Index>] = []
        if let re = try? NSRegularExpression(pattern: "\\.([A-Za-z][A-Za-z0-9_-]*)\\s*\\{([^}]*)\\}") {
            let ns = clean as NSString
            for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
                guard let whole = Range(m.range, in: clean),
                      let nameR = Range(m.range(at: 1), in: clean),
                      let bodyR = Range(m.range(at: 2), in: clean) else { continue }
                let body = String(clean[bodyR])
                guard body.lowercased().contains("font") || body.lowercased().contains("letter-spacing") else { continue }
                blockRanges.append(whole)
                var name = String(clean[nameR])
                if name.lowercased().hasPrefix("type-") { name = String(name.dropFirst(5)) }
                if let style = typeStyle(fromCSSBody: body, name: name),
                   seenStyleNames.insert(name.lowercased()).inserted {
                    out.typeStyles.append(style)
                }
            }
        }

        // 2. Variable declarations — CSS custom properties and SCSS variables.
        if let re = try? NSRegularExpression(pattern: "(?:--|\\$)([A-Za-z_][A-Za-z0-9_-]*)\\s*:\\s*([^;{}\\n]+)") {
            let ns = clean as NSString
            for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
                guard let whole = Range(m.range, in: clean),
                      let nameR = Range(m.range(at: 1), in: clean),
                      let valueR = Range(m.range(at: 2), in: clean) else { continue }
                if blockRanges.contains(where: { $0.overlaps(whole) }) { continue }
                let name = String(clean[nameR])
                var value = String(clean[valueR]).trimmingCharacters(in: .whitespaces)
                value = removing(value, pattern: "!\\s*(default|important|global)\\b")
                    .trimmingCharacters(in: .whitespaces)
                if let color = parseColorToken(value) {
                    let key = name.lowercased() + "|" + ColorMath.string(color, .hex)
                    if seenColorKeys.insert(key).inserted {
                        out.assets.append(DesignAsset(name: name, value: .solid(color),
                                                      provenance: "import: variables"))
                    }
                } else if let style = typeStyle(fromFontValue: value, name: name),
                          seenStyleNames.insert(name.lowercased()).inserted {
                    out.typeStyles.append(style)
                }
                // Anything else (sizes alone, spacing, z-indexes…) is skipped
                // quietly — forgiveness means never erroring on junk.
            }
        }

        // 3. Nothing declared? Try the loose scan (bare hex lists, Coolors URLs).
        if out.isEmpty { out.assets = parsePalette(text) }
        return out
    }

    /// CSS `font:` shorthand (`[weight] size[/line-height] family, …`) or a
    /// bare family list ("'Avenir Next', sans-serif"). nil = not type-ish.
    static func typeStyle(fromFontValue raw: String, name: String) -> TypeStyle? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        // Shorthand: find `size[/lh]` then treat the rest as the family.
        if let re = try? NSRegularExpression(
            pattern: "(?:^|\\s)([0-9.]+)(px|pt|rem|em)\\s*(?:/\\s*([0-9.]+)(px|em)?)?\\s+(.+)$"),
           let m = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) {
            func g(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: value) else { return nil }
                return String(value[r])
            }
            guard let sizeNum = g(1).flatMap(Double.init), let sizeUnit = g(2), let famRaw = g(5) else { return nil }
            let size = CGFloat(sizeNum) * (sizeUnit == "rem" || sizeUnit == "em" ? 16 : 1)
            var lh: CGFloat = 1.3
            var lhUnit: LineHeightUnit = .auto
            if let lhNum = g(3).flatMap(Double.init) {
                if g(4) == "px" { lh = CGFloat(lhNum); lhUnit = .px }
                else if g(4) == "em" { lh = CGFloat(lhNum); lhUnit = .em }
                else { lh = CGFloat(lhNum); lhUnit = .multiple }
            }
            return TypeStyle(name: name, provenance: "import: variables",
                             fontName: firstFamily(famRaw), fontSize: size,
                             lineHeight: lh, lineHeightUnit: lhUnit)
        }
        // Bare family list: quoted name, or comma list ending in a generic.
        let lower = value.lowercased()
        let looksLikeFamily = value.contains("\"") || value.contains("'")
            || ["sans-serif", "serif", "monospace", "system-ui", "cursive"].contains(where: lower.contains)
            || (name.lowercased().contains("font") && value.first?.isLetter == true)
        guard looksLikeFamily, !lower.contains("gradient") else { return nil }
        let family = firstFamily(value)
        // A pure generic ("sans-serif") maps to the system font ("").
        return TypeStyle(name: name, provenance: "import: variables", fontName: family)
    }

    /// First concrete family from a CSS family list, unquoted. Generic-only
    /// lists return "" (= system font).
    static func firstFamily(_ list: String) -> String {
        for part in list.split(separator: ",") {
            let fam = part.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            guard !fam.isEmpty else { continue }
            if ["sans-serif", "serif", "monospace", "system-ui", "cursive", "fantasy", "inherit", "initial"].contains(fam.lowercased()) { continue }
            return fam
        }
        return ""
    }

    /// A `.type-x { … }` body → TypeStyle (round-trips `cssTypeStyles`).
    static func typeStyle(fromCSSBody body: String, name: String) -> TypeStyle? {
        var style = TypeStyle(name: name, provenance: "import: css")
        var sawAnything = false
        for line in body.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let prop = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch prop {
            case "font-family":
                style.fontName = firstFamily(value); sawAnything = true
            case "font-size":
                if let n = leadingNumber(value) {
                    style.fontSize = value.contains("rem") || value.contains("em") ? n * 16 : n
                    sawAnything = true
                }
            case "line-height":
                if value.lowercased() == "normal" { style.lineHeightUnit = .auto }
                else if let n = leadingNumber(value) {
                    style.lineHeight = n
                    style.lineHeightUnit = value.contains("px") ? .px : (value.contains("em") ? .em : .multiple)
                }
                sawAnything = true
            case "letter-spacing":
                if let n = leadingNumber(value) { style.tracking = n; sawAnything = true }
            case "text-align":
                if let a = TextAlign(rawValue: value.lowercased()) { style.align = a; sawAnything = true }
            case "text-decoration":
                if value.lowercased().contains("underline") { style.underline = true; sawAnything = true }
            case "text-transform":
                switch value.lowercased() {
                case "uppercase": style.textCase = .upper
                case "lowercase": style.textCase = .lower
                case "capitalize": style.textCase = .title
                default: break
                }
                sawAnything = true
            default: break
            }
        }
        return sawAnything ? style : nil
    }

    private static func leadingNumber(_ s: String) -> CGFloat? {
        var token = ""
        for ch in s.trimmingCharacters(in: .whitespaces) {
            if ch.isNumber || ch == "." || ch == "-" { token.append(ch) } else { break }
        }
        return Double(token).map { CGFloat($0) }
    }

    private static func removing(_ s: String, pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }


    // MARK: Additional export formats (v1.3 transfer sheet)

    /// SCSS: `$slug: value;` variables plus one `@mixin type-slug { … }` per
    /// type style (mixins are the idiomatic SCSS reuse for text treatments).
    static func exportSCSS(_ dl: DesignLanguage) -> String {
        var used = Set<String>()
        func unique(_ base: String) -> String {
            var name = base; var n = 2
            while used.contains(name) { name = "\(base)-\(n)"; n += 1 }
            used.insert(name); return name
        }
        var lines: [String] = []
        for a in dl.assets {
            let name = unique(slug(a.name, fallback: a.representativeColor))
            lines.append("$\(name): \(css(for: a.value));")
        }
        var out = lines.joined(separator: "\n")
        if !dl.typeStyles.isEmpty {
            // Reuse the CSS class bodies, reshaped as mixins.
            let cssBlocks = cssTypeStyles(dl)
                .replacingOccurrences(of: ".type-", with: "@mixin type-")
            out += (out.isEmpty ? "" : "\n\n") + cssBlocks
        }
        return out.isEmpty ? "// (empty design language)\n" : out + "\n"
    }

    /// W3C Design Tokens Community Group JSON (`$type`/`$value`) — the format
    /// Style Dictionary and the token ecosystem read. Colors, typography, and
    /// (draft-spec) gradients.
    static func exportDesignTokensJSON(_ dl: DesignLanguage) throws -> Data {
        var used = Set<String>()
        func unique(_ base: String) -> String {
            var name = base; var n = 2
            while used.contains(name) { name = "\(base)-\(n)"; n += 1 }
            used.insert(name); return name
        }
        var colors: [String: Any] = [:]
        var gradients: [String: Any] = [:]
        for a in dl.assets {
            let name = unique(slug(a.name, fallback: a.representativeColor))
            switch a.value {
            case .solid(let c):
                colors[name] = ["$type": "color", "$value": ColorMath.string(c, .hex)]
            case .gradient(let g):
                let stops: [[String: Any]] = g.sortedStops.map {
                    ["color": ColorMath.string($0.color, .hex), "position": Double($0.position)]
                }
                gradients[name] = ["$type": "gradient", "$value": stops]
            }
        }
        var typography: [String: Any] = [:]
        used.removeAll()
        for t in dl.typeStyles {
            let name = unique(slug(t.name.isEmpty ? t.fallbackLabel : t.name, fallback: .black))
            var value: [String: Any] = [
                "fontFamily": t.fontName.isEmpty ? "system-ui" : t.fontName,
                "fontSize": "\(Int(t.fontSize.rounded()))px",
            ]
            switch t.lineHeightUnit {
            case .auto: break
            case .multiple: value["lineHeight"] = Double(t.lineHeight)
            case .px: value["lineHeight"] = "\(Int(t.lineHeight.rounded()))px"
            case .em: value["lineHeight"] = "\(Double(t.lineHeight))em"
            }
            if t.tracking != 0 { value["letterSpacing"] = "\(Double(t.tracking))px" }
            typography[name] = ["$type": "typography", "$value": value]
        }
        var root: [String: Any] = [:]
        if !colors.isEmpty { root["color"] = colors }
        if !gradients.isEmpty { root["gradient"] = gradients }
        if !typography.isEmpty { root["typography"] = typography }
        return try JSONSerialization.data(withJSONObject: root,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: W3C Design Tokens import

    private struct DTCGParseState {
        var categories: [DLCategory] = []
        var categoryIDs: [String: UUID] = [:]
        var assets: [DesignAsset] = []
        var typeStyles: [TypeStyle] = []

        mutating func categoryID(for name: String?) -> UUID? {
            guard let name, !name.isEmpty else { return nil }
            if let id = categoryIDs[name.lowercased()] { return id }
            let cat = DLCategory(name: name)
            categories.append(cat)
            categoryIDs[name.lowercased()] = cat.id
            return cat.id
        }
    }

    private static func walkDesignTokens(_ object: [String: Any], path: [String],
                                         inheritedType: String?, state: inout DTCGParseState) {
        let nextType = (object["$type"] as? String) ?? inheritedType
        if object.keys.contains("$value") {
            consumeDesignToken(object, path: path, inheritedType: nextType, state: &state)
            return
        }
        for key in object.keys.sorted() where !key.hasPrefix("$") {
            guard let child = object[key] as? [String: Any] else { continue }
            walkDesignTokens(child, path: path + [key], inheritedType: nextType, state: &state)
        }
    }

    private static func consumeDesignToken(_ token: [String: Any], path: [String],
                                           inheritedType: String?, state: inout DTCGParseState) {
        guard let value = token["$value"] else { return }
        let kind = ((token["$type"] as? String) ?? inheritedType ?? "").lowercased()
        let name = readableTokenName(path.last ?? "")
        let category = path.dropLast().last.map { readableTokenName($0) }
        let categoryID = state.categoryID(for: category)
        switch kind {
        case "color", "colour":
            guard let color = dtcgColor(value) else { return }
            state.assets.append(DesignAsset(name: name, categoryID: categoryID,
                                            value: .solid(color),
                                            provenance: "import: design tokens"))
        case "gradient":
            guard let gradient = dtcgGradient(value) else { return }
            state.assets.append(DesignAsset(name: name, categoryID: categoryID,
                                            value: .gradient(gradient),
                                            provenance: "import: design tokens"))
        case "typography", "font":
            guard let style = dtcgTypography(value, name: name, categoryID: categoryID) else { return }
            state.typeStyles.append(style)
        default:
            // Some files omit `$type`; infer only when the value is unambiguous.
            if let color = dtcgColor(value), looksColorish(path: path) {
                state.assets.append(DesignAsset(name: name, categoryID: categoryID,
                                                value: .solid(color),
                                                provenance: "import: design tokens"))
            } else if let gradient = dtcgGradient(value) {
                state.assets.append(DesignAsset(name: name, categoryID: categoryID,
                                                value: .gradient(gradient),
                                                provenance: "import: design tokens"))
            } else if let style = dtcgTypography(value, name: name, categoryID: categoryID),
                      looksTypeish(path: path) {
                state.typeStyles.append(style)
            }
        }
    }

    private static func dtcgColor(_ value: Any) -> RGBAColor? {
        if let s = value as? String { return parseColorToken(s) }
        guard let dict = value as? [String: Any] else { return nil }
        if let hex = dict["hex"] as? String { return parseColorToken(hex) }
        if let color = dict["color"] as? String { return parseColorToken(color) }
        if let components = dict["components"] as? [String: Any] {
            return colorFromComponents(components, alpha: number(dict["alpha"]))
        }
        if let r = number(dict["r"] ?? dict["red"]),
           let g = number(dict["g"] ?? dict["green"]),
           let b = number(dict["b"] ?? dict["blue"]) {
            let scale: Double = max(r, g, b) > 1 ? 255 : 1
            return RGBAColor(r: ColorMath.clamp01(r / scale),
                             g: ColorMath.clamp01(g / scale),
                             b: ColorMath.clamp01(b / scale),
                             a: ColorMath.clamp01(number(dict["a"] ?? dict["alpha"]) ?? 1))
        }
        if let space = (dict["colorSpace"] ?? dict["space"]) as? String {
            var comps: [String: Any] = [:]
            for (k, v) in dict where !k.hasPrefix("$") { comps[k] = v }
            comps["colorSpace"] = space
            return colorFromComponents(comps, alpha: number(dict["alpha"]))
        }
        return nil
    }

    private static func colorFromComponents(_ components: [String: Any], alpha: Double?) -> RGBAColor? {
        let space = ((components["colorSpace"] ?? components["space"]) as? String)?.lowercased() ?? "srgb"
        let a = ColorMath.clamp01(alpha ?? number(components["a"] ?? components["alpha"]) ?? 1)
        switch space {
        case "srgb", "rgb":
            guard let r = number(components["r"] ?? components["red"]),
                  let g = number(components["g"] ?? components["green"]),
                  let b = number(components["b"] ?? components["blue"]) else { return nil }
            let scale: Double = max(r, g, b) > 1 ? 255 : 1
            return RGBAColor(r: ColorMath.clamp01(r / scale),
                             g: ColorMath.clamp01(g / scale),
                             b: ColorMath.clamp01(b / scale),
                             a: a)
        case "hsl":
            guard let h = number(components["h"] ?? components["hue"]),
                  let s = number(components["s"] ?? components["saturation"]),
                  let l = number(components["l"] ?? components["lightness"]) else { return nil }
            let (r, g, b) = ColorMath.hslToRGB(h, s > 1 ? s / 100 : s, l > 1 ? l / 100 : l)
            return RGBAColor(r: r, g: g, b: b, a: a)
        case "oklch":
            guard let l = number(components["l"] ?? components["lightness"]),
                  let c = number(components["c"] ?? components["chroma"]),
                  let h = number(components["h"] ?? components["hue"]) else { return nil }
            let (r, g, b) = ColorMath.oklchToRGB(l > 1 ? l / 100 : l, c, h)
            return RGBAColor(r: r, g: g, b: b, a: a)
        case "lch":
            guard let l = number(components["l"] ?? components["lightness"]),
                  let c = number(components["c"] ?? components["chroma"]),
                  let h = number(components["h"] ?? components["hue"]) else { return nil }
            let (r, g, b) = ColorMath.lchToRGB(l, c, h)
            return RGBAColor(r: r, g: g, b: b, a: a)
        default:
            return nil
        }
    }

    private static func dtcgGradient(_ value: Any) -> GradientFill? {
        let rawStops: [Any]
        if let arr = value as? [Any] {
            rawStops = arr
        } else if let dict = value as? [String: Any],
                  let stops = (dict["stops"] ?? dict["colorStops"]) as? [Any] {
            rawStops = stops
        } else {
            return nil
        }
        let stops = rawStops.enumerated().compactMap { index, raw -> GradientStop? in
            if let dict = raw as? [String: Any] {
                let colorValue = dict["color"] ?? dict["value"] ?? dict["$value"]
                guard let colorValue, let color = dtcgColor(colorValue) else { return nil }
                let pos = number(dict["position"] ?? dict["stopPosition"] ?? dict["offset"])
                    ?? (rawStops.count <= 1 ? 0 : Double(index) / Double(rawStops.count - 1))
                return GradientStop(color: color, position: pos > 1 ? pos / 100 : pos)
            }
            guard let color = dtcgColor(raw) else { return nil }
            let pos = rawStops.count <= 1 ? 0 : Double(index) / Double(rawStops.count - 1)
            return GradientStop(color: color, position: pos)
        }
        guard stops.count >= 2 else { return nil }
        var gradient = GradientFill()
        gradient.stops = stops
        if let dict = value as? [String: Any] {
            let type = ((dict["gradientType"] ?? dict["type"]) as? String)?.lowercased()
            gradient.kind = type == "radial" ? .radial : .linear
            if let angle = number(dict["angle"]) { gradient.angle = angle }
        }
        return gradient
    }

    private static func dtcgTypography(_ value: Any, name: String, categoryID: UUID?) -> TypeStyle? {
        guard let dict = value as? [String: Any] else { return nil }
        var style = TypeStyle(name: name, categoryID: categoryID, provenance: "import: design tokens")
        var saw = false
        if let family = string(dict["fontFamily"] ?? dict["font-family"] ?? dict["font"]) {
            style.fontName = firstFamily(family)
            saw = true
        }
        if let size = dimension(dict["fontSize"] ?? dict["font-size"] ?? dict["size"]) {
            style.fontSize = size
            saw = true
        }
        if let lineHeight = dict["lineHeight"] ?? dict["line-height"] {
            if let parsed = lineHeightValue(lineHeight) {
                style.lineHeight = parsed.value
                style.lineHeightUnit = parsed.unit
                saw = true
            }
        }
        if let tracking = dimension(dict["letterSpacing"] ?? dict["letter-spacing"] ?? dict["tracking"]) {
            style.tracking = tracking
            saw = true
        }
        if let align = string(dict["textAlign"] ?? dict["text-align"]),
           let value = TextAlign(rawValue: align.lowercased()) {
            style.align = value
            saw = true
        }
        if let underline = bool(dict["underline"]) {
            style.underline = underline
            saw = true
        } else if let decoration = string(dict["textDecoration"] ?? dict["text-decoration"]),
                  decoration.lowercased().contains("underline") {
            style.underline = true
            saw = true
        }
        if let transform = string(dict["textTransform"] ?? dict["text-transform"] ?? dict["textCase"]) {
            switch transform.lowercased() {
            case "uppercase", "upper": style.textCase = .upper
            case "lowercase", "lower": style.textCase = .lower
            case "capitalize", "title": style.textCase = .title
            case "sentence": style.textCase = .sentence
            default: break
            }
            saw = true
        }
        return saw ? style : nil
    }

    private static func readableTokenName(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return spaced.split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    private static func looksColorish(path: [String]) -> Bool {
        path.contains { ["color", "colors", "colour", "colours"].contains($0.lowercased()) }
    }

    private static func looksTypeish(path: [String]) -> Bool {
        path.contains { ["type", "typography", "font", "fonts"].contains($0.lowercased()) }
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return leadingNumber(s).map(Double.init) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func dimension(_ value: Any?) -> CGFloat? {
        guard let n = number(value) else { return nil }
        if let s = value as? String, s.lowercased().contains("rem") { return CGFloat(n * 16) }
        return CGFloat(n)
    }

    private static func lineHeightValue(_ value: Any) -> (value: CGFloat, unit: LineHeightUnit)? {
        if let n = number(value) {
            if let s = value as? String {
                let lower = s.lowercased()
                if lower.contains("px") { return (CGFloat(n), .px) }
                if lower.contains("em") { return (CGFloat(n), .em) }
                if lower.contains("%") { return (CGFloat(n / 100), .multiple) }
            }
            return (CGFloat(n), .multiple)
        }
        if let s = value as? String, s.lowercased() == "normal" { return (1.3, .auto) }
        return nil
    }

    /// Sketch `.sketchpalette` (solid colors only — the format has no
    /// gradients or type).
    static func exportSketchPalette(_ dl: DesignLanguage) throws -> Data {
        let colors: [[String: Any]] = dl.solids.map { a in
            let c = a.representativeColor
            return ["red": c.r, "green": c.g, "blue": c.b, "alpha": c.a]
        }
        let root: [String: Any] = [
            "compatibleVersion": "2.0",
            "pluginVersion": "2.22",
            "colors": colors,
        ]
        return try JSONSerialization.data(withJSONObject: root,
                                          options: [.prettyPrinted, .sortedKeys])
    }

}

/// The transfer sheet's export formats (v1.3). Text formats preview + copy;
/// every format saves to file.
enum DLExportFormat: String, CaseIterable, Identifiable {
    case cssVars, scssVars, expJSON, designTokens, sketchPalette
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cssVars:       return "CSS variables"
        case .scssVars:      return "SCSS variables"
        case .expJSON:       return "EXP JSON"
        case .designTokens:  return "Design Tokens JSON"
        case .sketchPalette: return "Sketch palette"
        }
    }
    var fileExtension: String {
        switch self {
        case .cssVars:       return "css"
        case .scssVars:      return "scss"
        case .expJSON:       return "json"
        case .designTokens:  return "tokens.json"
        case .sketchPalette: return "sketchpalette"
        }
    }
    /// One honest line about who reads this format.
    var blurb: String {
        switch self {
        case .cssVars:       return "Custom properties in a :root block, plus .type-* classes. For the web, or pasting back into EXP."
        case .scssVars:      return "$variables plus @mixin type-* blocks for Sass/SCSS codebases."
        case .expJSON:       return "EXP's own format — everything round-trips losslessly between .design documents."
        case .designTokens:  return "W3C Design Tokens ($type/$value) — read by Style Dictionary and most token pipelines."
        case .sketchPalette: return "Sketch's palette format. Solid colors only — no gradients or type."
        }
    }

    /// The generated document (text formats return UTF-8 text data).
    func data(for dl: DesignLanguage) throws -> Data {
        switch self {
        case .cssVars:       return Data(DesignLanguageIO.exportCSS(dl).utf8)
        case .scssVars:      return Data(DesignLanguageIO.exportSCSS(dl).utf8)
        case .expJSON:       return try DesignLanguageIO.exportJSON(dl)
        case .designTokens:  return try DesignLanguageIO.exportDesignTokensJSON(dl)
        case .sketchPalette: return try DesignLanguageIO.exportSketchPalette(dl)
        }
    }
    /// Preview text (all our formats are text-representable).
    func previewText(for dl: DesignLanguage) -> String {
        (try? data(for: dl)).flatMap { String(data: $0, encoding: .utf8) } ?? "(nothing to export)"
    }
}

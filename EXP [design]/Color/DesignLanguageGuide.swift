import Foundation

/// The live window and offline export both render this payload with the same template.
struct DesignLanguageGuide: Encodable, Sendable {
    struct Value: Encodable, Sendable {
        let text: String
        var swatch: String?
        var alias: String?
        var contrast: String?
    }

    struct Row: Encodable, Sendable {
        let id: String
        let name: String
        let section: String
        let group: String
        let role: String
        var notes: String
        var deprecated: String?
        var uses: Int?
        let base: Value
        var overrides: [String: Value] = [:]
        var css: String?
        var scss: String?
        var dtcg: String?
        var specimenClass: String?
    }

    struct Mode: Encodable, Sendable {
        let id: String
        let name: String
        let axis: String
        let selector: String
        let active: Bool
        let background: String?
        let foreground: String?
        let contrast: String?
    }

    struct Library: Encodable, Sendable {
        let name: String
        let revision: String?
    }

    let title: String
    let modes: [Mode]
    let libraries: [Library]
    let rows: [Row]
    let specimenCSS: String
    let files: [String: String]

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    func html(template: String, embedded: Bool = false) throws -> String {
        guard let slot = template.range(of: "__EXP_GUIDE_DATA__") else { throw TemplateError.invalid }
        // Treat every user string as data, even inside the raw-text script element.
        let data = try json().replacingOccurrences(of: "<", with: #"\u003c"#)
        var html = template.replacingCharacters(in: slot, with: data)
        if embedded { html = html.replacingOccurrences(of: "<body>", with: "<body data-embedded>") }
        return html
    }

    static func template(in bundle: Bundle = .main) throws -> String {
        let url = bundle.url(forResource: "DesignLanguageGuide", withExtension: "html")
            ?? bundle.url(forResource: "DesignLanguageGuide", withExtension: "html", subdirectory: "Resources")
        guard let url else { throw TemplateError.invalid }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private enum TemplateError: LocalizedError {
        case invalid
        var errorDescription: String? { "The Design Language Guide template is unavailable." }
    }
}

enum DesignLanguageGuideBuilder {
    private struct CodeNames {
        var variables: [UUID: String] = [:]
        var paths: [UUID: [String]] = [:]
    }

    private struct Entry {
        var row: DesignLanguageGuide.Row
        var cssBase: String?
        var cssModes: [String: String] = [:]
        var dtcgBase: [String: Any]?
        var dtcgModes: [String: [String: Any]] = [:]
    }

    static func build(document: Document, title: String) throws -> DesignLanguageGuide {
        let language = document.designLanguage
        let uses = document.tokenUseCounts()
        let snapshots = document.librarySnapshots
        let assetBindings = DesignLanguageIO.cssAssetBindings(language)
        let typeBindings = DesignLanguageIO.cssTypeStyleBindings(language)
        let names = codeNames(language, assets: assetBindings, styles: typeBindings)
        let colors = language.colorModeSet?.id
        let modeSets = language.modeSets.filter { !$0.modes.isEmpty }
        var modes: [DesignLanguageGuide.Mode] = []
        var axisNames: [UUID: String] = [:]
        var modeNames: [UUID: String] = [:]
        var modeIDByKey: [String: UUID] = [:]
        var claimedAxes = Set<String>()
        for set in modeSets {
            let axis = unique(slug(set.name, fallback: "mode"), in: &claimedAxes)
            axisNames[set.id] = axis
            var claimedModes = Set<String>()
            for mode in set.modes {
                let key = mode.id.uuidString
                let name = unique(slug(mode.name, fallback: "mode"), in: &claimedModes)
                modeNames[mode.id] = name
                modeIDByKey[key] = mode.id
                let background = set.id == colors ? mode.resolvedBackground : nil
                let foreground = set.id == colors ? mode.resolvedForeground : nil
                modes.append(.init(id: key, name: mode.name, axis: set.name,
                                   selector: "data-exp-\(axis)=\u{22}\(name)\u{22}",
                                   active: set.resolvedActiveModeID == mode.id,
                                   background: background.map { ColorMath.string($0, .hex) },
                                   foreground: foreground.map { ColorMath.string($0, .hex) },
                                   contrast: foreground.flatMap { fg in background.map { contrast(fg, over: $0) } }))
            }
        }
        let pairs = Dictionary(language.colorModeSet?.modes.map { ($0.id.uuidString, $0.resolvedBackground) } ?? [],
                               uniquingKeysWith: { first, _ in first })
        let assetByID = Dictionary(language.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tokenByID = Dictionary(language.tokens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [(UUID, Entry)] = []

        for asset in language.assets {
            let section: String
            switch asset.value {
            case .solid: section = "Colors"
            case .gradient, .mesh: section = "Gradients"
            case .pattern: section = "Preserved Values"
            }
            let base = paintValue(asset.value, background: pairs[language.baseModeID?.uuidString ?? ""] ?? .white)
            var row = DesignLanguageGuide.Row(
                id: asset.id.uuidString, name: asset.name.isEmpty ? base.text : asset.name, section: section,
                group: displayGroup(asset.group, category: language.category(asset.categoryID)),
                role: "", notes: asset.notes, deprecated: asset.deprecated,
                uses: uses[asset.id] ?? 0, base: base)
            let token = paintToken(asset.value, notes: asset.notes, deprecated: asset.deprecated)
            var entry = Entry(row: row, cssBase: asset.value.isPattern ? nil : base.text, dtcgBase: token)
            for mode in modes {
                guard let id = modeIDByKey[mode.id], pairs[mode.id] != nil else { continue }
                let paint = language.paint(for: asset, in: id)
                var value = paintValue(paint, background: pairs[mode.id])
                if let target = asset.modeValues[mode.id]?.aliasTarget {
                    let trail = aliasTrail(startingAt: asset.id) { current in
                        guard let found = assetByID[current], case .solid = found.value else { return nil }
                        return (found.name, found.modeValues[mode.id]?.aliasTarget)
                    }
                    value.alias = trail?.text
                    let valid = trail?.valid == true
                    if valid, let variable = names.variables[target] { entry.cssModes[mode.id] = "var(--\(variable))" }
                    if valid, let path = names.paths[target], let token {
                        entry.dtcgModes[mode.id] = replacingValue(of: token, with: reference(path))
                    }
                }
                row.overrides[mode.id] = value
                if paint != asset.value || asset.modeValues[mode.id] != nil {
                    if entry.cssModes[mode.id] == nil { entry.cssModes[mode.id] = value.text }
                    if entry.dtcgModes[mode.id] == nil { entry.dtcgModes[mode.id] = paintToken(paint, notes: asset.notes, deprecated: asset.deprecated) }
                }
            }
            entry.row = row
            entries.append((asset.id, entry))
        }

        for binding in typeBindings {
            let style = binding.style
            let label = style.name.isEmpty ? style.fallbackLabel : style.name
            let face = style.fontName.isEmpty ? "System" : style.fontName
            let height = style.lineHeightUnit == .auto ? "Auto line height" : "Line height \(style.lineHeight) \(style.lineHeightUnit.rawValue)"
            let summary = "\(face) · \(style.fontSize.formatted()) px · \(height)"
            let row = DesignLanguageGuide.Row(id: style.id.uuidString, name: label, section: "Typography",
                group: displayGroup(style.group, category: language.category(style.categoryID)),
                role: "Type Style", notes: style.notes, deprecated: style.deprecated,
                uses: uses[style.id] ?? 0, base: .init(text: summary),
                css: ".\(binding.className)", scss: "@include \(binding.className);", specimenClass: binding.className)
            entries.append((style.id, Entry(row: row, dtcgBase: typographyToken(style))))
        }

        for token in language.tokens {
            let baseResult = language.resolvedTokenValue(token.id)
            var base = tokenValue(baseResult)
            if token.value.aliasTarget != nil {
                base.alias = aliasTrail(startingAt: token.id) { id in tokenByID[id].map { ($0.name, $0.value.aliasTarget) } }?.text
            }
            let group = displayGroup(token.group, category: language.category(token.categoryID))
            var row = DesignLanguageGuide.Row(id: token.id.uuidString, name: token.name.isEmpty ? "Unnamed Token" : token.name,
                section: section(for: token), group: group, role: token.role == .generic ? token.type.rawValue : token.role.rawValue,
                notes: token.notes, deprecated: token.deprecated, uses: uses[token.id] ?? 0, base: base)
            let baseJSON = typedToken(token, resolved: baseResult)
            let baseCSS = cssValue(dimensionValue(baseResult, for: token))
            var entry = Entry(row: row,
                              cssBase: cssAlias(token.value, resolved: baseCSS, names: names) ?? baseCSS,
                              dtcgBase: jsonAlias(token.value, resolved: baseJSON, token: token, names: names, tokens: tokenByID))
            for mode in modes {
                guard let id = modeIDByKey[mode.id] else { continue }
                let raw = token.value(inMode: id)
                let resolved = language.resolvedTokenValue(token.id, modeID: id)
                var value = tokenValue(resolved)
                if raw.aliasTarget != nil {
                    value.alias = aliasTrail(startingAt: token.id) { idInChain in
                        tokenByID[idInChain].map { ($0.name, $0.value(inMode: id).aliasTarget) }
                    }?.text
                }
                if raw != token.value || resolved != baseResult { row.overrides[mode.id] = value }
                if raw != token.value {
                    let modeCSS = cssValue(dimensionValue(resolved, for: token))
                    entry.cssModes[mode.id] = cssAlias(raw, resolved: modeCSS, names: names) ?? modeCSS
                    entry.dtcgModes[mode.id] = jsonAlias(raw, resolved: typedToken(token, resolved: resolved),
                                                        token: token, names: names, tokens: tokenByID)
                }
            }
            entry.row = row
            entries.append((token.id, entry))
        }

        var rows: [DesignLanguageGuide.Row] = []
        for (id, entry) in entries {
            var row = entry.row
            if let variable = names.variables[id], entry.cssBase != nil || !entry.cssModes.isEmpty {
                row.css = "var(--\(variable))"
                if entry.cssBase != nil { row.scss = "$\(variable)" }
            }
            if let path = names.paths[id], entry.dtcgBase != nil { row.dtcg = reference(path) }
            if entry.dtcgBase == nil && entry.cssBase == nil && row.specimenClass == nil && row.section != "Preserved Values" {
                row.notes = [row.notes, "Preserved for reference. This value has no supported token-file representation."]
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            rows.append(row)
        }
        let represented = Set(language.tokens.compactMap(\.externalID)).union(document.libraryTokenLinks.values.map(\.tokenID))
        for snapshot in snapshots {
            let namesByID = Dictionary(snapshot.tokens.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            for token in snapshot.tokens where !represented.contains(token.id) {
                func value(_ raw: LibraryTokenValue?) -> DesignLanguageGuide.Value {
                    .init(text: raw?.raw ?? "Unavailable",
                          alias: raw?.aliasOf.map { "→ " + (namesByID[$0] ?? $0) })
                }
                var row = DesignLanguageGuide.Row(id: snapshot.libraryID + ":" + token.id,
                    name: token.name, section: "Preserved Values",
                    group: snapshot.displayName, role: token.type.rawValue,
                    notes: token.note ?? "Preserved from the source library.",
                    base: value(token.baseValue))
                for mode in modes {
                    if let id = modeIDByKey[mode.id], let key = language.colorModeSet?.modes.first(where: { $0.id == id })?.libraryKey,
                       let raw = token.modes[key] { row.overrides[mode.id] = value(raw) }
                }
                rows.append(row)
            }
        }

        let specimenCSS = DesignLanguageIO.cssTypeStyles(language)
        let modeLookup = Dictionary(modes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exportOrder = modeSets.reversed().flatMap { $0.modes }.map { $0.id.uuidString }
        let preservedRows = rows.filter { $0.uses == nil }
        let files = try tokenFiles(entries: entries, preservedRows: preservedRows, names: names, modeSets: modeSets, modes: modeLookup,
                                   axisNames: axisNames, modeNames: modeNames, exportOrder: exportOrder,
                                   specimenCSS: specimenCSS)
        return .init(title: title, modes: modes,
                     libraries: snapshots.map { .init(name: $0.displayName, revision: $0.revision) },
                     rows: rows.sorted { a, b in
                         if a.group != b.group { return a.group.localizedStandardCompare(b.group) == .orderedAscending }
                         return a.name.localizedStandardCompare(b.name) == .orderedAscending
                     }, specimenCSS: specimenCSS, files: files)
    }

    private static func codeNames(_ language: DesignLanguage, assets: [DesignLanguageIO.CSSAssetBinding],
                                  styles: [DesignLanguageIO.CSSTypeStyleBinding]) -> CodeNames {
        var names = CodeNames()
        var usedCSS: Set<String> = ["exp-canvas-background", "exp-canvas-foreground", "exp-modes"]
        var usedPaths = Set<String>()
        let assetGroups = Dictionary(language.assets.compactMap { asset in
            asset.group.map { (asset.id, groupPath($0)) }
        }, uniquingKeysWith: { first, _ in first })
        for binding in assets {
            let name = variableName(binding.variableName, in: &usedCSS)
            names.variables[binding.assetID] = name
            let group: String
            if case .solid = binding.paint { group = "color" } else { group = "gradient" }
            let nested = assetGroups[binding.assetID] ?? []
            names.paths[binding.assetID] = path([group] + nested + [name], in: &usedPaths)
        }
        for binding in styles {
            let nested = binding.style.group.map(groupPath) ?? []
            let name = String(binding.className.dropFirst("type-".count))
            names.paths[binding.styleID] = path(["typography"] + nested + [name], in: &usedPaths)
        }
        for token in language.tokens {
            let group = groupPath(token.group)
            let tokenName = slug(token.name, fallback: "token")
            let sourceName = token.externalID.flatMap { source -> String? in
                guard source.hasPrefix("css:--") else { return nil }
                let name = String(source.dropFirst("css:--".count))
                return !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } ? name : nil
            }
            names.variables[token.id] = variableName(sourceName ?? (group + [tokenName]).joined(separator: "-"), in: &usedCSS)
            names.paths[token.id] = path(group + [tokenName], in: &usedPaths)
        }
        return names
    }

    private static func displayGroup(_ group: String?, category: DLCategory?) -> String {
        [group, category?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private static func groupPath(_ group: String) -> [String] {
        group.split(separator: "/").map { slug(String($0), fallback: "group") }
    }

    private static func path(_ proposed: [String], in used: inout Set<String>) -> [String] {
        let group = proposed.dropLast()
        let leaf = proposed.last ?? "token"
        var result = proposed
        var suffix = 2
        while used.contains(where: {
            let key = result.joined(separator: ".")
            return $0 == key || $0.hasPrefix(key + ".") || key.hasPrefix($0 + ".")
        }) {
            if let conflict = group.indices.first(where: { used.contains(group.prefix($0 + 1).joined(separator: ".")) }) {
                result[conflict] = "\(proposed[conflict])-\(suffix)"
            } else {
                result[result.count - 1] = "\(leaf)-\(suffix)"
            }
            suffix += 1
        }
        used.insert(result.joined(separator: "."))
        return result
    }

    private static func slug(_ name: String, fallback: String) -> String {
        let value = name.isEmpty ? fallback : name
        return DesignLanguageIO.slug(value, fallback: .black)
    }

    private static func unique(_ base: String, in used: inout Set<String>) -> String {
        var name = base
        var suffix = 2
        while !used.insert(name).inserted {
            name = "\(base)-\(suffix)"
            suffix += 1
        }
        return name
    }

    private static func variableName(_ base: String, in used: inout Set<String>) -> String {
        // Sass treats underscores and hyphens as equivalent in identifiers.
        let name = base.first?.isNumber == true ? "token-" + base : base
        var candidate = name
        var suffix = 2
        while !used.insert(candidate.replacingOccurrences(of: "_", with: "-")).inserted {
            candidate = "\(name)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func section(for token: DLToken) -> String {
        if case .preserved = token.value { return "Preserved Values" }
        switch token.role {
        case .spacing: return "Spacing"
        case .sizing, .breakpoint: return "Sizing"
        case .radius: return "Radius"
        case .borderWidth: return "Borders"
        case .elevation: return "Shadows"
        case .duration, .easing: return "Motion"
        case .fontSize, .lineHeight, .letterSpacing: return "Typography"
        default:
            switch token.type {
            case .border, .strokeStyle: return "Borders"
            case .shadow: return "Shadows"
            case .duration, .transition, .cubicBezier: return "Motion"
            case .fontFamily, .fontWeight: return "Typography"
            default: return "Other Tokens"
            }
        }
    }

    private static func paintValue(_ paint: Paint, background: RGBAColor?) -> DesignLanguageGuide.Value {
        let css = DesignLanguageIO.css(for: paint)
        if case .solid(let color) = paint {
            return .init(text: css, swatch: css, contrast: background.map { contrast(color, over: $0) })
        }
        if paint.isPattern { return .init(text: "Pattern fallback \(css)") }
        return .init(text: css, swatch: css)
    }

    private static func contrast(_ color: RGBAColor, over background: RGBAColor) -> String {
        let ratio = ContrastMath.report(foreground: color, background: background).ratio
        let result = ratio >= 4.5 ? "AA normal text" : ratio >= 3 ? "AA large text only" : "Below AA"
        return "\(String(format: "%.2f", ratio)):1 · \(result)"
    }

    private static func tokenValue(_ value: DLTokenValue?) -> DesignLanguageGuide.Value {
        guard let value else { return .init(text: "Unresolved") }
        switch value {
        case .color(let color):
            let hex = ColorMath.string(color, .hex)
            return .init(text: hex, swatch: hex)
        case .preserved(let data):
            return .init(text: (try? JSONEncoder().encode(data)).map { String(decoding: $0, as: UTF8.self) } ?? "Unavailable")
        default: return .init(text: value.authoredText)
        }
    }

    private static func aliasTrail(startingAt id: UUID, get: (UUID) -> (String, UUID?)?) -> (text: String, valid: Bool)? {
        var steps: [String] = []
        var active = Set([id])
        var next = get(id)?.1
        var valid = true
        while let target = next {
            guard active.insert(target).inserted else { steps.append("Cycle"); valid = false; break }
            guard let (name, successor) = get(target) else { steps.append("Missing token"); valid = false; break }
            steps.append(name.isEmpty ? "Unnamed token" : name)
            next = successor
        }
        return steps.isEmpty ? nil : ("→ " + steps.joined(separator: " → "), valid)
    }

    private static func cssValue(_ value: DLTokenValue?) -> String? {
        guard let value else { return nil }
        if case .color(let color) = value { return ColorMath.string(color, .hex) }
        let css = value.authoredText
        // Free-form imported data can be displayed in the guide. Only single
        // declaration values can be written to an executable stylesheet.
        guard !css.isEmpty, !css.contains("/*"), !css.lowercased().contains("url("),
              !css.unicodeScalars.contains(where: { $0.value < 32 }),
              css.rangeOfCharacter(from: CharacterSet(charactersIn: ";{}<>\\@")) == nil else { return nil }
        return css
    }

    private static func cssAlias(_ value: DLTokenValue, resolved: String?, names: CodeNames) -> String? {
        guard let resolved, let id = value.aliasTarget, let name = names.variables[id] else { return nil }
        return "var(--\(name), \(resolved))"
    }

    private static func reference(_ path: [String]) -> String { "{\(path.joined(separator: "."))}" }

    private static func jsonAlias(_ value: DLTokenValue, resolved: [String: Any]?, token: DLToken,
                                  names: CodeNames, tokens: [UUID: DLToken]) -> [String: Any]? {
        guard let resolved, let id = value.aliasTarget, let path = names.paths[id],
              tokens[id]?.type == token.type else { return resolved }
        return replacingValue(of: resolved, with: reference(path))
    }

    private static func replacingValue(of token: [String: Any], with value: String) -> [String: Any] {
        var updated = token
        updated["$value"] = value
        return updated
    }

    private static func colorTokenValue(_ color: RGBAColor) -> [String: Any] {
        ["colorSpace": "srgb", "components": [color.r, color.g, color.b].map(ColorMath.clamp01),
         "alpha": ColorMath.clamp01(color.a)]
    }

    private static func definition(_ type: String, _ value: Any, notes: String, deprecated: String? = nil) -> [String: Any] {
        var token: [String: Any] = ["$type": type, "$value": value]
        if !notes.isEmpty { token["$description"] = notes }
        if let deprecated { token["$deprecated"] = deprecated.isEmpty ? true as Any : deprecated }
        return token
    }

    private static func paintToken(_ paint: Paint, notes: String, deprecated: String?) -> [String: Any]? {
        switch paint {
        case .solid(let color): return definition("color", colorTokenValue(color), notes: notes, deprecated: deprecated)
        case .gradient(let gradient):
            let stops: [[String: Any]] = gradient.sortedStops.map { ["color": colorTokenValue($0.color), "position": $0.position] }
            var token = definition("gradient", stops, notes: notes, deprecated: deprecated)
            if let metadata = try? JSONEncoder().encode(gradient),
               let geometry = try? JSONSerialization.jsonObject(with: metadata) {
                token["$extensions"] = ["app.expdesign.gradient": geometry]
            }
            return token
        case .mesh, .pattern: return nil
        }
    }

    private static func typographyToken(_ style: TypeStyle) -> [String: Any] {
        let face = style.fontName.isEmpty ? "system-ui" : style.fontName
        let height = style.lineHeightUnit == .multiple ? Double(style.lineHeight)
            : style.lineHeightUnit == .em ? Double(style.lineHeight)
            : style.lineHeightUnit == .px ? Double(style.lineHeight / max(1, style.fontSize)) : 1.2
        let value: [String: Any] = [
            "fontFamily": face, "fontSize": ["value": Double(style.fontSize), "unit": "px"],
            "fontWeight": 400, "letterSpacing": ["value": Double(style.tracking), "unit": "px"], "lineHeight": height
        ]
        var token = definition("typography", value, notes: style.notes, deprecated: style.deprecated)
        if let data = try? JSONEncoder().encode(style), let original = try? JSONSerialization.jsonObject(with: data) {
            token["$extensions"] = ["app.expdesign.type-style": original]
        }
        return token
    }

    private static func dimensionValue(_ resolved: DLTokenValue?, for token: DLToken) -> DLTokenValue? {
        if token.type == .dimension, case .number(let number) = resolved { return .dimension(DLDimension(number)) }
        return resolved
    }

    private static func typedToken(_ token: DLToken, resolved: DLTokenValue?) -> [String: Any]? {
        guard let resolved = dimensionValue(resolved, for: token) else { return nil }
        let type = token.type.rawValue
        let value: Any
        switch (type, resolved) {
        case ("dimension", .dimension(let d)) where ["px", "rem"].contains(d.unit):
            value = ["value": d.value, "unit": d.unit]
        case ("duration", .dimension(let d)) where ["ms", "s"].contains(d.unit):
            value = ["value": d.value, "unit": d.unit]
        case ("number", .number(let n)): value = n
        case ("fontWeight", .number(let n)) where (1...1000).contains(n): value = n
        case ("color", .color(let color)): value = colorTokenValue(color)
        default: return nil
        }
        return definition(type, value, notes: token.notes, deprecated: token.deprecated)
    }

    private static func tokenFiles(entries: [(UUID, Entry)], preservedRows: [DesignLanguageGuide.Row],
                                   names: CodeNames, modeSets: [DLModeSet],
                                   modes: [String: DesignLanguageGuide.Mode], axisNames: [UUID: String],
                                   modeNames: [UUID: String], exportOrder: [String],
                                   specimenCSS: String) throws -> [String: String] {
        var base: [String: Any] = [:]
        var overlays: [String: [String: Any]] = [:]
        var preserved: [[String: String]] = []
        var css = [":root {"]
        var scss: [String] = []
        var scssModes: [String] = []
        for (id, entry) in entries {
            if let variable = names.variables[id], let value = entry.cssBase {
                css.append("  --\(variable): \(value);")
                let literal = entry.row.base.swatch ?? entry.row.base.text
                if value.hasPrefix("var("), !literal.isEmpty && literal != "Unresolved" {
                    scss.append("$\(variable): \(literal);")
                } else {
                    scss.append("$\(variable): \(value);")
                }
            }
            if let path = names.paths[id] {
                if let token = entry.dtcgBase { insert(token, at: path[...], in: &base) }
                for (mode, token) in entry.dtcgModes { insert(token, at: path[...], in: &overlays[mode, default: [:]]) }
            }
            if entry.dtcgBase == nil {
                preserved.append(["name": entry.row.name, "group": entry.row.group, "value": entry.row.base.text])
            }
            for mode in entry.row.overrides.keys.sorted() where entry.dtcgModes[mode] == nil {
                guard let value = entry.row.overrides[mode], value.text != entry.row.base.text else { continue }
                preserved.append(["name": entry.row.name, "group": entry.row.group,
                                  "mode": modes[mode]?.name ?? mode, "value": value.text])
            }
        }
        css.append("}")
        for id in exportOrder {
            guard let mode = modes[id] else { continue }
            let values = entries.compactMap { id, entry -> (String, String)? in
                guard let name = names.variables[id], let value = entry.cssModes[mode.id] else { return nil }
                return (name, value)
            }
            var declarations = values
            if let bg = mode.background, let fg = mode.foreground {
                declarations += [("exp-canvas-background", bg), ("exp-canvas-foreground", fg)]
            }
            guard !declarations.isEmpty else { continue }
            css.append(":root[\(mode.selector)] {")
            css += declarations.map { "  --\($0.0): \($0.1);" }
            css.append("}")
            if let modeID = UUID(uuidString: mode.id), let key = modeNames[modeID] {
                var literal = entries.compactMap { id, entry -> (String, String)? in
                    guard let name = names.variables[id], let css = entry.cssModes[mode.id] else { return nil }
                    let resolved = entry.row.overrides[mode.id]?.text ?? css
                    return (name, css.hasPrefix("var(") ? resolved : css)
                }
                if let bg = mode.background, let fg = mode.foreground {
                    literal += [("exp-canvas-background", bg), ("exp-canvas-foreground", fg)]
                }
                let values = literal.map { "    \u{22}\($0.0)\u{22}: \($0.1)" }.joined(separator: ",\n")
                let axis = mode.selector.prefix(while: { $0 != "=" }).dropFirst("data-exp-".count)
                scssModes.append("  \u{22}\(axis)/\(key)\u{22}: (\n\(values)\n  )")
            }
        }
        for row in preservedRows {
            preserved.append(["name": row.name, "group": row.group, "value": row.base.text, "reason": row.notes])
            for mode in row.overrides.keys.sorted() {
                guard let value = row.overrides[mode] else { continue }
                preserved.append(["name": row.name, "group": row.group,
                                  "mode": modes[mode]?.name ?? mode, "value": value.text, "reason": row.notes])
            }
        }
        if !preserved.isEmpty { base["$extensions"] = ["app.expdesign.preserved": preserved] }
        if !scssModes.isEmpty { scss.append("$exp-modes: (\n" + scssModes.joined(separator: ",\n") + "\n);") }
        if !specimenCSS.isEmpty {
            css.append(specimenCSS)
            scss.append(specimenCSS.replacingOccurrences(of: #"(?m)^\.type-"#, with: "@mixin type-", options: .regularExpression))
        }
        var files = ["tokens.css": css.joined(separator: "\n") + "\n",
                     "_tokens.scss": scss.joined(separator: "\n") + "\n",
                     "tokens.json": try json(base)]
        if !modeSets.isEmpty {
            var modifiers: [String: Any] = [:]
            var order = [["$ref": "#/sets/base"]]
            for set in modeSets.reversed() {
                guard let axis = axisNames[set.id] else { continue }
                var contexts: [String: [[String: Any]]] = [:]
                for mode in set.modes {
                    guard let key = modeNames[mode.id] else { continue }
                    contexts[key] = [overlays[mode.id.uuidString] ?? [:]]
                }
                var config: [String: Any] = ["description": set.name, "contexts": contexts]
                let defaultID = set.modes.first(where: { $0.id == set.defaultModeID })?.id ?? set.modes.first?.id
                if let defaultID, let defaultMode = modeNames[defaultID] { config["default"] = defaultMode }
                modifiers[axis] = config
                order.append(["$ref": "#/modifiers/\(axis)"])
            }
            files["tokens.resolver.json"] = try json([
                "$schema": "https://www.designtokens.org/schemas/2025.10/resolver.json",
                "version": "2025.10", "sets": ["base": ["sources": [base]]],
                "modifiers": modifiers, "resolutionOrder": order
            ])
        }
        return files
    }

    private static func insert(_ token: [String: Any], at path: ArraySlice<String>, in root: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 { root[key] = token; return }
        var group = root[key] as? [String: Any] ?? [:]
        insert(token, at: path.dropFirst(), in: &group)
        root[key] = group
    }

    private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self) + "\n"
    }
}

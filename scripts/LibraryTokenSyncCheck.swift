import Foundation

// FEAT-082 check: library token scan → Design Language adoption → save/reopen →
// refresh rules → CSS export names. Run through scripts/verify_library_token_sync.sh.

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}
private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    if try !condition() { fail(message) }
}
private var passed = 0
private func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("  ok  \(name)") }
    catch { fail("\(name): \(error)") }
}

private func write(_ text: String, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func roundTrip(_ doc: Document) throws -> Document {
    let data = try JSONEncoder().encode(doc)
    return try JSONDecoder().decode(Document.self, from: data)
}

private func asset(named name: String, in doc: Document) -> DesignAsset? {
    doc.designLanguage.assets.first { $0.name == name }
}

private func hexOf(_ asset: DesignAsset?) -> String? {
    guard let asset, case .solid(let c) = asset.value else { return nil }
    return LibraryTokenAdoption.hex(c)
}

@main
private enum LibraryTokenSyncCheck {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("usage: LibraryTokenSyncCheck <start-2 fixture> [live library]") }
        let fixture = URL(fileURLWithPath: args[1])
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("exp-library-token-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let scanner = LibraryTokenScanner()

        print("Start 2.0 fixture")
        let scanned = try scanner.scanWithSources(root: fixture, now: Date(timeIntervalSince1970: 1_800_000_000))
        let snapshot = scanned.snapshot
        var adopted = Document()

        check("identity from WordPress theme header") {
            require(snapshot.libraryID == "wp-theme:start-2", "libraryID \(snapshot.libraryID)")
            require(snapshot.displayName == "Start 2.0", "displayName \(snapshot.displayName)")
        }
        check("CSS custom properties selected; theme.json read but not adopted; dist skipped") {
            let css = snapshot.sources.filter { $0.kind == .cssCustomProperties }
            require(!css.isEmpty && css.allSatisfy(\.selected), "css sources \(css)")
            require(css.contains { $0.path == "assets/src/css/tokens.css" }, "tokens.css missing: \(css.map(\.path))")
            require(!snapshot.sources.contains { $0.path.hasPrefix("assets/dist/") }, "dist should be skipped")
            let theme = snapshot.sources.first { $0.kind == .wordPressThemeJSON }
            require(theme != nil && theme?.selected == false, "theme.json should be found and unselected")
            require(snapshot.sources.allSatisfy { $0.sha256.count == 64 }, "source digests")
        }
        check("literal tokens keep exact names, types and editability") {
            let accent = snapshot.token("css:--color-accent")
            require(accent?.name == "--color-accent" && accent?.type == .color && accent?.editable == true,
                    "accent \(String(describing: accent))")
            require(accent?.baseValue?.raw == "#1f7a70", "accent raw")
            require(snapshot.token("css:--space-md")?.type == .dimension, "space-md dimension")
            require(snapshot.token("css:--radius-sm")?.type == .dimension, "radius dimension")
            require(snapshot.token("css:--shadow-soft")?.type == .shadow, "shadow")
            require(snapshot.token("css:--shadow-soft")?.editable == false, "shadow read-only")
        }
        check("aliases stay aliases and resolve per mode") {
            let bg = snapshot.token("css:--color-bg")
            require(bg?.baseValue?.aliasOf == "css:--color-paper", "bg alias \(String(describing: bg))")
            require(bg?.editable == false, "alias not directly editable")
            require(bg?.modes[LibraryTokenMode.dark]?.raw == "#111820", "bg dark mode")
            require(LibraryTokenResolver.resolvedColor("css:--color-bg", mode: LibraryTokenMode.base,
                                                       in: snapshot.tokens).map(LibraryTokenAdoption.hex) == "#f8f6f1",
                    "bg base resolves to paper")
            require(LibraryTokenResolver.resolvedColor("css:--color-text", mode: LibraryTokenMode.dark,
                                                       in: snapshot.tokens).map(LibraryTokenAdoption.hex) == "#f8f6f1",
                    "text dark")
            let sans = snapshot.token("css:--font-sans")
            require(sans?.baseValue?.aliasOf == "css:--wp--preset--font-family--sans", "font-sans alias")
            require(LibraryTokenResolver.resolvedType(sans!, in: snapshot.tokens) == .fontFamily,
                    "font-sans resolves through its fallback")
        }
        check("expressions preserved byte-for-byte and read-only") {
            let border = snapshot.token("css:--color-border")
            require(border?.type == .expression && border?.editable == false, "border expression")
            require(border?.baseValue?.raw == "color-mix(in srgb, var(--color-ink) 18%, transparent)", "border raw")
            require(border?.modes[LibraryTokenMode.dark]?.raw.contains("var(--color-text) 20%") == true, "border dark")
            require(snapshot.token("css:--space-section")?.type == .expression, "clamp expression")
        }

        print("Adoption")
        var report = LibraryTokenAdoptionReport(libraryName: "")
        check("colors become Design Language assets with source names and a library category") {
            (adopted, report) = LibraryTokenAdoption.adopt(snapshot, sourceFiles: scanned.sourceFiles,
                                                           into: Document())
            require(report.addedColors == 10, "added \(report.addedColors): \(adopted.designLanguage.assets.map(\.name))")
            require(hexOf(asset(named: "color-accent", in: adopted)) == "#1f7a70", "accent asset")
            require(hexOf(asset(named: "color-bg", in: adopted)) == "#f8f6f1", "bg asset resolved")
            require(asset(named: "color-border", in: adopted) == nil, "color-mix not flattened into a solid")
            let category = adopted.designLanguage.categories.first { $0.name == "Start 2.0" }
            require(category != nil, "library category")
            require(adopted.designLanguage.assets.allSatisfy { $0.categoryID == category?.id }, "assets in category")
            require(report.nonColorCount > 0 && report.readOnlyCount > 0, "report counts")
        }
        check("asset links expose token name, dark value and writability") {
            let bg = asset(named: "color-bg", in: adopted)!
            let link = adopted.libraryTokenLink(forAsset: bg.id)
            require(link?.token == "--color-bg" && link?.library == "Start 2.0", "bg link \(String(describing: link))")
            require(link?.darkHex == "#111820" && link?.writable == false, "bg dark/writable")
            let accent = asset(named: "color-accent", in: adopted)!
            require(adopted.libraryTokenLink(forAsset: accent.id)?.writable == true, "accent writable")
        }
        check("CSS export keeps the library's exact variable names") {
            let css = DesignLanguageIO.exportCSS(adopted.designLanguage)
            require(css.contains("--color-accent: #1F7A70;") || css.contains("--color-accent: #1f7a70;"),
                    "accent var in export:\n\(css)")
            require(css.contains("--color-accent-strong:"), "accent-strong var")
            var injected = DesignAsset(name: "x", value: .solid(.white), tags: ["token:--bad; } body {"])
            injected.name = "Bad Name"
            require(DesignLanguageIO.libraryVariableName(injected) == nil, "unsafe token tag rejected")
        }
        check("save → reopen preserves snapshot, bindings and assets") {
            let reopened = try roundTrip(adopted)
            require(reopened.librarySnapshots.count == 1, "snapshot count")
            require(reopened.librarySnapshots[0] == snapshot, "snapshot equal after round trip")
            require(reopened.codeBridges[0].bindings == adopted.codeBridges[0].bindings, "bindings equal")
            require(reopened.designLanguage.assets.count == adopted.designLanguage.assets.count, "assets")
            let original = try Data(contentsOf: fixture.appendingPathComponent("assets/src/css/tokens.css"))
            let kept = reopened.codeBridges[0].resources.first { $0.path == "assets/src/css/tokens.css" }
            require(kept?.preservedData == original, "tokens.css preserved byte-for-byte as the baseline")
            let (refreshOnly, _) = LibraryTokenAdoption.adopt(snapshot, into: reopened)
            let still = refreshOnly.codeBridges[0].resources.first { $0.path == "assets/src/css/tokens.css" }
            require(still?.preservedData == original, "baseline kept across a snapshot-only refresh")
        }
        check("v2.7-shape file: snapshot travels in fields v2.7 already round-trips") {
            // Document.swift's CodeBridge types are unchanged since the v2.7 tag; prove
            // the payload uses only those fields by stripping every key they don't know.
            let data = try JSONEncoder().encode(adopted)
            var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let bridges = object["codeBridges"] as! [[String: Any]]
            let known: Set<String> = ["id", "schemaVersion", "connector", "source", "resources",
                                      "bindings", "behaviorContracts", "baseline", "metadata"]
            require(bridges.allSatisfy { Set($0.keys).isSubset(of: known) }, "unknown bridge keys")
            object["codeBridges"] = bridges
            let reopened = try JSONDecoder().decode(Document.self,
                                                    from: try JSONSerialization.data(withJSONObject: object))
            require(reopened.librarySnapshots.first?.tokens.count == snapshot.tokens.count, "tokens survive")
        }

        print("Refresh")
        check("re-import of the same revision changes nothing") {
            let (again, r) = LibraryTokenAdoption.adopt(snapshot, into: adopted)
            require(r.addedColors == 0 && r.updatedColors == 0 && r.keptLocalEdits.isEmpty, "\(r)")
            require(again.designLanguage.assets.count == adopted.designLanguage.assets.count, "no duplicates")
            require(again.codeBridges.count == 1, "one bridge per library")
        }
        check("library change updates untouched assets, keeps designer edits and deletions") {
            var edited = adopted
            let accentIndex = edited.designLanguage.assets.firstIndex { $0.name == "color-accent" }!
            edited.designLanguage.assets[accentIndex].value = .solid(RGBAColor(r: 1, g: 0, b: 0))
            edited.designLanguage.assets.removeAll { $0.name == "color-muted" }

            var next = snapshot
            for (id, value) in [("css:--color-ink", "#000000"), ("css:--color-accent", "#00ff00"),
                                ("css:--color-muted", "#777777")] {
                let i = next.tokens.firstIndex { $0.id == id }!
                next.tokens[i].modes[LibraryTokenMode.base]?.raw = value
            }
            let (refreshed, r) = LibraryTokenAdoption.adopt(next, into: edited)
            require(hexOf(asset(named: "color-ink", in: refreshed)) == "#000000", "ink updated")
            require(hexOf(asset(named: "color-text", in: refreshed)) == "#000000", "alias follows its target")
            require(hexOf(asset(named: "color-accent", in: refreshed)) == "#ff0000", "designer edit kept")
            require(r.keptLocalEdits == ["--color-accent"], "kept edits \(r.keptLocalEdits)")
            require(asset(named: "color-muted", in: refreshed) == nil && r.keptDeleted == ["--color-muted"],
                    "deletion respected \(r.keptDeleted)")
            // Third pass: the deletion stays a deliberate choice.
            let (third, r3) = LibraryTokenAdoption.adopt(next, into: refreshed)
            require(asset(named: "color-muted", in: third) == nil && r3.addedColors == 0, "still deleted")
        }

        print("Synthetic edge cases")
        check("mode selectors, nesting, media, scoped vars, comments, !important") {
            let css = """
            /* :root { --commented: #fff; } */
            :root { --a: #112233; --b: var(--a) !important; --gap: 1.5rem; --dur: 200ms; }
            html.dark { --a: #000000; }
            .wa-dark { --b: #ffffff; }
            @media (min-width: 40rem) { :root { --gap: 2rem; } }
            @media (prefers-color-scheme: dark) { :root:not(.light) { --gap-dark-only: 3px; } }
            .card { --card-pad: 1rem; }
            :root { & .inner { --nested-scoped: 1px; } }
            :root { --url: url("data:image/svg+xml;a{b}"); }
            """
            let result = LibraryCSSVariableParser.parse(css, sourcePath: "t.css")
            let byID = Dictionary(uniqueKeysWithValues: result.tokens.map { ($0.id, $0) })
            require(byID["css:--commented"] == nil, "comment stripped")
            require(byID["css:--a"]?.modes[LibraryTokenMode.dark]?.raw == "#000000", "html.dark")
            require(byID["css:--b"]?.baseValue?.aliasOf == "css:--a", "!important alias")
            require(byID["css:--b"]?.modes[LibraryTokenMode.dark]?.raw == "#ffffff", ".wa-dark")
            require(byID["css:--gap"]?.baseValue?.raw == "1.5rem", "width media is not a mode")
            require(byID["css:--dur"]?.type == .duration, "duration")
            require(byID["css:--gap-dark-only"]?.modes[LibraryTokenMode.dark] != nil, "dark-only token")
            require(byID["css:--card-pad"] == nil && byID["css:--nested-scoped"] == nil, "scoped skipped")
            require(result.skippedScopedDeclarations >= 3, "skipped count \(result.skippedScopedDeclarations)")
            require(byID["css:--url"]?.baseValue?.raw == "url(\"data:image/svg+xml;a{b}\")", "string with braces")
        }
        check("alias cycles resolve to nothing instead of looping") {
            let tokens = LibraryCSSVariableParser.parse(":root{--x:var(--y);--y:var(--x);}", sourcePath: "c.css").tokens
            require(LibraryTokenResolver.resolvedRaw("css:--x", mode: LibraryTokenMode.base, in: tokens) == nil, "cycle")
        }
        check("DTCG files win, with aliases, inherited types, dark file and preserved unknown types") {
            let lib = scratch.appendingPathComponent("dtcg-lib")
            try write("""
            {"color": {"$type": "color",
               "brand": {"$value": "#3366ff"},
               "action": {"$value": "{color.brand}", "$description": "buttons"}},
             "space": {"$type": "dimension", "md": {"$value": "16px"}},
             "motion": {"ease": {"$type": "cubicBezier", "$value": [0.2, 0, 0, 1]}}}
            """, lib.appendingPathComponent("tokens/base.tokens.json"))
            try write(##"{"color": {"$type": "color", "brand": {"$value": "#99bbff"}}}"##,
                      lib.appendingPathComponent("tokens/dark.tokens.json"))
            try write(":root { --ignored-because-dtcg-wins: #fff; }", lib.appendingPathComponent("src/x.css"))
            try write(":root { --from-node-modules: #fff; }", lib.appendingPathComponent("node_modules/pkg/a.css"))
            try write(#"{"name": "@acme/ui"}"#, lib.appendingPathComponent("package.json"))
            let snap = try scanner.scan(root: lib)
            require(snap.libraryID == "npm:@acme/ui", "npm identity \(snap.libraryID)")
            require(snap.sources.filter(\.selected).allSatisfy { $0.kind == .designTokens }, "dtcg preferred")
            require(!snap.sources.contains { $0.path.contains("node_modules") }, "node_modules excluded")
            let brand = snap.token("dtcg:color.brand")
            require(brand?.name == "{color.brand}" && brand?.type == .color, "brand")
            require(brand?.modes[LibraryTokenMode.dark]?.raw == "#99bbff", "dark file merged")
            require(snap.token("dtcg:color.action")?.baseValue?.aliasOf == "dtcg:color.brand", "dtcg alias")
            require(snap.token("dtcg:space.md")?.type == .dimension, "inherited dimension")
            let ease = snap.token("dtcg:motion.ease")
            require(ease?.editable == false && ease?.baseValue?.raw == "[0.2,0,0,1]", "cubicBezier preserved \(String(describing: ease))")
            let (doc, r) = LibraryTokenAdoption.adopt(snap, into: Document())
            require(r.addedColors == 2, "dtcg colors \(r.addedColors)")
            require(asset(named: "color.action", in: doc) != nil, "dtcg display name")
            let action = asset(named: "color.action", in: doc)!
            require(doc.libraryTokenLink(forAsset: action.id)?.darkHex == "#99bbff", "alias dark through target")
        }
        check("symlinks are not followed and .expsync identity wins") {
            let lib = scratch.appendingPathComponent("linked")
            let outside = scratch.appendingPathComponent("outside")
            try write(":root { --outside: #123456; }", outside.appendingPathComponent("evil.css"))
            try write(":root { --inside: #654321; }", lib.appendingPathComponent("a.css"))
            try write(#"{"libraryID": "acme-design-system", "displayName": "Acme DS"}"#,
                      lib.appendingPathComponent(".expsync/expsync.json"))
            try FileManager.default.createSymbolicLink(at: lib.appendingPathComponent("link"),
                                                       withDestinationURL: outside)
            let snap = try scanner.scan(root: lib)
            require(snap.token("css:--outside") == nil && snap.token("css:--inside") != nil, "symlink followed")
            require(snap.libraryID == "acme-design-system" && snap.displayName == "Acme DS", "expsync identity")
        }
        check("empty folder reports nothing found") {
            let empty = scratch.appendingPathComponent("empty")
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            do { _ = try scanner.scan(root: empty); fail("expected nothingFound") }
            catch LibraryTokenScanError.nothingFound { }
        }

        print("Newer-version warning")
        check("files from a newer EXP raise a notice; current and v2.7 files don't") {
            let current = try JSONEncoder().encode(adopted)
            var object = try JSONSerialization.jsonObject(with: current) as! [String: Any]
            func decode(_ o: [String: Any]) throws -> Document {
                try JSONDecoder().decode(Document.self, from: try JSONSerialization.data(withJSONObject: o))
            }
            try require(decode(object).newerVersionNotice(runningBuild: 19) == nil, "current file is safe")
            object["writtenBy"] = nil
            try require(decode(object).newerVersionNotice(runningBuild: 19) == nil, "v2.7-shape file is safe")

            var newerSchema = object; newerSchema["schemaVersion"] = Document.currentSchemaVersion + 1
            try require(decode(newerSchema).newerVersionNotice(runningBuild: 19)?.reasons.first?
                        .contains("file format") == true, "newer schema")

            var newerBuild = object
            newerBuild["writtenBy"] = ["appVersion": "2.9", "build": 21, "schemaVersion": Document.currentSchemaVersion]
            let notice = try decode(newerBuild).newerVersionNotice(runningBuild: 19)
            require(notice?.writerVersion == "2.9 (build 21)", "writer version \(String(describing: notice))")
            try require(decode(newerBuild).newerVersionNotice(runningBuild: 21) == nil, "same build is safe")
            try require(decode(newerBuild).newerVersionNotice(runningBuild: nil) == nil, "unknown running build")

            var unknownKey = object; unknownKey["componentContracts"] = [["id": "x"]]
            let unknown = try decode(unknownKey)
            require(unknown.unknownTopLevelKeys == ["componentContracts"], "unknown keys \(unknown.unknownTopLevelKeys)")
            require(unknown.newerVersionNotice(runningBuild: 19)?.reasons.first?.contains("componentContracts") == true,
                    "unknown key reason")
        }

        if args.count >= 3 {
            print("Live library: \(args[2])")
            let live = try scanner.scan(root: URL(fileURLWithPath: args[2]))
            let (doc, r) = LibraryTokenAdoption.adopt(live, into: Document())
            let reopened = try roundTrip(doc)
            require(reopened.librarySnapshots.first == live, "live round trip")
            print("  \(live.displayName) [\(live.libraryID)] \(live.tokens.count) tokens, \(live.sources.count) sources")
            print(r.summary.split(separator: "\n").map { "  | " + $0 }.joined(separator: "\n"))
            for w in live.warnings { print("  warn: \(w)") }
        }

        print("\nFixture summary:")
        print(report.summary.split(separator: "\n").map { "  | " + $0 }.joined(separator: "\n"))
        for w in snapshot.warnings { print("  warn: \(w)") }
        print("PASS — \(passed) checks")
    }
}

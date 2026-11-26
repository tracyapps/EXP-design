import Foundation

// FEAT-090a check: Design Language tokens + bindings (docs/DESIGN-LANGUAGE-PLAN.md
// §3–§4, §6 "S1 detail"). Run through scripts/verify_design_tokens.sh.

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

private func encoded(_ doc: Document) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(doc)
}
private func roundTrip(_ doc: Document) throws -> Document {
    try JSONDecoder().decode(Document.self, from: try encoded(doc))
}
private func text(_ doc: Document) throws -> String {
    String(decoding: try encoded(doc), as: UTF8.self)
}

private func leaf(_ name: String, x: CGFloat = 0) -> Node {
    Node(name: name, frame: CGRect(x: x, y: 0, width: 40, height: 20),
         content: .rectangle(RectangleShape()))
}
/// A horizontal auto-layout row with padding, holding two rectangles.
private func row(_ name: String, id: UUID = UUID()) -> Node {
    Node(id: id, name: name, frame: CGRect(x: 0, y: 0, width: 200, height: 40),
         autoLayout: AutoLayout(), autoPadding: AutoPadding(),
         content: .group(children: [leaf("a"), leaf("b", x: 60)]))
}
private func node(_ id: UUID, in nodes: [Node]) -> Node? {
    for n in nodes {
        if n.id == id { return n }
        if case .group(let kids) = n.content, let hit = node(id, in: kids) { return hit }
    }
    return nil
}
private func mutate(_ id: UUID, in nodes: inout [Node], _ change: (inout Node) -> Void) {
    for i in nodes.indices {
        if nodes[i].id == id { change(&nodes[i]); return }
        if case .group(var kids) = nodes[i].content {
            mutate(id, in: &kids, change)
            nodes[i].content = .group(children: kids)
        }
    }
}

@main
private enum DesignTokensCheck {
    static func main() throws {
        print("Design Language tokens + bindings (FEAT-090a)")

        let gapRow = UUID(), padRow = UUID(), nestedRow = UUID(), sourceRow = UUID()
        let medium = DLToken.spacing("Space / Medium", 16)

        func fixture() -> Document {
            var outer = Node(name: "outer", frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                             content: .group(children: [row("nested", id: nestedRow)]))
            outer.isVisible = true
            var doc = Document(nodes: [row("gap row", id: gapRow), row("pad row", id: padRow), outer],
                               sources: [ComponentSource(name: "Chip", size: CGSize(width: 100, height: 40),
                                                         children: [row("source row", id: sourceRow)])])
            doc.designLanguage.addToken(medium)
            mutate(gapRow, in: &doc.pages[0].nodes) { $0.setTokenBinding(TokenBindingKey.gap, to: medium.id) }
            mutate(padRow, in: &doc.pages[0].nodes) { $0.setTokenBinding(TokenBindingKey.paddingTop, to: medium.id) }
            mutate(nestedRow, in: &doc.pages[0].nodes) { $0.setTokenBinding(TokenBindingKey.marginLeft, to: medium.id) }
            mutate(sourceRow, in: &doc.sources[0].children) { $0.setTokenBinding(TokenBindingKey.gap, to: medium.id) }
            doc.applyTokenBindings()
            return doc
        }
        func gap(_ doc: Document) -> CGFloat? { node(gapRow, in: doc.pages[0].nodes)?.autoLayout?.gap }
        func padTop(_ doc: Document) -> CGFloat? { node(padRow, in: doc.pages[0].nodes)?.autoPadding?.paddingTop }
        func padRight(_ doc: Document) -> CGFloat? { node(padRow, in: doc.pages[0].nodes)?.autoPadding?.paddingRight }
        func nestedMargin(_ doc: Document) -> CGFloat? { node(nestedRow, in: doc.pages[0].nodes)?.autoPadding?.marginLeft }
        func sourceGap(_ doc: Document) -> CGFloat? { node(sourceRow, in: doc.sources[0].children)?.autoLayout?.gap }

        check("a document that uses no tokens writes no new keys") {
            let plain = Document(nodes: [row("plain")])
            let json = try text(plain)
            for key in ["tokenBindings", "\"tokens\"", "modeSets", "\"settings\""] {
                require(!json.contains(key), "unused document wrote \(key)")
            }
            let again = try roundTrip(plain)
            require(again.designLanguage.tokens.isEmpty && again.designLanguage.modeSets.isEmpty, "defaults")
            require(again.designLanguage.settings.remBase == 16, "rem base default")
            require(node(plain.pages[0].nodes[0].id, in: again.pages[0].nodes)?.tokenBindings == nil, "nil bindings")
        }

        check("a pre-v2.9 design language (four keys only) still decodes") {
            let old = #"{"categories":[],"assets":[],"typeStyles":[],"recents":[]}"#
            let dl = try JSONDecoder().decode(DesignLanguage.self, from: Data(old.utf8))
            require(dl.tokens.isEmpty && dl.modeSets.isEmpty && dl.isEmpty, "old design language")
        }

        check("linking resolves the token's number into every bound field") {
            let doc = fixture()
            require(gap(doc) == 16 && padTop(doc) == 16 && nestedMargin(doc) == 16 && sourceGap(doc) == 16,
                    "resolved \(String(describing: gap(doc))) \(String(describing: padTop(doc))) \(String(describing: nestedMargin(doc))) \(String(describing: sourceGap(doc)))")
            require(padRight(doc) == 12, "an unlinked side must keep its own value")
            require(doc.tokenUseCount(medium.id) == 4, "use count \(doc.tokenUseCount(medium.id))")
        }

        check("changing the token updates page, nested and component-source uses") {
            var doc = fixture()
            require(doc.setTokenValue(medium.id, to: .dimension(DLDimension(20))), "should report a change")
            require(gap(doc) == 20 && padTop(doc) == 20 && nestedMargin(doc) == 20 && sourceGap(doc) == 20, "20 everywhere")
        }

        check("applying twice changes nothing the second time") {
            var doc = fixture()
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(20)))
            let before = try encoded(doc)
            require(doc.applyTokenBindings() == false, "second pass reported a change")
            let after = try encoded(doc)
            require(after == before, "second pass altered the document")
        }

        check("the owner's example: 16 → 20, detach gap at 18, 24 moves padding only") {
            var doc = fixture()
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(20)))
            mutate(gapRow, in: &doc.pages[0].nodes) {
                $0.autoLayout?.gap = 18
                $0.setTokenBinding(TokenBindingKey.gap, to: nil)
            }
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(24)))
            require(gap(doc) == 18, "detached gap moved to \(String(describing: gap(doc)))")
            require(padTop(doc) == 24, "linked padding \(String(describing: padTop(doc)))")
            require(node(gapRow, in: doc.pages[0].nodes)?.tokenBindings == nil, "empty binding map should be nil")
        }

        check("clearing a link keeps the resolved number") {
            var doc = fixture()
            mutate(padRow, in: &doc.pages[0].nodes) { $0.setTokenBinding(TokenBindingKey.paddingTop, to: nil) }
            doc.applyTokenBindings()
            require(padTop(doc) == 16, "number after clearing the link")
        }

        check("renaming a token keeps every link") {
            var doc = fixture()
            doc.designLanguage.renameToken(medium.id, to: "Space / M")
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(22)))
            require(doc.designLanguage.token(medium.id)?.name == "Space / M" && gap(doc) == 22, "rename")
        }

        check("save and reopen keeps tokens, links and numbers") {
            var doc = try roundTrip(fixture())
            require(doc.designLanguage.token(medium.id) == medium, "token round trip")
            require(node(gapRow, in: doc.pages[0].nodes)?.boundTokenID(TokenBindingKey.gap) == medium.id, "page link")
            require(node(sourceRow, in: doc.sources[0].children)?.boundTokenID(TokenBindingKey.gap) == medium.id, "source link")
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(28)))
            require(gap(doc) == 28 && sourceGap(doc) == 28, "links still live after reopen")
        }

        check("deleting a token unlinks its uses and leaves the numbers alone") {
            var doc = fixture()
            require(doc.removeToken(medium.id) == 4, "removed link count")
            require(doc.designLanguage.token(medium.id) == nil && doc.tokenUseCount(medium.id) == 0, "token gone")
            require(gap(doc) == 16 && padTop(doc) == 16 && sourceGap(doc) == 16, "numbers kept")
            let json = try text(doc)
            require(!json.contains("tokenBindings"), "no empty binding maps left behind")
        }

        check("a link to a missing token leaves the value untouched") {
            var doc = fixture()
            doc.designLanguage.removeToken(medium.id)          // token gone, links left dangling
            require(doc.applyTokenBindings() == false && gap(doc) == 16, "dangling link changed a value")
            require(node(gapRow, in: doc.pages[0].nodes)?.boundTokenID(TokenBindingKey.gap) == medium.id,
                    "the dangling link must survive so it can be shown and relinked")
        }

        check("aliases resolve through a chain; a cycle resolves to nothing") {
            var dl = DesignLanguage()
            let base = DLToken.spacing("base", 8)
            let mid = DLToken(name: "mid", role: .spacing, value: .alias(base.id))
            let top = DLToken(name: "top", role: .spacing, value: .alias(mid.id))
            dl.addToken(base); dl.addToken(mid); dl.addToken(top)
            require(dl.resolvedNumber(top.id) == 8, "alias chain")
            dl.setTokenValue(base.id, to: .alias(top.id))
            require(dl.resolvedNumber(top.id) == nil && dl.resolvedTokenValue(mid.id) == nil, "cycle")
            require(dl.resolvedNumber(UUID()) == nil, "unknown id")
        }

        check("units: px and unitless resolve, rem uses the rem base, others refuse") {
            var dl = DesignLanguage()
            let rem = DLToken(name: "rem", role: .spacing, value: .dimension(DLDimension(1.5, unit: "rem")))
            let num = DLToken(name: "num", type: .number, role: .spacing, value: .number(4))
            let pct = DLToken(name: "pct", role: .spacing, value: .dimension(DLDimension(50, unit: "%")))
            let expr = DLToken(name: "expr", role: .spacing, value: .raw("clamp(1rem, 2vw, 2rem)"))
            for t in [rem, num, pct, expr] { dl.addToken(t) }
            require(dl.resolvedNumber(rem.id) == 24 && dl.resolvedNumber(num.id) == 4, "rem/number")
            dl.settings.remBase = 10
            require(dl.resolvedNumber(rem.id) == 15, "rem base")
            require(dl.resolvedNumber(pct.id) == nil && dl.resolvedNumber(expr.id) == nil,
                    "% and vw need a reference the plain context doesn't have")
        }

        check("flexible CSS lengths: em, calc, min, max, clamp, viewport units") {
            let board = DLResolveContext(viewport: CGSize(width: 1000, height: 800))
            func pts(_ css: String, _ ctx: DLResolveContext = DLResolveContext(), rem: Double = 16) -> CGFloat? {
                DLLength.points(css, context: ctx, remBase: rem)
            }
            require(pts("16px") == 16 && pts("1.5rem") == 24 && pts("2em") == 32 && pts("12") == 12, "fixed + font-relative")
            require(pts("2em", DLResolveContext(emBase: 10)) == 20, "em base")
            require(pts("calc(1rem + 2px)") == 18 && pts("calc((1rem + 4px) * 2)") == 40, "calc")
            require(pts("calc(1rem / 2)") == 8 && pts("calc(2 * 1rem - 4px)") == 28, "calc precedence")
            require(pts("min(1rem, 20px)") == 16 && pts("max(1rem, 20px, 4px)") == 20, "min/max")
            require(pts("clamp(1rem, 2vw, 2rem)", board) == 20, "clamp preferred value at 1000 wide")
            require(pts("clamp(1rem, 2vw, 2rem)", DLResolveContext(viewport: CGSize(width: 400, height: 800))) == 16, "clamp floor")
            require(pts("clamp(1rem, 2vw, 2rem)", DLResolveContext(viewport: CGSize(width: 3000, height: 800))) == 32, "clamp ceiling")
            require(pts("clamp(1rem, 0.5rem + 2vw, 3rem)", board) == 28, "fluid clamp")
            require(pts("5vh", board) == 40 && pts("1vmin", board) == 8 && pts("1vmax", board) == 10, "viewport units")
            require(pts("50%", DLResolveContext(percentBase: 200)) == 100, "percent with a base")
            for bad in ["2vw", "50%", "minmax(0, 1fr)", "1fr", "var(--space)", "auto", "calc(1rem + 2)",
                        "calc(1rem * 2px)", "calc(1rem / 0)", "clamp(1rem, 2rem)", "1rem 2rem", "", "calc(1rem"] {
                require(pts(bad) == nil, "should refuse \(bad)")
            }
        }

        check("each artboard resolves in its own size and mode") {
            let narrow = Artboard(name: "Phone", frame: CGRect(x: 0, y: 0, width: 400, height: 800))
            var wide = Artboard(name: "Desktop", frame: CGRect(x: 500, y: 0, width: 1500, height: 900))
            let a = UUID(), b = UUID(), wall = UUID()
            var onNarrow = row("a", id: a); onNarrow.artboardID = narrow.id
            var onWide = row("b", id: b); onWide.artboardID = wide.id
            let fluid = DLToken(name: "fluid", role: .spacing, value: .raw("clamp(1rem, 2vw, 2rem)"))
            let compact = DLMode(name: "Compact")
            let density = DLModeSet(name: "Density", modes: [DLMode(name: "Comfortable"), compact])
            wide.modeOverrides = [density.id.uuidString: compact.id]
            var doc = Document(artboards: [narrow, wide], nodes: [onNarrow, onWide, row("wall", id: wall)])
            doc.designLanguage.addToken(fluid)
            doc.designLanguage.addToken(medium)
            doc.designLanguage.modeSets = [density]
            doc.designLanguage.setTokenValue(medium.id, to: .dimension(DLDimension(10)), modeID: compact.id)
            for id in [a, b, wall] {
                mutate(id, in: &doc.pages[0].nodes) {
                    $0.setTokenBinding(TokenBindingKey.gap, to: fluid.id)
                    $0.setTokenBinding(TokenBindingKey.paddingTop, to: medium.id)
                }
            }
            doc.applyTokenBindings()
            func g(_ id: UUID) -> CGFloat? { node(id, in: doc.pages[0].nodes)?.autoLayout?.gap }
            func p(_ id: UUID) -> CGFloat? { node(id, in: doc.pages[0].nodes)?.autoPadding?.paddingTop }
            require(g(a) == 16 && g(b) == 30, "fluid gap per board: \(String(describing: g(a))) \(String(describing: g(b)))")
            require(g(wall) == 8, "no artboard, no viewport: the wall layer keeps its value")
            require(p(a) == 16 && p(wall) == 16 && p(b) == 10, "board mode override: \(String(describing: p(b)))")
            doc.pages[0].artboards[0].frame.size.width = 1200
            doc.applyTokenBindings()
            require(g(a) == 24, "resizing the board re-resolves on the next pass")
            let reopened = try roundTrip(doc)
            require(reopened.pages[0].artboards[1].modeOverrides == wide.modeOverrides, "board mode round trip")
            let json = try text(Document(artboards: [narrow]))
            require(!json.contains("modeOverrides"), "boards without a mode choice write no key")
        }

        check("an unresolvable or negative token never corrupts a field") {
            var doc = fixture()
            doc.setTokenValue(medium.id, to: .raw("minmax(0, 1fr)"))
            require(gap(doc) == 16, "an unmeasurable expression must leave the last number")
            doc.setTokenValue(medium.id, to: .raw("calc(1rem + 2px)"))
            require(gap(doc) == 18, "calc should resolve: \(String(describing: gap(doc)))")
            doc.setTokenValue(medium.id, to: .dimension(DLDimension(-4)))
            require(gap(doc) == 0, "negative spacing clamps to 0 like the Inspector")
        }

        check("per-mode values override the base; other modes fall back") {
            var doc = fixture()
            let compact = DLMode(name: "Compact")
            doc.designLanguage.modeSets = [DLModeSet(name: "Density", modes: [DLMode(name: "Comfortable"), compact])]
            doc.designLanguage.setTokenValue(medium.id, to: .dimension(DLDimension(12)), modeID: compact.id)
            require(doc.designLanguage.resolvedNumber(medium.id) == 16, "base")
            require(doc.designLanguage.resolvedNumber(medium.id, modeID: compact.id) == 12, "mode override")
            require(doc.designLanguage.resolvedNumber(medium.id, modeID: UUID()) == 16, "unknown mode falls back")
            doc.designLanguage.modeSets[0].activeModeID = compact.id
            doc.applyTokenBindings()
            require(gap(doc) == 12, "document mode applied")
            doc.designLanguage.modeSets[0].activeModeID = UUID()      // a mode that was deleted
            doc.applyTokenBindings()
            require(gap(doc) == 16, "a missing active mode falls back to the default")
            let reopened = try roundTrip(doc)
            require(reopened.designLanguage.modeSets == doc.designLanguage.modeSets, "mode sets round trip")
            require(reopened.designLanguage.resolvedNumber(medium.id, modeID: compact.id) == 12, "mode value round trip")
        }

        check("values and types from a newer build survive a save") {
            let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"future","type":"lineGap","role":"rhythm","value":{"steps":[1,2,{"x":true}],"note":null}}"#
            let token = try JSONDecoder().decode(DLToken.self, from: Data(json.utf8))
            require(token.type.rawValue == "lineGap" && token.role.rawValue == "rhythm", "unknown type/role kept")
            guard case .preserved = token.value else { fail("unknown value shape should be preserved") }
            let again = try JSONDecoder().decode(DLToken.self, from: try JSONEncoder().encode(token))
            require(again == token, "preserved value changed on re-save")
            var dl = DesignLanguage(); dl.addToken(token)
            require(dl.resolvedNumber(token.id) == nil, "preserved value must not resolve")
        }

        check("a damaged binding map does not stop a node opening") {
            var doc = Document(nodes: [row("r")])
            let data = try JSONSerialization.jsonObject(with: try encoded(doc)) as! [String: Any]
            var pages = data["pages"] as! [[String: Any]]
            var nodes = pages[0]["nodes"] as! [[String: Any]]
            nodes[0]["tokenBindings"] = ["autoLayout.gap": "not-a-uuid", "future.key": 7]
            pages[0]["nodes"] = nodes
            var patched = data; patched["pages"] = pages
            doc = try JSONDecoder().decode(Document.self, from: try JSONSerialization.data(withJSONObject: patched))
            require(doc.pages[0].nodes.count == 1 && doc.pages[0].nodes[0].tokenBindings == nil, "damaged map")
        }

        check("a binding key from a newer build is kept and ignored") {
            var doc = fixture()
            let future = UUID()
            mutate(gapRow, in: &doc.pages[0].nodes) { $0.setTokenBinding("cornerRadius.future", to: future) }
            doc.applyTokenBindings()
            let reopened = try roundTrip(doc)
            require(node(gapRow, in: reopened.pages[0].nodes)?.boundTokenID("cornerRadius.future") == future, "unknown key")
        }

        check("commit-time reconcile: context changes update, edited numbers detach") {
            let board = Artboard(name: "Board", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
            let a = UUID(), b = UUID()
            var first = row("a", id: a); first.artboardID = board.id
            var second = row("b", id: b); second.artboardID = board.id
            let fluid = DLToken(name: "fluid", role: .spacing, value: .raw("clamp(1rem, 2vw, 2rem)"))
            var doc = Document(artboards: [board], nodes: [first, second])
            doc.designLanguage.addToken(fluid)
            for id in [a, b] {
                mutate(id, in: &doc.pages[0].nodes) { $0.setTokenBinding(TokenBindingKey.gap, to: fluid.id) }
            }
            doc.applyTokenBindings()
            func g(_ d: Document, _ id: UUID) -> CGFloat? { node(id, in: d.pages[0].nodes)?.autoLayout?.gap }
            require(g(doc, a) == 20 && g(doc, b) == 20, "start at 20")

            var unchanged = doc
            require(unchanged.reconcileTokenBindings(after: doc) == false, "nothing changed, nothing to do")

            var resized = doc
            resized.pages[0].artboards[0].frame.size.width = 1400
            require(resized.reconcileTokenBindings(after: doc), "resize should re-resolve")
            require(g(resized, a) == 28 && g(resized, b) == 28, "resized board: \(String(describing: g(resized, a)))")
            require(node(a, in: resized.pages[0].nodes)?.boundTokenID(TokenBindingKey.gap) == fluid.id, "still linked")

            var edited = doc                      // some other code path sets one number directly
            mutate(a, in: &edited.pages[0].nodes) { $0.autoLayout?.gap = 33 }
            edited.reconcileTokenBindings(after: doc)
            require(g(edited, a) == 33, "an edited number must be kept, got \(String(describing: g(edited, a)))")
            require(node(a, in: edited.pages[0].nodes)?.boundTokenID(TokenBindingKey.gap) == nil, "edited field detaches")
            require(g(edited, b) == 20 && node(b, in: edited.pages[0].nodes)?.boundTokenID(TokenBindingKey.gap) == fluid.id,
                    "the other field stays linked")

            var plain = Document(nodes: [row("plain")])
            require(plain.reconcileTokenBindings(after: plain) == false, "no tokens: free and inert")
        }

        check("document and artboard modes reflow linked spacing without touching unlinked paint") {
            let board = Artboard(name: "Preview", frame: CGRect(x: 0, y: 0, width: 400, height: 400))
            let untouched = leaf("Unlinked")
            var linked = row("Linked")
            linked.artboardID = board.id
            linked.setTokenBinding(TokenBindingKey.gap, to: medium.id)
            var document = Document(artboards: [board], nodes: [linked, untouched])
            require(document.designLanguage.enableColorModes(), "enable explicitly")
            require(!document.designLanguage.enableColorModes(), "do not seed twice")
            let set = document.designLanguage.colorModeSet!
            let light = set.modes[0].id, dark = set.modes[1].id
            document.designLanguage.addToken(medium)
            document.designLanguage.setTokenValue(medium.id, to: .dimension(DLDimension(24)), modeID: dark)
            document.applyTokenBindings()
            let baseline = document
            require(document.designLanguage.selectDocumentColorMode(dark), "switch document")
            require(document.reconcileTokenBindings(after: baseline), "inherited mode reflows")
            require(document.pages[0].nodes[0].autoLayout?.gap == 24, "dark gap")
            let inherited = document
            require(document.selectArtboardColorMode(light, for: [board.id], on: document.pages[0].id), "set board override")
            require(document.reconcileTokenBindings(after: inherited), "overridden mode reflows")
            require(document.pages[0].nodes[0].autoLayout?.gap == 16, "light gap")
            require(document.designLanguage.colorMode()?.id == dark, "board does not change document mode")
            require(document.pages[0].nodes[1].layerPaintStyle?.fill == untouched.layerPaintStyle?.fill, "unlinked paint unaffected")
            let overridden = document
            require(document.selectArtboardColorMode(nil, for: [board.id], on: document.pages[0].id), "return to inheritance")
            require(document.reconcileTokenBindings(after: overridden), "clearing override reflows")
            require(document.pages[0].nodes[0].autoLayout?.gap == 24 && document.pages[0].artboards[0].modeOverrides == nil,
                    "inherits Dark and omits empty metadata")
        }

        check("saved color modes survive reopen and palette export uses the document mode") {
            var document = Document()
            document.designLanguage.enableColorModes()
            let dark = document.designLanguage.colorModeSet!.modes[1].id
            document.designLanguage.selectDocumentColorMode(dark)
            require(document.designLanguage.nameColorMode("Night", id: dark), "rename the active mode")
            require(document.designLanguage.nameColorMode("High Contrast"), "add a mode")
            require(!document.designLanguage.nameColorMode(" night "), "duplicate names rejected")
            var accent = DesignAsset(name: "Accent", value: .solid(.black))
            accent.modeValues[dark.uuidString] = .color(.white)
            var alias = DesignAsset(name: "Link", value: .solid(.black))
            alias.modeValues[dark.uuidString] = .alias(accent.id)
            document.designLanguage.add(accent)
            document.designLanguage.add(alias)
            let reopened = try roundTrip(document).designLanguage
            require(reopened.colorMode()?.id == dark && reopened.colorMode()?.name == "Night", "mode name and ID persist")
            require(reopened.paint(for: reopened.asset(alias.id)!, in: dark) == .solid(.white), "alias resolves through saved mode")
            require(reopened.paint(for: accent, in: reopened.colorModeSet?.modes.last?.id) == .solid(.black), "sparse mode uses base")
            let exported = try DesignLanguageIO.exportJSON(reopened)
            let entries = try JSONDecoder().decode(EXPDesignLanguageFile.self, from: exported).assets
            require(entries.count == 2 && entries.allSatisfy { $0.value == .solid(.white) && $0.modeValues.isEmpty },
                    "palette JSON materializes the chosen mode and contains no orphan mode IDs")
            let css = try DLExportFormat.cssVars.data(for: reopened)
            require(String(decoding: css, as: UTF8.self).contains("--accent: #FFFFFF;"), "CSS palette uses selected mode")
            var cyclic = reopened
            accent.modeValues[dark.uuidString] = .alias(alias.id)
            cyclic.assets[0] = accent
            require(cyclic.paint(for: alias, in: dark) == .solid(.black), "cycle falls back to base")
        }

        check("the saved palette supplies exact Base and mode colors to draft editors") {
            var language = DesignLanguage()
            language.enableColorModes()
            let dark = language.colorModeSet!.modes[1].id
            let destination = DesignAsset(name: "Destination", value: .solid(.black))
            var source = DesignAsset(name: "Source", value: .solid(.black))
            source.modeValues[dark.uuidString] = .color(.white)
            var alias = DesignAsset(name: "Alias", value: .solid(.black))
            alias.modeValues[dark.uuidString] = .alias(source.id)
            let gradient = DesignAsset(name: "Gradient", value: .gradient(GradientFill()))
            language.assets = [destination, source, alias, gradient]
            let base = language.savedColorChoices(in: nil, excluding: destination.id)
            let darkChoices = language.savedColorChoices(in: dark, excluding: destination.id)
            require(base.map { $0.asset.id } == [source.id, alias.id], "only eligible saved solids")
            require(base.map { $0.color } == [.black, .black], "Base choices keep their exact base values")
            require(darkChoices.map { $0.color } == [.white, .white], "mode choices resolve overrides and aliases")
            require(language.savedColorChoices(in: dark).count == 3, "mode-default editor can use the entire solid palette")
        }

        check("mode defaults follow document and artboard choices without overwriting custom paint") {
            let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
            let automatic = Artboard(name: "Automatic", frame: frame)
            let custom = Artboard(name: "Custom white", frame: frame.offsetBy(dx: 600, dy: 0), background: .white)
            let customColor = RGBAColor(r: 0.8, g: 0.2, b: 0.1)
            var mixedText = TextContent(runs: [
                TextRun(string: "Default", usesModeForeground: true),
                TextRun(string: "Custom", color: customColor)
            ])
            let text = Node(name: "Mixed", frame: frame, content: .text(mixedText))
            var wrapper = Node(name: "Nested", frame: frame, content: .group(children: [text]))
            wrapper.artboardID = automatic.id
            var doc = Document(artboards: [automatic, custom], nodes: [wrapper])
            doc.designLanguage.enableColorModes()
            let light = doc.designLanguage.colorModeSet!.modes[0].id
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            let darkBackground = RGBAColor(r: 0.08, g: 0.12, b: 0.16)
            let darkForeground = RGBAColor(r: 0.9, g: 0.85, b: 0.7)
            require(doc.designLanguage.setModeColor(darkBackground, for: .background, modeID: dark), "set Dark background")
            require(doc.designLanguage.setModeColor(darkForeground, for: .foreground, modeID: dark), "set Dark text")
            require(doc.designLanguage.selectDocumentColorMode(dark), "document Dark")
            require(doc.applyColorModeDefaults(), "update inherited paints")
            require(!doc.applyColorModeDefaults(), "second sync is idle")
            require(doc.pages[0].artboards[0].background == .solid(darkBackground), "uses Dark background")
            require(doc.pages[0].artboards[1].background == .white, "explicit white is preserved")
            guard case .text(let after)? = node(text.id, in: doc.pages[0].nodes)?.content else { fail("missing text") }
            require(after.runs.map(\.color) == [darkForeground, customColor], "only inherited runs update")

            require(doc.selectArtboardColorMode(light, for: [automatic.id], on: doc.pages[0].id), "board Light")
            require(doc.applyColorModeDefaults(), "board override updates paints")
            guard case .text(let afterLight)? = node(text.id, in: doc.pages[0].nodes)?.content else { fail("missing text") }
            require(doc.pages[0].artboards[0].background == .white
                    && afterLight.runs.map(\.color) == [.black, customColor], "Light becomes effective on the board")
            doc.pages[0].artboards[0].background = .white  // deliberately choose the current color
            mixedText = afterLight
            mixedText.runs[0].color = .black
            mutate(text.id, in: &doc.pages[0].nodes) { $0.content = .text(mixedText) }
            let reopened = try roundTrip(doc)
            require(reopened.pages[0].artboards[0].usesModeBackground == false, "manual white stays custom on open")
            var restored = reopened
            require(restored.selectArtboardColorMode(nil, for: [automatic.id], on: restored.pages[0].id), "return to Dark")
            require(!restored.applyColorModeDefaults(), "manual same-color edits detach")
            require(restored.useModeBackground(for: [automatic.id], on: restored.pages[0].id), "reattach board")
            require(restored.applyColorModeDefaults()
                    && restored.pages[0].artboards[0].background == .solid(darkBackground), "inherit once again")
        }

        check("pre-default artboards preserve custom backgrounds and inherit ordinary white") {
            let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
            var white = Artboard(name: "Old white", frame: frame)
            white.usesModeBackground = nil
            let custom = Artboard(name: "Old colored board", frame: frame, background: .solid(.black))
            var doc = try roundTrip(Document(artboards: [white, custom]))
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1]
            doc.designLanguage.selectDocumentColorMode(dark.id)
            require(doc.applyColorModeDefaults(), "legacy white board opts into defaults")
            require(doc.pages[0].artboards[0].background == .solid(dark.resolvedBackground)
                    && doc.pages[0].artboards[1].background == .solid(.black), "legacy custom fill is untouched")
        }

        check("inline editor attributes keep mode text independent from custom runs") {
            let original = TextContent(runs: [
                TextRun(string: "Default", color: .white, usesModeForeground: true),
                TextRun(string: "Custom", color: .white)
            ])
            let buffer = original.attributedString(applyCase: false, includeModeForeground: true)
            let saved = TextContent(attributed: buffer, align: .left, lineHeight: 1.3, lineHeightUnit: .auto,
                                    tracking: 0, box: .auto)
            require(saved.runs.count == 2 && saved.runs[0].usesModeForeground == true
                    && saved.runs[1].usesModeForeground != true, "color equality must not collapse the two sources")
        }

        check("typed values parse to what was typed, and read back the same") {
            func parsed(_ s: String) -> DLTokenValue? { DLTokenValue.parsingLength(s) }
            require(parsed("16") == .dimension(DLDimension(16, unit: "px")), "bare number is px")
            require(parsed(" 1.5REM ") == .dimension(DLDimension(1.5, unit: "rem")), "unit kept, lowercased")
            require(parsed("2em")?.authoredText == "2em" && parsed("16")?.authoredText == "16px", "authored text")
            require(parsed("clamp(1rem, 2vw, 2rem)") == .raw("clamp(1rem, 2vw, 2rem)"), "expression kept verbatim")
            require(parsed("") == nil && parsed("   ") == nil, "empty input")
            require(parsed("1.5.2rem") == .raw("1.5.2rem"), "nonsense is preserved, not guessed")
        }

        check("use counts for every token come from one walk") {
            let doc = fixture()
            require(doc.tokenUseCounts() == [medium.id: 4], "counts \(doc.tokenUseCounts())")
        }

        check("live appearance links follow modes, stay separate, and survive a round trip") {
            let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
            let first = Artboard(name: "Document mode", frame: frame)
            let lockedMode = Artboard(name: "Fixed Dark", frame: frame.offsetBy(dx: 600, dy: 0))
            var doc = Document(artboards: [first, lockedMode])
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            let base = RGBAColor(r: 0.2, g: 0.4, b: 0.6)
            let night = RGBAColor(r: 0.8, g: 0.7, b: 0.2)
            let target = doc.designLanguage.save(.solid(night), name: "night")
            var asset = DesignAsset(name: "Brand", value: .solid(base))
            asset.modeValues[dark.uuidString] = .alias(target)
            doc.designLanguage.add(asset)
            let style = TypeStyle(name: "Heading", fontSize: 32)
            doc.designLanguage.saveTypeStyle(style)
            var lightNode = leaf("Light")
            lightNode.artboardID = first.id
            var darkNode = leaf("Dark")
            darkNode.artboardID = lockedMode.id
            var title = Node(name: "Title", frame: frame,
                content: .text(TextContent(runs: [TextRun(string: "Hello", usesModeForeground: true)])))
            title.artboardID = lockedMode.id
            let unlinked = leaf("Literal")
            doc.pages[0].nodes = [lightNode, darkNode, title, unlinked]
            doc.selectArtboardColorMode(dark, for: [lockedMode.id], on: doc.pages[0].id)
            let language = doc.designLanguage
            require(Node.linkAppearance(in: &doc.pages[0].nodes,
                                        selection: [lightNode.id, darkNode.id, title.id],
                                        key: TokenBindingKey.fill, to: asset.id, language: language), "link fill")
            require(Node.linkAppearance(in: &doc.pages[0].nodes, selection: [title.id],
                                        key: TokenBindingKey.textStyle, to: style.id, language: language), "link type")
            require(doc.applyTokenBindings(), "materialize links")
            require(!doc.applyTokenBindings(), "idempotent")
            require(doc.pages[0].nodes[0].layerPaintStyle?.fill == .solid(base), "default mode's paint")
            require(doc.pages[0].nodes[1].layerPaintStyle?.fill == .solid(night), "Dark board's alias")
            guard case .text(let styled) = doc.pages[0].nodes[2].content else { fail("missing title") }
            require(styled.firstRun.color == night && styled.firstRun.usesModeForeground == nil && styled.firstRun.fontSize == 32,
                    "separate links for color and type replace default color and keep text")
            require(doc.pages[0].nodes[3].layerPaintStyle?.fill == unlinked.layerPaintStyle?.fill, "no automatic link")
            let saved = try roundTrip(doc)
            require(saved.tokenUseCount(asset.id) == 3 && saved.tokenUseCount(style.id) == 1, "saved use counts")
            require(saved.pages[0].nodes[2].frame.size == doc.pages[0].nodes[2].frame.size, "saved frame")
            var changed = saved
            changed.designLanguage.rename(asset.id, to: "Brand renamed")
            changed.designLanguage.selectDocumentColorMode(dark)
            changed.designLanguage.setTypeStyleValues(style.id, from: TypeStyle(fontSize: 46))
            require(changed.reconcileTokenBindings(after: saved), "refresh")
            require(changed.pages[0].nodes[0].layerPaintStyle?.fill == .solid(night), "document mode switches linked fill")
            guard case .text(var manualText) = changed.pages[0].nodes[2].content else { fail("missing text") }
            require(manualText.firstRun.fontSize == 46 && manualText.plainString == "Hello", "linked style remeasures without replacing content")
            let beforeManual = changed
            manualText.applyToAllRuns { $0.color = .black }
            changed.pages[0].nodes[2].content = .text(manualText)
            require(changed.reconcileTokenBindings(after: beforeManual), "manual color detaches")
            require(changed.pages[0].nodes[2].boundTokenID(TokenBindingKey.textColor) == nil &&
                    changed.pages[0].nodes[2].boundTokenID(TokenBindingKey.textStyle) == style.id, "only edited property detaches")
            changed.removeAppearanceAsset(asset.id, typeStyle: false)
            require(changed.tokenUseCount(asset.id) == 0 &&
                    changed.pages[0].nodes[1].layerPaintStyle?.fill == .solid(night), "deletion keeps paint")
        }

        check("matching styles skips hidden branches and ambiguous paint and keeps an exact gradient") {
            var gradient = GradientFill()
            gradient.start = CGPoint(x: 0.2, y: 0.4)
            gradient.end = CGPoint(x: 0.8, y: 0.4)
            var authored = gradient
            for i in authored.stops.indices { authored.stops[i].id = UUID() }
            let gradientNode = Node(name: "Gradient", frame: CGRect(x: 0, y: 0, width: 50, height: 50),
                content: .rectangle(RectangleShape(fill: .gradient(authored))))
            let solidNode = Node(name: "Ambiguous", frame: gradientNode.frame,
                content: .rectangle(RectangleShape(fill: .black)))
            var hidden = Node(name: "Hidden", frame: gradientNode.frame, content: .group(children: [gradientNode]))
            hidden.isVisible = false
            var doc = Document(nodes: [gradientNode, solidNode, hidden])
            let id = doc.designLanguage.save(.gradient(gradient), name: "Ribbon")
            doc.designLanguage.add(DesignAsset(name: "Black One", value: .black))
            doc.designLanguage.add(DesignAsset(name: "Black Two", value: .black))
            let preview = doc.matchingAppearanceBindings()
            require(preview.matches.count == 1 && preview.matches[0].tokenID == id, "exact geometry and stops")
            require(preview.ambiguousCount == 1, "duplicate paints and hidden layers should be skipped")
            require(doc.linkMatchingAppearance(preview), "explicit confirmation links matched fields")
            require(doc.pages[0].nodes[0].boundTokenID(TokenBindingKey.fill) == id, "link stored")
        }

        check("component artwork follows the placement mode and honors local overrides") {
            var doc = Document()
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            var asset = DesignAsset(name: "Surface", value: .white)
            asset.modeValues[dark.uuidString] = .color(.black)
            doc.designLanguage.add(asset)
            var child = leaf("Surface")
            child.setTokenBinding(TokenBindingKey.fill, to: asset.id)
            let source = ComponentSource(name: "Card", size: CGSize(width: 40, height: 20), children: [child])
            doc.sources = [source]
            doc.applyTokenBindings()
            let instance = ComponentInstance(sourceID: source.id)
            require(doc.resolvedChildren(of: instance).first?.layerPaintStyle?.fill == .white, "source follows document mode")
            require(doc.resolvedChildren(of: instance, appearanceModeID: dark).first?.layerPaintStyle?.fill == .black, "Dark placement resolves locally")
            var custom = instance
            custom.overrides = [InstanceOverride(targetNodeID: child.id, value: .fill(.white))]
            let resolved = doc.resolvedChildren(of: custom, appearanceModeID: dark).first
            require(resolved?.layerPaintStyle?.fill == .white && resolved?.boundTokenID(TokenBindingKey.fill) == nil,
                    "explicit override takes precedence and stays literal if detached")
        }

        check("canvas mode labels contrast with the wall and light artboards stay distinct") {
            let light = DLMode(name: "Light", libraryKey: "light")
            let dark = DLMode(name: "Dark", libraryKey: "dark")
            require(ColorMath.string(light.canvasWallBackground, .hex).uppercased() == "#F2F2F2",
                    "apply a slight gray tint to the white wall")
            require(light.resolvedBackground == .white, "leave the artboard background white")
            require(dark.canvasWallBackground == dark.resolvedBackground, "keep the dark wall color")
            for mode in [light, dark] {
                require(ContrastMath.report(foreground: mode.canvasWallLabelColor,
                                            background: mode.canvasWallBackground).passes(.normalText),
                        "canvas label remains readable in \(mode.name)")
            }
        }

        check("saved swatch links and spacing follow page and artboard ancestry") {
            let board = Artboard(name: "Follows Page", frame: CGRect(x: 100, y: 0, width: 300, height: 200))
            let pinned = Artboard(name: "Pinned Light", frame: CGRect(x: 500, y: 0, width: 300, height: 200))
            var shape = leaf("Linked shape")
            let text = Node(name: "Default text", frame: shape.frame,
                content: .text(TextContent(runs: [TextRun(string: "Wall", usesModeForeground: true)])))
            var layout = row("Linked spacing")
            let first = CanvasPage(name: "Theme", artboards: [board, pinned], nodes: [shape, text])
            let second = CanvasPage(name: "Document mode", nodes: [leaf("Unlinked")])
            var doc = Document()
            doc.pages = [first, second]
            require(doc.designLanguage.enableColorModes(), "enable modes")
            let light = doc.designLanguage.colorModeSet!.modes[0]
            let dark = doc.designLanguage.colorModeSet!.modes[1]
            require(light.resolvedIconSymbol == "sun.max" && dark.resolvedIconSymbol == "moon", "default symbols")
            var accent = DesignAsset(name: "Accent", value: .white)
            accent.modeValues[dark.id.uuidString] = .color(.black)
            doc.designLanguage.add(accent)
            var space = DLToken.spacing("Gap", 12)
            space.modeValues[dark.id.uuidString] = .dimension(DLDimension(24))
            doc.designLanguage.addToken(space)
            layout.setTokenBinding(TokenBindingKey.gap, to: space.id)
            doc.pages[0].nodes.append(layout)
            let language = doc.designLanguage
            require(Node.linkAppearance(in: &doc.pages[0].nodes, selection: [shape.id],
                                        key: TokenBindingKey.fill, to: accent.id, language: language),
                    "applying the saved swatch stores the token link")
            doc.applyTokenBindings()
            require(doc.pages[0].nodes[0].layerPaintStyle?.fill == .white, "wall follows document initially")

            let beforePageMode = doc
            require(doc.selectPageColorMode(dark.id, on: first.id), "pin page Dark")
            require(doc.selectArtboardColorMode(light.id, for: [pinned.id], on: first.id), "pin board Light")
            require(doc.reconcileTokenBindings(after: beforePageMode), "refresh linked values")
            require(doc.applyColorModeDefaults(), "refresh default paint and text")
            require(doc.pages[0].nodes[0].layerPaintStyle?.fill == .black, "wall follows page")
            require(doc.pages[0].nodes[2].autoLayout?.gap == 24, "wall spacing follows page")
            guard case .text(let wallText) = doc.pages[0].nodes[1].content else { fail("missing text") }
            require(wallText.firstRun.color == dark.resolvedForeground, "wall text uses page foreground")
            require(doc.pages[0].artboards[0].background == .solid(dark.resolvedBackground), "artboard inherits page")
            require(doc.pages[0].artboards[1].background == .solid(light.resolvedBackground), "explicit artboard override wins")
            require(doc.designLanguage.colorMode(on: doc.pages[1])?.id == light.id, "other page follows document")
            require(doc.colorMode(for: board)?.id == dark.id, "export resolves the owning page's mode")

            let beforeMove = doc
            shape = doc.pages[0].nodes[0]
            shape.frame.origin.x = pinned.frame.minX + 15
            doc.pages[0].nodes[0] = shape
            doc.reconcileArtboardOwnership(on: first.id)
            require(doc.pages[0].nodes[0].artboardID == pinned.id, "drag onto pinned artboard")
            require(doc.reconcileTokenBindings(after: beforeMove), "refresh after dragging onto artboard")
            require(doc.pages[0].nodes[0].layerPaintStyle?.fill == .white, "linked swatch follows artboard")
            let beforeExit = doc
            doc.pages[0].nodes[0].frame.origin.x = -100
            doc.reconcileArtboardOwnership(on: first.id)
            require(doc.pages[0].nodes[0].artboardID == nil, "drag back to wall")
            require(doc.reconcileTokenBindings(after: beforeExit), "refresh after dragging to wall")
            require(doc.pages[0].nodes[0].layerPaintStyle?.fill == .black &&
                    doc.pages[0].nodes[0].boundTokenID(TokenBindingKey.fill) == accent.id, "restored page mode, link kept")

            require(doc.designLanguage.setModeIcon("star", modeID: dark.id), "custom icon")
            require(doc.designLanguage.nameColorMode("Night", id: dark.id), "rename preserves identity")
            var reopened = try roundTrip(doc)
            require(reopened.designLanguage.colorMode(on: reopened.pages[0])?.resolvedIconSymbol == "star", "page and icon survive save")
            let copy = Document.duplicatingPage(reopened.pages[0], named: "Copy")
            require(reopened.designLanguage.colorMode(on: copy)?.id == dark.id, "duplicate carries the page's mode")
            require(reopened.selectPageColorMode(nil, on: first.id), "reset to document")
            require(reopened.pages[0].modeOverrides == nil &&
                    reopened.designLanguage.colorMode(on: reopened.pages[0])?.id == light.id, "page inherits again")
            require(reopened.designLanguage.setModeIcon(nil, modeID: dark.id) &&
                    reopened.designLanguage.colorModeSet?.modes[1].resolvedIconSymbol == "moon", "renamed mode can reset to its default icon")
        }

        check("semantic handoff keeps the exact named token and the artboard mode") {
            let board = Artboard(name: "Dark", frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            var doc = Document(artboards: [board])
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            let accent = RGBAColor(r: 1, g: 0, b: 0)
            doc.designLanguage.add(DesignAsset(name: "Same Base", value: .white))
            var brand = DesignAsset(name: "Brand", value: .white)
            brand.modeValues[dark.uuidString] = .color(accent)
            doc.designLanguage.add(brand)
            doc.designLanguage.saveTypeStyle(TypeStyle(name: "First", fontSize: 24))
            let exact = TypeStyle(name: "Exact", fontSize: 24)
            doc.designLanguage.saveTypeStyle(exact)
            var rectangle = leaf("Rectangle")
            rectangle.artboardID = board.id
            rectangle.setTokenBinding(TokenBindingKey.fill, to: brand.id)
            var label = Node(name: "Title", frame: rectangle.frame, content: .text(TextContent(runs: [TextRun(string: "Hello")])))
            label.artboardID = board.id
            label.setTokenBinding(TokenBindingKey.textStyle, to: exact.id)
            doc.pages[0].nodes = [rectangle, label]
            doc.selectPageColorMode(dark, on: doc.pages[0].id)
            doc.applyTokenBindings()
            let bundle = SemanticHTMLExporter(document: doc).makeBundle()
            let css = String(decoding: bundle.artifacts[0].data, as: UTF8.self)
            let html = String(decoding: bundle.artifacts[1].data, as: UTF8.self)
            require(css.contains("--exp-linked-brand: rgb(255 0 0 / 1)") &&
                    css.contains("background: var(--exp-linked-brand, rgb(255 0 0 / 1))"), "board-scoped exact color identity")
            require(html.contains("exp-text type-exact") && !html.contains("exp-text type-first"),
                    "matching typography uses the exact named link")
        }

        check("code drafts rename and add by identity, preserve modes and update linked artwork") {
            var doc = Document()
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            let category = DLCategory(name: "Brand")
            doc.designLanguage.categories = [category]
            var swatch = DesignAsset(name: "Primary", categoryID: category.id, value: .white)
            swatch.modeValues[dark.uuidString] = .color(.black)
            doc.designLanguage.assets = [swatch]
            let spacing = DLToken.spacing("Inset", 12)
            let alias = DLToken(name: "Panel inset", role: .spacing, value: .alias(spacing.id))
            doc.designLanguage.tokens = [spacing, alias]
            var shape = leaf("Rectangle")
            shape.setTokenBinding(TokenBindingKey.fill, to: swatch.id)
            doc.pages[0].nodes = [shape]
            doc.applyTokenBindings()

            let start = DesignLanguageCode.Content(doc.designLanguage)
            let initialJSON = try DesignLanguageCode.encode(start)
            let unedited = try DesignLanguageCode.preview(initialJSON, from: start, in: doc)
            require(unedited.changes.isEmpty, "canonical JSON round-trips including mode aliases")

            var object = try JSONSerialization.jsonObject(with: Data(initialJSON.utf8)) as! [String: Any]
            var assets = object["assets"] as! [[String: Any]]
            assets[0]["name"] = "Accent"
            assets[0]["value"] = "#336699"
            assets.append(["name": "Added from JSON", "value": "#eeaa44"])
            object["assets"] = assets
            let input = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            let preview = try DesignLanguageCode.preview(input, from: start, in: doc)
            require(preview.changes.count == 2 &&
                    preview.changes.contains { $0.action == .update && $0.title == "Accent" }, "preview shows the rename and addition")
            require(doc.designLanguage.assets.count == 1, "preview does not mutate the document")
            doc.designLanguage.remember(.black)
            var updated = try preview.applying(to: doc)
            require(updated.designLanguage.recents == doc.designLanguage.recents, "live recent colors survive")
            require(updated.designLanguage.assets[0].id == swatch.id &&
                    updated.designLanguage.assets[0].modeValues == swatch.modeValues, "identity and overrides preserved")
            require(updated.designLanguage.assets[1].id != swatch.id && updated.designLanguage.tokens[1].value == .alias(spacing.id),
                    "new entry has its own identity and existing aliases stay aliases")
            require(updated.reconcileTokenBindings(after: doc), "normal commit re-resolves the linked fill")
            require(updated.pages[0].nodes[0].layerPaintStyle?.fill == .solid(ColorMath.parseHex("#336699")!),
                    "materialized paint updates with the code")
        }

        check("code review rejects malformed and ambiguous drafts and protects library swatches") {
            let swatch = DesignAsset(name: "Read-only", value: .white)
            var doc = Document()
            doc.designLanguage.assets = [swatch]
            doc.codeBridges = [CodeBridgeManifest(connector: LibraryTokenSnapshot.connector,
                source: CodeBridgeSource(displayName: "Test library"),
                bindings: [CodeBridgeBinding(externalID: "css:--color", externalKind: "color",
                    metadata: [LibraryTokenBindingKey.assetID: swatch.id.uuidString])])]
            let start = DesignLanguageCode.Content(doc.designLanguage)
            let json = try DesignLanguageCode.encode(start)
            func reject(_ text: String, contains expected: String) {
                do {
                    _ = try DesignLanguageCode.preview(text, from: start, in: doc)
                    fail("draft unexpectedly accepted")
                } catch {
                    require(error.localizedDescription.contains(expected), error.localizedDescription)
                }
            }
            reject("{\"assets\": [}", contains: "Invalid JSON")
            var original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            let entry = (original["assets"] as! [[String: Any]])[0]
            func replaceAssets(_ assets: [[String: Any]]) throws -> String {
                original["assets"] = assets
                return String(decoding: try JSONSerialization.data(withJSONObject: original), as: UTF8.self)
            }
            var broken = entry
            broken["value"] = ["kind": "gradent"]
            reject(try replaceAssets([broken]), contains: "assets[0].value.kind")
            reject(try replaceAssets([entry, entry]), contains: "appears more than once")
            broken = entry
            broken["name"] = "Changed inside EXP"
            reject(try replaceAssets([broken]), contains: "read-only")
            require(doc.designLanguage.assets == [swatch], "review never touched the live swatch")
        }

        check("code deletion previews links, preserves artwork, and refuses a stale draft") {
            let swatch = DesignAsset(name: "Old ink", value: .black)
            var shape = leaf("Linked fill")
            shape.setTokenBinding(TokenBindingKey.fill, to: swatch.id)
            var doc = Document(nodes: [shape])
            doc.designLanguage.assets = [swatch]
            doc.applyTokenBindings()
            let start = DesignLanguageCode.Content(doc.designLanguage)
            var draft = start
            draft.assets = []
            let input = try DesignLanguageCode.encode(draft)
            let preview = try DesignLanguageCode.preview(input, from: start, in: doc)
            require(preview.affectedLinkCount(in: doc) == 1, "removal preview reports linked properties")
            doc.pages[0].nodes[0].name = "Recently renamed layer"
            let updated = try preview.applying(to: doc)
            require(updated.designLanguage.assets.isEmpty && updated.pages[0].nodes[0].tokenBindings == nil,
                    "remove the swatch and only its bindings")
            require(updated.pages[0].nodes[0].layerPaintStyle?.fill == .black &&
                    updated.pages[0].nodes[0].name == "Recently renamed layer", "keep paint and unrelated canvas edits")

            doc.designLanguage.assets[0].name = "Edited in Table"
            do {
                _ = try preview.applying(to: doc)
                fail("preview overwrote newer Table edits")
            } catch {
                require(error.localizedDescription.contains("changed since this draft"), "show stale draft diagnosis")
            }
        }

        check("Radius and border width stay independently linked across modes, edits and reopening") {
            let width = DLToken(name: "Standard border", type: .dimension, role: .borderWidth, value: .number(2))
            var radius = DLToken(name: "Soft corner", type: .dimension, role: .radius, value: .dimension(DLDimension(8)))
            var doc = Document()
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            radius.modeValues[dark.uuidString] = .dimension(DLDimension(12))
            doc.designLanguage.addToken(radius)
            doc.designLanguage.addToken(width)
            var target = leaf("Card")
            target.setTokenBinding(TokenBindingKey.cornerRadius, to: radius.id)
            target.setTokenBinding(TokenBindingKey.borderWidth, to: width.id)
            var line = Node(name: "Line", frame: target.frame, content: .line(LineShape(start: .zero, end: CGPoint(x: 40, y: 0))))
            let clampedWidth = DLToken(name: "Thin border", type: .dimension, role: .borderWidth, value: .number(0.5))
            line.setTokenBinding(TokenBindingKey.borderWidth, to: clampedWidth.id)
            doc.designLanguage.addToken(clampedWidth)
            doc.pages[0].nodes = [target, line]
            doc.applyTokenBindings()
            let baseline = doc
            require(doc.pages[0].nodes[0].numericValue(forBindingKey: TokenBindingKey.cornerRadius) == 8, "base corners")
            require(doc.pages[0].nodes[1].numericValue(forBindingKey: TokenBindingKey.borderWidth) == 1, "line width minimum")
            doc.pages[0].modeOverrides = [doc.designLanguage.colorModeSet!.id.uuidString: dark]
            doc.reconcileTokenBindings(after: baseline)
            require(doc.pages[0].nodes[0].numericValue(forBindingKey: TokenBindingKey.cornerRadius) == 12, "page mode radius")
            var edited = doc
            edited.pages[0].nodes[0].setNumericValue(4, forBindingKey: TokenBindingKey.topLeftRadius)
            edited.reconcileTokenBindings(after: doc)
            require(edited.pages[0].nodes[0].boundTokenID(TokenBindingKey.cornerRadius) == nil, "mixed corners clear the uniform link")
            edited.pages[0].nodes[0].setTokenBinding(TokenBindingKey.topRightRadius, to: radius.id)
            edited.setTokenValue(radius.id, to: .dimension(DLDimension(16)), modeID: dark)
            let saved = try roundTrip(edited)
            let card = saved.pages[0].nodes[0]
            require(card.boundTokenID(TokenBindingKey.topRightRadius) == radius.id
                    && card.numericValue(forBindingKey: TokenBindingKey.topRightRadius) == 16
                    && card.numericValue(forBindingKey: TokenBindingKey.topLeftRadius) == 4, "individual corner link round-trip")
            require(card.boundTokenID(TokenBindingKey.borderWidth) == width.id
                    && card.numericValue(forBindingKey: TokenBindingKey.borderWidth) == 2, "border width link round-trip")
            var uniform = card
            uniform.replaceCornerBindingScope(for: TokenBindingKey.cornerRadius)
            uniform.setTokenBinding(TokenBindingKey.cornerRadius, to: radius.id)
            uniform.setNumericValue(16, forBindingKey: TokenBindingKey.cornerRadius)
            require(uniform.boundTokenID(TokenBindingKey.topRightRadius) == nil
                    && uniform.numericValue(forBindingKey: TokenBindingKey.topLeftRadius) == 16, "uniform field replaces the individual links")
            let guide = try DesignLanguageGuideBuilder.build(document: saved, title: "Dimensions")
            require(guide.rows.contains { $0.name == width.name && $0.section == "Borders" }
                    && guide.rows.contains { $0.name == radius.name && $0.section == "Radius" }, "Guide sections")
            require(guide.files["tokens.css"]?.contains("--standard-border: 2px") == true
                    && guide.files["_tokens.scss"]?.contains("$soft-corner: 8px") == true, "CSS and SCSS units")
            require(guide.files["tokens.json"]?.contains("\"standard-border\"") == true, "DTCG dimension")
        }
        check("Dimension tokens count toward their category and return to Other when it is deleted") {
            var language = DesignLanguage()
            let category = language.ensureCategory("Controls")
            let token = DLToken(name: "Button Radius", group: "Buttons", categoryID: category,
                                role: .radius, value: .dimension(DLDimension(8)), notes: "Use on controls")
            language.addToken(token)
            require(language.count(in: category) == 1 && !language.hasUncategorized,
                    "dimension token participates in category counts")
            language.removeCategory(category)
            var expected = token
            expected.categoryID = nil
            require(language.token(token.id) == expected && language.count(in: nil) == 1 && language.hasUncategorized,
                    "deletion clears only the token category")
        }
        check("Saved paint and type metadata survives edits and appears in the Guide") {
            var doc = Document()
            let category = doc.designLanguage.ensureCategory("Product")
            let color = DesignAsset(name: "Primary", categoryID: category, value: .white,
                                    notes: "Use sparingly", group: "Controls / Action", deprecated: "Use Accent")
            let gradient = DesignAsset(name: "Hero", value: .gradient(GradientFill()), group: "Brand")
            let style = TypeStyle(name: "Heading", categoryID: category, notes: "Use for sections",
                                  fontSize: 24, group: "Editorial", deprecated: "")
            doc.designLanguage.assets = [color, gradient]
            doc.designLanguage.typeStyles = [style]
            doc.designLanguage.setTypeStyleValues(style.id, from: TypeStyle(fontSize: 32))
            let reopened = try roundTrip(doc)
            require(reopened.designLanguage.asset(color.id) == color && reopened.designLanguage.asset(gradient.id) == gradient,
                    "paint metadata survives native save and reopen")
            guard let updated = reopened.designLanguage.typeStyle(style.id) else { fail("missing type style") }
            require(updated.fontSize == 32 && updated.notes == style.notes && updated.group == style.group &&
                    updated.deprecated == style.deprecated && updated.categoryID == category,
                    "recapturing style values retains its metadata")
            let guide = try DesignLanguageGuideBuilder.build(document: reopened, title: "Metadata")
            let rows = Dictionary(uniqueKeysWithValues: guide.rows.map { ($0.id, $0) })
            require(rows[color.id.uuidString]?.group == "Controls / Action / Product"
                    && rows[color.id.uuidString]?.deprecated == "Use Accent", "color metadata reaches the Guide")
            require(rows[gradient.id.uuidString]?.group == "Brand"
                    && rows[style.id.uuidString]?.deprecated == "", "gradient and typography metadata reaches the Guide")
            let data = Data((guide.files["tokens.json"] ?? "").utf8)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let colors = json?["color"] as? [String: Any]
            let controls = colors?["controls"] as? [String: Any]
            let action = controls?["action"] as? [String: Any]
            let primary = action?["primary"] as? [String: Any]
            require(primary?["$deprecated"] as? String == "Use Accent", "exports nest the token and retain its status")
        }
        check("Percentage corners resize on both axes and survive save and export") {
            var card = leaf("Card")
            card.frame.size = CGSize(width: 200, height: 100)
            let board = Artboard(name: "Radii", frame: CGRect(x: 0, y: 0, width: 400, height: 240))
            card.artboardID = board.id
            let pill = DLToken(name: "Round", type: .dimension, role: .radius, value: .dimension(DLDimension(50, unit: "%")))
            var doc = Document()
            doc.pages[0].artboards = [board]
            doc.pages[0].nodes = [card]
            doc.designLanguage.addToken(pill)
            require(doc.applyNumericToken(pill.id, on: doc.pages[0].id, selection: [card.id], linked: true),
                    "percentage token can be applied")
            let saved = try roundTrip(doc)
            guard case .rectangle(let original) = saved.pages[0].nodes[0].content else { fail("expected rectangle") }
            let first = original.effectiveRadii.clamped(to: card.frame.size)
            require(first.topLeft == CGSize(width: 100, height: 50), "50% resolves against both border box axes")
            let newSize = CGSize(width: 240, height: 60)
            let resized = original.effectiveRadii.clamped(to: newSize)
            require(resized.topLeft == CGSize(width: 120, height: 30), "resizing resolves relative radius again")
            let zoomedPath = original.effectiveRadii.path(in: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 2)
            require(!zoomedPath.contains(CGPoint(x: 0, y: 0)) && zoomedPath.contains(CGPoint(x: 200, y: 0.1)),
                    "canvas path is an ellipse")
            let svg = ExportRenderer(document: saved).svgString(for: board)
            require(svg.contains("A100,50"), "SVG uses elliptical arc radii")
            let css = String(decoding: SemanticHTMLExporter(document: saved).makeBundle().artifacts[0].data, as: UTF8.self)
            require(css.contains("border-radius: 50% 50% 50% 50%"), "handoff CSS keeps the authored unit")
            var excessive = CornerRadii(percent: 80, fallback: 0)
            let clamped = excessive.clamped(to: card.frame.size)
            require(abs(clamped.bottomRight.width - 100) < 0.001 && abs(clamped.bottomRight.height - 50) < 0.001,
                    "overlap reduces every corner by one proportional factor")
            excessive.setPercentage(nil, for: .topLeft)
            excessive[.topLeft] = 4
            require(excessive.clamped(to: card.frame.size).topLeft == CGSize(width: 2.5, height: 2.5),
                    "mixed absolute and percentage corners")
            var changed = saved
            _ = changed.setTokenValue(pill.id, to: .dimension(DLDimension(12)))
            changed.reconcileTokenBindings(after: saved)
            let node = changed.pages[0].nodes[0]
            require(node.boundTokenID(TokenBindingKey.cornerRadius) == pill.id &&
                    node.radiusPercentage(for: TokenBindingKey.cornerRadius) == nil &&
                    node.numericValue(forBindingKey: TokenBindingKey.cornerRadius) == 12, "unit changes keep the link")
        }
        check("Panel dimension actions honor compatibility and group selection") {
            let radius = DLToken(name: "Round", type: .dimension, role: .radius, value: .dimension(DLDimension(25, unit: "%")))
            let width = DLToken(name: "Border", type: .dimension, role: .borderWidth, value: .number(3))
            let box = leaf("Visible")
            var locked = leaf("Locked")
            locked.isLocked = true
            let polygon = Node(name: "Polygon", frame: box.frame, content: .polygon(PolygonShape()))
            let text = Node(name: "Label", frame: box.frame, content: .text(TextContent(string: "A")))
            let group = Node(name: "Group", frame: box.frame, content: .group(children: [box, locked, polygon, text]))
            var doc = Document()
            doc.pages[0].nodes = [group]
            doc.designLanguage.addToken(radius)
            doc.designLanguage.addToken(width)
            let selection: Set<UUID> = [group.id, box.id]
            require(doc.applyNumericToken(radius.id, on: nil, selection: selection, linked: true), "group radius apply")
            require(doc.applyNumericToken(width.id, on: nil, selection: selection, linked: false), "group width apply")
            let nodes = doc.pages[0].nodes
            require(doc.tokenUseCount(radius.id) == 1 &&
                    node(box.id, in: nodes)?.radiusPercentage(for: TokenBindingKey.cornerRadius) == 25,
                    "radius applies once to the compatible rectangle")
            require(node(locked.id, in: nodes)?.numericValue(forBindingKey: TokenBindingKey.borderWidth) == 0 &&
                    node(polygon.id, in: nodes)?.numericValue(forBindingKey: TokenBindingKey.borderWidth) == 3 &&
                    node(text.id, in: nodes)?.numericValue(forBindingKey: TokenBindingKey.borderWidth) == 3,
                    "width applies only to unlocked compatible descendants")
            require(doc.tokenUseCount(width.id) == 0, "literal application leaves no link")
            require(!doc.applyNumericToken(radius.id, on: nil, selection: [text.id], linked: true), "incompatible selection makes no change")
        }
        check("Code coloring and folding preserve full source and UTF-16 positions") {
            let json = "{\r\n  \"🔵\": [\r\n    true, \"[inside a string]\"\r\n  ],\r\n  \"next\": 3\r\n}\r\n"
            let syntax = DLCodeSyntax(json, format: .json)
            require(syntax.lines.count == 7 && syntax.folds.count == 2, "multiline JSON brackets or CRLF lines")
            require(syntax.highlights.map(\.style) == [.key, .literal, .string, .key, .number], "JSON lexing")
            let projected = syntax.project(json, folded: [syntax.folds[1]])
            let marker = projected.replacements[0]
            let end = projected.sourceOffset(for: NSMaxRange(marker.display), trailing: true)
            require(end == NSMaxRange(marker.source) && projected.text.contains("\"🔵\": [ … ]"), "fold marker and original offsets")
            let restored = syntax.project(json, folded: [])
            require(restored.text == json, "expand damaged source")
            let css = DLCodeSyntax("/* { a } */\n:root {\n --size: 2px;\n}", format: .css)
            require(css.folds.count == 1 && css.highlights.contains { $0.style == .variable }, "CSS comments and variables")
            let scss = DLCodeSyntax("// {\n$values: (\n value: \"a)b\",\n);", format: .scss)
            require(scss.folds.count == 1 && scss.highlights.contains { $0.style == .comment }, "SCSS comment and map")
        }

        if CommandLine.arguments.count > 1 {
            try guideChecks()
        }

        print("\(passed) checks passed")
    }

    static func guideChecks() throws {
        check("Guide rows and CSS, SCSS, DTCG and resolver downloads agree") {
            var doc = Document()
            doc.designLanguage.enableColorModes()
            let dark = doc.designLanguage.colorModeSet!.modes[1].id
            let target = doc.designLanguage.save(.black, name: "Navy")
            var brand = DesignAsset(name: "Brand", value: .white, notes: "</script><script>alert(1)</script>")
            brand.modeValues[dark.uuidString] = .alias(target)
            doc.designLanguage.add(brand)
            doc.designLanguage.saveTypeStyle(TypeStyle(name: "Heading", fontSize: 24))
            let fixed = DLToken.spacing("Medium", 16)
            doc.designLanguage.addToken(fixed)
            doc.designLanguage.addToken(DLToken(name: "Inset", group: "Space", role: .spacing, value: .alias(fixed.id)))
            doc.designLanguage.addToken(DLToken(name: "Fluid", role: .spacing, value: .raw("clamp(1rem, 3vw, 3rem)")))
            doc.designLanguage.addToken(DLToken(name: "Broken", value: .alias(UUID())))
            doc.designLanguage.addToken(DLToken(name: "Other", value: .preserved(.object(["complex": .bool(true)]))))
            let guide = try DesignLanguageGuideBuilder.build(document: doc, title: "Example </script> & Co")
            let brandRow = guide.rows.first { $0.name == "Brand" }
            require(brandRow?.css == "var(--brand)" && brandRow?.dtcg == "{color.brand}", "consistent code names")
            require(brandRow?.overrides[dark.uuidString]?.alias == "→ Navy", "alias trail")
            require(brandRow?.overrides[dark.uuidString]?.contrast?.contains(":1") == true, "mode contrast is text")
            let css = guide.files["tokens.css"] ?? ""
            require(css.contains("--brand: var(--navy)") && css.contains("data-exp-color-scheme"), "mode CSS references")
            let scss = guide.files["_tokens.scss"] ?? ""
            require(scss.contains("$brand: #FFFFFF") && scss.contains("@mixin type-heading"), "SCSS variable and type mixin")
            func json(_ name: String) throws -> [String: Any] {
                guard let text = guide.files[name],
                      let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
                else { fail("missing or invalid \(name)") }
                return object
            }
            let tokens = try json("tokens.json")
            let colors = tokens["color"] as? [String: [String: Any]]
            let baseValue = colors?["brand"]?["$value"] as? [String: Any]
            require(baseValue?["colorSpace"] as? String == "srgb", "structured DTCG color")
            require(tokens["$extensions"] != nil, "unsupported tokens are preserved")
            let resolver = try json("tokens.resolver.json")
            let modifiers = resolver["modifiers"] as? [String: [String: Any]]
            let modes = modifiers?["color-scheme"]?["contexts"] as? [String: [[String: [String: [String: Any]]]]]
            let darkColor = modes?["dark"]?.first?["color"]?["brand"]?["$value"] as? String
            require(darkColor == "{color.navy}", "DTCG override links to the same asset")
            require((resolver["resolutionOrder"] as? [[String: String]])?.count == 2, "base before mode modifier")

            let template = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            let html = try guide.html(template: template)
            require(html.contains("role=\u{22}status\u{22}") && html.contains("scope: 'col'"), "native table and live status")
            require(!html.contains("</script><script>alert"), "user strings cannot escape the JSON script element")
            require(html.contains("Example \\u003c"), "escaped document title")
            require(!html.contains("__EXP_GUIDE_DATA__"), "template is populated")
            if CommandLine.arguments.count > 2 {
                try html.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            }
        }
        check("Guide folder has matching files and keeps existing exports intact") {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: parent) }
            let template = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            var doc = Document()
            let base = try DesignLanguageGuideBuilder.build(document: doc, title: "Folder Check")
            let export = try DesignLanguageFolderExport(guide: base, template: template)
            let folder = try export.write(to: parent, folderName: "Design Language")
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            require(Set(files) == ["index.html", "tokens.css", "_tokens.scss", "tokens.json"],
                    "wrong folder contents without modes")
            let exportedHTML = try String(contentsOf: folder.appendingPathComponent("index.html"), encoding: .utf8)
            try require(exportedHTML == base.html(template: template), "folder and single-file HTML differ")
            for (name, contents) in base.files {
                let written = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
                require(written == contents, "\(name) does not match the download")
            }
            doc.designLanguage.enableColorModes()
            let themed = try DesignLanguageFolderExport(
                guide: DesignLanguageGuideBuilder.build(document: doc, title: "Folder Check"),
                template: template)
            for name in ["Design Language", "../escape", " "] {
                do {
                    try themed.write(to: parent, folderName: name)
                    fail("export accepted \(name)")
                } catch { }
            }
            let intact = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            require(Set(intact) == Set(files), "a rejected export changed the destination")
            let themedFolder = try themed.write(to: parent, folderName: "Themed")
            let themedFiles = try FileManager.default.contentsOfDirectory(atPath: themedFolder.path)
            require(Set(themedFiles) == Set(files).union(["tokens.resolver.json"]), "mode resolver missing")
            let children = try FileManager.default.contentsOfDirectory(atPath: parent.path)
            require(Set(children) == ["Design Language", "Themed"], "staging files left behind")
        }
    }
}

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

        print("\(passed) checks passed")
    }
}

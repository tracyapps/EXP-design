//
//  SemanticHTMLExporter.swift
//  EXP [design]
//
//  v2.0 semantic HTML/CSS package exporter. Free-positioned artwork keeps honest
//  absolute geometry; managed stacks become flexbox and exact Design Language
//  paint/type matches retain their reusable token identity.
//

import Foundation
import CoreGraphics

struct SemanticHTMLArtifact: Sendable {
    var path: String
    var role: String
    var mediaType: String
    var data: Data
}

struct SemanticHTMLFidelityIssue: Sendable {
    enum Category: String, Sendable {
        case semanticRequirement
        case visualFallback
        /// Valid markup that is probably not what was meant. Kept SEPARATE from
        /// `semanticRequirement` on purpose: a reader must be able to tell "you
        /// broke a rule" from "this is legal but unusual," and collapsing the two
        /// would make the report either alarmist or ignorable. FEAT-016.
        case advisory
    }

    var artboardID: UUID
    var nodeID: UUID
    var instanceID: UUID?
    var sourceID: UUID?
    var role: AriaRole?
    var category: Category
    var requirement: String
    var detail: String
}

struct SemanticHTMLBundle: Sendable {
    var artifacts: [SemanticHTMLArtifact]
    var pagePaths: [String]
    var emittedNodeCount: Int
    var omittedWallNodeCount: Int
    var fidelityIssues: [SemanticHTMLFidelityIssue]
}

struct SemanticHTMLExporter {
    static let formatVersion = 1

    let document: Document

    /// A nil filter preserves the full-package behavior. Connectors such as
    /// CodePen can request one explicit board without leaking unrelated
    /// canvases or generating unused CSS.
    func makeBundle(artboardIDs: Set<UUID>? = nil) -> SemanticHTMLBundle {
        var css = CSSWriter(document: document)
        var artifacts: [SemanticHTMLArtifact] = []
        var pages: [String] = []
        var emittedNodeCount = 0
        var fidelityIssues: [SemanticHTMLFidelityIssue] = []

        for canvasPage in document.pages {
            for artboard in canvasPage.artboards {
                if let artboardIDs, !artboardIDs.contains(artboard.id) { continue }
                let owned = canvasPage.nodes.enumerated().filter {
                    document.owningArtboard(of: $0.element, on: canvasPage.id)?.id == artboard.id
                }
                let page = HTMLWriter(document: document, artboard: artboard,
                                      topLevelNodes: owned).render()
                css.append(artboard: artboard, topLevelNodes: owned)
                let filename = SemanticHTMLIdentity.artboardFilename(name: artboard.name, id: artboard.id)
                let path = "html/\(filename)"
                pages.append(path)
                emittedNodeCount += page.nodeCount
                fidelityIssues.append(contentsOf: page.issues)
                artifacts.append(.init(path: path, role: "semantic-html",
                                       mediaType: "text/html", data: Data(page.html.utf8)))
            }
        }

        let omitted = document.pages.reduce(0) { total, canvasPage in
            total + canvasPage.nodes
                .filter { document.owningArtboard(of: $0, on: canvasPage.id) == nil }
                .reduce(0) { $0 + Self.nodeCount($1) }
        }
        artifacts.insert(.init(path: "html/styles.css", role: "semantic-stylesheet",
                               mediaType: "text/css", data: Data(css.render().utf8)), at: 0)
        return SemanticHTMLBundle(artifacts: artifacts, pagePaths: pages,
                                  emittedNodeCount: emittedNodeCount,
                                  omittedWallNodeCount: omitted,
                                  fidelityIssues: fidelityIssues)
    }

    private static func nodeCount(_ node: Node) -> Int {
        if case .group(let children) = node.content {
            return 1 + children.reduce(0) { $0 + nodeCount($1) }
        }
        return 1
    }
}

// MARK: - HTML

private struct HTMLWriter {
    private struct Attribute {
        var name: String
        var value: String?
    }

    let document: Document
    let artboard: Artboard
    let topLevelNodes: [(offset: Int, element: Node)]

    func render() -> (html: String, nodeCount: Int,
                      issues: [SemanticHTMLFidelityIssue]) {
        var count = 0
        var issues: [SemanticHTMLFidelityIssue] = []
        let available = availableDOMIDs()
        // The DOCUMENT root is an anchor too. Authoring never creates one — the
        // neighborhood rule requires a group — but a migrated legacy relationship
        // between two ungrouped top-level layers lands here, and dropping it
        // silently would lose real work from an older file.
        let rootAnchored: [String: [String: String]] = document.anchoredRelationships.isEmpty
            ? [:]
            : anchoredAttributes(document.anchoredRelationships,
                                 anchorID: artboard.id,
                                 anchorElementID: SemanticHTMLIdentity.artboardDOMID(artboard.id),
                                 anchorChildren: topLevelNodes.map(\.element),
                                 anchorRole: nil,
                                 context: [], availableDOMIDs: available,
                                 node: topLevelNodes.first?.element
                                     ?? Node(name: artboard.name, frame: artboard.frame,
                                             content: .group(children: [])),
                                 sourceID: nil, issues: &issues)
        let nodeHTML = topLevelNodes.reversed().map { item in
            render(node: item.element, instanceChain: [], sourceID: nil,
                   instanceNodeIDs: nil, semanticAncestors: [],
                   phrasingOnly: false,
                   availableDOMIDs: available,
                   anchoredAttributes: rootAnchored, level: 2,
                   count: &count, issues: &issues)
        }.joined(separator: "\n")
        let note = artboard.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = note.isEmpty ? "" : "  <!-- EXP artboard notes: \(SemanticHTMLEscape.comment(note)) -->\n"
        let title = SemanticHTMLEscape.text(artboard.name)
        let rootID = SemanticHTMLIdentity.artboardDOMID(artboard.id)
        let rootName = SemanticHTMLEscape.attribute(artboard.name)

        let html = """
        <!doctype html>
        <html lang="und">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          <link rel="stylesheet" href="styles.css">
        </head>
        <body>
        \(comment)  <div id="\(rootID)" class="exp-artboard" data-exp-artboard-id="\(artboard.id.uuidString.lowercased())" data-exp-name="\(rootName)">
        \(nodeHTML)
          </div>
        </body>
        </html>
        """
        return (html + "\n", count, issues)
    }

    /// - Parameter instanceChain: the component instances this node sits inside,
    ///   OUTERMOST FIRST. It is what makes a DOM id unique at any depth, and it is
    ///   the same addressing `RelationshipEndpoint` uses, so an element and a
    ///   relationship naming it agree by construction (FEAT-012 chunk I-d).
    /// - Parameter anchoredAttributes: attributes contributed by ANCESTOR anchors,
    ///   keyed by the DOM id of the element that must carry them. Relationships are
    ///   stored on the anchor but belong on the SUBJECT, so each anchor resolves its
    ///   entries once and every descendant simply looks itself up.
    private func render(node: Node, instanceChain: [UUID], sourceID: UUID?,
                        instanceNodeIDs: Set<UUID>?,
                        semanticAncestors: [AriaRole],
                        phrasingOnly: Bool,
                        availableDOMIDs: Set<String>,
                        anchoredAttributes: [String: [String: String]],
                        level: Int,
                        count: inout Int,
                        issues: inout [SemanticHTMLFidelityIssue]) -> String {
        count += 1
        let instanceID = instanceChain.last
        let indent = String(repeating: "  ", count: level)
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, chain: instanceChain)
        let expID = node.id.uuidString.lowercased()
        var common = [
            Attribute(name: "id", value: id),
            Attribute(name: "data-exp-id", value: expID),
            Attribute(name: "data-exp-name", value: node.name)
        ]
        if let instanceID {
            common.append(Attribute(name: "data-exp-instance-id",
                                    value: instanceID.uuidString.lowercased()))
        }
        if !node.isVisible { common.append(Attribute(name: "hidden", value: nil)) }

        reportVisualFallbacks(node: node, sourceID: sourceID,
                              instanceID: instanceID, issues: &issues)

        // ARIA roles do NOT inherit, so this element's role is its OWN, never its
        // container's. Only a component instance carries one; every other layer
        // exports as a plain container with the implicit `generic` role.
        // The emission step below needs this to know whether a NAMING attribute
        // would be prohibited here.
        let hostRole: AriaRole? = {
            if case .instance(let inst) = node.content {
                return document.source(for: inst.sourceID)?.a11y.role
            }
            return nil
        }()
        // Relationships are read from ANCESTOR ANCHORS now, not from the node.
        // Anything stored the old way was rewritten into an anchored twin at decode
        // (`Document.migrateRelationshipsToAnchors`), so nothing is lost — and
        // reading only one of the two is what makes a DELETE actually delete,
        // instead of a stale legacy entry resurrecting the attribute.
        var relationships = anchoredAttributes[id] ?? [:]
        // The one conformance rule that has to live at the point of emission,
        // because only here is the host's role known: `aria-labelledby` is
        // PROHIBITED on an element with no role (it exports as a `<div>`, implicit
        // role `generic`, which is nameless). `aria-controls` and `aria-describedby`
        // are GLOBAL and stay. Verified 2026-07-24 — see BACKLOG BUG-008, and do not
        // collapse these into one rule; they are not the same case.
        if hostRole == nil {
            for kind in NodeRelationship.Kind.allCases where kind.isProhibitedWithoutRole {
                guard relationships[kind.ariaAttribute] != nil else { continue }
                relationships[kind.ariaAttribute] = nil
                issues.append(issue(node: node, sourceID: sourceID,
                                    instanceID: instanceID, role: nil,
                                    requirement: "prohibitedRelationship",
                                    detail: "\(kind.ariaAttribute) was dropped: this layer has no role, so it exports as a generic container, and naming attributes are prohibited there."))
            }
        }

        // This node is itself an ANCHOR when it is a group holding relationships:
        // resolve them once here and hand them down.
        var childAnchored = anchoredAttributes
        if !node.anchoredRelationships.isEmpty {
            let groupChildren: [Node] = {
                if case .group(let children) = node.content { return children }
                return []
            }()
            childAnchored = merging(childAnchored, self.anchoredAttributes(
                node.anchoredRelationships,
                anchorID: node.id, anchorElementID: id,
                anchorChildren: groupChildren, anchorRole: hostRole,
                context: instanceChain, availableDOMIDs: availableDOMIDs,
                node: node, sourceID: sourceID, issues: &issues))
        }

        switch node.content {
        case .group(let children):
            let childHTML = orderedChildren(children, autoLayout: node.autoLayout).map {
                render(node: $0, instanceChain: instanceChain, sourceID: sourceID,
                       instanceNodeIDs: instanceNodeIDs,
                       semanticAncestors: semanticAncestors,
                       phrasingOnly: phrasingOnly,
                       availableDOMIDs: availableDOMIDs,
                       anchoredAttributes: childAnchored, level: level + 1,
                       count: &count, issues: &issues)
            }.joined(separator: "\n")
            var attrs = common
            let layoutClass = node.autoLayout == nil ? "" : " exp-auto-layout"
            attrs.append(Attribute(name: "class", value: "exp-node exp-group\(layoutClass)"))
            attrs.append(Attribute(name: "data-exp-content", value: "group"))
            append(relationships, to: &attrs)
            let tag = phrasingOnly ? "span" : "div"
            return "\(indent)<\(tag)\(attributes(attrs))>\n\(childHTML)\n\(indent)</\(tag)>"

        case .instance(let instance):
            guard let source = document.source(for: instance.sourceID) else {
                issues.append(issue(node: node, sourceID: instance.sourceID,
                                    role: nil, requirement: "missingComponentSource",
                                    detail: "The component source could not be resolved."))
                var attrs = common
                attrs.append(Attribute(name: "class", value: "exp-node exp-instance"))
                attrs.append(Attribute(name: "data-exp-content", value: "instance"))
                attrs.append(Attribute(name: "data-exp-source-id",
                                       value: instance.sourceID.uuidString.lowercased()))
                let tag = phrasingOnly ? "span" : "div"
                return "\(indent)<\(tag)\(attributes(attrs))></\(tag)>"
            }

            let baseInstance = instance.withoutActiveState
            let children = document.semanticHTMLResolvedChildren(of: baseInstance)
            let sourceNodeIDs = allNodeIDs(source.children)
            let role = source.a11y.role
            let mapping = role?.semanticHTMLMapping
            let preferredTag = mapping?.tag ?? "div"
            let tag = phrasingOnly ? "span" : preferredTag
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-instance"))
            attrs.append(Attribute(name: "data-exp-content", value: "instance"))
            attrs.append(Attribute(name: "data-exp-source-id", value: source.id.uuidString.lowercased()))
            if phrasingOnly, let role {
                attrs.append(Attribute(name: "data-exp-intended-role", value: role.rawValue))
                issues.append(issue(
                    node: node, sourceID: source.id, instanceID: instanceID, role: role,
                    requirement: "nestedInteractiveStructure",
                    detail: "A semantic component is nested inside a phrasing-only control host; EXP preserved valid HTML and recorded the intended role for downstream restructuring."
                ))
            }

            var semanticAttributes = relationships

            // The SOURCE is an anchor too: it holds links between this component's
            // own children, and the component's own links (whose subject names the
            // source itself, standing for the element hosting THIS instance). Both
            // ends resolve against this instance's copies, so two placements can
            // never cross-link to each other's layers.
            let sourceAnchored = self.anchoredAttributes(
                source.anchoredRelationships,
                anchorID: source.id, anchorElementID: id,
                anchorChildren: source.children, anchorRole: role,
                context: instanceChain + [node.id],
                availableDOMIDs: availableDOMIDs,
                node: node, sourceID: source.id, issues: &issues)
            for (name, value) in sourceAnchored[id] ?? [:] {
                for token in value.split(separator: " ").map(String.init) {
                    appendAttributeValue(token, name: name, to: &semanticAttributes)
                }
            }

            if let labelID = source.a11y.accessibleNameLayerID {
                let target = SemanticHTMLIdentity.nodeDOMID(labelID, chain: instanceChain + [node.id])
                if sourceNodeIDs.contains(labelID), availableDOMIDs.contains(target) {
                    appendAttributeValue(target, name: "aria-labelledby",
                                         to: &semanticAttributes)
                } else {
                    issues.append(issue(node: node, sourceID: source.id, role: role,
                                        requirement: "accessibleName",
                                        detail: "The configured accessible-name layer is missing from this instance."))
                }
            }
            if let mapping, let role, !phrasingOnly {
                if role == .heading,
                   let level = unambiguousHeadingLevel(in: children) {
                    semanticAttributes["aria-level"] = String(level)
                }
                for (name, value) in mapping.fixedAttributes.sorted(by: { $0.key < $1.key }) {
                    attrs.append(Attribute(name: name, value: value))
                }
                // BUG-018. Two problems with the previous form
                // `(role == .banner || role == .contentinfo), !semanticAncestors.isEmpty`:
                //
                // 1. `complementary` was missing, so a nested EXP complementary
                //    exported as a bare `<aside>` and computed as `generic`
                //    whenever it had no accessible name (HTML-AAM §3.5.10) —
                //    the authored role lost with nothing reported.
                // 2. "any semantic ancestor" is not the spec's rule. Only
                //    sectioning content and `main` rescope a nested
                //    header/footer/aside, so an EXP banner inside an EXP group
                //    (a plain `<div>`) was getting a redundant role attribute
                //    that ARIA in HTML calls NOT RECOMMENDED.
                var explicitRole = mapping.explicitRole
                if role.needsExplicitRoleWhenNested,
                   semanticAncestors.contains(where: { $0.hostRescopesNestedLandmarks }) {
                    explicitRole = role
                }
                if let explicitRole {
                    attrs.append(Attribute(name: "role", value: explicitRole.rawValue))
                }
                applyActiveState(instance: instance, source: source, mapping: mapping,
                                 attributes: &attrs, node: node, issues: &issues)
                reportMissingRequirements(mapping: mapping, role: role,
                                          semanticAttributes: semanticAttributes,
                                          semanticAncestors: semanticAncestors,
                                          node: node, source: source,
                                          issues: &issues)
            }
            append(semanticAttributes, to: &attrs)

            let childHTML = children.reversed().map {
                render(node: $0, instanceChain: instanceChain + [node.id], sourceID: source.id,
                       instanceNodeIDs: sourceNodeIDs,
                       semanticAncestors: role.map { semanticAncestors + [$0] }
                           ?? semanticAncestors,
                       phrasingOnly: phrasingOnly || tag == "button",
                       availableDOMIDs: availableDOMIDs,
                       anchoredAttributes: merging(childAnchored, sourceAnchored),
                       level: level + 1,
                       count: &count, issues: &issues)
            }.joined(separator: "\n")
            return "\(indent)<\(tag)\(attributes(attrs))>\n\(childHTML)\n\(indent)</\(tag)>"

        case .text(let text):
            let runs = text.runs.enumerated().map { index, run in
                let content = SemanticHTMLEscape.text(text.textCase.apply(run.string))
                let className = "exp-text-run exp-text-run-\(index)"
                if let href = run.linkURL, !href.isEmpty {
                    return "<a class=\"\(className)\" href=\"\(SemanticHTMLEscape.attribute(href))\">\(content)</a>"
                }
                return "<span class=\"\(className)\">\(content)</span>"
            }.joined()
            var attrs = common
            let typeClass = DesignLanguageIO.firstTypeStyleBinding(
                matching: text, in: document.designLanguage).map { " \($0.className)" } ?? ""
            attrs.append(Attribute(name: "class", value: "exp-node exp-text\(typeClass)"))
            attrs.append(Attribute(name: "data-exp-content", value: "text"))
            append(relationships, to: &attrs)
            // A component categorized as Heading owns the heading semantics at
            // its host. Its authored text role supplies aria-level, but renders
            // as a span here so assistive technology does not encounter a nested
            // duplicate heading. Ordinary text layers use their native tag.
            let tag = phrasingOnly || semanticAncestors.last == .heading
                ? "span" : text.contentRole.htmlTag
            return "\(indent)<\(tag)\(attributes(attrs))>\(runs)</\(tag)>"

        case .path(let path):
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-path"))
            attrs.append(Attribute(name: "data-exp-content", value: "path"))
            append(relationships, to: &attrs)
            let tag = phrasingOnly ? "span" : "div"
            return "\(indent)<\(tag)\(attributes(attrs))>\(svg(path: path, domID: id, size: node.frame.size))</\(tag)>"

        default:
            let kind = contentName(node.content)
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-\(kind)"))
            attrs.append(Attribute(name: "data-exp-content", value: kind))
            append(relationships, to: &attrs)
            let tag = phrasingOnly ? "span" : "div"
            return "\(indent)<\(tag)\(attributes(attrs))></\(tag)>"
        }
    }

    private func availableDOMIDs() -> Set<String> {
        var result = Set<String>()
        for item in topLevelNodes {
            collectDOMIDs(node: item.element, chain: [], into: &result)
        }
        return result
    }

    /// Every DOM id an artboard will emit, so a relationship pointing at something
    /// outside it can be REPORTED rather than emitted as a dangling reference.
    /// Mirrors `render`'s chain handling exactly — if these two ever disagree about
    /// how an id is composed, every relationship silently becomes unresolvable.
    private func collectDOMIDs(node: Node, chain: [UUID],
                               into result: inout Set<String>) {
        result.insert(SemanticHTMLIdentity.nodeDOMID(node.id, chain: chain))
        switch node.content {
        case .group(let children):
            for child in children { collectDOMIDs(node: child, chain: chain, into: &result) }
        case .instance(let instance):
            for child in document.semanticHTMLResolvedChildren(of: instance.withoutActiveState) {
                collectDOMIDs(node: child, chain: chain + [node.id], into: &result)
            }
        default:
            break
        }
    }

    /// Resolve one anchor's relationships into attributes keyed by the DOM id of
    /// the element that must CARRY each one.
    ///
    /// Relationships live on the anchor but belong on the subject, so this is the
    /// translation step. Both ends are addressed by path relative to the anchor, and
    /// `context` is the instance chain the anchor itself sits in — so the emitted id
    /// is composed exactly the way `render` composes it, and the two cannot drift.
    ///
    /// `anchorElementID` is the DOM id of the anchor's own element, used when a
    /// subject names the ANCHOR ITSELF. That is how a component's own relationships
    /// are expressed: the element carrying the role hosts the instance, so it IS the
    /// anchor, and nothing inside the source can stand for it.
    private func anchoredAttributes(
        _ relationships: [AnchoredRelationship],
        anchorID: UUID,
        anchorElementID: String,
        anchorChildren: [Node],
        anchorRole: AriaRole?,
        context: [UUID],
        availableDOMIDs: Set<String>,
        node: Node, sourceID: UUID?,
        issues: inout [SemanticHTMLFidelityIssue]
    ) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        /// Which subjects point at each target, so a target serving several
        /// subjects can be noticed once rather than per-subject.
        var subjectsPerTarget: [String: [UUID]] = [:]
        func role(of endpoint: RelationshipEndpoint) -> AriaRole? {
            if endpoint.isDirect, endpoint.nodeID == anchorID { return anchorRole }
            guard let resolved = document.resolveEndpoint(endpoint, in: anchorChildren)
            else { return nil }
            return document.roleForExport(of: resolved)
        }
        /// Fidelity issues belong to the relationship's SUBJECT, not whichever
        /// container happens to store the relationship. This matters most at the
        /// document root, where there is no real anchor node and the old fallback
        /// attributed every issue to an arbitrary first artboard layer.
        func diagnosticNode(for endpoint: RelationshipEndpoint) -> Node {
            if endpoint.isDirect, endpoint.nodeID == anchorID { return node }
            if let resolved = document.resolveEndpoint(endpoint, in: anchorChildren) {
                return resolved
            }
            // Preserve the missing subject's id in the report even when the layer
            // itself cannot be resolved. Geometry/content are diagnostic-only.
            return Node(id: endpoint.nodeID,
                        name: "Missing relationship subject",
                        frame: .zero,
                        content: .group(children: []))
        }
        for relationship in relationships {
            let subjectNode = diagnosticNode(for: relationship.subject)
            let subjectID: String
            if relationship.subject.isDirect, relationship.subject.nodeID == anchorID {
                subjectID = anchorElementID
            } else {
                subjectID = SemanticHTMLIdentity.nodeDOMID(
                    relationship.subject.nodeID,
                    chain: context + relationship.subject.instanceChain)
            }
            // Validate the SUBJECT as well as the target. Only the target used to
            // be checked, so a relationship whose subject layer had since been
            // deleted resolved to a DOM id nothing would ever emit — and then
            // vanished in total silence, with no fidelity issue and no trace in the
            // export. Found in a real file: three authored relationships had
            // evaporated exactly this way. Silent loss is the one thing a fidelity
            // tool must not do.
            guard availableDOMIDs.contains(subjectID) else {
                issues.append(issue(node: subjectNode, sourceID: sourceID,
                                    instanceID: context.last, role: nil,
                                    requirement: "orphanedRelationship",
                                    detail: "A \(relationship.kind.ariaAttribute) connection was authored on a layer that no longer exists, so nothing carries it. Remove it, or restore the layer."))
                continue
            }
            let targetID = SemanticHTMLIdentity.nodeDOMID(
                relationship.target.nodeID,
                chain: context + relationship.target.instanceChain)
            guard availableDOMIDs.contains(targetID) else {
                issues.append(issue(node: subjectNode, sourceID: sourceID,
                                    instanceID: context.last, role: nil,
                                    requirement: "unresolvedRelationship",
                                    detail: "\(relationship.kind.ariaAttribute) target \(relationship.target.nodeID.uuidString.lowercased()) is outside this artboard or missing."))
                continue
            }
            // ADVICE, not an error: the link resolves and the markup is valid, it
            // just points at an unexpected KIND of thing for this pattern. A
            // developer or a model reading this package would otherwise produce a
            // plausible-but-wrong component from it, with nothing flagging why.
            let subjectRole = role(of: relationship.subject)
            let expected = subjectRole?.expectedRelationshipTargetRoles(for: relationship.kind) ?? []
            if !expected.isEmpty {
                let actual = role(of: relationship.target)
                if actual == nil || !expected.contains(actual!) {
                    let wanted = expected.map(\.friendlyLabel).joined(separator: " or ")
                    let got = actual?.friendlyLabel ?? "a layer with no role"
                    issues.append(issue(node: subjectNode, sourceID: sourceID,
                                        instanceID: context.last, role: subjectRole,
                                        category: .advisory,
                                        requirement: "unexpectedRelationshipTarget",
                                        detail: "\(relationship.kind.ariaAttribute) on a \(subjectRole?.friendlyLabel ?? "layer") usually points at \(wanted); this one points at \(got). Valid markup, but check it is what you meant."))
                }
            }
            subjectsPerTarget[targetID, default: []].append(relationship.subject.nodeID)

            var attributes = result[subjectID] ?? [:]
            appendAttributeValue(targetID, name: relationship.kind.ariaAttribute,
                                 to: &attributes)
            result[subjectID] = attributes
        }

        // One panel serving several tabs. The APG describes a 1:1 pairing ("its
        // associated tabpanel"), but states no prohibition — so this is advice and
        // must stay advice. NOT VERIFIED that anything forbids it; do not promote
        // this to a requirement without finding text that does.
        for (targetID, subjects) in subjectsPerTarget where subjects.count > 1 {
            guard let match = relationships.first(where: { relationship in
                SemanticHTMLIdentity.nodeDOMID(relationship.target.nodeID,
                                               chain: context + relationship.target.instanceChain) == targetID
            }), role(of: match.target) == .tabpanel else { continue }
            issues.append(issue(node: diagnosticNode(for: match.subject), sourceID: sourceID,
                                instanceID: context.last, role: .tabpanel,
                                category: .advisory,
                                requirement: "sharedRelationshipTarget",
                                detail: "\(subjects.count) tabs point at the same Tab Panel. The WAI-APG tabs pattern pairs each tab with its own panel, so a downstream implementation may not behave as expected. Nothing here is invalid."))
        }
        return result
    }

    /// Merge anchor-contributed attributes into the inherited map. Later anchors do
    /// not replace earlier ones — a subject can legitimately be named by one anchor
    /// and described by another, so values ACCUMULATE per attribute.
    private func merging(_ inherited: [String: [String: String]],
                         _ added: [String: [String: String]]) -> [String: [String: String]] {
        var result = inherited
        for (domID, attributes) in added {
            var existing = result[domID] ?? [:]
            for (name, value) in attributes {
                for token in value.split(separator: " ").map(String.init) {
                    appendAttributeValue(token, name: name, to: &existing)
                }
            }
            result[domID] = existing
        }
        return result
    }


    private func applyActiveState(instance: ComponentInstance,
                                  source: ComponentSource,
                                  mapping: SemanticHTMLRoleMapping,
                                  attributes: inout [Attribute],
                                  node: Node,
                                  issues: inout [SemanticHTMLFidelityIssue]) {
        guard let stateID = instance.activeStateID else { return }
        guard let state = source.states.first(where: { $0.id == stateID }) else {
            issues.append(issue(node: node, sourceID: source.id, role: source.a11y.role,
                                requirement: "activeState",
                                detail: "The selected component state no longer exists."))
            return
        }
        switch SemanticHTMLStateSelector.forName(state.name) {
        case .dataState(let name):
            attributes.append(Attribute(name: "data-state", value: name))
        case .disabled:
            if mapping.tag == "button" {
                attributes.append(Attribute(name: "disabled", value: nil))
            } else {
                attributes.append(Attribute(name: "aria-disabled", value: "true"))
            }
        case .pseudoClass:
            break
        }
    }

    private func reportMissingRequirements(
        mapping: SemanticHTMLRoleMapping, role: AriaRole,
        semanticAttributes: [String: String],
        semanticAncestors: [AriaRole], node: Node, source: ComponentSource,
        issues: inout [SemanticHTMLFidelityIssue]
    ) {
        for requirement in mapping.requirements.sorted(by: { $0.rawValue < $1.rawValue }) {
            let fulfilled: Bool
            switch requirement {
            case .accessibleName:
                fulfilled = semanticAttributes["aria-labelledby"]?.isEmpty == false
            case .controlsRelationship:
                fulfilled = semanticAttributes["aria-controls"]?.isEmpty == false
            case .labelledByRelationship:
                fulfilled = semanticAttributes["aria-labelledby"]?.isEmpty == false
            case .describedByRelationship:
                fulfilled = semanticAttributes["aria-describedby"]?.isEmpty == false
            case .listOwnership:
                fulfilled = semanticAncestors.last == .list
            case .listStructure:
                // Visual source children are not silently promoted to list
                // items. Nested semantic components will satisfy this in v2.1.
                fulfilled = false
            case .headingLevel:
                fulfilled = Int(semanticAttributes["aria-level"] ?? "") != nil
            default:
                fulfilled = false
            }
            if !fulfilled {
                issues.append(issue(node: node, sourceID: source.id, role: role,
                                    requirement: requirement.rawValue,
                                    detail: "ARIA \(role.rawValue) still requires \(requirement.rawValue); EXP did not invent a value."))
            }
        }
        for state in source.states where state.overrides.contains(where: { $0.value.textValue != nil }) {
            issues.append(issue(node: node, sourceID: source.id, role: role,
                                requirement: "stateTextContent",
                                detail: "State ‘\(state.name)’ changes text; CSS cannot implement text content, so downstream code must apply it."))
        }
    }

    private func issue(node: Node, sourceID: UUID?,
                       instanceID: UUID? = nil, role: AriaRole?,
                       category: SemanticHTMLFidelityIssue.Category = .semanticRequirement,
                       requirement: String, detail: String) -> SemanticHTMLFidelityIssue {
        .init(artboardID: artboard.id, nodeID: node.id,
              instanceID: instanceID, sourceID: sourceID,
              role: role, category: category,
              requirement: requirement, detail: detail)
    }

    /// CSS/SVG covers the common geometry and paint path. Anything we cannot
    /// reproduce exactly is surfaced here instead of disappearing silently.
    private func reportVisualFallbacks(
        node: Node, sourceID: UUID?, instanceID: UUID?,
        issues: inout [SemanticHTMLFidelityIssue]
    ) {
        func report(_ requirement: String, _ detail: String) {
            issues.append(issue(node: node, sourceID: sourceID,
                                instanceID: instanceID, role: nil,
                                category: .visualFallback,
                                requirement: requirement, detail: detail))
        }
        func reportStrokeAlignment(_ alignment: StrokeAlignment) {
            report("strokeAlignment",
                   "The \(alignment.rawValue) stroke is approximated by the browser's available border/SVG stroke alignment.")
        }

        for effect in node.effects where effect.isEnabled {
            report("unsupportedEffect",
                   "The enabled \(effect.kind.rawValue) effect is preserved in design.json but is not reproduced by semantic HTML/CSS.")
        }
        if node.isMask {
            report("maskClippingApproximation",
                   "The mask group falls back to rectangular overflow clipping; its authored mask silhouette remains in design.json.")
        }
        if node.isMaskShape {
            report("maskShape",
                   "This mask-shape layer cannot drive the HTML clipping silhouette and may remain visible in the preview.")
        }

        switch node.content {
        case .rectangle(let shape):
            if shape.strokeWidth > 0, shape.strokeAlignment != .inside {
                reportStrokeAlignment(shape.strokeAlignment)
            }
        case .ellipse(let shape):
            if shape.strokeWidth > 0, shape.strokeAlignment != .inside {
                reportStrokeAlignment(shape.strokeAlignment)
            }
        case .polygon(let shape):
            if shape.strokeWidth > 0 {
                report("polygonStroke",
                       "The polygon fill is preserved with clip-path, but its stroke is not reproduced in semantic CSS.")
            }
        case .line(let line):
            let horizontal = abs(line.start.y - line.end.y) < 0.0001
                && abs(line.start.x) < 0.0001
                && abs(line.end.x - node.frame.width) < 0.0001
            if !horizontal {
                report("lineGeometry",
                       "A non-horizontal line is approximated by the layer's horizontal CSS border; exact endpoints remain in design.json.")
            }
        case .path(let shape):
            if shape.strokeWidth > 0, shape.strokeAlignment != .center {
                reportStrokeAlignment(shape.strokeAlignment)
            }
        case .group:
            if let padding = node.autoPadding,
               [padding.marginTop, padding.marginRight,
                padding.marginBottom, padding.marginLeft].contains(where: { $0 != 0 }) {
                report("autoLayoutMargin",
                       "Managed margins are folded into HTML padding; the transparent outer margin remains exact only in design.json.")
            }
            if let padding = node.autoPadding, padding.strokeWidth > 0,
               padding.strokeAlignment != .inside {
                reportStrokeAlignment(padding.strokeAlignment)
            }
        case .image(let image):
            if imageMediaTypeForFidelity(image.data) == "application/octet-stream" {
                report("unknownImageFormat",
                       "The embedded image format was not recognized as PNG, JPEG, GIF, or WebP.")
            }
        default:
            break
        }
    }

    private func imageMediaTypeForFidelity(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.count >= 12,
           Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46],
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        return "application/octet-stream"
    }

    private func allNodeIDs(_ nodes: [Node]) -> Set<UUID> {
        var result = Set<UUID>()
        func collect(_ node: Node) {
            result.insert(node.id)
            if case .group(let children) = node.content { children.forEach(collect) }
        }
        nodes.forEach(collect)
        return result
    }

    /// A Heading component may contain decoration as well as text. Resolve its
    /// level only when every explicitly headed descendant agrees; ambiguity is
    /// reported by the existing `headingLevel` fidelity requirement.
    private func unambiguousHeadingLevel(in nodes: [Node]) -> Int? {
        var levels = Set<Int>()
        func collect(_ node: Node) {
            if case .text(let text) = node.content,
               let level = text.contentRole.headingLevel {
                levels.insert(level)
            }
            if case .group(let children) = node.content {
                children.forEach(collect)
            }
        }
        nodes.forEach(collect)
        return levels.count == 1 ? levels.first : nil
    }

    private func appendAttributeValue(_ value: String, name: String,
                                      to attributes: inout [String: String]) {
        var values = attributes[name]?.split(separator: " ").map(String.init) ?? []
        if !values.contains(value) { values.append(value) }
        attributes[name] = values.joined(separator: " ")
    }

    private func append(_ semantic: [String: String],
                        to attributes: inout [Attribute]) {
        for (name, value) in semantic.sorted(by: { $0.key < $1.key }) {
            attributes.append(Attribute(name: name, value: value))
        }
    }

    private func attributes(_ attributes: [Attribute]) -> String {
        attributes.map { attribute in
            guard let value = attribute.value else { return " \(attribute.name)" }
            return " \(attribute.name)=\"\(SemanticHTMLEscape.attribute(value))\""
        }.joined()
    }

    private func svg(path: PathShape, domID: String, size: CGSize) -> String {
        let width = max(0.0001, size.width)
        let height = max(0.0001, size.height)
        let fills = path.isMultiContour || path.closed
        let fill: String
        let fillOpacity: String
        var definitions = ""
        if fills {
            switch path.fill {
            case .solid(let color):
                fill = "var(--exp-path-fill, \(svgColor(color)))"
                fillOpacity = "1"
            case .gradient(let gradient):
                let gradientID = "\(domID)-fill"
                definitions = svgGradient(gradient, id: gradientID,
                                          rect: CGRect(x: 0, y: 0,
                                                       width: width, height: height))
                fill = "url(#\(gradientID))"
                fillOpacity = "1"
            }
        } else {
            fill = "none"
            fillOpacity = "1"
        }
        let stroke = path.strokeWidth > 0
            ? " stroke=\"var(--exp-path-stroke, \(svgColor(path.stroke)))\" stroke-width=\"\(number(path.strokeWidth))\"\(svgStrokePattern(path.strokePattern, width: path.strokeWidth))"
            : ""
        let defs = definitions.isEmpty ? "" : "<defs>\(definitions)</defs>"
        return "<svg class=\"exp-path-svg\" viewBox=\"0 0 \(number(width)) \(number(height))\" preserveAspectRatio=\"none\" aria-hidden=\"true\" focusable=\"false\">\(defs)<path class=\"exp-path-shape\" d=\"\(svgPathData(path))\" fill=\"\(fill)\" fill-opacity=\"\(fillOpacity)\"\(stroke) stroke-linejoin=\"round\" stroke-linecap=\"round\"/></svg>"
    }

    private func svgStrokePattern(_ pattern: StrokePattern, width: CGFloat) -> String {
        switch pattern {
        case .solid: return ""
        case .dashed:
            return " stroke-dasharray=\"\(number(max(3, width * 3))) \(number(max(2, width * 2)))\" stroke-linecap=\"butt\""
        case .dotted:
            return " stroke-dasharray=\"0.001 \(number(max(2, width * 2.25)))\" stroke-linecap=\"round\""
        }
    }

    private func svgPathData(_ path: PathShape) -> String {
        func contour(_ points: [PathPoint], closed: Bool) -> String {
            guard let first = points.first else { return "" }
            var data = "M \(number(first.point.x)) \(number(first.point.y))"
            func segment(from previous: PathPoint, to current: PathPoint) {
                let control1 = previous.controlOut ?? previous.point
                let control2 = current.controlIn ?? current.point
                data += " C \(number(control1.x)) \(number(control1.y)) \(number(control2.x)) \(number(control2.y)) \(number(current.point.x)) \(number(current.point.y))"
            }
            for index in points.indices.dropFirst() {
                segment(from: points[index - 1], to: points[index])
            }
            if closed, points.count >= 2 {
                segment(from: points[points.count - 1], to: first)
                data += " Z"
            }
            return data
        }
        if path.isMultiContour {
            return path.renderContours.map { contour($0, closed: true) }
                .joined(separator: " ")
        }
        return contour(path.points, closed: path.closed)
    }

    private func svgGradient(_ gradient: GradientFill, id: String,
                             rect: CGRect) -> String {
        let stops = gradient.sortedStops.map { stop in
            "<stop offset=\"\(number(stop.position * 100))%\" stop-color=\"\(svgColor(stop.color))\"/>"
        }.joined()
        switch gradient.kind {
        case .linear:
            let points = gradient.linearPoints(in: rect)
            return "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(number(points.0.x))\" y1=\"\(number(points.0.y))\" x2=\"\(number(points.1.x))\" y2=\"\(number(points.1.y))\">\(stops)</linearGradient>"
        case .radial:
            let radius = hypot(rect.width / 2, rect.height / 2)
            return "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(number(rect.midX))\" cy=\"\(number(rect.midY))\" r=\"\(number(radius))\">\(stops)</radialGradient>"
        }
    }

    private func svgColor(_ color: RGBAColor) -> String {
        let red = Int((min(1, max(0, color.r)) * 255).rounded())
        let green = Int((min(1, max(0, color.g)) * 255).rounded())
        let blue = Int((min(1, max(0, color.b)) * 255).rounded())
        return "rgb(\(red) \(green) \(blue) / \(number(min(1, max(0, color.a)))))"
    }

    private func number<T: BinaryFloatingPoint>(_ value: T) -> String {
        let double = abs(Double(value)) < 0.000_000_1 ? 0 : Double(value)
        var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), double)
        while result.contains(".") && result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }

    private func contentName(_ content: NodeContent) -> String {
        switch content {
        case .group:     return "group"
        case .rectangle: return "rectangle"
        case .ellipse:   return "ellipse"
        case .polygon:   return "polygon"
        case .line:      return "line"
        case .path:      return "path"
        case .text:      return "text"
        case .instance:  return "instance"
        case .image:     return "image"
        }
    }

    /// Plain groups follow Layers-panel/frontmost-first reading order. Managed
    /// stacks follow their visual primary axis, independent of paint z-order.
    private func orderedChildren(_ children: [Node],
                                 autoLayout: AutoLayout?) -> [Node] {
        guard let autoLayout else { return Array(children.reversed()) }
        return children.enumerated().sorted { lhs, rhs in
            let a = autoLayout.direction == .horizontal
                ? lhs.element.frame.minX : lhs.element.frame.minY
            let b = autoLayout.direction == .horizontal
                ? rhs.element.frame.minX : rhs.element.frame.minY
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}

// MARK: - CSS

private struct CSSWriter {
    let document: Document
    private var rules: [String] = []

    init(document: Document) {
        self.document = document
    }

    mutating func append(artboard: Artboard,
                         topLevelNodes: [(offset: Int, element: Node)]) {
        let rootID = SemanticHTMLIdentity.artboardDOMID(artboard.id)
        rules.append(rule("#\(rootID)", [
            "width: \(number(artboard.frame.width))px",
            "height: \(number(artboard.frame.height))px",
            "background: \(paint(artboard.background))"
        ]))

        for item in topLevelNodes {
            append(node: item.element,
                   origin: CGPoint(x: item.element.frame.minX - artboard.frame.minX,
                                   y: item.element.frame.minY - artboard.frame.minY),
                   zIndex: item.offset + 1,
                   chain: [])
        }
    }

    func render() -> String {
        let header = """
        /* EXP semantic HTML/CSS format \(SemanticHTMLExporter.formatVersion).
           Free-positioned nodes retain absolute geometry; managed stacks use
           flexbox. Exact Design Language matches keep reusable token identity. */

        *, *::before, *::after {
          box-sizing: border-box;
        }

        html, body {
          margin: 0;
          min-width: 100%;
          min-height: 100%;
        }

        html {
          color-scheme: light dark;
        }

        body {
          width: max-content;
          color: #000;
          background: #d8d8d8;
          font-family: system-ui, sans-serif;
        }

        .exp-artboard {
          position: relative;
          overflow: hidden;
          isolation: isolate;
        }

        .exp-node {
          position: absolute;
          margin: 0;
          padding: 0;
          transform-origin: center;
        }

        .exp-group,
        .exp-instance {
          background: transparent;
        }

        button.exp-instance {
          border: 0;
          color: inherit;
          font: inherit;
          text-align: inherit;
        }

        [role="list"].exp-instance {
          list-style: none;
        }

        .exp-instance:focus-visible {
          outline: 3px solid currentColor;
          outline-offset: 2px;
        }

        .exp-text {
          white-space: pre-wrap;
          overflow-wrap: break-word;
        }

        .exp-path-svg {
          display: block;
          width: 100%;
          height: 100%;
          overflow: visible;
        }

        [hidden] {
          display: none !important;
        }

        @media (prefers-contrast: more) {
          .exp-artboard {
            outline: 2px solid currentColor;
            outline-offset: -2px;
          }

          .exp-instance:focus-visible {
            outline-width: 4px;
          }
        }
        """
        let designLanguage = DesignLanguageIO.exportCSS(document.designLanguage)
        return header + "\n\n" + designLanguage + "\n" + rules.joined(separator: "\n\n") + "\n"
    }

    /// - Parameter chain: the component instances above this node, outermost first.
    ///   MUST be composed the same way `render` composes it, or the CSS selector and
    ///   the element it is meant to style stop matching at nesting depth 2 — the
    ///   exact collision FEAT-012 chunk I-d exists to remove.
    private mutating func append(node: Node, origin: CGPoint, zIndex: Int,
                                 chain: [UUID], flexItem: Bool = false) {
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, chain: chain)
        var declarations = geometry(node: node, origin: origin, zIndex: zIndex,
                                    flexItem: flexItem)
        declarations.append(contentsOf: appearance(node))
        rules.append(rule("#\(id)", declarations))

        if case .text(let text) = node.content {
            let linked = DesignLanguageIO.firstTypeStyleBinding(
                matching: text, in: document.designLanguage) != nil
            for (index, run) in text.runs.enumerated() {
                var runRules = ["color: \(color(run.color))"]
                if !linked {
                    runRules.insert("font-size: \(number(run.fontSize))px", at: 0)
                    if !run.fontName.isEmpty {
                        runRules.append("font-family: \(cssString(run.fontName))")
                    }
                    if run.underline { runRules.append("text-decoration: underline") }
                }
                rules.append(rule("#\(id) > .exp-text-run-\(index)", runRules))
            }
        }

        switch node.content {
        case .group(let children):
            for (index, child) in children.enumerated() {
                append(node: child, origin: child.frame.origin, zIndex: index + 1,
                       chain: chain, flexItem: node.autoLayout != nil)
            }
        case .instance(let instance):
            let base = instance.withoutActiveState
            let baseChildren = document.semanticHTMLResolvedChildren(of: base)
            for (index, child) in baseChildren.enumerated() {
                append(node: child, origin: child.frame.origin, zIndex: index + 1,
                       chain: chain + [node.id])
            }
            appendStateRules(rootNode: node, rootDOMID: id, chain: chain + [node.id],
                             instance: base, baseChildren: baseChildren)
        default:
            break
        }
    }

    private mutating func appendStateRules(rootNode: Node, rootDOMID: String,
                                           chain: [UUID],
                                           instance: ComponentInstance,
                                           baseChildren: [Node]) {
        guard let source = document.source(for: instance.sourceID) else { return }
        var baseVisibility: [UUID: Bool] = [:]
        collectVisibility(baseChildren, into: &baseVisibility)
        for state in source.states {
            var stateInstance = instance
            stateInstance.activeStateID = state.id
            let children = document.semanticHTMLResolvedChildren(of: stateInstance)
            let prefix = stateRootSelector(rootID: rootDOMID, stateName: state.name,
                                           mapping: source.a11y.role?.semanticHTMLMapping)
            for (index, child) in children.enumerated() {
                appendState(node: child, origin: child.frame.origin,
                            zIndex: index + 1, chain: chain,
                            prefix: prefix, baseVisibility: baseVisibility)
            }
        }
    }

    private mutating func appendState(node: Node, origin: CGPoint, zIndex: Int,
                                      chain: [UUID], prefix: String,
                                      baseVisibility: [UUID: Bool],
                                      flexItem: Bool = false) {
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, chain: chain)
        var declarations = geometry(node: node, origin: origin, zIndex: zIndex,
                                    flexItem: flexItem)
        declarations.append(contentsOf: appearance(node))
        if baseVisibility[node.id] != node.isVisible {
            declarations.append(node.isVisible
                ? "display: block !important" : "display: none !important")
        }
        rules.append(rule("\(prefix) #\(id)", declarations))

        if case .text(let text) = node.content {
            let linked = DesignLanguageIO.firstTypeStyleBinding(
                matching: text, in: document.designLanguage) != nil
            for (index, run) in text.runs.enumerated() {
                var runRules = ["color: \(color(run.color))"]
                if !linked {
                    runRules.insert("font-size: \(number(run.fontSize))px", at: 0)
                    if !run.fontName.isEmpty { runRules.append("font-family: \(cssString(run.fontName))") }
                    if run.underline { runRules.append("text-decoration: underline") }
                }
                rules.append(rule("\(prefix) #\(id) > .exp-text-run-\(index)", runRules))
            }
        }
        if case .group(let children) = node.content {
            for (index, child) in children.enumerated() {
                appendState(node: child, origin: child.frame.origin,
                            zIndex: index + 1, chain: chain,
                            prefix: prefix, baseVisibility: baseVisibility,
                            flexItem: node.autoLayout != nil)
            }
        }
    }

    private func collectVisibility(_ nodes: [Node],
                                   into values: inout [UUID: Bool]) {
        for node in nodes {
            values[node.id] = node.isVisible
            if case .group(let children) = node.content {
                collectVisibility(children, into: &values)
            }
        }
    }

    private func stateRootSelector(rootID: String, stateName: String,
                                   mapping: SemanticHTMLRoleMapping?) -> String {
        switch SemanticHTMLStateSelector.forName(stateName) {
        case .pseudoClass(let pseudoClass):
            return "#\(rootID)\(pseudoClass)"
        case .disabled:
            return mapping?.tag == "button"
                ? "#\(rootID):disabled"
                : "#\(rootID)[aria-disabled=\"true\"]"
        case .dataState(let name):
            return "#\(rootID)[data-state=\(cssString(name))]"
        }
    }

    private func geometry(node: Node, origin: CGPoint, zIndex: Int,
                          flexItem: Bool) -> [String] {
        var declarations = [
            "width: \(number(node.frame.width))px",
            "height: \(number(node.frame.height))px",
            "z-index: \(zIndex)"
        ]
        if flexItem {
            declarations.insert("position: relative", at: 0)
            declarations.append("flex: 0 0 auto")
        } else {
            declarations.insert("top: \(number(origin.y))px", at: 0)
            declarations.insert("left: \(number(origin.x))px", at: 0)
        }
        var transforms: [String] = []
        if node.rotation != 0 { transforms.append("rotate(\(number(node.rotation))deg)") }
        if node.flipH { transforms.append("scaleX(-1)") }
        if node.flipV { transforms.append("scaleY(-1)") }
        if !transforms.isEmpty { declarations.append("transform: \(transforms.joined(separator: " "))") }
        if node.opacity != 1 { declarations.append("opacity: \(number(node.opacity))") }
        if node.blendMode != .normal { declarations.append("mix-blend-mode: \(node.blendMode.cssName)") }
        if node.isMask { declarations.append("overflow: hidden") }
        return declarations
    }

    private func appearance(_ node: Node) -> [String] {
        switch node.content {
        case .rectangle(let shape):
            var d = ["background: \(paint(shape.fill))"]
            d.append(contentsOf: border(color: shape.stroke, width: shape.strokeWidth,
                                        pattern: shape.strokePattern))
            let r = shape.effectiveRadii
            if !r.isZero {
                d.append("border-radius: \(number(r.topLeft))px \(number(r.topRight))px \(number(r.bottomRight))px \(number(r.bottomLeft))px")
            }
            return d
        case .ellipse(let shape):
            return ["background: \(paint(shape.fill))", "border-radius: 50%"]
                + border(color: shape.stroke, width: shape.strokeWidth,
                         pattern: shape.strokePattern)
        case .polygon(let shape):
            let points = shape.vertices(in: CGRect(origin: .zero, size: node.frame.size))
            let pairs = points.map {
                "\(number(node.frame.width == 0 ? 0 : $0.x / node.frame.width * 100))% \(number(node.frame.height == 0 ? 0 : $0.y / node.frame.height * 100))%"
            }.joined(separator: ", ")
            return ["background: \(paint(shape.fill))", "clip-path: polygon(\(pairs))"]
        case .path(let shape):
            var declarations: [String] = []
            if shape.closed || shape.isMultiContour,
               case .solid(let fill) = shape.fill {
                declarations.append("--exp-path-fill: \(color(fill))")
            }
            if shape.strokeWidth > 0 {
                declarations.append("--exp-path-stroke: \(color(shape.stroke))")
            }
            return declarations
        case .line(let shape):
            return ["border-top: \(number(shape.strokeWidth))px \(cssStrokePattern(shape.strokePattern)) \(color(shape.stroke))"]
        case .text(let text):
            if DesignLanguageIO.firstTypeStyleBinding(
                matching: text, in: document.designLanguage) != nil { return [] }
            var d = ["text-align: \(text.align.rawValue)",
                     "letter-spacing: \(number(text.tracking))px"]
            switch text.lineHeightUnit {
            case .auto:     d.append("line-height: normal")
            case .multiple: d.append("line-height: \(number(text.lineHeight))")
            case .px:       d.append("line-height: \(number(text.lineHeight))px")
            case .em:       d.append("line-height: \(number(text.lineHeight))em")
            }
            return d
        case .image(let image):
            let mime = imageMediaType(image.data)
            return ["background-image: url(\"data:\(mime);base64,\(image.data.base64EncodedString())\")",
                    "background-size: 100% 100%", "background-repeat: no-repeat"]
        case .group:
            var d: [String] = []
            if let layout = node.autoLayout {
                d.append("display: flex")
                d.append("flex-direction: \(layout.direction == .horizontal ? "row" : "column")")
                if layout.distribution == .spaceBetween {
                    d.append("justify-content: space-between")
                } else {
                    d.append("justify-content: \(flexAlignment(layout.primary))")
                    d.append("gap: \(number(layout.gap))px")
                }
                d.append("align-items: \(flexAlignment(layout.cross))")
            }
            guard let padding = node.autoPadding else { return d }
            if node.autoLayout != nil {
                let top = padding.paddingTop + padding.marginTop
                let right = padding.paddingRight + padding.marginRight
                let bottom = padding.paddingBottom + padding.marginBottom
                let left = padding.paddingLeft + padding.marginLeft
                d.append("padding: \(number(top))px \(number(right))px \(number(bottom))px \(number(left))px")
            }
            if let fill = padding.fill { d.append("background: \(paint(fill))") }
            if padding.cornerRadius > 0 { d.append("border-radius: \(number(padding.cornerRadius))px") }
            if let stroke = padding.stroke {
                d += border(color: stroke, width: padding.strokeWidth,
                            pattern: padding.strokePattern)
            }
            return d
        case .instance:
            return []
        }
    }

    private func border(color: RGBAColor, width: CGFloat,
                        pattern: StrokePattern = .solid) -> [String] {
        width > 0 ? ["border: \(number(width))px \(cssStrokePattern(pattern)) \(self.color(color))"] : []
    }

    private func cssStrokePattern(_ pattern: StrokePattern) -> String {
        switch pattern { case .solid: return "solid"; case .dashed: return "dashed"; case .dotted: return "dotted" }
    }

    private func paint(_ value: Paint) -> String {
        if let binding = DesignLanguageIO.firstAssetBinding(
            matching: value, in: document.designLanguage) {
            return "var(--\(binding.variableName), \(paintFallback(value)))"
        }
        return paintFallback(value)
    }

    private func paintFallback(_ value: Paint) -> String {
        switch value {
        case .solid(let c):
            return color(c)
        case .gradient(let gradient):
            let stops = gradient.sortedStops.map {
                "\(color($0.color)) \(number($0.position * 100))%"
            }.joined(separator: ", ")
            switch gradient.kind {
            case .linear: return "linear-gradient(\(number(cssGradientAngle(gradient.angle)))deg, \(stops))"
            case .radial: return "radial-gradient(circle, \(stops))"
            }
        }
    }

    private func color(_ c: RGBAColor) -> String {
        if let binding = DesignLanguageIO.firstAssetBinding(
            matching: .solid(c), in: document.designLanguage) {
            return "var(--\(binding.variableName), \(colorFallback(c)))"
        }
        return colorFallback(c)
    }

    private func colorFallback(_ c: RGBAColor) -> String {
        let r = Int((min(1, max(0, c.r)) * 255).rounded())
        let g = Int((min(1, max(0, c.g)) * 255).rounded())
        let b = Int((min(1, max(0, c.b)) * 255).rounded())
        return "rgb(\(r) \(g) \(b) / \(number(min(1, max(0, c.a)))))"
    }

    private func flexAlignment(_ alignment: AutoLayout.Align) -> String {
        switch alignment {
        case .start: return "flex-start"
        case .center: return "center"
        case .end: return "flex-end"
        }
    }

    /// EXP angles live in a y-down canvas (0° points right, 90° points down).
    /// CSS angles point up at 0° and rotate clockwise, so add a quarter turn.
    private func cssGradientAngle(_ expAngle: Double) -> Double {
        let normalized = (expAngle + 90).truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private func imageMediaType(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.count >= 12,
           Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46],
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        return "application/octet-stream"
    }

    private func cssString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0: result += "\\fffd "
            case 10, 13, 12: result += "\\a "
            case 34: result += "\\22 "
            case 92: result += "\\5c "
            default: result.unicodeScalars.append(scalar)
            }
        }
        result.append("\"")
        return result
    }

    private func rule(_ selector: String, _ declarations: [String]) -> String {
        guard !declarations.isEmpty else { return "\(selector) {}" }
        return selector + " {\n" + declarations.map { "  \($0);" }.joined(separator: "\n") + "\n}"
    }

    private func number<T: BinaryFloatingPoint>(_ value: T) -> String {
        let double = abs(Double(value)) < 0.000_000_1 ? 0 : Double(value)
        var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), double)
        while result.contains(".") && result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}

// The canvas renderer drops invisible source layers for speed. Semantic export
// keeps them in the DOM with `hidden`, because stable relationships must remain
// addressable and a later component state may reveal them.
extension Document {
    func semanticHTMLResolvedChildren(of instance: ComponentInstance) -> [Node] {
        guard let source = source(for: instance.sourceID) else { return [] }
        let effective = instance.applyingState(instance.activeStateID.flatMap { stateID in
            source.states.first { $0.id == stateID }
        })
        let resolved = source.children
            .map { semanticHTMLResolvedNode($0, instance: effective) }
            // FEAT-017 chunk J-d. This is a PARALLEL resolver — it keeps hidden
            // layers so it can emit `hidden`, which is why it does not call
            // `resolvedChildren` — and that meant J-b's push-down never reached the
            // HTML. Same call, same position (before the reflow, so a re-hug
            // measures the overridden content). If a third resolver ever appears,
            // it needs this line too; the duplication is the hazard here, not the
            // logic.
            .map { Document.pushingNestedOverrides(effective.nestedOverrides, into: $0) }
        let laid = reflowed(resolved)
        let bounds = sourceUsesManagedBounds(source)
            ? (managedRootBounds(in: laid) ?? source.bounds)
            : source.bounds
        guard bounds.origin != .zero else { return laid }
        return laid.map { node in
            var shifted = node
            shifted.frame.origin.x -= bounds.origin.x
            shifted.frame.origin.y -= bounds.origin.y
            return shifted
        }
    }

    func semanticHTMLResolvedNode(_ original: Node,
                                  instance: ComponentInstance) -> Node {
        var node = original
        node.isVisible = instance.isLayerVisible(node.id, sourceDefault: node.isVisible)
        for override in instance.overrides where override.targetNodeID == node.id {
            switch override.value {
            case .text(let string):
                if case .text(var text) = node.content {
                    text.setPlainString(string)
                    node.content = .text(text)
                    node.frame.size = text.measuredSize(boxWidth: node.frame.width)
                }
            case .fill(let fill):
                switch node.content {
                case .rectangle(var shape): shape.fill = fill; node.content = .rectangle(shape)
                case .ellipse(var shape):   shape.fill = fill; node.content = .ellipse(shape)
                case .polygon(var shape):   shape.fill = fill; node.content = .polygon(shape)
                case .path(var shape):      shape.fill = fill; node.content = .path(shape)
                case .group:
                    if node.autoPadding != nil { node.autoPadding?.fill = fill }
                default:
                    break
                }
            case .textStyle(let style):
                // Per-state typography. The state CSS emitter re-resolves the node
                // in each state and writes full run/appearance declarations, so
                // folding the style in here is all that handoff needs.
                if case .text(var text) = node.content {
                    text = style.applied(to: text)
                    node.content = .text(text)
                    if style.affectsMetrics {
                        node.frame.size = text.measuredSize(boxWidth: node.frame.width)
                    }
                }
            case .opacity(let value):
                // geometry() emits `opacity` from the resolved node, so per-state
                // opacity flows into the state rule automatically.
                node.opacity = value
            case .blendMode(let value):
                // visualDeclarations() emits mix-blend-mode from the resolved
                // node, so state-local compositing reaches the generated CSS.
                node.blendMode = value
            case .stroke(let stroke):
                switch node.content {
                case .rectangle(var shape): shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .rectangle(shape)
                case .ellipse(var shape):   shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .ellipse(shape)
                case .polygon(var shape):   shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .polygon(shape)
                case .path(var shape):      shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .path(shape)
                case .line(var shape):      shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokePattern = stroke.pattern ?? .solid; node.content = .line(shape)
                case .group:
                    if node.autoPadding != nil {
                        node.autoPadding?.stroke = stroke.color
                        node.autoPadding?.strokeWidth = stroke.width
                        node.autoPadding?.strokeAlignment = stroke.alignment
                        node.autoPadding?.strokePattern = stroke.pattern ?? .solid
                    }
                default: break
                }
            case .componentState(let stateID):
                if case .instance(var nested) = node.content {
                    nested.activeStateID = stateID
                    node.content = .instance(nested)
                }
            }
        }
        if case .group(let children) = node.content {
            node.content = .group(children: children.map {
                semanticHTMLResolvedNode($0, instance: instance)
            })
        }
        return node
    }
}

private extension ComponentInstance {
    var withoutActiveState: ComponentInstance {
        var copy = self
        copy.activeStateID = nil
        return copy
    }
}

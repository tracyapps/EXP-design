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
    var artboardID: UUID
    var nodeID: UUID
    var sourceID: UUID?
    var role: AriaRole?
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

    func makeBundle() -> SemanticHTMLBundle {
        var css = CSSWriter(document: document)
        var artifacts: [SemanticHTMLArtifact] = []
        var pages: [String] = []
        var emittedNodeCount = 0
        var fidelityIssues: [SemanticHTMLFidelityIssue] = []

        for artboard in document.artboards {
            let owned = document.nodes.enumerated().filter {
                document.owningArtboard(of: $0.element.frame)?.id == artboard.id
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

        let omitted = document.nodes
            .filter { document.owningArtboard(of: $0.frame) == nil }
            .reduce(0) { $0 + Self.nodeCount($1) }
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
        let nodeHTML = topLevelNodes.reversed().map { item in
            render(node: item.element, instanceID: nil, sourceID: nil,
                   instanceNodeIDs: nil, semanticAncestors: [],
                   availableDOMIDs: available, level: 2,
                   count: &count, issues: &issues)
        }.joined(separator: "\n")
        let note = artboard.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = note.isEmpty ? "" : "  <!-- EXP artboard notes: \(SemanticHTMLEscape.comment(note)) -->\n"
        let title = SemanticHTMLEscape.text(artboard.name)
        let rootID = SemanticHTMLIdentity.artboardDOMID(artboard.id)
        let rootName = SemanticHTMLEscape.attribute(artboard.name)

        let html = """
        <!doctype html>
        <html>
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

    private func render(node: Node, instanceID: UUID?, sourceID: UUID?,
                        instanceNodeIDs: Set<UUID>?,
                        semanticAncestors: [AriaRole],
                        availableDOMIDs: Set<String>, level: Int,
                        count: inout Int,
                        issues: inout [SemanticHTMLFidelityIssue]) -> String {
        count += 1
        let indent = String(repeating: "  ", count: level)
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, instanceID: instanceID)
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

        let relationships = relationshipAttributes(
            node: node, instanceID: instanceID,
            instanceNodeIDs: instanceNodeIDs,
            availableDOMIDs: availableDOMIDs,
            sourceID: sourceID, issues: &issues)

        switch node.content {
        case .group(let children):
            let childHTML = orderedChildren(children, autoLayout: node.autoLayout).map {
                render(node: $0, instanceID: instanceID, sourceID: sourceID,
                       instanceNodeIDs: instanceNodeIDs,
                       semanticAncestors: semanticAncestors,
                       availableDOMIDs: availableDOMIDs, level: level + 1,
                       count: &count, issues: &issues)
            }.joined(separator: "\n")
            var attrs = common
            let layoutClass = node.autoLayout == nil ? "" : " exp-auto-layout"
            attrs.append(Attribute(name: "class", value: "exp-node exp-group\(layoutClass)"))
            attrs.append(Attribute(name: "data-exp-content", value: "group"))
            append(relationships, to: &attrs)
            return "\(indent)<div\(attributes(attrs))>\n\(childHTML)\n\(indent)</div>"

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
                return "\(indent)<div\(attributes(attrs))></div>"
            }

            let baseInstance = instance.withoutActiveState
            let children = document.semanticHTMLResolvedChildren(of: baseInstance)
            let sourceNodeIDs = allNodeIDs(source.children)
            let role = source.a11y.role
            let mapping = role?.semanticHTMLMapping
            let tag = mapping?.tag ?? "div"
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-instance"))
            attrs.append(Attribute(name: "data-exp-content", value: "instance"))
            attrs.append(Attribute(name: "data-exp-source-id", value: source.id.uuidString.lowercased()))

            var semanticAttributes = relationships
            if let labelID = source.a11y.accessibleNameLayerID {
                let target = SemanticHTMLIdentity.nodeDOMID(labelID, instanceID: node.id)
                if sourceNodeIDs.contains(labelID), availableDOMIDs.contains(target) {
                    appendAttributeValue(target, name: "aria-labelledby",
                                         to: &semanticAttributes)
                } else {
                    issues.append(issue(node: node, sourceID: source.id, role: role,
                                        requirement: "accessibleName",
                                        detail: "The configured accessible-name layer is missing from this instance."))
                }
            }
            if let mapping, let role {
                if role == .heading,
                   let level = unambiguousHeadingLevel(in: children) {
                    semanticAttributes["aria-level"] = String(level)
                }
                for (name, value) in mapping.fixedAttributes.sorted(by: { $0.key < $1.key }) {
                    attrs.append(Attribute(name: name, value: value))
                }
                var explicitRole = mapping.explicitRole
                if (role == .banner || role == .contentinfo), !semanticAncestors.isEmpty {
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
                render(node: $0, instanceID: node.id, sourceID: source.id,
                       instanceNodeIDs: sourceNodeIDs,
                       semanticAncestors: role.map { semanticAncestors + [$0] }
                           ?? semanticAncestors,
                       availableDOMIDs: availableDOMIDs, level: level + 1,
                       count: &count, issues: &issues)
            }.joined(separator: "\n")
            return "\(indent)<\(tag)\(attributes(attrs))>\n\(childHTML)\n\(indent)</\(tag)>"

        case .text(let text):
            let runs = text.runs.enumerated().map { index, run in
                let content = SemanticHTMLEscape.text(text.textCase.apply(run.string))
                return "<span class=\"exp-text-run exp-text-run-\(index)\">\(content)</span>"
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
            let tag = semanticAncestors.last == .heading ? "span" : text.contentRole.htmlTag
            return "\(indent)<\(tag)\(attributes(attrs))>\(runs)</\(tag)>"

        case .path(let path):
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-path"))
            attrs.append(Attribute(name: "data-exp-content", value: "path"))
            append(relationships, to: &attrs)
            return "\(indent)<div\(attributes(attrs))>\(svg(path: path, domID: id, size: node.frame.size))</div>"

        default:
            let kind = contentName(node.content)
            var attrs = common
            attrs.append(Attribute(name: "class", value: "exp-node exp-\(kind)"))
            attrs.append(Attribute(name: "data-exp-content", value: kind))
            append(relationships, to: &attrs)
            return "\(indent)<div\(attributes(attrs))></div>"
        }
    }

    private func availableDOMIDs() -> Set<String> {
        var result = Set<String>()
        for item in topLevelNodes {
            collectDOMIDs(node: item.element, instanceID: nil, into: &result)
        }
        return result
    }

    private func collectDOMIDs(node: Node, instanceID: UUID?,
                               into result: inout Set<String>) {
        result.insert(SemanticHTMLIdentity.nodeDOMID(node.id, instanceID: instanceID))
        switch node.content {
        case .group(let children):
            for child in children { collectDOMIDs(node: child, instanceID: instanceID, into: &result) }
        case .instance(let instance):
            for child in document.semanticHTMLResolvedChildren(of: instance.withoutActiveState) {
                collectDOMIDs(node: child, instanceID: node.id, into: &result)
            }
        default:
            break
        }
    }

    private func relationshipAttributes(
        node: Node, instanceID: UUID?, instanceNodeIDs: Set<UUID>?,
        availableDOMIDs: Set<String>, sourceID: UUID?,
        issues: inout [SemanticHTMLFidelityIssue]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for relationship in node.relationships {
            let target = SemanticHTMLIdentity.nodeDOMID(
                relationship.targetID,
                instanceID: instanceID != nil && instanceNodeIDs?.contains(relationship.targetID) == true
                    ? instanceID : nil)
            guard availableDOMIDs.contains(target) else {
                issues.append(issue(node: node, sourceID: sourceID, role: nil,
                                    requirement: "unresolvedRelationship",
                                    detail: "\(relationship.kind.ariaAttribute) target \(relationship.targetID.uuidString.lowercased()) is outside this artboard or missing."))
                continue
            }
            appendAttributeValue(target, name: relationship.kind.ariaAttribute,
                                 to: &result)
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

    private func issue(node: Node, sourceID: UUID?, role: AriaRole?,
                       requirement: String, detail: String) -> SemanticHTMLFidelityIssue {
        .init(artboardID: artboard.id, nodeID: node.id, sourceID: sourceID,
              role: role, requirement: requirement, detail: detail)
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
            ? " stroke=\"var(--exp-path-stroke, \(svgColor(path.stroke)))\" stroke-width=\"\(number(path.strokeWidth))\""
            : ""
        let defs = definitions.isEmpty ? "" : "<defs>\(definitions)</defs>"
        return "<svg class=\"exp-path-svg\" viewBox=\"0 0 \(number(width)) \(number(height))\" preserveAspectRatio=\"none\" aria-hidden=\"true\" focusable=\"false\">\(defs)<path class=\"exp-path-shape\" d=\"\(svgPathData(path))\" fill=\"\(fill)\" fill-opacity=\"\(fillOpacity)\"\(stroke) stroke-linejoin=\"round\" stroke-linecap=\"round\"/></svg>"
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
                   instanceID: nil)
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

        ul.exp-instance {
          list-style: none;
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
        """
        let designLanguage = DesignLanguageIO.exportCSS(document.designLanguage)
        return header + "\n\n" + designLanguage + "\n" + rules.joined(separator: "\n\n") + "\n"
    }

    private mutating func append(node: Node, origin: CGPoint, zIndex: Int,
                                 instanceID: UUID?, flexItem: Bool = false) {
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, instanceID: instanceID)
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
                       instanceID: instanceID, flexItem: node.autoLayout != nil)
            }
        case .instance(let instance):
            let base = instance.withoutActiveState
            let baseChildren = document.semanticHTMLResolvedChildren(of: base)
            for (index, child) in baseChildren.enumerated() {
                append(node: child, origin: child.frame.origin, zIndex: index + 1,
                       instanceID: node.id)
            }
            appendStateRules(rootNode: node, rootDOMID: id, instance: base,
                             baseChildren: baseChildren)
        default:
            break
        }
    }

    private mutating func appendStateRules(rootNode: Node, rootDOMID: String,
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
                            zIndex: index + 1, instanceID: rootNode.id,
                            prefix: prefix, baseVisibility: baseVisibility)
            }
        }
    }

    private mutating func appendState(node: Node, origin: CGPoint, zIndex: Int,
                                      instanceID: UUID, prefix: String,
                                      baseVisibility: [UUID: Bool],
                                      flexItem: Bool = false) {
        let id = SemanticHTMLIdentity.nodeDOMID(node.id, instanceID: instanceID)
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
                            zIndex: index + 1, instanceID: instanceID,
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
            d.append(contentsOf: border(color: shape.stroke, width: shape.strokeWidth))
            let r = shape.effectiveRadii
            if !r.isZero {
                d.append("border-radius: \(number(r.topLeft))px \(number(r.topRight))px \(number(r.bottomRight))px \(number(r.bottomLeft))px")
            }
            return d
        case .ellipse(let shape):
            return ["background: \(paint(shape.fill))", "border-radius: 50%"]
                + border(color: shape.stroke, width: shape.strokeWidth)
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
            return ["border-top: \(number(shape.strokeWidth))px solid \(color(shape.stroke))"]
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
            if let stroke = padding.stroke { d += border(color: stroke, width: padding.strokeWidth) }
            return d
        case .instance:
            return []
        }
    }

    private func border(color: RGBAColor, width: CGFloat) -> [String] {
        width > 0 ? ["border: \(number(width))px solid \(self.color(color))"] : []
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
private extension Document {
    func semanticHTMLResolvedChildren(of instance: ComponentInstance) -> [Node] {
        guard let source = source(for: instance.sourceID) else { return [] }
        let effective = instance.applyingState(instance.activeStateID.flatMap { stateID in
            source.states.first { $0.id == stateID }
        })
        let resolved = source.children.map { semanticHTMLResolvedNode($0, instance: effective) }
        let laid = AutoLayoutEngine.reflowed(resolved)
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
                    node.frame.size = text.measuredSize()
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

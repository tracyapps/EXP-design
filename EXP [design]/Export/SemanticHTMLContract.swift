//
//  SemanticHTMLContract.swift
//  EXP [design]
//
//  v2.0 Chunk B0: deterministic semantics shared by HTML export and the later
//  HTML import codec. This file contains decisions, not rendering. B1 consumes
//  these mappings when it writes per-artboard HTML and shared CSS.
//

import Foundation

enum SemanticHTMLRequirement: String, CaseIterable, Sendable {
    case accessibleName
    case href
    case checkedState
    case selectedState
    case rangeValues
    case headingLevel
    case listOwnership
    case listStructure
    case tableStructure
    case controlsRelationship
    case labelledByRelationship
    case describedByRelationship
    case textInputImplementation
}

struct SemanticHTMLRoleMapping: Equatable, Sendable {
    /// Preferred host element. Native elements are used only when EXP can emit
    /// them without invalid child structure or invented model data.
    var tag: String
    /// Nil means the host element already supplies the intended implicit role.
    /// A value is emitted when native HTML cannot honestly carry the contract.
    var explicitRole: AriaRole?
    /// Safe, deterministic attributes that do not fabricate behavior/data.
    var fixedAttributes: [String: String] = [:]
    /// Missing model facts that B1 must report rather than silently invent.
    var requirements: Set<SemanticHTMLRequirement> = []
}

extension AriaRole {
    /// Native-first mapping, constrained by what EXP currently models. The
    /// explicit ARIA fallbacks intentionally keep arbitrary component artwork as
    /// descendants; void elements such as input/img cannot do that safely.
    var semanticHTMLMapping: SemanticHTMLRoleMapping {
        switch self {
        // Landmarks / regions with honest native containers.
        case .banner:        return .init(tag: "header")
        case .navigation:    return .init(tag: "nav")
        case .main:          return .init(tag: "main")
        case .complementary: return .init(tag: "aside")
        case .contentinfo:   return .init(tag: "footer")
        case .search:        return .init(tag: "search")
        case .form:          return .init(tag: "form", requirements: [.accessibleName])
        case .region:        return .init(tag: "section", requirements: [.accessibleName])

        // Widgets. Button is complete as a host; the remaining roles need model
        // facts EXP does not yet store, so the handoff reports those requirements.
        case .button:
            return .init(tag: "button", fixedAttributes: ["type": "button"])
        case .link:
            return .init(tag: "a", explicitRole: .link, requirements: [.href])
        case .checkbox:
            return .init(tag: "button", explicitRole: .checkbox,
                         fixedAttributes: ["type": "button"], requirements: [.checkedState])
        case .radio:
            return .init(tag: "button", explicitRole: .radio,
                         fixedAttributes: ["type": "button"], requirements: [.checkedState])
        case .switch:
            return .init(tag: "button", explicitRole: .switch,
                         fixedAttributes: ["type": "button"], requirements: [.checkedState])
        case .textbox:
            return .init(tag: "div", explicitRole: .textbox,
                         requirements: [.accessibleName, .textInputImplementation])
        case .searchbox:
            return .init(tag: "div", explicitRole: .searchbox,
                         requirements: [.accessibleName, .textInputImplementation])
        case .slider:
            return .init(tag: "div", explicitRole: .slider,
                         requirements: [.accessibleName, .rangeValues])
        case .spinbutton:
            return .init(tag: "div", explicitRole: .spinbutton,
                         requirements: [.accessibleName, .rangeValues])
        case .progressbar:
            return .init(tag: "div", explicitRole: .progressbar,
                         requirements: [.accessibleName, .rangeValues])
        case .tooltip:
            return .init(tag: "div", explicitRole: .tooltip,
                         requirements: [.describedByRelationship])

        // Composite widgets keep an explicit public ARIA contract. EXP exports
        // no JavaScript; downstream implementation follows the WAI-APG pattern.
        case .tablist:
            return .init(tag: "div", explicitRole: .tablist,
                         requirements: [.accessibleName])
        case .tab:
            return .init(tag: "button", explicitRole: .tab,
                         fixedAttributes: ["type": "button"],
                         requirements: [.selectedState, .controlsRelationship])
        case .tabpanel:
            return .init(tag: "section", explicitRole: .tabpanel,
                         requirements: [.labelledByRelationship])
        case .menu:       return .init(tag: "div", explicitRole: .menu)
        case .menubar:    return .init(tag: "div", explicitRole: .menubar)
        case .menuitem:
            return .init(tag: "button", explicitRole: .menuitem,
                         fixedAttributes: ["type": "button"])
        case .listbox:
            return .init(tag: "div", explicitRole: .listbox,
                         requirements: [.accessibleName])
        case .option:
            return .init(tag: "div", explicitRole: .option,
                         requirements: [.selectedState])
        case .radiogroup:
            return .init(tag: "div", explicitRole: .radiogroup,
                         requirements: [.accessibleName])
        case .toolbar:
            return .init(tag: "div", explicitRole: .toolbar,
                         requirements: [.accessibleName])
        case .dialog:
            return .init(tag: "div", explicitRole: .dialog,
                         requirements: [.accessibleName])
        case .alertdialog:
            return .init(tag: "div", explicitRole: .alertdialog,
                         requirements: [.accessibleName])
        case .alert:      return .init(tag: "div", explicitRole: .alert)
        case .tree:
            return .init(tag: "div", explicitRole: .tree,
                         requirements: [.accessibleName])
        case .treeitem:
            return .init(tag: "div", explicitRole: .treeitem,
                         requirements: [.selectedState])
        case .grid:
            return .init(tag: "div", explicitRole: .grid,
                         requirements: [.accessibleName, .tableStructure])

        // Document structure. Heading level and table/list ownership are never
        // guessed: the generated markup carries the role and reports the gap.
        case .heading:
            return .init(tag: "div", explicitRole: .heading,
                         requirements: [.headingLevel])
        // Source children are visual layers, not authored list items. A div
        // keeps the HTML content model valid while the fidelity report carries
        // the missing structural work explicitly.
        case .list:
            return .init(tag: "div", explicitRole: .list,
                         requirements: [.listStructure])
        case .listitem:
            return .init(tag: "div", explicitRole: .listitem,
                         requirements: [.listOwnership])
        case .img:
            return .init(tag: "div", explicitRole: .img,
                         requirements: [.accessibleName])
        case .figure:     return .init(tag: "figure")
        case .table:
            return .init(tag: "div", explicitRole: .table,
                         requirements: [.accessibleName, .tableStructure])
        case .separator:  return .init(tag: "div", explicitRole: .separator)
        case .group:      return .init(tag: "div", explicitRole: .group)
        // Table parts stay on div hosts to match the div-based `table`/`grid`
        // above: native <tr>/<td> are only valid inside a native <table>, and
        // emitting one without the other would produce markup the browser
        // silently reparents. Promoting the whole family to native elements is
        // its own change, once authored rows/cells are common enough to rely on.
        case .row:          return .init(tag: "div", explicitRole: .row)
        case .cell:         return .init(tag: "div", explicitRole: .cell)
        case .columnheader: return .init(tag: "div", explicitRole: .columnheader)
        case .rowheader:    return .init(tag: "div", explicitRole: .rowheader)
        }
    }
}

enum SemanticHTMLIdentity {
    static func artboardDOMID(_ id: UUID) -> String {
        "exp-artboard-\(uuid(id))"
    }

    /// Source-layer UUIDs repeat in every component instance, so a DOM id has to be
    /// composed from the INSTANCE CHAIN above the node, outermost first.
    ///
    /// This used to carry a single instance id, which is exact at one level of
    /// nesting and COLLIDES below it: two placements of the same component inside a
    /// third would mint identical ids for their children. Passing the whole chain
    /// makes the id unique at any depth and matches how `RelationshipEndpoint`
    /// addresses things, so a relationship and the element it names agree by
    /// construction (FEAT-012 chunk I-d).
    ///
    /// Depth-1 output is unchanged (`exp-<instance>-<node>`), so existing exports
    /// keep their ids; only the previously-colliding cases move.
    static func nodeDOMID(_ nodeID: UUID, chain: [UUID]) -> String {
        guard !chain.isEmpty else { return "exp-\(uuid(nodeID))" }
        return "exp-" + chain.map(uuid).joined(separator: "-") + "-\(uuid(nodeID))"
    }

    /// Single-level convenience. Kept because plenty of call sites legitimately
    /// know only the immediate host.
    static func nodeDOMID(_ nodeID: UUID, instanceID: UUID? = nil) -> String {
        nodeDOMID(nodeID, chain: instanceID.map { [$0] } ?? [])
    }

    static func artboardFilename(name: String, id: UUID) -> String {
        let base = slug(name, fallback: "artboard")
        return "\(base)--\(uuid(id)).html"
    }

    static func slug(_ value: String, fallback: String) -> String {
        var result = ""
        var pendingDash = false
        for character in value.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingDash, !result.isEmpty { result.append("-") }
                result.append(character)
                pendingDash = false
            } else if !result.isEmpty {
                pendingDash = true
            }
        }
        return result.isEmpty ? fallback : result
    }

    private static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }
}

enum SemanticHTMLStateSelector: Equatable, Sendable {
    case pseudoClass(String)
    case disabled
    case dataState(String)

    static func forName(_ name: String) -> Self {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hover":    return .pseudoClass(":hover")
        case "pressed":  return .pseudoClass(":active")
        case "focus":    return .pseudoClass(":focus-visible")
        case "disabled": return .disabled
        default:          return .dataState(name)
        }
    }
}

enum SemanticHTMLEscape {
    static func text(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func attribute(_ value: String) -> String {
        text(value).replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// HTML comments cannot contain `--` or end in `-`. Notes remain readable,
    /// but never get a chance to terminate the generated comment early.
    static func comment(_ value: String) -> String {
        var safe = value.replacingOccurrences(of: "--", with: "—")
        if safe.hasSuffix("-") { safe.append(" ") }
        return safe
    }
}

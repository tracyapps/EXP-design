//
//  SanaaEdits.swift
//  EXP [design]
//
//  FEAT-048 — Sanaa's write-back spine (chunk F3 on the shipped agent bridge).
//
//  ONE transactional tool, `apply_edits`. The designer's own MCP agent reaches
//  in and draws; EXP ships no LLM, holds no API keys, and this file opens no
//  network path of any kind. Nothing here does anything unless BOTH Sanaa
//  switches are on, and edits that touch content the designer already made
//  additionally require a per-document consent granted in a sheet.
//
//  One call = one new `Document` value = ONE `setModel` = one undo step named
//  "Sanaa: <summary>". A batch either applies whole or changes nothing.
//
//  App target only. Nothing here is referenced from a file shared with the
//  EXPThumbnail extension.
//

import Foundation
import AppKit

// MARK: - Switches

/// Sanaa's app-wide switches. Deliberately plain `Bool` UserDefaults keys, not a
/// persisted `Codable` settings struct — that is the FEAT-022 synthesized-decoder
/// trap. If a struct ever becomes necessary it gets hand-written decoding like
/// `PanelTray`.
enum SanaaPreferences {
    static let enabled      = "exp.sanaa.enabled"       // Bool, default false
    static let writeEnabled = "exp.sanaa.writeEnabled"  // Bool, default false
    static let avatar       = "exp.sanaa.avatar"        // Bool, default false — reserved for FEAT-052

    /// Master switch. When this is off, no Sanaa surface is installed anywhere.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabled) }

    /// Write access, deliberately separate from read access.
    static var isWriteEnabled: Bool { UserDefaults.standard.bool(forKey: writeEnabled) }

    /// Both switches, which is what `apply_edits` requires before it looks at a
    /// single operation. `bool(forKey:)` returns false for an unset key, so the
    /// default is off without registering anything.
    static var canDraw: Bool { isEnabled && isWriteEnabled }
}

// MARK: - Errors

/// Every failure is distinct and says what to do about it, because these strings
/// are what a connected agent reads back and what the designer sees quoted in
/// their agent's transcript.
enum SanaaEditError: LocalizedError {
    case sanaaDisabled
    case drawingDisabled
    case noDocument
    case consentDeclined(document: String)
    case consentAlreadyOpen
    case tooManyOps(count: Int, limit: Int)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .sanaaDisabled:
            return "Sanaa is turned off in EXP. The designer enables it in Settings ▸ Sanaa ▸ Enable Sanaa. Nothing was changed."
        case .drawingDisabled:
            return "Sanaa is enabled but not allowed to draw. The designer turns on Settings ▸ Sanaa ▸ Allow Sanaa to draw. Nothing was changed."
        case .noDocument:
            return "No EXP document is currently open. Nothing was changed."
        case .consentDeclined(let document):
            return "The designer has not allowed drawing in “\(document)” this session. Nothing was changed. Ask them to allow it, or create new artboards instead of editing existing ones."
        case .consentAlreadyOpen:
            return "EXP is already asking the designer for permission to draw. Wait for their answer and try again. Nothing was changed."
        case .tooManyOps(let count, let limit):
            return "apply_edits accepts at most \(limit) operations per call and this call had \(count). Split the work into smaller, honestly summarized batches. Nothing was changed."
        case .malformed(let detail):
            return "\(detail) Nothing was changed."
        }
    }
}

// MARK: - Per-document consent

/// Session-scoped, per-document permission to change content the designer
/// already made. Never persisted: a relaunch starts from "ask again", which is
/// the conservative direction for a permission this consequential.
@MainActor
final class SanaaConsent {
    static let shared = SanaaConsent()

    private var granted: Set<ObjectIdentifier> = []
    private var declinedUntil: [ObjectIdentifier: Date] = [:]
    private var isAsking = false

    /// A decline is not permanent — the designer may simply have been mid-thought.
    /// But a runaway agent must not be able to throw sheet after sheet at them,
    /// so re-asking for the same document waits this long.
    private static let declineCooldown: TimeInterval = 60

    private init() {}

    func hasConsent(for document: ExpDocument) -> Bool {
        granted.contains(ObjectIdentifier(document))
    }

    /// Called when Sanaa is switched off. Turning the feature off must not leave
    /// a live permission behind for the next time it is switched on.
    func forgetEverything() {
        granted.removeAll()
        declinedUntil.removeAll()
    }

    func requireConsent(for document: ExpDocument, named name: String,
                        client: String, preview: [String] = []) async throws {
        let key = ObjectIdentifier(document)
        if granted.contains(key) { return }
        if let until = declinedUntil[key], until > Date() {
            throw SanaaEditError.consentDeclined(document: name)
        }
        guard !isAsking else { throw SanaaEditError.consentAlreadyOpen }

        isAsking = true
        let allowed = await presentConsent(documentName: name, client: client,
                                           preview: preview)
        isAsking = false

        if allowed {
            granted.insert(key)
            declinedUntil[key] = nil
        } else {
            declinedUntil[key] = Date().addingTimeInterval(Self.declineCooldown)
            throw SanaaEditError.consentDeclined(document: name)
        }
    }

    private func presentConsent(documentName: String, client: String,
                                preview: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "“\(client)” wants to change “\(documentName)”."
            // FEAT-058: bulk batches show WHAT they will do — the count the dry
            // run computed and the warnings it collected — so Allow is an
            // informed act, not a leap. Bounded by construction upstream.
            let previewBlock = preview.isEmpty ? "" : "\n\nThis batch will:\n" +
                preview.prefix(12).map { "• " + $0 }.joined(separator: "\n")
            alert.informativeText = """
                Sanaa applies changes from the agent you connected — it is that agent \
                drawing here, not EXP. Changes arrive as ordinary layers you can edit, \
                and each batch is one step you can undo.
                \(previewBlock)

                This permission covers changes to work that is already on the canvas, \
                for this document, until EXP quits.
                """
            alert.addButton(withTitle: "Allow for This Session")
            alert.addButton(withTitle: "Not Now")
            // The default button is the safe one: Return declines.
            alert.buttons[1].keyEquivalent = "\r"
            alert.buttons[0].keyEquivalent = ""

            if let window = NSApp.mainWindow {
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            } else {
                continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
            }
        }
    }
}

// MARK: - The batch

@MainActor
enum SanaaEdits {

    /// Hard cap per call. The socket's existing 4 MB read framing bounds payload
    /// size; this bounds how much one undo step is allowed to mean.
    static let maxOperations = 200

    struct Target {
        var document: ExpDocument
        var app: AppState
        var undoManager: UndoManager?
        var name: String
    }

    // MARK: Placement

    enum Placement {
        case samePage(pageRef: Reference?, afterArtboard: Reference?)
        case newPage(name: String?)
        case exact(pageRef: Reference?)
        case besideOriginal
    }

    /// A UUID the agent read from the document, or a reference to something this
    /// same batch is about to create. Agents cannot know an id EXP has not
    /// generated yet, so `$last` and `$3` (op index) close that gap.
    enum Reference {
        case existing(UUID)
        case created(opIndex: Int)
        case lastCreated

        static func parse(_ raw: String, field: String) throws -> Reference {
            if let id = UUID(uuidString: raw) { return .existing(id) }
            if raw == "$last" { return .lastCreated }
            if raw.hasPrefix("$"), let index = Int(raw.dropFirst()) {
                return .created(opIndex: index)
            }
            throw SanaaEditError.malformed(
                "\(field) must be a UUID from a read tool, \"$last\" for the thing this batch just created, or \"$<op index>\".")
        }

        var isExisting: Bool { if case .existing = self { return true }; return false }
    }

    // MARK: Operations

    enum Operation {
        case createPage(newID: UUID, name: String)
        case createArtboard(newID: UUID, name: String, size: CGSize,
                            origin: CGPoint?, placement: Placement)
        case duplicateArtboard(newID: UUID, source: UUID, placement: Placement)
        case insertNodes(artboard: Reference, nodes: [Node], artboardLocal: Bool)
        case replaceNode(id: UUID, node: Node)
        case removeNodes(ids: [UUID])
        // FEAT-058 — cleanup & repetitive ops. All four mutate work the designer
        // already made, so all four are consent-gated and all four resolve their
        // predicate through the SAME Builder pass the dry run uses: the preview
        // the designer consents to and the edit that lands are one code path,
        // not two that agree by effort.
        case restyleNodes(predicate: NodePredicate, set: RestyleSet)
        case applyToken(predicate: NodePredicate, tokenName: String,
                        property: TokenProperty)
        case normalizeSpacing(predicate: NodePredicate, unit: CGFloat)
        case renameNodes(predicate: NodePredicate, rule: RenameRule)

        /// True when the operation changes something the designer (or an earlier
        /// session) already made, rather than only adding new content. These are
        /// the operations gated behind per-document consent.
        var touchesExistingContent: Bool {
            switch self {
            case .createPage, .createArtboard, .duplicateArtboard: return false
            case .insertNodes(let artboard, _, _):                 return artboard.isExisting
            case .replaceNode, .removeNodes:                       return true
            case .restyleNodes, .applyToken, .normalizeSpacing, .renameNodes:
                return true
            }
        }
    }

    // MARK: FEAT-058 — predicates, payloads, rules

    /// A content kind as the agent spells it — the same names `get_node`
    /// fragments carry in their `content` discriminator.
    enum NodeKind: String, CaseIterable {
        case rectangle, ellipse, polygon, path, line, text, image, group, instance
    }

    /// What a bulk operation targets. Resolution lives in ONE place —
    /// `Builder.resolveMatches` — which the dry run and the real apply both
    /// call, so the receipt the designer consents to and the edit that lands
    /// cannot diverge.
    struct NodePredicate {
        enum Scope: Equatable {
            case selection
            case artboard(UUID)
            case page(UUID)
            /// Every page AND every component source. Deliberately the only
            /// scope that reaches source-owned nodes; matching one means the
            /// receipt warns that every placement of that component changes.
            case document
        }

        var scope: Scope
        var kinds: Set<NodeKind>?
        /// Case-insensitive substring match on layer names.
        var nameContains: String?

        var isBroad: Bool {
            switch scope {
            case .page, .document: return true
            case .selection, .artboard: return false
            }
        }

        var scopeWords: String {
            switch scope {
            case .selection: return "the current selection"
            case .artboard(let id): return "one artboard (\(id.uuidString))"
            case .page(let id): return "every layer on one canvas page (\(id.uuidString)) — a broad scope"
            case .document: return "every layer in the document, including component sources — the broadest scope"
            }
        }
    }

    /// The property vocabulary for `restyleNodes`. Every field is optional;
    /// a node that cannot carry ANY of the chosen properties is counted as
    /// skipped, not silently changed.
    struct RestyleSet {
        var fill: Paint?
        var stroke: Paint?
        var strokeWidth: CGFloat?
        var cornerRadius: CGFloat?
        var opacity: Double?

        var isEmpty: Bool {
            fill == nil && stroke == nil && strokeWidth == nil
                && cornerRadius == nil && opacity == nil
        }

        /// Which chosen properties this node can actually carry. Empty means
        /// the node is skipped entirely.
        func applicable(on kind: NodeKind) -> [String] {
            var supported: [String] = []
            switch kind {
            case .rectangle:
                supported = ["fill", "stroke", "strokeWidth", "cornerRadius"]
            case .ellipse, .polygon, .path:
                supported = ["fill", "stroke", "strokeWidth"]
            case .line:
                supported = ["stroke", "strokeWidth"]
            case .group, .image, .instance:
                break
            case .text:
                break
            }
            if opacity != nil { supported.append("opacity") }
            return supported.filter { chosen.contains($0) }
        }

        private var chosen: Set<String> {
            var set = Set<String>()
            if fill != nil { set.insert("fill") }
            if stroke != nil { set.insert("stroke") }
            if strokeWidth != nil { set.insert("strokeWidth") }
            if cornerRadius != nil { set.insert("cornerRadius") }
            if opacity != nil { set.insert("opacity") }
            return set
        }
    }

    enum TokenProperty: String {
        case fill, stroke, text
    }

    enum RenameRule {
        case findReplace(find: String, replace: String)
        case prefix(String)
        case suffix(String)
        case sequence(base: String, start: Int)
    }

    // MARK: Entry point

    /// Validate everything, ask for consent if the batch needs it, then apply the
    /// whole batch as one undoable commit. Any failure throws before `setModel`.
    static func apply(arguments: [String: Any], client: String,
                      target: Target) async throws -> [String: Any] {
        guard SanaaPreferences.isEnabled else { throw SanaaEditError.sanaaDisabled }
        guard SanaaPreferences.isWriteEnabled else { throw SanaaEditError.drawingDisabled }

        let extras = Set(arguments.keys).subtracting(["summary", "ops"])
        guard extras.isEmpty else {
            throw SanaaEditError.malformed(
                "apply_edits does not accept \(extras.sorted().map { "\"\($0)\"" }.joined(separator: ", ")). It takes exactly \"summary\" and \"ops\".")
        }

        let summary = (arguments["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty else {
            throw SanaaEditError.malformed(
                "apply_edits requires a short \"summary\" of what this batch does; it becomes the undo step the designer reads in the Edit menu.")
        }
        guard summary.count <= 120 else {
            throw SanaaEditError.malformed(
                "\"summary\" must be 120 characters or fewer so it reads as an undo step, not a paragraph.")
        }
        guard let rawOps = arguments["ops"] as? [[String: Any]] else {
            throw SanaaEditError.malformed("apply_edits requires \"ops\", an array of operation objects.")
        }
        guard !rawOps.isEmpty else {
            throw SanaaEditError.malformed("apply_edits was called with no operations.")
        }
        guard rawOps.count <= maxOperations else {
            throw SanaaEditError.tooManyOps(count: rawOps.count, limit: maxOperations)
        }

        // Pass 1 — parse and validate everything. Nothing is mutated here, so a
        // bad operation at index 47 cannot leave a half-applied document behind.
        var operations: [Operation] = []
        operations.reserveCapacity(rawOps.count)
        for (index, raw) in rawOps.enumerated() {
            do { operations.append(try parse(raw, at: index)) }
            catch let error as SanaaEditError {
                guard case .malformed(let detail) = error else { throw error }
                throw SanaaEditError.malformed("Operation \(index): \(detail)")
            }
        }

        // Pass 2 — a dry run against a COPY of the document. This resolves every
        // reference and catches "no node exists with id …" before anyone is asked
        // for anything, so a batch that was never going to work cannot put a
        // permission sheet in front of the designer. FEAT-058: for bulk ops the
        // dry run also produces the plain-language preview the consent sheet
        // shows — counts and warnings computed from the SAME predicate pass the
        // apply will run, not a parallel estimate.
        let dryRun = try build(operations, target: target)

        // Pass 3 — consent, decided from the parsed batch and asked for once.
        if operations.contains(where: \.touchesExistingContent) {
            try await SanaaConsent.shared.requireConsent(
                for: target.document, named: target.name, client: client,
                preview: dryRun.consentLines)
        }

        // Pass 4 — build again against the document AS IT STANDS NOW. The consent
        // sheet is asynchronous and the designer may well have kept drawing while
        // it was up; committing the pass-2 value would silently throw that away.
        // If their edit made this batch impossible, it fails here having changed
        // nothing, which is the correct outcome.
        let builder = try build(operations, target: target)

        target.document.setModel(builder.model,
                                 undoManager: target.undoManager,
                                 actionName: "Sanaa: \(summary)")

        var result: [String: Any] = [
            "created": ["pages": builder.createdPages,
                        "artboards": builder.createdArtboards,
                        "nodes": builder.createdNodes],
            "affected": ["pages": builder.affectedPages,
                         "artboardIds": builder.affectedArtboardIDs,
                         "nodeIds": builder.affectedNodeIDs],
            "undoStep": "Sanaa: \(summary)"
        ]
        if !builder.bulkReceipts.isEmpty {
            result["operations"] = builder.bulkReceipts
        }
        return result
    }

    /// Apply a parsed batch to a `Document` VALUE. Never touches the live
    /// document, so this doubles as the dry run.
    private static func build(_ operations: [Operation], target: Target) throws -> Builder {
        var builder = Builder(model: target.document.model,
                              activePageID: target.app.activeCanvasPageID,
                              selectedNodeIDs: target.app.selectedNodeIDs)
        for (index, operation) in operations.enumerated() {
            do { try builder.perform(operation, at: index) }
            catch let error as SanaaEditError {
                guard case .malformed(let detail) = error else { throw error }
                throw SanaaEditError.malformed("Operation \(index): \(detail)")
            }
        }
        builder.settle()
        return builder
    }

    // MARK: Parsing

    private static func parse(_ raw: [String: Any], at index: Int) throws -> Operation {
        guard let op = raw["op"] as? String else {
            throw SanaaEditError.malformed("every operation needs an \"op\" name.")
        }
        switch op {
        case "createPage":
            return .createPage(newID: UUID(), name: try requiredName(raw, what: "page"))

        case "createArtboard":
            let name = try requiredName(raw, what: "artboard")
            guard let frame = raw["frame"] as? [String: Any],
                  let width = number(frame["width"]), let height = number(frame["height"]),
                  width > 0, height > 0 else {
                throw SanaaEditError.malformed(
                    "createArtboard needs \"frame\" with positive \"width\" and \"height\" (\"x\" and \"y\" are optional).")
            }
            var origin: CGPoint?
            if let x = number(frame["x"]), let y = number(frame["y"]) {
                origin = CGPoint(x: x, y: y)
            }
            return .createArtboard(newID: UUID(), name: name,
                                   size: CGSize(width: width, height: height),
                                   origin: origin,
                                   placement: try parsePlacement(raw["placement"],
                                                                 default: .samePage(pageRef: nil, afterArtboard: nil)))

        case "duplicateArtboard":
            guard let rawID = raw["id"] as? String, let id = UUID(uuidString: rawID) else {
                throw SanaaEditError.malformed("duplicateArtboard needs \"id\", the UUID of an existing artboard.")
            }
            return .duplicateArtboard(newID: UUID(), source: id,
                                      placement: try parsePlacement(raw["placement"],
                                                                    default: .besideOriginal))

        case "insertNodes":
            guard let rawArtboard = raw["artboardId"] as? String else {
                throw SanaaEditError.malformed(
                    "insertNodes needs \"artboardId\" — a UUID, or \"$last\"/\"$<op index>\" for an artboard this batch creates.")
            }
            let artboard = try Reference.parse(rawArtboard, field: "insertNodes \"artboardId\"")
            guard let fragments = raw["nodes"] as? [[String: Any]], !fragments.isEmpty else {
                throw SanaaEditError.malformed("insertNodes needs a non-empty \"nodes\" array of design.json node fragments.")
            }
            let nodes = try fragments.enumerated().map { offset, fragment in
                try decodeNode(fragment, position: offset)
            }
            // Frames from a read tool are document coordinates; frames for an
            // artboard this batch is still creating can only be artboard-local,
            // because its final origin is EXP's to decide.
            let artboardLocal: Bool
            if let raw = raw["coordinates"] as? String {
                switch raw {
                case "artboard": artboardLocal = true
                case "document": artboardLocal = false
                default:
                    throw SanaaEditError.malformed("insertNodes \"coordinates\" must be \"artboard\" or \"document\".")
                }
            } else {
                artboardLocal = !artboard.isExisting
            }
            return .insertNodes(artboard: artboard, nodes: nodes, artboardLocal: artboardLocal)

        case "replaceNode":
            guard let rawID = raw["id"] as? String, let id = UUID(uuidString: rawID) else {
                throw SanaaEditError.malformed("replaceNode needs \"id\", the UUID of the node to replace.")
            }
            guard let fragment = raw["node"] as? [String: Any] else {
                throw SanaaEditError.malformed("replaceNode needs \"node\", one design.json node fragment.")
            }
            return .replaceNode(id: id, node: try decodeNode(fragment, position: nil))

        case "removeNodes":
            guard let rawIDs = raw["ids"] as? [String], !rawIDs.isEmpty else {
                throw SanaaEditError.malformed("removeNodes needs a non-empty \"ids\" array of node UUIDs.")
            }
            let ids = try rawIDs.map { raw -> UUID in
                guard let id = UUID(uuidString: raw) else {
                    throw SanaaEditError.malformed("removeNodes was given \"\(raw)\", which is not a UUID.")
                }
                return id
            }
            return .removeNodes(ids: ids)

        case "restyleNodes":
            try checkKeys(raw, allowed: ["op", "select", "set"], what: "restyleNodes")
            let predicate = try parsePredicate(raw["select"])
            guard let setDict = raw["set"] as? [String: Any] else {
                throw SanaaEditError.malformed("restyleNodes needs \"set\", the properties to apply.")
            }
            let set = try parseRestyleSet(setDict)
            guard !set.isEmpty else {
                throw SanaaEditError.malformed(
                    "restyleNodes \"set\" named no supported property. Use fill, stroke, strokeWidth, cornerRadius, or opacity.")
            }
            return .restyleNodes(predicate: predicate, set: set)

        case "applyToken":
            try checkKeys(raw, allowed: ["op", "select", "token", "property"], what: "applyToken")
            let predicate = try parsePredicate(raw["select"])
            guard let rawToken = raw["token"] as? String,
                  !rawToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SanaaEditError.malformed(
                    "applyToken needs \"token\", the exact Design Language asset or type-style name (get_tokens lists them).")
            }
            let tokenName = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            var property = TokenProperty.fill
            if let rawProperty = raw["property"] as? String {
                guard let parsed = TokenProperty(rawValue: rawProperty) else {
                    throw SanaaEditError.malformed(
                        "applyToken \"property\" must be \"fill\", \"stroke\", or \"text\".")
                }
                property = parsed
            }
            return .applyToken(predicate: predicate, tokenName: tokenName, property: property)

        case "normalizeSpacing":
            try checkKeys(raw, allowed: ["op", "select", "unit"], what: "normalizeSpacing")
            let predicate = try parsePredicate(raw["select"])
            if case .selection = predicate.scope {
                throw SanaaEditError.malformed(
                    "normalizeSpacing spaces artboards and managed groups, so a selection scope has nothing to space. Use \"artboard\", \"page\", or \"document\".")
            }
            guard let unit = number(raw["unit"]), unit > 0 else {
                throw SanaaEditError.malformed(
                    "normalizeSpacing needs a positive \"unit\" (the spacing scale to snap to, e.g. 8).")
            }
            return .normalizeSpacing(predicate: predicate, unit: unit)

        case "renameNodes":
            try checkKeys(raw, allowed: ["op", "select", "rule"], what: "renameNodes")
            let predicate = try parsePredicate(raw["select"])
            guard let ruleDict = raw["rule"] as? [String: Any] else {
                throw SanaaEditError.malformed("renameNodes needs \"rule\".")
            }
            return .renameNodes(predicate: predicate, rule: try parseRenameRule(ruleDict))

        default:
            throw SanaaEditError.malformed(
                "\"\(op)\" is not an apply_edits operation. Use createPage, createArtboard, duplicateArtboard, insertNodes, replaceNode, removeNodes, restyleNodes, applyToken, normalizeSpacing, or renameNodes.")
        }
    }

    private static func requiredName(_ raw: [String: Any], what: String) throws -> String {
        let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            throw SanaaEditError.malformed("this operation needs a \"name\" for the new \(what).")
        }
        return name
    }

    // MARK: FEAT-058 parsing helpers

    /// Unknown keys are refused everywhere, the same discipline the top-level
    /// argument check follows: a typo like \"stoke\" must fail loudly, not
    /// silently apply four of five properties.
    private static func checkKeys(_ dict: [String: Any], allowed: Set<String>,
                                  what: String) throws {
        let extras = Set(dict.keys).subtracting(allowed)
        guard extras.isEmpty else {
            throw SanaaEditError.malformed(
                "\(what) does not accept \(extras.sorted().map { "\"\($0)\"" }.joined(separator: ", ")).")
        }
    }

    /// Default scope is the SELECTION — the narrowest thing EXP can name — so a
    /// lazy or ambiguous predicate touches as little as possible. Broad scopes
    /// exist and are labelled broad everywhere they appear.
    private static func parsePredicate(_ raw: Any?) throws -> NodePredicate {
        guard let raw else {
            return NodePredicate(scope: .selection, kinds: nil, nameContains: nil)
        }
        guard let dict = raw as? [String: Any] else {
            throw SanaaEditError.malformed("\"select\" must be an object.")
        }
        try checkKeys(dict, allowed: ["scope", "artboardId", "pageId", "types", "nameContains"],
                      what: "\"select\"")

        let scopeWord = (dict["scope"] as? String) ?? "selection"
        let scope: NodePredicate.Scope
        switch scopeWord {
        case "selection":
            scope = .selection
        case "artboard":
            guard let rawID = dict["artboardId"] as? String,
                  let id = UUID(uuidString: rawID) else {
                throw SanaaEditError.malformed(
                    "scope \"artboard\" needs \"artboardId\", the UUID of an existing artboard.")
            }
            scope = .artboard(id)
        case "page":
            guard let rawID = dict["pageId"] as? String,
                  let id = UUID(uuidString: rawID) else {
                throw SanaaEditError.malformed(
                    "scope \"page\" needs \"pageId\", the UUID of an existing canvas page.")
            }
            scope = .page(id)
        case "document":
            scope = .document
        default:
            throw SanaaEditError.malformed(
                "\"scope\" must be \"selection\", \"artboard\", \"page\", or \"document\".")
        }

        var kinds: Set<NodeKind>?
        if let rawTypes = dict["types"] {
            guard let typeWords = rawTypes as? [String], !typeWords.isEmpty else {
                throw SanaaEditError.malformed(
                    "\"types\" must be a non-empty array like [\"rectangle\",\"text\"].")
            }
            var parsed = Set<NodeKind>()
            for word in typeWords {
                guard let kind = NodeKind(rawValue: word) else {
                    throw SanaaEditError.malformed(
                        "\"\(word)\" is not a layer type. Use rectangle, ellipse, polygon, path, line, text, image, group, or instance.")
                }
                parsed.insert(kind)
            }
            kinds = parsed
        }

        var nameContains: String?
        if let rawName = dict["nameContains"] as? String {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SanaaEditError.malformed("\"nameContains\" must not be empty — remove it instead.")
            }
            nameContains = trimmed
        }

        return NodePredicate(scope: scope, kinds: kinds, nameContains: nameContains)
    }

    private static func parseRestyleSet(_ dict: [String: Any]) throws -> RestyleSet {
        try checkKeys(dict,
                      allowed: ["fill", "stroke", "strokeWidth", "cornerRadius", "opacity"],
                      what: "restyleNodes \"set\"")
        var set = RestyleSet()
        if dict["fill"] != nil { set.fill = try decodePaint(dict["fill"]!, what: "fill") }
        if dict["stroke"] != nil { set.stroke = try decodePaint(dict["stroke"]!, what: "stroke") }
        if let width = number(dict["strokeWidth"]) {
            guard width >= 0 else {
                throw SanaaEditError.malformed("\"strokeWidth\" must be 0 or more.")
            }
            set.strokeWidth = width
        } else if dict["strokeWidth"] != nil {
            throw SanaaEditError.malformed("\"strokeWidth\" must be a number.")
        }
        if let radius = number(dict["cornerRadius"]) {
            guard radius >= 0 else {
                throw SanaaEditError.malformed("\"cornerRadius\" must be 0 or more.")
            }
            set.cornerRadius = radius
        } else if dict["cornerRadius"] != nil {
            throw SanaaEditError.malformed("\"cornerRadius\" must be a number.")
        }
        if let opacity = dict["opacity"] as? Double {
            guard opacity >= 0, opacity <= 1 else {
                throw SanaaEditError.malformed("\"opacity\" must be between 0 and 1.")
            }
            set.opacity = opacity
        } else if dict["opacity"] != nil {
            throw SanaaEditError.malformed("\"opacity\" must be a number between 0 and 1.")
        }
        return set
    }

    /// Paints decode through the REAL model, like node fragments do, so a
    /// gradient or pattern restyle is exactly what EXP renders.
    private static func decodePaint(_ raw: Any, what: String) throws -> Paint {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else {
            throw SanaaEditError.malformed("\(what) must be a paint object (a color, gradient, or pattern fragment).")
        }
        do {
            return try JSONDecoder().decode(Paint.self, from: data)
        } catch {
            throw SanaaEditError.malformed("\(what) is not a valid EXP paint (\(error.localizedDescription)).")
        }
    }

    private static func parseRenameRule(_ dict: [String: Any]) throws -> RenameRule {
        let named = Set(dict.keys).intersection(["find", "replace", "prefix", "suffix", "sequence"])
        guard named.count <= 1 else {
            throw SanaaEditError.malformed(
                "renameNodes \"rule\" must name exactly ONE kind of rule (find, prefix, suffix, or sequence).")
        }
        if let find = dict["find"] as? String {
            try checkKeys(dict, allowed: ["find", "replace"], what: "renameNodes \"rule\"")
            guard !find.isEmpty else {
                throw SanaaEditError.malformed("\"find\" must not be empty.")
            }
            return .findReplace(find: find, replace: dict["replace"] as? String ?? "")
        }
        if let prefix = dict["prefix"] as? String {
            try checkKeys(dict, allowed: ["prefix"], what: "renameNodes \"rule\"")
            return .prefix(prefix)
        }
        if let suffix = dict["suffix"] as? String {
            try checkKeys(dict, allowed: ["suffix"], what: "renameNodes \"rule\"")
            return .suffix(suffix)
        }
        if let sequence = dict["sequence"] as? [String: Any] {
            try checkKeys(dict, allowed: ["sequence"], what: "renameNodes \"rule\"")
            try checkKeys(sequence, allowed: ["base", "start"], what: "sequence")
            guard let base = sequence["base"] as? String, !base.isEmpty else {
                throw SanaaEditError.malformed("\"sequence\" needs a non-empty \"base\" (e.g. \"Card \").")
            }
            let start = sequence["start"] as? Int ?? 1
            guard start >= 0 else {
                throw SanaaEditError.malformed("\"sequence\" \"start\" must be 0 or more.")
            }
            return .sequence(base: base, start: start)
        }
        throw SanaaEditError.malformed(
            "renameNodes \"rule\" must name one of: {\"find\", \"replace\"}, {\"prefix\"}, {\"suffix\"}, or {\"sequence\": {\"base\", \"start\"}}.")
    }

    private static func parsePlacement(_ raw: Any?, default fallback: Placement) throws -> Placement {
        guard let raw else { return fallback }
        guard let dict = raw as? [String: Any], let kind = dict["kind"] as? String else {
            throw SanaaEditError.malformed("\"placement\" must be an object with a \"kind\".")
        }
        let pageRef = try (dict["pageId"] as? String).map { try Reference.parse($0, field: "placement \"pageId\"") }
        switch kind {
        case "samePage":
            let after = try (dict["afterArtboardId"] as? String)
                .map { try Reference.parse($0, field: "placement \"afterArtboardId\"") }
            return .samePage(pageRef: pageRef, afterArtboard: after)
        case "newPage":
            return .newPage(name: (dict["pageName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines))
        case "exact":
            return .exact(pageRef: pageRef)
        case "besideOriginal":
            return .besideOriginal
        default:
            throw SanaaEditError.malformed(
                "placement \"kind\" must be \"samePage\", \"newPage\", \"exact\", or \"besideOriginal\".")
        }
    }

    /// Node fragments are validated by decoding the REAL model, never hand-parsed,
    /// so anything that survives this is something EXP can render, save, and export.
    private static func decodeNode(_ fragment: [String: Any], position: Int?) throws -> Node {
        let where_ = position.map { " at index \($0)" } ?? ""
        guard JSONSerialization.isValidJSONObject(fragment),
              let data = try? JSONSerialization.data(withJSONObject: fragment) else {
            throw SanaaEditError.malformed("the node fragment\(where_) is not valid JSON.")
        }
        do {
            return try JSONDecoder().decode(Node.self, from: data)
        } catch {
            throw SanaaEditError.malformed(
                "the node fragment\(where_) is not a valid EXP node (\(error.localizedDescription)). Copy the exact shape returned by get_node or get_artboard.")
        }
    }

    private static func number(_ any: Any?) -> CGFloat? {
        if let d = any as? Double { return CGFloat(d) }
        if let i = any as? Int { return CGFloat(i) }
        if let n = any as? NSNumber { return CGFloat(n.doubleValue) }
        return nil
    }
}

// MARK: - The builder

extension SanaaEdits {

    /// Applies parsed operations to a `Document` VALUE. Nothing here touches the
    /// live `ExpDocument`; the caller commits the finished value once, so a throw
    /// part-way through simply discards this whole builder.
    struct Builder {
        var model: Document
        let activePageID: UUID?
        let selectedNodeIDs: Set<UUID>

        private var pagesByOpIndex: [Int: UUID] = [:]
        private var artboardsByOpIndex: [Int: UUID] = [:]
        private var lastCreatedPage: UUID?
        private var lastCreatedArtboard: UUID?
        private var touchedPages: Set<UUID> = []
        private var touchedArtboards: Set<UUID> = []
        private var touchedNodes: Set<UUID> = []

        private(set) var createdPages: [[String: String]] = []
        private(set) var createdArtboards: [[String: String]] = []
        private(set) var createdNodes: [[String: String]] = []

        /// FEAT-058. One receipt per bulk operation, returned to the agent in
        /// the apply result so what changed is quotable, not implied.
        private(set) var bulkReceipts: [[String: Any]] = []

        /// FEAT-058. Plain-language lines for the consent sheet, collected
        /// during the DRY run so the designer reads exactly what the batch will
        /// do before allowing it — count first, warnings after.
        private(set) var consentLines: [String] = []

        var affectedPages: [[String: String]] {
            model.pages.compactMap { page in
                touchedPages.contains(page.id)
                    ? ["id": page.id.uuidString, "name": page.name]
                    : nil
            }
        }

        var affectedArtboardIDs: [String] {
            touchedArtboards.map(\.uuidString).sorted()
        }

        var affectedNodeIDs: [String] {
            touchedNodes.map(\.uuidString).sorted()
        }

        init(model: Document, activePageID: UUID?, selectedNodeIDs: Set<UUID> = []) {
            self.model = model
            self.activePageID = activePageID
            self.selectedNodeIDs = selectedNodeIDs
        }

        // MARK: Dispatch

        mutating func perform(_ operation: Operation, at index: Int) throws {
            switch operation {
            case .createPage(let newID, let name):
                try createPage(id: newID, name: name, at: index)

            case .createArtboard(let newID, let name, let size, let origin, let placement):
                try createArtboard(id: newID, name: name, size: size,
                                   origin: origin, placement: placement, at: index)

            case .duplicateArtboard(let newID, let source, let placement):
                try duplicateArtboard(id: newID, source: source, placement: placement, at: index)

            case .insertNodes(let artboard, let nodes, let artboardLocal):
                try insertNodes(into: artboard, nodes: nodes, artboardLocal: artboardLocal)

            case .replaceNode(let id, let node):
                try replaceNode(id: id, with: node)

            case .removeNodes(let ids):
                try removeNodes(ids)

            case .restyleNodes(let predicate, let set):
                try restyleNodes(predicate: predicate, set: set)

            case .applyToken(let predicate, let tokenName, let property):
                try applyToken(predicate: predicate, tokenName: tokenName, property: property)

            case .normalizeSpacing(let predicate, let unit):
                try normalizeSpacing(predicate: predicate, unit: unit)

            case .renameNodes(let predicate, let rule):
                try renameNodes(predicate: predicate, rule: rule)
            }
        }

        /// Reflow auto-layout and re-settle artboard ownership on every page this
        /// batch touched, exactly as a hand edit does, inside the same commit.
        mutating func settle() {
            for pageID in touchedPages {
                guard let index = model.pages.firstIndex(where: { $0.id == pageID }) else { continue }
                model.pages[index].nodes = model.reflowed(model.pages[index].nodes)
                model.reconcileArtboardOwnership(on: pageID)
            }
        }

        // MARK: Operations

        private mutating func createPage(id: UUID, name: String, at index: Int) throws {
            let page = CanvasPage(id: id, name: name)
            model.pages.append(page)
            pagesByOpIndex[index] = id
            lastCreatedPage = id
            touchedPages.insert(id)
            createdPages.append(["id": id.uuidString, "name": name])
        }

        private mutating func createArtboard(id: UUID, name: String, size: CGSize,
                                             origin: CGPoint?, placement: Placement,
                                             at index: Int) throws {
            let pageID: UUID
            var explicitOrigin = false
            var after: Artboard?

            switch placement {
            case .besideOriginal:
                throw SanaaEditError.malformed(
                    "placement \"besideOriginal\" only applies to duplicateArtboard.")
            case .newPage(let pageName):
                let newPage = UUID()
                let title: String
                if let pageName, !pageName.isEmpty { title = pageName }
                else { title = "Sanaa — \(name)" }
                try createPage(id: newPage, name: title, at: index)
                pageID = newPage
            case .exact(let pageRef):
                guard origin != nil else {
                    throw SanaaEditError.malformed(
                        "placement \"exact\" needs \"x\" and \"y\" in \"frame\".")
                }
                explicitOrigin = true
                pageID = try resolvePage(pageRef)
            case .samePage(let pageRef, let afterRef):
                if let afterRef {
                    let resolved = try resolveArtboard(afterRef)
                    after = resolved.artboard
                    pageID = pageRef == nil ? resolved.pageID : (try resolvePage(pageRef))
                } else {
                    pageID = try resolvePage(pageRef)
                }
            }

            guard let pageIndex = model.pages.firstIndex(where: { $0.id == pageID }) else {
                throw SanaaEditError.malformed("the target page for this artboard no longer exists.")
            }

            let placedOrigin: CGPoint
            if explicitOrigin, let origin {
                placedOrigin = origin
            } else if let after {
                placedOrigin = CGPoint(x: after.frame.maxX + AppPreferences.artboardSpacingValue,
                                       y: after.frame.minY)
            } else if model.pages[pageIndex].artboards.isEmpty {
                placedOrigin = .zero
            } else {
                placedOrigin = CGPoint(
                    x: model.contentBounds(on: pageID).maxX + AppPreferences.artboardSpacingValue,
                    y: 0)
            }

            let preferredFrame = CGRect(origin: placedOrigin, size: size)
            let placedFrame = explicitOrigin
                ? preferredFrame
                : model.availableArtboardFrame(
                    preferred: preferredFrame,
                    on: pageID,
                    spacing: AppPreferences.artboardSpacingValue)
            let artboard = Artboard(id: id, name: name, frame: placedFrame)
            model.pages[pageIndex].artboards.append(artboard)
            artboardsByOpIndex[index] = id
            lastCreatedArtboard = id
            touchedPages.insert(pageID)
            touchedArtboards.insert(id)
            createdArtboards.append(["id": id.uuidString, "name": name,
                                     "pageId": pageID.uuidString])
        }

        private mutating func duplicateArtboard(id: UUID, source: UUID,
                                                placement: Placement, at index: Int) throws {
            guard let sourcePageID = model.page(containingArtboard: source)?.id,
                  let sourcePageIndex = model.pages.firstIndex(where: { $0.id == sourcePageID }),
                  let original = model.pages[sourcePageIndex].artboards.first(where: { $0.id == source })
            else {
                throw SanaaEditError.malformed("no artboard exists with id \(source.uuidString).")
            }

            let targetPageID: UUID
            switch placement {
            case .besideOriginal:
                targetPageID = sourcePageID
            case .newPage(let pageName):
                let newPage = UUID()
                let title: String
                if let pageName, !pageName.isEmpty { title = pageName }
                else { title = "Sanaa — \(original.name)" }
                try createPage(id: newPage, name: title, at: index)
                targetPageID = newPage
            case .samePage(let pageRef, _), .exact(let pageRef):
                if let pageRef {
                    targetPageID = try resolvePage(pageRef)
                } else {
                    targetPageID = sourcePageID
                }
            }
            guard let targetPageIndex = model.pages.firstIndex(where: { $0.id == targetPageID }) else {
                throw SanaaEditError.malformed("the target page for this duplicate no longer exists.")
            }

            let preferredOrigin: CGPoint
            if targetPageID == sourcePageID {
                preferredOrigin = CGPoint(x: original.frame.maxX + AppPreferences.artboardSpacingValue,
                                          y: original.frame.minY)
            } else if model.pages[targetPageIndex].artboards.isEmpty {
                preferredOrigin = .zero
            } else {
                preferredOrigin = CGPoint(
                    x: model.contentBounds(on: targetPageID).maxX + AppPreferences.artboardSpacingValue,
                    y: 0)
            }
            let preferredFrame = CGRect(origin: preferredOrigin, size: original.frame.size)
            let newOrigin: CGPoint
            if case .exact = placement {
                // Preserve the existing explicit-placement behavior. Collision
                // avoidance applies only when EXP chooses the slot automatically.
                newOrigin = preferredOrigin
            } else {
                newOrigin = model.availableArtboardFrame(
                    preferred: preferredFrame,
                    on: targetPageID,
                    spacing: AppPreferences.artboardSpacingValue).origin
            }
            let delta = CGPoint(x: newOrigin.x - original.frame.minX,
                                y: newOrigin.y - original.frame.minY)

            var copy = original
            copy.id = id
            copy.name = original.name + " copy"
            copy.frame.origin = newOrigin

            // Copy the layers this board owns, keeping relationships between them
            // pointed at the copies rather than back at the original.
            let owned = model.pages[sourcePageIndex].nodes.filter {
                model.owningArtboard(of: $0, on: sourcePageID)?.id == source
            }
            var fresh = Document.duplicatingNodesForTransfer(owned)
            for i in fresh.indices {
                fresh[i].frame.origin.x += delta.x
                fresh[i].frame.origin.y += delta.y
                fresh[i].artboardID = id
                touchedNodes.insert(fresh[i].id)
                createdNodes.append(["id": fresh[i].id.uuidString, "name": fresh[i].name,
                                     "artboardId": id.uuidString])
            }

            model.pages[targetPageIndex].artboards.append(copy)
            model.pages[targetPageIndex].nodes.append(contentsOf: fresh)
            artboardsByOpIndex[index] = id
            lastCreatedArtboard = id
            touchedPages.insert(targetPageID)
            touchedPages.insert(sourcePageID)
            touchedArtboards.insert(id)
            createdArtboards.append(["id": id.uuidString, "name": copy.name,
                                     "pageId": targetPageID.uuidString])
        }

        private mutating func insertNodes(into reference: Reference, nodes: [Node],
                                          artboardLocal: Bool) throws {
            let resolved = try resolveArtboard(reference)
            guard let pageIndex = model.pages.firstIndex(where: { $0.id == resolved.pageID }) else {
                throw SanaaEditError.malformed("the target page for these layers no longer exists.")
            }

            // Fresh ids always: a fragment copied from elsewhere in the document
            // must never collide with the node it was copied from.
            var fresh = Document.duplicatingNodesForTransfer(nodes)
            for i in fresh.indices {
                if artboardLocal {
                    fresh[i].frame.origin.x += resolved.artboard.frame.minX
                    fresh[i].frame.origin.y += resolved.artboard.frame.minY
                }
                fresh[i].artboardID = resolved.artboard.id
                touchedNodes.insert(fresh[i].id)
                createdNodes.append(["id": fresh[i].id.uuidString, "name": fresh[i].name,
                                     "artboardId": resolved.artboard.id.uuidString])
            }
            model.pages[pageIndex].nodes.append(contentsOf: fresh)
            touchedPages.insert(resolved.pageID)
            touchedArtboards.insert(resolved.artboard.id)
        }

        private mutating func replaceNode(id: UUID, with node: Node) throws {
            var replacement = node
            replacement.id = id
            var done = false
            for pageIndex in model.pages.indices where !done {
                var nodes = model.pages[pageIndex].nodes
                if Self.substitute(id, in: &nodes, with: { existing in
                    // Membership and placement belong to the document, not to a
                    // fragment that may have been written from scratch.
                    if replacement.artboardID == nil { replacement.artboardID = existing.artboardID }
                    return replacement
                }) {
                    if let existing = Self.node(id, in: model.pages[pageIndex].nodes),
                       let artboard = existing.artboardID
                        ?? model.owningArtboard(of: existing, on: model.pages[pageIndex].id)?.id {
                        touchedArtboards.insert(artboard)
                    }
                    model.pages[pageIndex].nodes = nodes
                    touchedPages.insert(model.pages[pageIndex].id)
                    touchedNodes.insert(id)
                    done = true
                }
            }
            guard done else {
                throw SanaaEditError.malformed("no node exists with id \(id.uuidString).")
            }
        }

        private mutating func removeNodes(_ ids: [UUID]) throws {
            let wanted = Set(ids)
            var removed: Set<UUID> = []
            for pageIndex in model.pages.indices {
                for id in wanted {
                    // A nested child's frame is parent-local. Resolve ownership
                    // through its page-level root before removing the subtree so
                    // the receipt can still select the affected artboard later.
                    guard let root = model.pages[pageIndex].nodes.first(where: {
                        Self.node(id, in: [$0]) != nil
                    }) else { continue }
                    if let artboard = root.artboardID
                        ?? model.owningArtboard(of: root, on: model.pages[pageIndex].id)?.id {
                        touchedArtboards.insert(artboard)
                    }
                }
                var nodes = model.pages[pageIndex].nodes
                let hit = Self.prune(wanted, from: &nodes, removed: &removed)
                guard hit else { continue }
                model.pages[pageIndex].nodes = nodes
                model.pages[pageIndex].anchoredRelationships = Document.removingAnchors(
                    referencing: removed, in: model.pages[pageIndex].anchoredRelationships)
                Document.removingAnchors(referencing: removed, in: &model.pages[pageIndex].nodes)
                touchedPages.insert(model.pages[pageIndex].id)
            }
            let missing = wanted.subtracting(removed)
            guard missing.isEmpty else {
                throw SanaaEditError.malformed(
                    "no node exists with id \(missing.map(\.uuidString).sorted().joined(separator: ", ")).")
            }
            touchedNodes.formUnion(removed)
        }

        // MARK: FEAT-058 — shared predicate resolution
        //
        // THE SAFETY INVARIANT: this is the only place a predicate turns into
        // node ids. The dry run (pass 2) and the real apply (pass 4) both go
        // through `perform` → here, so the set the designer consents to and the
        // set that changes are the same code on the same document value. A
        // second resolution path anywhere would be the divergence the plan
        // calls the worst-case defect.

        private enum MatchLocation: Equatable {
            case page(index: Int)
            /// A component source's children — editing these hits every
            /// placement of the component, which the receipt must warn about.
            case source(index: Int)
        }

        private struct MatchedNode {
            let id: UUID
            let name: String
            let kind: NodeKind
            let location: MatchLocation
        }

        private struct PredicateMatches {
            var nodes: [MatchedNode]
            var sourceNames: [String]
            var broadScope: Bool
            var scopeWords: String

            var sampleNames: [String] {
                Array(nodes.prefix(8).map(\.name))
            }
        }

        private static func kind(of node: Node) -> NodeKind {
            switch node.content {
            case .rectangle: return .rectangle
            case .ellipse: return .ellipse
            case .polygon: return .polygon
            case .path: return .path
            case .line: return .line
            case .text: return .text
            case .image: return .image
            case .group: return .group
            case .instance: return .instance
            }
        }

        private func passesFilters(_ node: Node, kinds: Set<NodeKind>?,
                                   nameContains: String?) -> Bool {
            if let kinds, !kinds.contains(Self.kind(of: node)) { return false }
            if let nameContains,
               node.name.range(of: nameContains, options: .caseInsensitive) == nil {
                return false
            }
            return true
        }

        /// Collect matching nodes IN DOCUMENT ORDER (page trees first, then
        /// sources), nested layers included. `member` decides scope membership
        /// for a page-level root; descendants inherit it.
        private func collect(in nodes: [Node], location: MatchLocation,
                             member: (Node) -> Bool, predicate: NodePredicate,
                             into out: inout [MatchedNode]) {
            for node in nodes {
                let inScope = member(node)
                if inScope, passesFilters(node, kinds: predicate.kinds,
                                          nameContains: predicate.nameContains) {
                    out.append(MatchedNode(id: node.id, name: node.name,
                                           kind: Self.kind(of: node), location: location))
                }
                if case .group(let children) = node.content {
                    // Selection membership is per-node; every other scope is
                    // inherited from the page-level root.
                    if case .selection = predicate.scope {
                        collect(in: children, location: location,
                                member: member, predicate: predicate, into: &out)
                    } else if inScope {
                        collect(in: children, location: location,
                                member: { _ in true }, predicate: predicate, into: &out)
                    }
                }
            }
        }

        private func resolveMatches(_ predicate: NodePredicate) throws -> PredicateMatches {
            var matches: [MatchedNode] = []

            switch predicate.scope {
            case .selection:
                guard !selectedNodeIDs.isEmpty else {
                    throw SanaaEditError.malformed(
                        "the predicate defaults to the current selection, but nothing is selected. Name a scope (\"artboard\", \"page\", or \"document\") or select layers first. Nothing was changed.")
                }
                for pageIndex in model.pages.indices {
                    collect(in: model.pages[pageIndex].nodes,
                            location: .page(index: pageIndex),
                            member: { selectedNodeIDs.contains($0.id) },
                            predicate: predicate, into: &matches)
                }

            case .artboard(let artboardID):
                guard model.page(containingArtboard: artboardID) != nil else {
                    throw SanaaEditError.malformed(
                        "no artboard exists with id \(artboardID.uuidString).")
                }
                for pageIndex in model.pages.indices {
                    let pageID = model.pages[pageIndex].id
                    collect(in: model.pages[pageIndex].nodes,
                            location: .page(index: pageIndex),
                            member: { root in
                                (root.artboardID
                                    ?? model.owningArtboard(of: root, on: pageID)?.id) == artboardID
                            },
                            predicate: predicate, into: &matches)
                }

            case .page(let pageID):
                guard let pageIndex = model.pages.firstIndex(where: { $0.id == pageID }) else {
                    throw SanaaEditError.malformed("no page exists with id \(pageID.uuidString).")
                }
                collect(in: model.pages[pageIndex].nodes,
                        location: .page(index: pageIndex),
                        member: { _ in true }, predicate: predicate, into: &matches)

            case .document:
                for pageIndex in model.pages.indices {
                    collect(in: model.pages[pageIndex].nodes,
                            location: .page(index: pageIndex),
                            member: { _ in true }, predicate: predicate, into: &matches)
                }
                for sourceIndex in model.sources.indices {
                    collect(in: model.sources[sourceIndex].children,
                            location: .source(index: sourceIndex),
                            member: { _ in true }, predicate: predicate, into: &matches)
                }
            }

            guard !matches.isEmpty else {
                throw SanaaEditError.malformed(
                    "the predicate matched no layers. Nothing was changed — widen the scope or filters (types, nameContains) rather than assuming ids. Scope was \(predicate.scopeWords).")
            }

            let sourceNames: [String] = {
                var names = Set<String>()
                for match in matches {
                    if case .source(let index) = match.location,
                       index < model.sources.count {
                        names.insert(model.sources[index].name)
                    }
                }
                return names.sorted()
            }()

            return PredicateMatches(nodes: matches, sourceNames: sourceNames,
                                    broadScope: predicate.isBroad,
                                    scopeWords: predicate.scopeWords)
        }

        /// Consent + receipt lines shared by every bulk op: the honest count
        /// first, then the scope statement, then warnings. Bounded so a
        /// 10,000-layer document cannot build a 10,000-line sheet.
        private mutating func recordConsentLines(headline: String,
                                                 matches: PredicateMatches) {
            consentLines.append(headline)
            if matches.broadScope {
                consentLines.append("Scope: \(matches.scopeWords).")
            }
            for name in matches.sourceNames.prefix(4) {
                consentLines.append(
                    "Also changes the component “\(name)” — every placement of it updates.")
            }
        }

        /// Apply per-node mutations to every container the matches live in,
        /// recursing into groups. Page containers are marked touched so
        /// `settle()` reflows and re-settles ownership; source edits are
        /// disclosed through the receipt and consent warning instead.
        private mutating func applyEdits(_ edits: [UUID: (inout Node) -> Void]) {
            for id in edits.keys { touchedNodes.insert(id) }
            for pageIndex in model.pages.indices {
                var nodes = model.pages[pageIndex].nodes
                if Self.edit(matches: edits, in: &nodes) {
                    model.pages[pageIndex].nodes = nodes
                    touchedPages.insert(model.pages[pageIndex].id)
                }
            }
            for sourceIndex in model.sources.indices {
                var children = model.sources[sourceIndex].children
                if Self.edit(matches: edits, in: &children) {
                    model.sources[sourceIndex].children = children
                }
            }
        }

        private static func edit(matches edits: [UUID: (inout Node) -> Void],
                                 in nodes: inout [Node]) -> Bool {
            var changed = false
            for index in nodes.indices {
                if let edit = edits[nodes[index].id] {
                    edit(&nodes[index])
                    changed = true
                }
                if case .group(var children) = nodes[index].content {
                    if edit(matches: edits, in: &children) {
                        nodes[index].content = .group(children: children)
                        changed = true
                    }
                }
            }
            return changed
        }

        // MARK: FEAT-058 — the four operations

        private mutating func restyleNodes(predicate: NodePredicate, set: RestyleSet) throws {
            let matches = try resolveMatches(predicate)
            var edits: [UUID: (inout Node) -> Void] = [:]
            for match in matches.nodes where !set.applicable(on: match.kind).isEmpty {
                edits[match.id] = { node in
                    if let opacity = set.opacity { node.opacity = opacity }
                    switch node.content {
                    case .rectangle(let shape):
                        var shape = shape
                        if let fill = set.fill { shape.fill = fill }
                        if let stroke = set.stroke { shape.stroke = stroke }
                        if let strokeWidth = set.strokeWidth { shape.strokeWidth = strokeWidth }
                        if let radius = set.cornerRadius { shape.cornerRadius = radius }
                        node.content = .rectangle(shape)
                    case .ellipse(let shape):
                        var shape = shape
                        if let fill = set.fill { shape.fill = fill }
                        if let stroke = set.stroke { shape.stroke = stroke }
                        if let strokeWidth = set.strokeWidth { shape.strokeWidth = strokeWidth }
                        node.content = .ellipse(shape)
                    case .polygon(let shape):
                        var shape = shape
                        if let fill = set.fill { shape.fill = fill }
                        if let stroke = set.stroke { shape.stroke = stroke }
                        if let strokeWidth = set.strokeWidth { shape.strokeWidth = strokeWidth }
                        node.content = .polygon(shape)
                    case .path(let shape):
                        var shape = shape
                        if let fill = set.fill { shape.fill = fill }
                        if let stroke = set.stroke { shape.stroke = stroke }
                        if let strokeWidth = set.strokeWidth { shape.strokeWidth = strokeWidth }
                        node.content = .path(shape)
                    case .line(let shape):
                        var shape = shape
                        if let stroke = set.stroke { shape.stroke = stroke }
                        if let strokeWidth = set.strokeWidth { shape.strokeWidth = strokeWidth }
                        node.content = .line(shape)
                    default:
                        break
                    }
                }
            }
            let skipped = matches.nodes.count - edits.count
            applyEdits(edits)

            recordConsentLines(
                headline: "Restyle \(edits.count) layer\(edits.count == 1 ? "" : "s")"
                    + (skipped > 0 ? " (\(skipped) skipped — the properties do not apply to them)" : "")
                    + " — \(matches.scopeWords.capitalizedFirst).",
                matches: matches)
            bulkReceipts.append([
                "kind": "restyleNodes",
                "matched": matches.nodes.count,
                "changed": edits.count,
                "skipped": skipped,
                "sample": matches.sampleNames,
                "notes": ["instance internals are never edited — an instance restyles only as a whole layer"]
            ])
        }

        private mutating func applyToken(predicate: NodePredicate, tokenName: String,
                                         property: TokenProperty) throws {
            // Resolve BY VALUE, BY NAME, against the document as it stands —
            // and never create a link: the receipt says so because it is the
            // one thing a designer would otherwise assume happened.
            let language = model.designLanguage
            let asset = language.assets.first {
                $0.name.compare(tokenName, options: [.caseInsensitive]) == .orderedSame
            }
            let typeStyle = language.typeStyles.first {
                $0.name.compare(tokenName, options: [.caseInsensitive]) == .orderedSame
            }
            guard asset != nil || typeStyle != nil else {
                let available = (language.assets.map(\.name) + language.typeStyles.map(\.name))
                    .sorted().prefix(10).joined(separator: ", ")
                throw SanaaEditError.malformed(
                    "no Design Language entry is named “\(tokenName)”. get_tokens lists the exact names.\(available.isEmpty ? "" : " Closest known: \(available).")")
            }

            var set = RestyleSet()
            switch (property, asset, typeStyle) {
            case (.fill, let paint?, nil), (.stroke, let paint?, nil):
                if property == .fill { set.fill = paint.value } else { set.stroke = paint.value }
            case (.text, nil, _?):
                break // the type style is applied on text layers below
            case (.fill, nil, let style?):
                throw SanaaEditError.malformed(
                    "“\(style.name)” is a type style; property \"fill\" needs a color/gradient token. Use \"property\":\"text\".")
            case (.stroke, nil, let style?):
                throw SanaaEditError.malformed(
                    "“\(style.name)” is a type style; property \"stroke\" needs a color/gradient token. Use \"property\":\"text\".")
            case (.text, let paint?, nil):
                throw SanaaEditError.malformed(
                    "“\(paint.name)” is a color; property \"text\" needs a type style. Use \"property\":\"fill\" or \"stroke\".")
            default:
                throw SanaaEditError.malformed(
                    "token “\(tokenName)” could not be resolved to a property to apply.")
            }

            let matches = try resolveMatches(predicate)
            var edits: [UUID: (inout Node) -> Void] = [:]
            var skipped = 0
            for match in matches.nodes {
                switch (property, match.kind) {
                case (.fill, .rectangle), (.fill, .ellipse), (.fill, .polygon), (.fill, .path),
                     (.stroke, .rectangle), (.stroke, .ellipse), (.stroke, .polygon),
                     (.stroke, .path), (.stroke, .line):
                    guard !set.applicable(on: match.kind).isEmpty else {
                        skipped += 1; continue
                    }
                    edits[match.id] = { node in
                        if let fill = set.fill {
                            switch node.content {
                            case .rectangle(var shape): shape.fill = fill; node.content = .rectangle(shape)
                            case .ellipse(var shape): shape.fill = fill; node.content = .ellipse(shape)
                            case .polygon(var shape): shape.fill = fill; node.content = .polygon(shape)
                            case .path(var shape): shape.fill = fill; node.content = .path(shape)
                            default: break
                            }
                        }
                        if let stroke = set.stroke {
                            switch node.content {
                            case .rectangle(var shape): shape.stroke = stroke; node.content = .rectangle(shape)
                            case .ellipse(var shape): shape.stroke = stroke; node.content = .ellipse(shape)
                            case .polygon(var shape): shape.stroke = stroke; node.content = .polygon(shape)
                            case .path(var shape): shape.stroke = stroke; node.content = .path(shape)
                            case .line(var shape): shape.stroke = stroke; node.content = .line(shape)
                            default: break
                            }
                        }
                    }
                case (.text, .text):
                    guard let style = typeStyle else { break }
                    edits[match.id] = { node in
                        guard case .text(var text) = node.content else { return }
                        text.align = style.align
                        text.lineHeight = style.lineHeight
                        text.lineHeightUnit = style.lineHeightUnit
                        text.tracking = style.tracking
                        text.textCase = style.textCase
                        for runIndex in text.runs.indices {
                            text.runs[runIndex].fontName = style.fontName
                            text.runs[runIndex].fontSize = style.fontSize
                            text.runs[runIndex].underline = style.underline
                        }
                        node.content = .text(text)
                    }
                default:
                    skipped += 1
                }
            }
            applyEdits(edits)
            guard !edits.isEmpty else {
                throw SanaaEditError.malformed(
                    "the token applied to none of the \(matches.nodes.count) matched layer(s) — \(property.rawValue) does not fit their types. Nothing was changed.")
            }

            recordConsentLines(
                headline: "Apply “\(tokenName)” to \(edits.count) layer\(edits.count == 1 ? "" : "s") as \(property.rawValue)"
                    + (skipped > 0 ? " (\(skipped) skipped)" : "")
                    + " — \(matches.scopeWords.capitalizedFirst).",
                matches: matches)
            bulkReceipts.append([
                "kind": "applyToken",
                "token": tokenName,
                "property": property.rawValue,
                "matched": matches.nodes.count,
                "changed": edits.count,
                "skipped": skipped,
                "sample": matches.sampleNames,
                "notes": ["values were SET, not linked — later token changes do not cascade to these layers",
                          "instance internals are never edited"]
            ])
        }

        private mutating func normalizeSpacing(predicate: NodePredicate, unit: CGFloat) throws {
            let matches = try resolveMatches(predicate)

            // Managed gaps: every matched group with a packed auto-layout.
            var groupEdits: [UUID: (inout Node) -> Void] = [:]
            var groupsSnapped = 0
            for match in matches.nodes
            where match.kind == .group {
                groupEdits[match.id] = { node in
                    guard var layout = node.autoLayout,
                          layout.distribution == .packed else { return }
                    let snapped = max(0, (layout.gap / unit).rounded() * unit)
                    if abs(snapped - layout.gap) >= 0.01 {
                        layout.gap = snapped
                        node.autoLayout = layout
                        groupsSnapped += 1
                    }
                }
            }
            applyEdits(groupEdits)

            // Free sibling spacing: the top-level layers of every artboard the
            // scope covers, snapped along the board's dominant stacking axis.
            var boardIDs: [UUID] = []
            switch predicate.scope {
            case .artboard(let id): boardIDs = [id]
            case .page(let pageID):
                if let pageIndex = model.pages.firstIndex(where: { $0.id == pageID }) {
                    boardIDs = model.pages[pageIndex].artboards.map(\.id)
                }
            case .document:
                boardIDs = model.pages.flatMap { $0.artboards.map(\.id) }
            case .selection:
                break // refused at parse time
            }
            var moveEdits: [UUID: (inout Node) -> Void] = [:]
            for boardID in boardIDs {
                guard let page = model.page(containingArtboard: boardID),
                      let pageIndex = model.pages.firstIndex(where: { $0.id == page.id }) else { continue }
                let roots = model.pages[pageIndex].nodes.filter {
                    $0.isVisible
                        && ($0.artboardID ?? model.owningArtboard(of: $0, on: page.id)?.id) == boardID
                }
                guard roots.count >= 2 else { continue }
                let vertical = {
                    let ys = roots.map { $0.frame.minY }
                    let xs = roots.map { $0.frame.minX }
                    return (ys.max() ?? 0) - (ys.min() ?? 0) >= (xs.max() ?? 0) - (xs.min() ?? 0)
                }()
                let ordered = roots.sorted {
                    vertical ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
                }
                var cumulative: CGFloat = 0
                for index in ordered.indices.dropFirst() {
                    let previous = ordered[index - 1]
                    let current = ordered[index]
                    let delta = vertical
                        ? current.frame.minY - previous.frame.maxY
                        : current.frame.minX - previous.frame.maxX
                    let snapped = max(0, (delta / unit).rounded() * unit)
                    cumulative += snapped - delta
                    if abs(cumulative) >= 0.01 {
                        let shift = cumulative
                        let id = current.id
                        moveEdits[id] = { node in
                            if vertical { node.frame.origin.y += shift }
                            else { node.frame.origin.x += shift }
                        }
                    }
                }
            }
            let layersMoved = moveEdits.count
            applyEdits(moveEdits)
            guard groupsSnapped > 0 || layersMoved > 0 else {
                throw SanaaEditError.malformed(
                    "normalizeSpacing found nothing to change — matched groups were already on the \(Int(unit))-pt scale and no artboard needed its free spacing snapped. Nothing was changed.")
            }

            let boardWords = boardIDs.count == 1 ? "1 artboard" : "\(boardIDs.count) artboards"
            recordConsentLines(
                headline: "Normalize spacing to the \(Int(unit))-pt scale — \(groupsSnapped) managed group(s), \(layersMoved) layer(s) moved across \(boardWords). \(matches.scopeWords.capitalizedFirst).",
                matches: matches)
            bulkReceipts.append([
                "kind": "normalizeSpacing",
                "unit": unit,
                "groupsSnapped": groupsSnapped,
                "layersMoved": layersMoved,
                "artboardsConsidered": boardIDs.count,
                "notes": ["free spacing snaps the gaps between a board's top-level layers along its dominant axis; nested free layers are untouched"]
            ])
        }

        private mutating func renameNodes(predicate: NodePredicate, rule: RenameRule) throws {
            let matches = try resolveMatches(predicate)
            var edits: [UUID: (inout Node) -> Void] = [:]
            var renamed: [[String: String]] = []
            var sequenceNumber = 0
            for match in matches.nodes {
                let newName: String
                switch rule {
                case .findReplace(let find, let replace):
                    newName = match.name.replacingOccurrences(of: find, with: replace)
                case .prefix(let prefix):
                    newName = prefix + match.name
                case .suffix(let suffix):
                    newName = match.name + suffix
                case .sequence(let base, let start):
                    newName = "\(base)\(start + sequenceNumber)"
                    sequenceNumber += 1
                }
                guard newName != match.name, !newName.isEmpty else { continue }
                let id = match.id
                edits[id] = { node in node.name = newName }
                if renamed.count < 50 {
                    renamed.append(["id": id.uuidString, "from": match.name, "to": newName])
                }
            }
            applyEdits(edits)
            guard !edits.isEmpty else {
                throw SanaaEditError.malformed(
                    "the rename rule changed none of the \(matches.nodes.count) matched name(s) — every result was identical or empty. Nothing was changed.")
            }

            recordConsentLines(
                headline: "Rename \(edits.count) layer\(edits.count == 1 ? "" : "s") — \(renameRuleWords(rule)). \(matches.scopeWords.capitalizedFirst).",
                matches: matches)
            bulkReceipts.append([
                "kind": "renameNodes",
                "matched": matches.nodes.count,
                "renamed": edits.count,
                "renames": renamed,
                "notes": renamed.count < edits.count
                    ? ["first 50 renames shown of \(edits.count)"] : []
            ] as [String: Any])
        }

        private func renameRuleWords(_ rule: RenameRule) -> String {
            switch rule {
            case .findReplace(let find, let replace):
                return "every “\(find)” becomes “\(replace)”"
            case .prefix(let prefix): return "prefix “\(prefix)”"
            case .suffix(let suffix): return "suffix “\(suffix)”"
            case .sequence(let base, let start): return "sequence “\(base)\(start)…”"
            }
        }

        // MARK: Reference resolution

        private func resolvePage(_ reference: Reference?) throws -> UUID {
            guard let reference else {
                // "Same page" with nothing named means the page this batch just
                // created, or the page the designer is actually looking at.
                if let lastCreatedPage { return lastCreatedPage }
                if let resolved = model.pageID(resolving: activePageID) { return resolved }
                throw SanaaEditError.malformed("this document has no page to draw on.")
            }
            switch reference {
            case .existing(let id):
                guard model.pages.contains(where: { $0.id == id }) else {
                    throw SanaaEditError.malformed("no page exists with id \(id.uuidString).")
                }
                return id
            case .lastCreated:
                guard let lastCreatedPage else {
                    throw SanaaEditError.malformed("\"$last\" was used for a page, but this batch has not created one.")
                }
                return lastCreatedPage
            case .created(let opIndex):
                guard let id = pagesByOpIndex[opIndex] else {
                    throw SanaaEditError.malformed("operation \(opIndex) did not create a page.")
                }
                return id
            }
        }

        private func resolveArtboard(_ reference: Reference) throws -> (artboard: Artboard, pageID: UUID) {
            let id: UUID
            switch reference {
            case .existing(let existing):
                id = existing
            case .lastCreated:
                guard let lastCreatedArtboard else {
                    throw SanaaEditError.malformed("\"$last\" was used for an artboard, but this batch has not created one.")
                }
                id = lastCreatedArtboard
            case .created(let opIndex):
                guard let created = artboardsByOpIndex[opIndex] else {
                    throw SanaaEditError.malformed("operation \(opIndex) did not create an artboard.")
                }
                id = created
            }
            guard let page = model.page(containingArtboard: id),
                  let artboard = page.artboards.first(where: { $0.id == id }) else {
                throw SanaaEditError.malformed("no artboard exists with id \(id.uuidString).")
            }
            return (artboard, page.id)
        }

        // MARK: Recursive node surgery

        /// Replace one node wherever it lives, including inside groups.
        private static func substitute(_ id: UUID, in nodes: inout [Node],
                                       with make: (Node) -> Node) -> Bool {
            for i in nodes.indices {
                if nodes[i].id == id { nodes[i] = make(nodes[i]); return true }
                if case .group(var children) = nodes[i].content {
                    if substitute(id, in: &children, with: make) {
                        nodes[i].content = .group(children: children)
                        return true
                    }
                }
            }
            return false
        }

        private static func node(_ id: UUID, in nodes: [Node]) -> Node? {
            for node in nodes {
                if node.id == id { return node }
                if case .group(let children) = node.content,
                   let match = self.node(id, in: children) { return match }
            }
            return nil
        }

        /// Remove every wanted node wherever it lives, recording what was found.
        private static func prune(_ wanted: Set<UUID>, from nodes: inout [Node],
                                  removed: inout Set<UUID>) -> Bool {
            var changed = false
            var index = 0
            while index < nodes.count {
                if wanted.contains(nodes[index].id) {
                    removed.insert(nodes[index].id)
                    nodes.remove(at: index)
                    changed = true
                    continue
                }
                if case .group(var children) = nodes[index].content {
                    if prune(wanted, from: &children, removed: &removed) {
                        nodes[index].content = .group(children: children)
                        changed = true
                    }
                }
                index += 1
            }
            return changed
        }
    }
}

private extension String {
    /// "the current selection" → "The current selection", for consent lines
    /// that read as sentences without touching the rest of the string.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

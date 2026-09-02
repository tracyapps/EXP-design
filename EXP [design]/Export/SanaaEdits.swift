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
                        client: String) async throws {
        let key = ObjectIdentifier(document)
        if granted.contains(key) { return }
        if let until = declinedUntil[key], until > Date() {
            throw SanaaEditError.consentDeclined(document: name)
        }
        guard !isAsking else { throw SanaaEditError.consentAlreadyOpen }

        isAsking = true
        let allowed = await presentConsent(documentName: name, client: client)
        isAsking = false

        if allowed {
            granted.insert(key)
            declinedUntil[key] = nil
        } else {
            declinedUntil[key] = Date().addingTimeInterval(Self.declineCooldown)
            throw SanaaEditError.consentDeclined(document: name)
        }
    }

    private func presentConsent(documentName: String, client: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "“\(client)” wants to change “\(documentName)”."
            alert.informativeText = """
                Sanaa applies changes from the agent you connected — it is that agent \
                drawing here, not EXP. Changes arrive as ordinary layers you can edit, \
                and each batch is one step you can undo.

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

        /// True when the operation changes something the designer (or an earlier
        /// session) already made, rather than only adding new content. These are
        /// the operations gated behind per-document consent.
        var touchesExistingContent: Bool {
            switch self {
            case .createPage, .createArtboard, .duplicateArtboard: return false
            case .insertNodes(let artboard, _, _):                 return artboard.isExisting
            case .replaceNode, .removeNodes:                       return true
            }
        }
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
        // permission sheet in front of the designer.
        _ = try build(operations, target: target)

        // Pass 3 — consent, decided from the parsed batch and asked for once.
        if operations.contains(where: \.touchesExistingContent) {
            try await SanaaConsent.shared.requireConsent(
                for: target.document, named: target.name, client: client)
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

        return ["created": ["pages": builder.createdPages,
                            "artboards": builder.createdArtboards,
                            "nodes": builder.createdNodes],
                "affected": ["pages": builder.affectedPages,
                             "artboardIds": builder.affectedArtboardIDs,
                             "nodeIds": builder.affectedNodeIDs],
                "undoStep": "Sanaa: \(summary)"]
    }

    /// Apply a parsed batch to a `Document` VALUE. Never touches the live
    /// document, so this doubles as the dry run.
    private static func build(_ operations: [Operation], target: Target) throws -> Builder {
        var builder = Builder(model: target.document.model,
                              activePageID: target.app.activeCanvasPageID)
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

        default:
            throw SanaaEditError.malformed(
                "\"\(op)\" is not an apply_edits operation. Use createPage, createArtboard, duplicateArtboard, insertNodes, replaceNode, or removeNodes.")
        }
    }

    private static func requiredName(_ raw: [String: Any], what: String) throws -> String {
        let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            throw SanaaEditError.malformed("this operation needs a \"name\" for the new \(what).")
        }
        return name
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

        init(model: Document, activePageID: UUID?) {
            self.model = model
            self.activePageID = activePageID
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

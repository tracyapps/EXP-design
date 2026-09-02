//
//  SanaaActivityController.swift
//  EXP [design]
//
//  FEAT-049 — app-wide, session-scoped conversation state above the provider-
//  neutral Sanaa Runtime client. Document mutation still lives exclusively in
//  AgentBridge/SanaaEdits; this controller presents conversation and activity.
//

import AppKit
import Foundation
import Observation

struct SanaaTranscriptEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case designer
        case assistant
        case status
        case appliedBatch
    }

    let id: UUID
    var kind: Kind
    var text: String
    var timestamp: Date
    var isStreaming: Bool
    var receipt: SanaaAppliedBatchReceipt?

    init(id: UUID = UUID(),
         kind: Kind,
         text: String,
         timestamp: Date = Date(),
         isStreaming: Bool = false,
         receipt: SanaaAppliedBatchReceipt? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.receipt = receipt
    }
}

struct SanaaAffectedPage: Equatable {
    var id: UUID
    var name: String
}

struct SanaaAppliedBatchReceipt: Identifiable, Equatable {
    let id: UUID
    let documentID: ObjectIdentifier
    let client: String
    let summary: String
    let timestamp: Date
    let pages: [SanaaAffectedPage]
    let artboardIDs: Set<UUID>
    let nodeIDs: Set<UUID>
    let createdArtboardCount: Int
    let createdNodeCount: Int

    var pageDescription: String {
        if pages.count == 1 { return pages[0].name }
        if pages.isEmpty { return "the current page" }
        return "\(pages.count) pages"
    }
}

final class SanaaCanvasHighlightRequest: NSObject {
    weak var document: ExpDocument?
    let pageID: UUID?
    let artboardIDs: Set<UUID>
    let nodeIDs: Set<UUID>
    let documentRects: [CGRect]

    init(document: ExpDocument,
         pageID: UUID?,
         artboardIDs: Set<UUID>,
         nodeIDs: Set<UUID>,
         documentRects: [CGRect] = []) {
        self.document = document
        self.pageID = pageID
        self.artboardIDs = artboardIDs
        self.nodeIDs = nodeIDs
        self.documentRects = documentRects
    }
}

@MainActor
private final class SanaaResponseOrigin {
    weak var document: ExpDocument?
    let documentID: ObjectIdentifier
    let pageID: UUID?

    init(document: ExpDocument, pageID: UUID?) {
        self.document = document
        documentID = ObjectIdentifier(document)
        self.pageID = pageID
    }
}

extension Notification.Name {
    static let sanaaCanvasHighlight = Notification.Name("exp.sanaa.canvas-highlight")
}

struct SanaaConversationAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
}

@MainActor
@Observable
final class SanaaActivityController {
    static let shared = SanaaActivityController()

    /// A deliberately human-scale description of work Sanaa is doing. Keep
    /// host/tool vocabulary out of the designer-facing presence.
    enum WorkActivity: Equatable {
        case thinking
        case designing
        case working

        var accessibilityLabel: String {
            switch self {
            case .thinking: return "Sanaa is thinking"
            case .designing: return "Sanaa is designing"
            case .working: return "Sanaa is working"
            }
        }
    }

    enum Phase: Equatable {
        case off
        case idle
        case connecting
        case ready
        case replying
        case stopping
        case failed
    }

    private(set) var phase: Phase = .off
    private(set) var transcript: [SanaaTranscriptEntry] = []
    private(set) var transcriptRevision = 0
    private(set) var conversationID: String?
    private(set) var failureCode: SanaaRuntimeErrorCode?
    private(set) var failureMessage: String?
    private(set) var copiedDraft = false
    private(set) var workActivity: WorkActivity?
    private(set) var hostName: String?
    private(set) var hostVersion: String?
    private(set) var account: SanaaRuntimeAccount?
    private(set) var rateLimits: [SanaaRuntimeRateLimit] = []
    private(set) var usageSummary: SanaaRuntimeUsageSummary?
    private(set) var draftFocusRevision = 0
    var draft = ""
    var selectedAgentID = "codex"

    /// Only send-capable runtime adapters belong here. Canvas-only MCP clients
    /// are displayed in Settings but cannot honestly receive a panel prompt.
    var conversationAgents: [SanaaConversationAgent] {
        [SanaaConversationAgent(id: "codex",
                                name: "Codex",
                                detail: "Signed-in local Codex account")]
    }

    var selectedAgent: SanaaConversationAgent {
        conversationAgents.first(where: { $0.id == selectedAgentID })
            ?? conversationAgents[0]
    }

    @ObservationIgnored private let runtime = SanaaRuntimeClient()
    @ObservationIgnored private var pendingMessage: (requestID: String, text: String)?
    @ObservationIgnored private var assistantEntryByRequest: [String: UUID] = [:]
    @ObservationIgnored private var responseOriginByRequest: [String: SanaaResponseOrigin] = [:]
    @ObservationIgnored private var responseOriginByEntry: [UUID: SanaaResponseOrigin] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    private init() {
        runtime.eventHandler = { [weak self] event in self?.receive(event) }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdownRuntime(deletingConversation: true) }
        }
    }

    var isResponding: Bool { phase == .replying || phase == .stopping }

    var canSend: Bool {
        phase == .ready
            && pendingMessage == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyFallback: Bool {
        phase == .failed && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var latestActionableReceipt: SanaaAppliedBatchReceipt? {
        transcript.reversed().compactMap(\.receipt).first(where: canAct(on:))
    }

    var canActOnLatestReceipt: Bool { latestActionableReceipt != nil }

    func transcriptEntry(id: UUID) -> SanaaTranscriptEntry? {
        transcript.first { $0.id == id }
    }

    func canShowResponseElements(_ elements: [SanaaStructuredResponse.Element],
                                 entryID: UUID) -> Bool {
        guard let origin = responseOriginByEntry[entryID],
              let document = origin.document,
              let active = PanelHub.shared.activeDocument else { return false }
        guard ObjectIdentifier(active) == origin.documentID else { return false }
        return elements.contains { !locatedElements($0, in: document.model).isEmpty }
    }

    func responseElementName(_ element: SanaaStructuredResponse.Element,
                             entryID: UUID) -> String {
        guard let origin = responseOriginByEntry[entryID], let document = origin.document,
              let match = locatedElements(element, in: document.model).first else {
            return responseElementFallbackName(element)
        }
        let resolved = match.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? responseElementFallbackName(element) : resolved
    }

    func showResponseElements(_ elements: [SanaaStructuredResponse.Element],
                              entryID: UUID, center: Bool = false) {
        guard let origin = responseOriginByEntry[entryID],
              let document = origin.document,
              let activeDocument = PanelHub.shared.activeDocument,
              let app = PanelHub.shared.activeApp,
              ObjectIdentifier(activeDocument) == origin.documentID else {
            NSSound.beep()
            return
        }
        let matches = elements.flatMap { locatedElements($0, in: document.model) }
        guard let pageID = matches.first?.pageID else {
            NSSound.beep()
            return
        }
        let onPage = matches.filter { $0.pageID == pageID }
        let selectable = Set(onPage.map(\.selectableNodeID))
        app.activeCanvasPageID = pageID
        app.selectedNodeIDs = selectable
        app.selectedArtboardIDs = []
        app.selectionAnchorID = selectable.first
        NotificationCenter.default.post(
            name: .sanaaCanvasHighlight,
            object: SanaaCanvasHighlightRequest(
                document: document, pageID: pageID,
                artboardIDs: [], nodeIDs: [],
                documentRects: onPage.map(\.documentRect)))
        if center { sendCanvasAction("centerSelectionAction:") }
        announce("Highlighted \(onPage.count) \(onPage.count == 1 ? "layer" : "layers") from the Sanaa response.")
    }

    /// Structured reply buttons always stage editable text. They never auto-send.
    func useResponseSuggestion(_ prompt: String) {
        guard let app = PanelHub.shared.activeApp else { return }
        app.revealPanel(.sanaa)
        prepareDraft(prompt)
        if app.workspaceMode == .multiWindow {
            PanelWindowManager.shared.focusPanel(.sanaa)
        } else {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func canAct(on receipt: SanaaAppliedBatchReceipt) -> Bool {
        guard let document = PanelHub.shared.activeDocument,
              ObjectIdentifier(document) == receipt.documentID else { return false }
        return selection(for: receipt, in: document.model).isEmpty == false
    }

    /// Called only by AgentBridge after SanaaEdits has committed successfully.
    /// A Codex notification alone can never manufacture an applied receipt.
    func recordAppliedBatch(client: String,
                            summary: String,
                            document: ExpDocument,
                            pages: [SanaaAffectedPage],
                            artboardIDs: Set<UUID>,
                            nodeIDs: Set<UUID>,
                            createdArtboardCount: Int,
                            createdNodeCount: Int) {
        guard SanaaPreferences.isEnabled else { return }
        // Codex's MCP transport client name is implementation plumbing. While
        // this controller is actively in Sanaa's designing state, present the
        // collaborator the designer addressed—not the relay underneath her.
        let displayedClient = phase == .replying && workActivity == .designing
            ? "Sanaa"
            : client
        let receipt = SanaaAppliedBatchReceipt(
            id: UUID(),
            documentID: ObjectIdentifier(document),
            client: displayedClient,
            summary: summary,
            timestamp: Date(),
            pages: pages,
            artboardIDs: artboardIDs,
            nodeIDs: nodeIDs,
            createdArtboardCount: createdArtboardCount,
            createdNodeCount: createdNodeCount
        )
        append(.init(kind: .appliedBatch,
                     text: summary,
                     timestamp: receipt.timestamp,
                     receipt: receipt))

        NotificationCenter.default.post(
            name: .sanaaCanvasHighlight,
            object: SanaaCanvasHighlightRequest(
                document: document,
                pageID: pages.first?.id,
                artboardIDs: artboardIDs,
                nodeIDs: nodeIDs
            )
        )
        announce(receipt)
    }

    func selectChanges(_ receipt: SanaaAppliedBatchReceipt) {
        guard let document = PanelHub.shared.activeDocument,
              let app = PanelHub.shared.activeApp,
              ObjectIdentifier(document) == receipt.documentID else { return }
        applySelection(selection(for: receipt, in: document.model), document: document, app: app)
    }

    func goToChanges(_ receipt: SanaaAppliedBatchReceipt) {
        guard canAct(on: receipt) else { return }
        selectChanges(receipt)
        sendCanvasAction("centerSelectionAction:")
    }

    func selectLatestChanges() {
        guard let receipt = latestActionableReceipt else { return }
        selectChanges(receipt)
    }

    func goToLatestChanges() {
        guard let receipt = latestActionableReceipt else { return }
        goToChanges(receipt)
    }

    var statusText: String {
        switch phase {
        case .off: return "Sanaa is off"
        case .idle: return "Not connected"
        case .connecting: return "Connecting to local Codex…"
        case .ready: return "Ready"
        case .replying: return workActivity?.accessibilityLabel ?? "Sanaa is replying"
        case .stopping: return "Stopping reply…"
        case .failed: return failureMessage ?? "Sanaa Runtime is unavailable"
        }
    }

    func activate() {
        guard SanaaPreferences.isEnabled else {
            phase = .off
            return
        }
        guard !runtime.isRunning else { return }
        workActivity = nil
        phase = .connecting
        failureCode = nil
        failureMessage = nil
        do {
            try runtime.launch()
        } catch {
            fail(code: .helperUnavailable, message: error.localizedDescription)
        }
    }

    func reconnect() {
        guard SanaaPreferences.isEnabled else { return }
        workActivity = nil
        markStreamingEntriesFinished()
        runtime.shutdown()
        pendingMessage = nil
        phase = .idle
        activate()
    }

    func refreshAccountStatus() {
        guard runtime.isRunning else { return }
        do {
            _ = try runtime.refreshAccountStatus()
        } catch {
            fail(code: .hostDisconnected, message: error.localizedDescription)
        }
    }

    func sendDraft() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let requestID = try runtime.sendMessage(text)
            pendingMessage = (requestID, text)
            if let document = PanelHub.shared.activeDocument {
                let pageID = document.model.pageID(
                    resolving: PanelHub.shared.activeApp?.activeCanvasPageID)
                responseOriginByRequest[requestID] = SanaaResponseOrigin(
                    document: document, pageID: pageID)
            }
        } catch {
            fail(code: .hostDisconnected, message: error.localizedDescription)
        }
    }

    /// FEAT-050 prompt starters enter the same editable composer as ordinary
    /// typing. They never auto-send: the designer reviews and may revise first.
    func prepareDraft(_ text: String) {
        draft = text
        copiedDraft = false
        draftFocusRevision += 1
    }

    func stopReply() {
        guard phase == .replying else { return }
        do {
            _ = try runtime.stop()
            workActivity = nil
            phase = .stopping
        } catch {
            fail(code: .hostDisconnected, message: error.localizedDescription)
        }
    }

    func copyDraftFallback() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedDraft = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.copiedDraft = false
        }
    }

    /// Master-off is a privacy boundary: clear every in-memory transcript/draft
    /// and stop the child processes. Saved dock/tray placement lives elsewhere
    /// and is deliberately untouched.
    func disable() {
        shutdownRuntime(deletingConversation: true)
        SanaaResponseWindowManager.shared.closeAll()
        transcript.removeAll()
        transcriptRevision += 1
        draft = ""
        conversationID = nil
        pendingMessage = nil
        assistantEntryByRequest.removeAll()
        responseOriginByRequest.removeAll()
        responseOriginByEntry.removeAll()
        failureCode = nil
        failureMessage = nil
        copiedDraft = false
        workActivity = nil
        hostName = nil
        hostVersion = nil
        account = nil
        rateLimits = []
        usageSummary = nil
        phase = .off
    }

    private func receive(_ event: SanaaRuntimeEvent) {
        switch event.kind {
        case .ready:
            phase = .connecting
            do {
                _ = try runtime.connect()
            } catch {
                fail(code: .hostDisconnected, message: error.localizedDescription)
            }

        case .hostReady:
            hostName = event.host
            hostVersion = event.hostVersion
            phase = .connecting

        case .accountStatus:
            account = event.account
            rateLimits = event.rateLimits ?? []
            usageSummary = event.usageSummary
            guard event.accountAvailable == true, phase == .connecting else { return }
            do {
                if let conversationID {
                    _ = try runtime.resumeConversation(conversationID)
                } else {
                    _ = try runtime.startConversation()
                }
            } catch {
                fail(code: .hostDisconnected, message: error.localizedDescription)
            }

        case .conversationStarted, .conversationResumed:
            conversationID = event.conversationID
            failureCode = nil
            failureMessage = nil
            workActivity = nil
            phase = .ready

        case .userMessage:
            let text = event.text ?? pendingMessage?.text ?? ""
            append(.init(kind: .designer, text: text))
            if let pendingMessage, pendingMessage.requestID == event.requestID {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == pendingMessage.text {
                    draft = ""
                }
                self.pendingMessage = nil
            }
            workActivity = .thinking
            phase = .replying

        case .assistantDelta:
            receiveDelta(event)

        case .completed:
            workActivity = nil
            finishAssistant(for: event.requestID)
            phase = .ready

        case .interrupted:
            workActivity = nil
            finishAssistant(for: event.requestID)
            append(.init(kind: .status, text: "Reply stopped."))
            phase = .ready

        case .conversationDeleted:
            conversationID = nil

        case .failed:
            let failure = event.failure ?? SanaaRuntimeFailure(
                code: .internalFailure,
                message: "Sanaa Runtime failed without a reason.",
                recoverable: true
            )
            fail(code: failure.code, message: failure.message, addToTranscript: true)

        case .toolRequest:
            workActivity = event.status == "apply_edits" ? .designing : .working
            phase = .replying

        case .toolResult:
            // The model may continue with another read, a write, or its reply.
            // A completed write gets its durable visual receipt from the
            // AgentBridge success path, not from an optimistic host event.
            workActivity = .thinking
            phase = .replying

        case .approvalRequired:
            let message = event.failure?.message
                ?? "Sanaa refused an unexpected host approval request."
            fail(code: .unexpectedHostRequest, message: message, addToTranscript: true)
        }
    }

    private func receiveDelta(_ event: SanaaRuntimeEvent) {
        let key = event.requestID ?? event.turnID ?? "unkeyed"
        let delta = event.text ?? ""
        guard !delta.isEmpty else { return }
        workActivity = nil
        if let id = assistantEntryByRequest[key],
           let index = transcript.firstIndex(where: { $0.id == id }) {
            transcript[index].text += delta
            transcript[index].isStreaming = true
            transcriptRevision += 1
        } else {
            let entry = SanaaTranscriptEntry(kind: .assistant,
                                             text: delta,
                                             isStreaming: true)
            assistantEntryByRequest[key] = entry.id
            if let origin = responseOriginByRequest[key] {
                responseOriginByEntry[entry.id] = origin
            }
            append(entry)
        }
        phase = .replying
    }

    private func finishAssistant(for requestID: String?) {
        if let requestID { responseOriginByRequest[requestID] = nil }
        if let requestID,
           let id = assistantEntryByRequest.removeValue(forKey: requestID),
           let index = transcript.firstIndex(where: { $0.id == id }) {
            transcript[index].isStreaming = false
            transcriptRevision += 1
        } else {
            markStreamingEntriesFinished()
        }
    }

    private func markStreamingEntriesFinished() {
        var changed = false
        for index in transcript.indices where transcript[index].isStreaming {
            transcript[index].isStreaming = false
            changed = true
        }
        assistantEntryByRequest.removeAll()
        responseOriginByRequest.removeAll()
        if changed { transcriptRevision += 1 }
    }

    private func append(_ entry: SanaaTranscriptEntry) {
        transcript.append(entry)
        transcriptRevision += 1
    }

    private struct ReceiptSelection {
        var pageID: UUID?
        var artboardIDs: Set<UUID>
        var nodeIDs: Set<UUID>

        var isEmpty: Bool { artboardIDs.isEmpty && nodeIDs.isEmpty }
    }

    private func selection(for receipt: SanaaAppliedBatchReceipt,
                           in model: Document) -> ReceiptSelection {
        let pageID = receipt.pages.first?.id
            ?? model.pageID(resolving: PanelHub.shared.activeApp?.activeCanvasPageID)
        guard let page = model.page(for: pageID) else {
            return ReceiptSelection(pageID: nil, artboardIDs: [], nodeIDs: [])
        }
        let existingArtboards = Set(page.artboards.map(\.id)).intersection(receipt.artboardIDs)
        let existingNodes = Set(flattenedNodeIDs(page.nodes)).intersection(receipt.nodeIDs)
        // Canvas selection is intentionally one kind at a time. Prefer concrete
        // changed layers; fall back to whole artboards for board-only batches.
        return ReceiptSelection(pageID: page.id,
                                artboardIDs: existingNodes.isEmpty ? existingArtboards : [],
                                nodeIDs: existingNodes)
    }

    private func applySelection(_ selection: ReceiptSelection,
                                document: ExpDocument,
                                app: AppState) {
        guard !selection.isEmpty else { return }
        app.activeCanvasPageID = selection.pageID
        app.selectedNodeIDs = selection.nodeIDs
        app.selectedArtboardIDs = selection.artboardIDs
        app.selectionAnchorID = selection.nodeIDs.first
        NotificationCenter.default.post(
            name: .sanaaCanvasHighlight,
            object: SanaaCanvasHighlightRequest(
                document: document,
                pageID: selection.pageID,
                artboardIDs: selection.artboardIDs,
                nodeIDs: selection.nodeIDs
            )
        )
    }

    private func flattenedNodeIDs(_ nodes: [Node]) -> [UUID] {
        nodes.flatMap { node -> [UUID] in
            if case .group(let children) = node.content {
                return [node.id] + flattenedNodeIDs(children)
            }
            return [node.id]
        }
    }

    private struct LocatedResponseElement {
        var pageID: UUID
        var documentRect: CGRect
        var selectableNodeID: UUID
        var name: String
    }

    private func responseElementFallbackName(_ element: SanaaStructuredResponse.Element) -> String {
        let supplied = element.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return supplied.isEmpty ? "Layer" : supplied
    }

    private func locatedElements(_ reference: SanaaStructuredResponse.Element,
                                 in model: Document) -> [LocatedResponseElement] {
        guard let targetID = reference.uuid else { return [] }
        let wantedPath = reference.instanceUUIDs
        var result: [LocatedResponseElement] = []

        func walk(_ nodes: [Node], pageID: UUID, offset: CGPoint,
                  instancePath: [UUID], outerInstanceID: UUID?) {
            for node in nodes where node.isVisible {
                let absolute = node.frame.offsetBy(dx: offset.x, dy: offset.y)
                if node.id == targetID && (wantedPath.isEmpty || wantedPath == instancePath) {
                    result.append(LocatedResponseElement(
                        pageID: pageID, documentRect: absolute,
                        selectableNodeID: outerInstanceID ?? node.id,
                        name: node.name))
                }
                let childOffset = CGPoint(x: offset.x + node.frame.minX,
                                          y: offset.y + node.frame.minY)
                switch node.content {
                case .group(let children):
                    walk(children, pageID: pageID, offset: childOffset,
                         instancePath: instancePath,
                         outerInstanceID: outerInstanceID)
                case .instance(let instance):
                    let path = instancePath + [node.id]
                    walk(model.resolvedChildren(of: instance), pageID: pageID,
                         offset: childOffset, instancePath: path,
                         outerInstanceID: outerInstanceID ?? node.id)
                default:
                    break
                }
            }
        }

        for page in model.pages {
            walk(page.nodes, pageID: page.id, offset: .zero,
                 instancePath: [], outerInstanceID: nil)
        }
        return result
    }

    /// Apple requires both `.announcement` and `.priority` in the user-info
    /// payload for an announcement request. Medium is informative without
    /// interrupting a higher-priority VoiceOver event.
    private func announce(_ receipt: SanaaAppliedBatchReceipt) {
        let message: String
        if receipt.createdArtboardCount > 0 {
            let noun = receipt.createdArtboardCount == 1 ? "artboard" : "artboards"
            message = "Sanaa added \(receipt.createdArtboardCount) \(noun) on \(receipt.pageDescription)."
        } else if receipt.createdNodeCount > 0 {
            let noun = receipt.createdNodeCount == 1 ? "layer" : "layers"
            message = "Sanaa added \(receipt.createdNodeCount) \(noun) on \(receipt.pageDescription)."
        } else {
            message = "Sanaa finished \(receipt.summary) on \(receipt.pageDescription)."
        }
        guard let application = NSApp else { return }
        let element: Any = application.mainWindow ?? application
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func announce(_ message: String) {
        guard let application = NSApp else { return }
        let element: Any = application.mainWindow ?? application
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])
    }

    private func fail(code: SanaaRuntimeErrorCode,
                      message: String,
                      addToTranscript: Bool = false) {
        workActivity = nil
        markStreamingEntriesFinished()
        pendingMessage = nil
        failureCode = code
        failureMessage = message
        phase = .failed
        if addToTranscript,
           transcript.last?.kind != .status || transcript.last?.text != message {
            append(.init(kind: .status, text: message))
        }
    }

    private func shutdownRuntime(deletingConversation: Bool) {
        if deletingConversation, runtime.isRunning, conversationID != nil, !isResponding {
            _ = try? runtime.deleteConversation()
        }
        runtime.shutdown()
    }
}

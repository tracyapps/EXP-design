//
//  AgentBridge.swift
//  EXP [design]
//
//  Chunk F1 — the dark, read-only MCP spine. A stdio helper relays newline-
//  delimited JSON-RPC over a current-user Unix socket. Nothing listens on the
//  network, and the listener does not exist unless the hidden default is true.
//

import Foundation
import Darwin
import AppKit
import Observation

enum AgentBridgeLocation {
    static let enabledDefaultsKey = "exp.agentBridge.enabled"
    static let unavailableMessage =
        "EXP is not running, or agent access is disabled in EXP's Handoff panel"

    /// The sandbox permits AF_UNIX bind only inside EXP's container. The bundled
    /// (unsandboxed) helper resolves the same container path from our bundle id.
    static func socketURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EXP", isDirectory: true)
            .appendingPathComponent("agent.sock", isDirectory: false)
    }
}

@MainActor
@Observable
final class AgentBridgeController {
    static let shared = AgentBridgeController()

    struct ConnectedClient: Identifiable, Equatable {
        var id: String { rawName }
        let rawName: String
        let displayName: String
        let connectionCount: Int
    }

    @ObservationIgnored private var server: AgentSocketServer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    private(set) var isRunning = false
    private(set) var connectionCount = 0
    private(set) var connectedClients: [ConnectedClient] = []
    private(set) var lastError: String?
    @ObservationIgnored private var clientNamesByConnection: [UUID: String] = [:]

    var unidentifiedConnectionCount: Int {
        max(0, connectionCount - connectedClients.reduce(0) { $0 + $1.connectionCount })
    }

    /// Kept for the single-client status/receipt path. With multiple clients,
    /// request routing supplies the exact connection identity instead.
    var clientName: String? {
        connectedClients.count == 1 ? connectedClients[0].displayName : nil
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AgentBridgeLocation.enabledDefaultsKey)
    }

    private init() {}

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AgentBridgeLocation.enabledDefaultsKey)
        if enabled { start() } else { stop() }
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    private func start() {
        guard server == nil else { return }
        lastError = nil
        do {
            let socketServer = try AgentSocketServer(
                socketURL: AgentBridgeLocation.socketURL(),
                connectionsChanged: { count in
                    Task { @MainActor in
                        let bridge = AgentBridgeController.shared
                        bridge.connectionCount = count
                        if count == 0 {
                            bridge.clientNamesByConnection.removeAll()
                            bridge.rebuildConnectedClients()
                        }
                    }
                },
                connectionClosed: { connectionID in
                    Task { @MainActor in
                        let bridge = AgentBridgeController.shared
                        bridge.clientNamesByConnection.removeValue(forKey: connectionID)
                        bridge.rebuildConnectedClients()
                    }
                },
                handler: { connectionID, request, reply in
                    Task { @MainActor in
                        if let name = Self.initializingClientName(in: request) {
                            AgentBridgeController.shared.recordClient(name, for: connectionID)
                        }
                        let client = AgentBridgeController.shared.clientDisplayName(for: connectionID)
                        reply(await AgentMCPRouter.handle(request, client: client))
                    }
                })
            server = socketServer
            isRunning = true
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            DiagnosticLog.shared.log("Agent bridge did not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        connectionCount = 0
        clientNamesByConnection.removeAll()
        rebuildConnectedClients()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    private static func initializingClientName(in request: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
              json["method"] as? String == "initialize",
              let params = json["params"] as? [String: Any],
              let client = params["clientInfo"] as? [String: Any],
              let name = client["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return name
    }

    private func recordClient(_ name: String, for connectionID: UUID) {
        clientNamesByConnection[connectionID] = name
        rebuildConnectedClients()
    }

    private func clientDisplayName(for connectionID: UUID) -> String {
        guard let rawName = clientNamesByConnection[connectionID] else {
            return "A connected agent"
        }
        return Self.displayName(for: rawName)
    }

    private func rebuildConnectedClients() {
        connectedClients = Dictionary(grouping: clientNamesByConnection.values, by: { $0 })
            .map { rawName, sessions in
                ConnectedClient(rawName: rawName,
                                displayName: Self.displayName(for: rawName),
                                connectionCount: sessions.count)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func displayName(for rawName: String) -> String {
        switch rawName.lowercased() {
        case "codex-mcp-client", "exp-sanaa-runtime": return "Sanaa (Codex)"
        case "claude-code": return "Claude Code"
        case "claude-desktop": return "Claude Desktop"
        default: return rawName
        }
    }
}

@MainActor
private enum AgentMCPRouter {
    private static let protocolVersion = "2025-06-18"
    private static let orientationURI = "exp://orientation"
    private static let sanaaGuideURI = "exp://sanaa/guide"
    private static let sanaaGuideFile = "sanaa-guide"

    /// The Sanaa design knowledge pack: bundled markdown modules served as MCP
    /// resources. Filenames are flat and unique because the synchronized build
    /// flattens bundle resources (same lookup discipline as FontRegistration).
    private static let knowledgeResources: [(uri: String, file: String, name: String, description: String)] = [
        ("exp://sanaa/knowledge/index", "sanaa-knowledge-index", "Sanaa knowledge — index", "Module map and when-to-load guidance for EXP's bundled design knowledge pack."),
        ("exp://sanaa/knowledge/design-principles", "sanaa-knowledge-design-principles", "Sanaa knowledge — design principles", "Hierarchy, alignment, proximity, whitespace, and Gestalt as canvas-checkable observations."),
        ("exp://sanaa/knowledge/color", "sanaa-knowledge-color", "Sanaa knowledge — color", "Palette construction on the document's own tokens: semantic roles, harmony starting points, dark-mode adaptation."),
        ("exp://sanaa/knowledge/typography", "sanaa-knowledge-typography", "Sanaa knowledge — typography", "Type scales, measure, leading, tracking, and hierarchy through text-run facts."),
        ("exp://sanaa/knowledge/spacing-layout", "sanaa-knowledge-spacing-layout", "Sanaa knowledge — spacing & layout", "4/8pt spacing systems, grids, and density as descriptive observation (the document has no spacing tokens)."),
        ("exp://sanaa/knowledge/components-states", "sanaa-knowledge-components-states", "Sanaa knowledge — components & states", "State completeness (hover/focus/active/disabled/error/empty/loading) and form patterns."),
        ("exp://sanaa/knowledge/copy-microcopy", "sanaa-knowledge-copy-microcopy", "Sanaa knowledge — copy & microcopy", "Copy as design material: user-side vocabulary, active voice, error and empty-state patterns."),
        ("exp://sanaa/knowledge/anti-generic", "sanaa-knowledge-anti-generic", "Sanaa knowledge — anti-generic", "Steering rules against generic AI output: documented model-default clusters and the self-revision check."),
        ("exp://sanaa/knowledge/critique-framework", "sanaa-knowledge-critique-framework", "Sanaa knowledge — critique framework", "The structured critique contract: facts first, five finding groups, severity anchors, opt-in fixes."),
        ("exp://sanaa/knowledge/directions", "sanaa-knowledge-directions", "Sanaa knowledge — directions", "Composing 2–4 genuinely distinct directions with explicit style-genome diffs, rationale, and tradeoffs."),
        ("exp://sanaa/knowledge/procedural-tasks", "sanaa-knowledge-procedural-tasks", "Sanaa knowledge — procedural tasks", "Deterministic builds: repeated rows, placeholder data, and pattern replication from measured exemplars."),
        ("exp://sanaa/knowledge/bulk-adjustments", "sanaa-knowledge-bulk-adjustments", "Sanaa knowledge — bulk adjustments", "Compact and spacious variants plus batch edits that preserve layout structure and content floors."),
        ("exp://sanaa/knowledge/a11y-applied", "sanaa-knowledge-a11y-applied", "Sanaa knowledge — applied accessibility", "Canvas workflows for measured contrast, target sizes, semantic roles, focus treatment, and honest limits."),
        ("exp://sanaa/knowledge/style-profile", "sanaa-knowledge-style-profile", "Sanaa knowledge — style grounding", "Document and session style inference, honest memory boundaries, and the clearly labeled future profile contract."),
        ("exp://sanaa/knowledge/voice", "sanaa-knowledge-voice", "Sanaa knowledge — voice", "Sanaa's language rules: draft/suggest framing, banned and allowed claim patterns, exact DO/DON'T strings."),
        ("exp://sanaa/knowledge/a11y-foundations", "sanaa-knowledge-a11y-foundations", "Sanaa knowledge — a11y foundations", "Accessibility standards map (508 / ADA Title II / WCAG / EN 301 549 / EAA), design-stage vs implementation-stage, computable vs judgment checks; facts verified 2026-08-29."),
        ("exp://sanaa/knowledge/styles/swiss-international", "sanaa-knowledge-style-swiss-international", "Sanaa knowledge — style: swiss international", "Style vocabulary: International Typographic Style — grid-ruled, type-led, flat."),
        ("exp://sanaa/knowledge/styles/minimal", "sanaa-knowledge-style-minimal", "Sanaa knowledge — style: minimal", "Style vocabulary: minimal — few elements, generous space, one accent."),
        ("exp://sanaa/knowledge/styles/editorial", "sanaa-knowledge-style-editorial", "Sanaa knowledge — style: editorial", "Style vocabulary: editorial — serif-led, column-based, magazine logic."),
        ("exp://sanaa/knowledge/styles/neo-brutalist", "sanaa-knowledge-style-neo-brutalist", "Sanaa knowledge — style: neo-brutalist", "Style vocabulary: neo-brutalist — heavy borders, hard offset shadows, flat saturated blocks."),
        ("exp://sanaa/knowledge/styles/glassmorphic", "sanaa-knowledge-style-glassmorphic", "Sanaa knowledge — style: glassmorphic", "Style vocabulary: glassmorphic — frosted translucent layers over rich backings."),
        ("exp://sanaa/knowledge/styles/claymorphic", "sanaa-knowledge-style-claymorphic", "Sanaa knowledge — style: claymorphic", "Style vocabulary: claymorphic — soft tactile pastel depth."),
        ("exp://sanaa/knowledge/styles/corporate-safe", "sanaa-knowledge-style-corporate-safe", "Sanaa knowledge — style: corporate safe", "Style vocabulary: corporate safe — the credible neutral default with one brand accent."),
        ("exp://sanaa/knowledge/styles/playful", "sanaa-knowledge-style-playful", "Sanaa knowledge — style: playful", "Style vocabulary: playful — bright, rounded, expressive consumer energy.")
    ]

    static func handle(_ data: Data, client: String) async -> Data? {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return response(id: NSNull(), errorCode: -32600, message: "Invalid JSON-RPC request")
        }

        let id = request["id"]
        // Notifications are deliberately accepted without a response.
        if id == nil { return nil }

        switch method {
        case "initialize":
            return response(id: id!, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:], "resources": [:]],
                "serverInfo": ["name": "EXP [design]", "version": appVersion],
                "instructions": instructions
            ])
        case "ping":
            return response(id: id!, result: [:])
        case "tools/list":
            return response(id: id!, result: ["tools": toolDefinitions])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                return response(id: id!, errorCode: -32602, message: "tools/call requires a tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return response(id: id!, result: await callTool(name, arguments: arguments,
                                                             client: client))
        case "resources/list":
            let knowledge = knowledgeResources.map { entry in
                ["uri": entry.uri,
                 "name": entry.name,
                 "description": entry.description,
                 "mimeType": "text/markdown"]
            }
            return response(id: id!, result: ["resources": [[
                "uri": orientationURI,
                "name": "EXP Handoff Orientation",
                "description": "How to read the frontmost EXP document and its stable ids.",
                "mimeType": "text/markdown"
            ], [
                "uri": sanaaGuideURI,
                "name": "Sanaa agent etiquette",
                "description": "Placement, ids, reviewable batches, Design Language, deletion, consent, and honest failure rules for agents working with an EXP designer.",
                "mimeType": "text/markdown"
            ]] + knowledge])
        case "resources/read":
            guard let params = request["params"] as? [String: Any],
                  let uri = params["uri"] as? String else {
                return response(id: id!, errorCode: -32602, message: "Unknown EXP resource URI")
            }
            if uri == orientationURI {
                guard let context = activeContext() else {
                    return response(id: id!, errorCode: -32002, message: "No EXP document is currently open")
                }
                return response(id: id!, result: ["contents": [[
                    "uri": orientationURI,
                    "mimeType": "text/markdown",
                    "text": orientation(document: context.document, sourceURL: context.sourceURL)
                ]]])
            }
            if uri == sanaaGuideURI {
                guard let text = bundledMarkdown(named: sanaaGuideFile) else {
                    return response(id: id!, errorCode: -32603,
                                    message: "Sanaa etiquette guide missing from the app bundle")
                }
                return response(id: id!, result: ["contents": [[
                    "uri": sanaaGuideURI,
                    "mimeType": "text/markdown",
                    "text": text
                ]]])
            }
            guard let entry = knowledgeResources.first(where: { $0.uri == uri }) else {
                return response(id: id!, errorCode: -32602, message: "Unknown EXP resource URI")
            }
            // The knowledge pack is static reference material: unlike the
            // orientation branch it needs no open document.
            guard let url = Bundle.main.url(forResource: entry.file, withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return response(id: id!, errorCode: -32603,
                                message: "Sanaa knowledge module missing from the app bundle: \(entry.file).md")
            }
            return response(id: id!, result: ["contents": [[
                "uri": entry.uri,
                "mimeType": "text/markdown",
                "text": text
            ]]])
        default:
            return response(id: id!, errorCode: -32601, message: "Method not found: \(method)")
        }
    }

    /// What this connection can actually do, stated at connect time rather than
    /// left for the agent to discover by being refused.
    private static var instructions: String {
        let base = "Read access to the frontmost EXP [design] document. Use node and artboard ids as the only reference currency. Read exp://sanaa/guide (or call get_sanaa_guide) before changing a canvas."
        guard SanaaPreferences.isEnabled else { return base }
        guard SanaaPreferences.isWriteEnabled else {
            return base + " Sanaa is enabled but not allowed to draw, so apply_edits will refuse until the designer turns on \"Allow Sanaa to draw\"."
        }
        return base + " You may also draw with apply_edits: one call is one transaction and one undo step, so send small batches with honest summaries. Ask the designer where work should go when they have not said \u{2014} never guess between editing their artboard in place and putting your work beside it."
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var toolDefinitions: [[String: Any]] {
        SanaaPreferences.isEnabled ? readTools + [applyEditsTool] : readTools
    }

    private static var readTools: [[String: Any]] {[
        tool("get_sanaa_guide",
             "Returns EXP's bundled agent-etiquette guide: placement questions, stable-id discipline, small honest undo batches, token reuse, deletion boundaries, consent, and graceful failure. Read it before changing a canvas.",
             properties: [:], required: []),
        tool("get_design_guidance",
             "Returns one bundled Sanaa design-knowledge markdown module. Read module \"index\" first, then request only modules relevant to the task. This is static reference material and works without an open document.",
             properties: ["module": [
                "type": "string",
                "description": "Knowledge module path from the index, without the exp://sanaa/knowledge/ prefix.",
                "enum": knowledgeResources.map { String($0.uri.dropFirst("exp://sanaa/knowledge/".count)) }
             ]],
             required: ["module"]),
        tool("get_design_facts",
             "Returns bounded, read-only measured facts for one artboard or the current selection: text/non-text contrast pairs with WCAG citations, text and heuristic target sizes, descriptive spacing, fonts, explicit estimates, notAssessed reasons, and truncation. The response contains facts, not compliance verdicts. Pass artboardId, or omit it to use the current selection.",
             properties: ["artboardId": stringProperty("Optional stable artboard UUID. Omit to inspect the current selection.")],
             required: []),
        tool("get_orientation",
             "Returns README.llm.md orientation text for the frontmost EXP document. Example call: {\"name\":\"get_orientation\",\"arguments\":{}}. Example response text begins: # EXP Handoff Package.",
             properties: [:], required: []),
        tool("list_artboards",
             "Returns small artboard summaries only: stable id and name. Example call: {\"name\":\"list_artboards\",\"arguments\":{}}. Example response: {\"artboards\":[{\"id\":\"…\",\"name\":\"Checkout\"}]}.",
             properties: [:], required: []),
        tool("get_artboard",
             "Returns one verbatim design.json artboard plus its owned top-level node fragments. Example call: {\"name\":\"get_artboard\",\"arguments\":{\"id\":\"…\"}}. Example response: {\"artboard\":{…},\"nodes\":[…]}.",
             properties: ["id": stringProperty("Stable artboard UUID from list_artboards.")], required: ["id"]),
        tool("get_selection",
             "Returns verbatim design.json fragments for every currently selected artboard and node. Example call: {\"name\":\"get_selection\",\"arguments\":{}}. Example response: {\"artboards\":[…],\"nodes\":[…]}.",
             properties: [:], required: []),
        tool("get_node",
             "Returns one verbatim design.json node fragment and its document/source scope. Example call: {\"name\":\"get_node\",\"arguments\":{\"id\":\"…\"}}. Example response: {\"node\":{…},\"scope\":\"document\",\"sourceId\":null}.",
             properties: ["id": stringProperty("Stable node UUID from selection or an artboard fragment.")], required: ["id"]),
        tool("get_tokens",
             "Returns the frontmost document Design Language as verbatim W3C Design Tokens JSON. Example call: {\"name\":\"get_tokens\",\"arguments\":{}}. Example response: {\"color\":{\"Primary\":{\"$type\":\"color\",\"$value\":…}}}.",
             properties: [:], required: [])
    ]}

    /// FEAT-048. One write tool, deliberately transactional: the whole batch
    /// applies or nothing does, and the designer gets exactly one undo step.
    private static var applyEditsTool: [String: Any] {
        tool("apply_edits",
             """
             Draws in the frontmost EXP document. ONE call is ONE transaction and ONE undo step named "Sanaa: <summary>", so send small batches you can describe honestly. If any operation is invalid the whole call is refused and nothing changes.

             Operations (max \(SanaaEdits.maxOperations) per call), applied in order:
             - {"op":"createPage","name":"Sanaa \u{2014} Pricing variations"}
             - {"op":"createArtboard","name":"Variation A","frame":{"width":390,"height":844},"placement":{"kind":"samePage"}} \u{2014} placement kind is "samePage" (EXP lays it out to the right of existing content, or after "afterArtboardId"), "newPage" (optional "pageName"), or "exact" (honours "x" and "y" in frame).
             - {"op":"duplicateArtboard","id":"<uuid>","placement":{"kind":"besideOriginal"}} \u{2014} copies the board and the layers it owns.
             - {"op":"insertNodes","artboardId":"$last","nodes":[<design.json node fragments>]} \u{2014} artboardId is a UUID, "$last" for the artboard this batch just created, or "$<op index>". EXP always assigns fresh ids and returns them. Frames are artboard-local for an artboard this batch created and document coordinates for an existing one; override with "coordinates":"artboard"|"document".
             - {"op":"replaceNode","id":"<uuid>","node":{\u{2026}}} \u{2014} keeps the id you name, so relationships survive. Start from the fragment get_node returned.
             - {"op":"removeNodes","ids":["<uuid>"]}

             Node fragments must be the real design.json shape \u{2014} copy what get_node or get_artboard returned and edit it. Anything else is refused with the decoding error.

             Consent: creating pages, artboards, duplicates, and layers inside artboards from this same batch needs only the designer's Sanaa switches. Changing what is already on the canvas (replaceNode, removeNodes, insertNodes into an existing artboard) also asks the designer, per document, once per session. Ask them where work should go rather than assuming; "complete this" means in place OR on a duplicate beside it, and that is their choice, not yours.

             Returns {"created":{"pages":[\u{2026}],"artboards":[\u{2026}],"nodes":[\u{2026}]},"undoStep":"\u{2026}"}.
             """,
             properties: [
                "summary": stringProperty("A short, honest description of what this batch does (120 characters or fewer). It becomes the undo step the designer reads in the Edit menu."),
                "ops": ["type": "array", "description": "The operations to apply, in order.",
                        "items": ["type": "object"]]
             ],
             required: ["summary", "ops"])
    }

    private static func tool(_ name: String, _ description: String,
                             properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties,
                         "required": required, "additionalProperties": false]]
    }

    private static func stringProperty(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private struct ActiveContext {
        var document: Document
        var app: AppState
        var sourceURL: URL?
    }

    private static func activeContext() -> ActiveContext? {
        let hub = PanelHub.shared
        guard let document = hub.activeDocument, let app = hub.activeApp else { return nil }
        return ActiveContext(document: document.model, app: app, sourceURL: hub.activeFileURL)
    }

    private static func callTool(_ name: String,
                                 arguments: [String: Any],
                                 client: String) async -> [String: Any] {
        // Static bundled guidance deliberately needs no active document. Keep it
        // ahead of the live-context gate used by every canvas read/write tool.
        if name == "get_sanaa_guide" {
            guard arguments.isEmpty else { return toolError("get_sanaa_guide accepts no arguments") }
            guard let text = bundledMarkdown(named: sanaaGuideFile) else {
                return toolError("Sanaa etiquette guide is missing from the app bundle")
            }
            return toolText(text)
        }
        if name == "get_design_guidance" {
            return designGuidance(arguments)
        }
        guard let context = activeContext() else { return toolError("No EXP document is currently open") }
        do {
            switch name {
            case "get_orientation":
                guard arguments.isEmpty else { return toolError("get_orientation accepts no arguments") }
                return toolText(orientation(document: context.document, sourceURL: context.sourceURL))
            case "get_design_facts":
                guard arguments.keys.allSatisfy({ $0 == "artboardId" }),
                      arguments.count <= 1 else {
                    return toolError("get_design_facts accepts only optional artboardId; omit it to use the current selection")
                }
                let artboardID: UUID?
                if let raw = arguments["artboardId"] {
                    guard let string = raw as? String, let parsed = UUID(uuidString: string) else {
                        return toolError("get_design_facts artboardId must be one valid UUID string")
                    }
                    artboardID = parsed
                } else {
                    artboardID = nil
                }
                let facts = try SanaaFacts.report(
                    document: context.document, artboardID: artboardID,
                    selectedNodeIDs: context.app.selectedNodeIDs,
                    selectedArtboardIDs: context.app.selectedArtboardIDs)
                return toolJSON(try jsonObject(facts))
            case "list_artboards":
                guard arguments.isEmpty else { return toolError("list_artboards accepts no arguments") }
                let summaries = context.document.allArtboards.map {
                    ["id": $0.id.uuidString, "name": $0.name]
                }
                return toolJSON(["artboards": summaries])
            case "get_artboard":
                guard arguments.count == 1, let raw = arguments["id"] as? String,
                      let id = UUID(uuidString: raw) else { return toolError("get_artboard requires one valid UUID string named id") }
                guard let artboard = context.document.allArtboards.first(where: { $0.id == id }),
                      let page = context.document.page(containingArtboard: id) else {
                    return toolError("No artboard exists with id \(raw)")
                }
                let nodes = page.nodes.filter {
                    context.document.owningArtboard(of: $0, on: page.id)?.id == id
                }
                return toolJSON(["artboard": try jsonObject(artboard), "nodes": try jsonObject(nodes)])
            case "get_selection":
                guard arguments.isEmpty else { return toolError("get_selection accepts no arguments") }
                let artboards = context.document.allArtboards.filter { context.app.selectedArtboardIDs.contains($0.id) }
                let nodes = context.app.selectedNodeIDs.compactMap { findNode($0, in: context.document)?.node }
                return toolJSON(["artboards": try jsonObject(artboards), "nodes": try jsonObject(nodes)])
            case "get_node":
                guard arguments.count == 1, let raw = arguments["id"] as? String,
                      let id = UUID(uuidString: raw) else { return toolError("get_node requires one valid UUID string named id") }
                guard let found = findNode(id, in: context.document) else {
                    return toolError("No node exists with id \(raw)")
                }
                return toolJSON(["node": try jsonObject(found.node), "scope": found.scope,
                                 "sourceId": found.sourceID?.uuidString ?? NSNull()])
            case "apply_edits":
                return await applyEdits(arguments, client: client)
            case "get_tokens":
                guard arguments.isEmpty else { return toolError("get_tokens accepts no arguments") }
                let data = try DesignLanguageIO.exportDesignTokensJSON(context.document.designLanguage)
                let value = try JSONSerialization.jsonObject(with: data)
                return toolJSON(value)
            default:
                return toolError("Unknown EXP tool: \(name)")
            }
        } catch let error as SanaaFacts.FactsError {
            return toolError(error.localizedDescription)
        } catch {
            return toolError("EXP could not serialize this response: \(error.localizedDescription)")
        }
    }

    private static func designGuidance(_ arguments: [String: Any]) -> [String: Any] {
        guard arguments.count == 1,
              let module = arguments["module"] as? String else {
            return toolError("get_design_guidance requires one string named module; use \"index\" first")
        }
        let uri = "exp://sanaa/knowledge/\(module)"
        guard let entry = knowledgeResources.first(where: { $0.uri == uri }) else {
            return toolError("Unknown Sanaa knowledge module: \(module). Use get_design_guidance with module \"index\" for the module map.")
        }
        guard let url = Bundle.main.url(forResource: entry.file, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return toolError("Sanaa knowledge module is missing from the app bundle: \(entry.file).md")
        }
        return toolText(text)
    }

    private static func bundledMarkdown(named file: String) -> String? {
        guard let url = Bundle.main.url(forResource: file, withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The one write path. Every gate lives in `SanaaEdits`; this only supplies
    /// the live document, its undo manager, and the name of the agent asking, so
    /// the consent sheet can say who is at the door.
    private static func applyEdits(_ arguments: [String: Any],
                                   client: String) async -> [String: Any] {
        let hub = PanelHub.shared
        guard let document = hub.activeDocument, let app = hub.activeApp else {
            return toolError(SanaaEditError.noDocument.localizedDescription)
        }
        let name = hub.activeFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        do {
            let result = try await SanaaEdits.apply(
                arguments: arguments, client: client,
                target: SanaaEdits.Target(document: document, app: app,
                                          undoManager: hub.activeUndo, name: name))
            recordAppliedBatch(result,
                               summary: arguments["summary"] as? String ?? "Canvas update",
                               client: client,
                               document: document)
            return toolJSON(result)
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    /// FEAT-049's activity truth starts here, after the live document commit.
    /// Host-side tool notifications are intentionally insufficient evidence.
    private static func recordAppliedBatch(_ result: [String: Any],
                                           summary: String,
                                           client: String,
                                           document: ExpDocument) {
        let affected = result["affected"] as? [String: Any] ?? [:]
        let pages: [SanaaAffectedPage] = (affected["pages"] as? [[String: String]] ?? [])
            .compactMap { value in
                guard let rawID = value["id"], let id = UUID(uuidString: rawID),
                      let name = value["name"] else { return nil }
                return SanaaAffectedPage(id: id, name: name)
            }
        let artboardIDs = Set((affected["artboardIds"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:)))
        let nodeIDs = Set((affected["nodeIds"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:)))
        let created = result["created"] as? [String: Any] ?? [:]
        SanaaActivityController.shared.recordAppliedBatch(
            client: client,
            summary: summary,
            document: document,
            pages: pages,
            artboardIDs: artboardIDs,
            nodeIDs: nodeIDs,
            createdArtboardCount: (created["artboards"] as? [[String: String]])?.count ?? 0,
            createdNodeCount: (created["nodes"] as? [[String: String]])?.count ?? 0
        )
    }

    private struct FoundNode {
        var node: Node
        var scope: String
        var sourceID: UUID?
    }

    private static func findNode(_ id: UUID, in document: Document) -> FoundNode? {
        func walk(_ nodes: [Node], scope: String, sourceID: UUID?) -> FoundNode? {
            for node in nodes {
                if node.id == id { return FoundNode(node: node, scope: scope, sourceID: sourceID) }
                if case .group(let children) = node.content,
                   let found = walk(children, scope: scope, sourceID: sourceID) { return found }
            }
            return nil
        }
        if let found = walk(document.allNodes, scope: "document", sourceID: nil) { return found }
        for source in document.sources {
            if let found = walk(source.children, scope: "componentSource", sourceID: source.id) { return found }
        }
        return nil
    }

    private static func orientation(document: Document, sourceURL: URL?) -> String {
        HandoffPackageWriter(document: document, sourceURL: sourceURL).orientationMarkdown()
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private static func toolText(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private static func toolJSON(_ value: Any) -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return toolError("EXP could not encode this tool response")
        }
        return toolText(text)
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func response(id: Any, result: Any) -> Data? {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func response(id: Any, errorCode: Int, message: String) -> Data? {
        encode(["jsonrpc": "2.0", "id": id,
                "error": ["code": errorCode, "message": message]])
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

/// POSIX listener kept outside MainActor. Its serial queue owns every descriptor
/// and client buffer; only parsed requests cross to the main-actor router.
private nonisolated final class AgentSocketServer: @unchecked Sendable {
    typealias Handler = @Sendable (UUID, Data, @escaping @Sendable (Data?) -> Void) -> Void
    typealias ConnectionsChanged = @Sendable (Int) -> Void
    typealias ConnectionClosed = @Sendable (UUID) -> Void

    private struct Client {
        var id: UUID
        var readSource: any DispatchSourceRead
        var writeSource: (any DispatchSourceWrite)?
        var readBuffer = Data()
        var writeBuffer = Data()
        /// Set once `readBuffer` exceeds `maxLineBytes` before a terminating
        /// newline turns up. While true, incoming bytes are swallowed (not
        /// buffered) until that newline finally arrives, so one oversized
        /// message cannot grow without bound in memory.
        var discardingOversizedLine = false
    }

    /// NDJSON framing bound for one request line. `SanaaEdits` deliberately
    /// treats this as the payload cap for `apply_edits` (see its `maxOperations`
    /// doc comment) — so hitting it is an expected, not exceptional, shape of
    /// request, and must fail with a JSON-RPC error the caller can read rather
    /// than by silently closing the connection out from under them.
    private static let maxLineBytes = 4 * 1_024 * 1_024

    private static let oversizedLineResponse: Data = {
        let megabytes = maxLineBytes / (1_024 * 1_024)
        let object: [String: Any] = [
            "jsonrpc": "2.0",
            "id": NSNull(),
            "error": ["code": -32003,
                      "message": "EXP could not read this request: one message was larger than the \(megabytes) MB the agent bridge accepts. Split apply_edits into smaller batches."]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32003,\"message\":\"Request too large\"}}".utf8)
        }
        return data
    }()

    private let socketURL: URL
    private let handler: Handler
    private let connectionsChanged: ConnectionsChanged
    private let connectionClosed: ConnectionClosed
    private let queue = DispatchQueue(label: "app.expdesign.agent-bridge")
    private var listener: Int32 = -1
    private var listenerSource: (any DispatchSourceRead)?
    private var clients: [Int32: Client] = [:]

    init(socketURL: URL,
         connectionsChanged: @escaping ConnectionsChanged,
         connectionClosed: @escaping ConnectionClosed,
         handler: @escaping Handler) throws {
        self.socketURL = socketURL
        self.connectionsChanged = connectionsChanged
        self.connectionClosed = connectionClosed
        self.handler = handler
        try start()
    }

    deinit { stop() }

    func stop() {
        queue.sync {
            listenerSource?.cancel()
            listenerSource = nil
            for (fd, client) in clients {
                client.readSource.cancel()
                client.writeSource?.cancel()
                Darwin.close(fd)
            }
            clients.removeAll()
            connectionsChanged(0)
            if listener >= 0 { Darwin.close(listener); listener = -1 }
            unlink(socketURL.path)
        }
    }

    private func start() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("create agent socket") }
        listener = fd
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let error = posixError("make agent socket nonblocking")
            Darwin.close(fd); listener = -1
            throw error
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path.utf8CString
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd); listener = -1
            throw CocoaError(.fileWriteInvalidFileName)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let length = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + path.count
        address.sun_len = UInt8(length)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(length))
            }
        }
        guard bindResult == 0 else {
            let error = posixError("bind agent socket")
            Darwin.close(fd); listener = -1
            throw error
        }
        guard chmod(socketURL.path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            let error = posixError("secure/listen on agent socket")
            Darwin.close(fd); listener = -1; unlink(socketURL.path)
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.setCancelHandler {}
        listenerSource = source
        source.resume()
    }

    private func acceptClients() {
        while true {
            let fd = Darwin.accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else {
                Darwin.close(fd)
                continue
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readClient(fd) }
            source.setCancelHandler {}
            clients[fd] = Client(id: UUID(), readSource: source)
            source.resume()
            connectionsChanged(clients.count)
        }
    }

    private func readClient(_ fd: Int32) {
        var bytes = [UInt8](repeating: 0, count: 32_768)
        let count = Darwin.read(fd, &bytes, bytes.count)
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
        guard count > 0 else { closeClient(fd); return }
        guard var client = clients[fd] else { return }

        if client.discardingOversizedLine {
            // Still swallowing the tail of a message already rejected below;
            // look for its terminating newline in this chunk before resuming
            // normal framing on whatever follows it.
            if let newline = bytes.prefix(count).firstIndex(of: 0x0A) {
                client.discardingOversizedLine = false
                client.readBuffer = Data(bytes[(newline + 1)..<count])
            } else {
                clients[fd] = client
                return
            }
        } else {
            client.readBuffer.append(contentsOf: bytes.prefix(count))
        }

        // A request this large will never be something EXP can parse or hold
        // as one message. Reject it with a JSON-RPC error and keep the
        // connection alive — closing it here (the prior behavior) tore down
        // the whole agent connection over one oversized apply_edits batch,
        // which read to a connected agent as the canvas connection itself
        // vanishing mid-turn rather than as one refused request.
        if !client.readBuffer.contains(0x0A), client.readBuffer.count > Self.maxLineBytes {
            client.readBuffer.removeAll(keepingCapacity: false)
            client.discardingOversizedLine = true
            clients[fd] = client
            DiagnosticLog.shared.log("[Agent bridge] rejected an oversized request (> \(Self.maxLineBytes) bytes) instead of closing the connection")
            enqueue(Self.oversizedLineResponse + Data([0x0A]), to: fd)
            return
        }

        while let newline = client.readBuffer.firstIndex(of: 0x0A) {
            var line = client.readBuffer.subdata(in: client.readBuffer.startIndex..<newline)
            client.readBuffer.removeSubrange(client.readBuffer.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { continue }
            handler(client.id, line) { [weak self] response in
                guard let response else { return }
                self?.queue.async { [weak self] in self?.enqueue(response + Data([0x0A]), to: fd) }
            }
        }
        clients[fd] = client
    }

    private func enqueue(_ data: Data, to fd: Int32) {
        guard clients[fd] != nil else { return }
        clients[fd]?.writeBuffer.append(data)
        flushClient(fd)
    }

    private func flushClient(_ fd: Int32) {
        guard var client = clients[fd] else { return }
        while !client.writeBuffer.isEmpty {
            let written = client.writeBuffer.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.write(fd, base, raw.count)
            }
            if written > 0 {
                client.writeBuffer.removeFirst(written)
                continue
            }
            if written < 0, errno == EINTR { continue }
            if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                if client.writeSource == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
                    source.setEventHandler { [weak self] in self?.flushClient(fd) }
                    source.setCancelHandler {}
                    client.writeSource = source
                    clients[fd] = client
                    source.resume()
                } else {
                    clients[fd] = client
                }
                return
            }
            closeClient(fd)
            return
        }
        client.writeSource?.cancel()
        client.writeSource = nil
        clients[fd] = client
    }

    private func closeClient(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.readSource.cancel()
        client.writeSource?.cancel()
        Darwin.close(fd)
        connectionClosed(client.id)
        connectionsChanged(clients.count)
    }

    private func posixError(_ operation: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not \(operation): \(String(cString: strerror(errno)))"])
    }
}

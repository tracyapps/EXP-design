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

    @ObservationIgnored private var server: AgentSocketServer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    private(set) var isRunning = false
    private(set) var connectionCount = 0
    private(set) var clientName: String?
    private(set) var lastError: String?

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
                        if count == 0 { bridge.clientName = nil }
                    }
                },
                handler: { request, reply in
                    Task { @MainActor in
                        if let name = Self.initializingClientName(in: request) {
                            AgentBridgeController.shared.clientName = name
                        }
                        reply(await AgentMCPRouter.handle(request))
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
        clientName = nil
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
}

@MainActor
private enum AgentMCPRouter {
    private static let protocolVersion = "2025-06-18"
    private static let orientationURI = "exp://orientation"

    static func handle(_ data: Data) async -> Data? {
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
            return response(id: id!, result: await callTool(name, arguments: arguments))
        case "resources/list":
            return response(id: id!, result: ["resources": [[
                "uri": orientationURI,
                "name": "EXP Handoff Orientation",
                "description": "How to read the frontmost EXP document and its stable ids.",
                "mimeType": "text/markdown"
            ]]])
        case "resources/read":
            guard let params = request["params"] as? [String: Any],
                  params["uri"] as? String == orientationURI else {
                return response(id: id!, errorCode: -32602, message: "Unknown EXP resource URI")
            }
            guard let context = activeContext() else {
                return response(id: id!, errorCode: -32002, message: "No EXP document is currently open")
            }
            return response(id: id!, result: ["contents": [[
                "uri": orientationURI,
                "mimeType": "text/markdown",
                "text": orientation(document: context.document, sourceURL: context.sourceURL)
            ]]])
        default:
            return response(id: id!, errorCode: -32601, message: "Method not found: \(method)")
        }
    }

    /// What this connection can actually do, stated at connect time rather than
    /// left for the agent to discover by being refused.
    private static var instructions: String {
        let base = "Read access to the frontmost EXP [design] document. Use node and artboard ids as the only reference currency."
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

    private static func callTool(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        guard let context = activeContext() else { return toolError("No EXP document is currently open") }
        do {
            switch name {
            case "get_orientation":
                guard arguments.isEmpty else { return toolError("get_orientation accepts no arguments") }
                return toolText(orientation(document: context.document, sourceURL: context.sourceURL))
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
                return await applyEdits(arguments)
            case "get_tokens":
                guard arguments.isEmpty else { return toolError("get_tokens accepts no arguments") }
                let data = try DesignLanguageIO.exportDesignTokensJSON(context.document.designLanguage)
                let value = try JSONSerialization.jsonObject(with: data)
                return toolJSON(value)
            default:
                return toolError("Unknown EXP tool: \(name)")
            }
        } catch {
            return toolError("EXP could not serialize this response: \(error.localizedDescription)")
        }
    }

    /// The one write path. Every gate lives in `SanaaEdits`; this only supplies
    /// the live document, its undo manager, and the name of the agent asking, so
    /// the consent sheet can say who is at the door.
    private static func applyEdits(_ arguments: [String: Any]) async -> [String: Any] {
        let hub = PanelHub.shared
        guard let document = hub.activeDocument, let app = hub.activeApp else {
            return toolError(SanaaEditError.noDocument.localizedDescription)
        }
        let name = hub.activeFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let client = AgentBridgeController.shared.clientName ?? "A connected agent"
        do {
            let result = try await SanaaEdits.apply(
                arguments: arguments, client: client,
                target: SanaaEdits.Target(document: document, app: app,
                                          undoManager: hub.activeUndo, name: name))
            return toolJSON(result)
        } catch {
            return toolError(error.localizedDescription)
        }
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
    typealias Handler = @Sendable (Data, @escaping @Sendable (Data?) -> Void) -> Void
    typealias ConnectionsChanged = @Sendable (Int) -> Void

    private struct Client {
        var readSource: any DispatchSourceRead
        var writeSource: (any DispatchSourceWrite)?
        var readBuffer = Data()
        var writeBuffer = Data()
    }

    private let socketURL: URL
    private let handler: Handler
    private let connectionsChanged: ConnectionsChanged
    private let queue = DispatchQueue(label: "app.expdesign.agent-bridge")
    private var listener: Int32 = -1
    private var listenerSource: (any DispatchSourceRead)?
    private var clients: [Int32: Client] = [:]

    init(socketURL: URL, connectionsChanged: @escaping ConnectionsChanged,
         handler: @escaping Handler) throws {
        self.socketURL = socketURL
        self.connectionsChanged = connectionsChanged
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
            clients[fd] = Client(readSource: source)
            source.resume()
            connectionsChanged(clients.count)
        }
    }

    private func readClient(_ fd: Int32) {
        var bytes = [UInt8](repeating: 0, count: 32_768)
        let count = Darwin.read(fd, &bytes, bytes.count)
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
        guard count > 0 else { closeClient(fd); return }
        clients[fd]?.readBuffer.append(contentsOf: bytes.prefix(count))
        guard var client = clients[fd] else { return }
        if client.readBuffer.count > 4 * 1_024 * 1_024 { closeClient(fd); return }
        while let newline = client.readBuffer.firstIndex(of: 0x0A) {
            var line = client.readBuffer.subdata(in: client.readBuffer.startIndex..<newline)
            client.readBuffer.removeSubrange(client.readBuffer.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { continue }
            handler(line) { [weak self] response in
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
        connectionsChanged(clients.count)
    }

    private func posixError(_ operation: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not \(operation): \(String(cString: strerror(errno)))"])
    }
}

import Foundation

enum CodexAdapterError: LocalizedError {
    case unavailable(String)
    case protocolFailure(String)
    case timedOut(String)
    case disconnected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .protocolFailure(let message),
             .timedOut(let message), .disconnected(let message):
            return message
        }
    }
}

enum CodexHostNotification: Sendable {
    case assistantDelta(turnID: String, text: String)
    case toolStarted(turnID: String?, itemID: String?, tool: String, summary: String)
    case toolCompleted(turnID: String?, itemID: String?, tool: String, summary: String, status: String?)
    case turnCompleted(turnID: String, status: String)
    case serverRequest(method: String, turnID: String?)
    case disconnected(message: String)
}

private final class CodexPendingResponse: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var message: [String: Any]?
}

/// The only Codex-specific code in the runtime. Everything above this seam uses
/// `SanaaRuntimeEvent`, so a future Claude adapter cannot leak host JSON into UI.
final class CodexAppServerAdapter: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var nextID = 1
    private var pending: [Int: CodexPendingResponse] = [:]
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var stoppedIntentionally = false

    var notificationHandler: (@Sendable (CodexHostNotification) -> Void)?

    init(executablePath: String,
         currentDirectory: URL,
         codexHome: URL,
         expMCPPath: String,
         timeout: TimeInterval = 90) {
        self.timeout = timeout
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "app-server", "--stdio", "--strict-config",
            "-c", "mcp_servers={}",
            "-c", "mcp_servers.exp-design.command=\(Self.tomlString(expMCPPath))",
            "-c", "mcp_servers.exp-design.enabled_tools=[\"get_orientation\",\"list_artboards\",\"get_artboard\",\"get_selection\",\"get_node\",\"get_tokens\",\"apply_edits\"]",
            // The runtime has no approval UI. `auto` may classify a canvas read
            // as needing approval, which `approvalPolicy=never` then rejects
            // invisibly. `approve` is safe here because `enabled_tools` above is
            // the complete allowlist and EXP still owns write consent + Undo.
            "-c", "mcp_servers.exp-design.default_tools_approval_mode=\"approve\"",
            "-c", "mcp_servers.exp-design.startup_timeout_sec=5",
            "-c", "mcp_servers.exp-design.tool_timeout_sec=120",
            "-c", "web_search=\"disabled\"",
            "-c", "tools.web_search=false",
            "--disable", "shell_tool",
            "--disable", "shell_snapshot",
            "--disable", "unified_exec",
            "--disable", "skill_mcp_dependency_install",
            "--disable", "apps",
            "--disable", "browser_use",
            "--disable", "browser_use_external",
            "--disable", "computer_use",
            "--disable", "image_generation",
            "--disable", "multi_agent",
            "--disable", "plugins",
            "--disable", "workspace_dependencies"
        ]
        process.currentDirectoryURL = currentDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Authentication is a symlink to the account's existing Codex login,
        // prepared by the runtime. Configuration, threads, logs, and every other
        // host artifact stay in Sanaa's isolated app-container directory. This
        // prevents the user's normal MCP/plugin/config setup from leaking in.
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        process.environment = environment
    }

    var isRunning: Bool { process.isRunning }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receive(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.lock.withLock { self?.errorBuffer.append(data) }
        }
        process.terminationHandler = { [weak self] process in
            self?.processTerminated(status: process.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            throw CodexAdapterError.unavailable("Codex could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        lock.withLock { stoppedIntentionally = true }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? input.fileHandleForWriting.close()
        failPending(message: "Codex app-server stopped")
    }

    func initialize() throws -> String? {
        let result = try request("initialize", params: [
            "clientInfo": [
                "name": "exp-sanaa-runtime",
                "title": "EXP Sanaa Runtime",
                "version": "0.1.0"
            ],
            "capabilities": ["experimentalApi": false]
        ])
        try notify("initialized", params: [:])
        return result["userAgent"] as? String
    }

    func accountStatus() throws -> (available: Bool, account: SanaaRuntimeAccount?) {
        let result = try request("account/read", params: ["refreshToken": false])
        guard let value = result["account"] as? [String: Any] else {
            return (false, nil)
        }
        let type = value["type"] as? String ?? "unknown"
        return (true, SanaaRuntimeAccount(type: type,
                                          email: value["email"] as? String,
                                          planType: value["planType"] as? String))
    }

    func rateLimits() throws -> [SanaaRuntimeRateLimit] {
        let result = try request("account/rateLimits/read", params: [:])
        if let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]] {
            return buckets.keys.sorted().compactMap { key in
                Self.rateLimit(from: buckets[key] ?? [:], fallbackID: key)
            }
        }
        guard let bucket = result["rateLimits"] as? [String: Any],
              let parsed = Self.rateLimit(from: bucket, fallbackID: "codex") else { return [] }
        return [parsed]
    }

    func usageSummary() throws -> SanaaRuntimeUsageSummary? {
        let result = try request("account/usage/read", params: [:])
        let summary = result["summary"] as? [String: Any] ?? [:]
        let latest = (result["dailyUsageBuckets"] as? [[String: Any]])?
            .sorted { ($0["startDate"] as? String ?? "") < ($1["startDate"] as? String ?? "") }
            .last
        guard !summary.isEmpty || latest != nil else { return nil }
        return SanaaRuntimeUsageSummary(
            lifetimeTokens: (summary["lifetimeTokens"] as? NSNumber)?.int64Value,
            peakDailyTokens: (summary["peakDailyTokens"] as? NSNumber)?.int64Value,
            currentStreakDays: (summary["currentStreakDays"] as? NSNumber)?.intValue,
            longestStreakDays: (summary["longestStreakDays"] as? NSNumber)?.intValue,
            latestDate: latest?["startDate"] as? String,
            latestTokens: (latest?["tokens"] as? NSNumber)?.int64Value
        )
    }

    func startConversation(cwd: URL) throws -> String {
        let result = try request("thread/start", params: canvasThreadParams(cwd: cwd))
        return try responseString(result, path: "thread", "id")
    }

    func resumeConversation(_ conversationID: String, cwd: URL) throws {
        var params = canvasThreadParams(cwd: cwd)
        params["threadId"] = conversationID
        _ = try request("thread/resume", params: params)
    }

    func startTurn(conversationID: String, text: String) throws -> String {
        let result = try request("turn/start", params: [
            "threadId": conversationID,
            "input": [["type": "text", "text": text]]
        ])
        return try responseString(result, path: "turn", "id")
    }

    func interrupt(conversationID: String, turnID: String) throws {
        _ = try request("turn/interrupt", params: [
            "threadId": conversationID,
            "turnId": turnID
        ])
    }

    func deleteConversation(_ conversationID: String) throws {
        _ = try request("thread/delete", params: ["threadId": conversationID])
    }

    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        guard process.isRunning else {
            throw CodexAdapterError.disconnected("Codex app-server is not running")
        }
        let waiter = CodexPendingResponse()
        let id = lock.withLock { () -> Int in
            let value = nextID
            nextID += 1
            pending[value] = waiter
            return value
        }
        do {
            try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        } catch {
            _ = lock.withLock { pending.removeValue(forKey: id) }
            throw error
        }

        guard waiter.semaphore.wait(timeout: .now() + timeout) == .success else {
            _ = lock.withLock { pending.removeValue(forKey: id) }
            throw CodexAdapterError.timedOut("Timed out waiting for Codex \(method)")
        }
        guard let message = waiter.message else {
            throw CodexAdapterError.disconnected("Codex disconnected during \(method)")
        }
        if let error = message["error"] as? [String: Any] {
            let detail = error["message"] as? String ?? String(describing: error)
            throw CodexAdapterError.protocolFailure("Codex \(method) failed: \(detail)")
        }
        guard let result = message["result"] as? [String: Any] else {
            if message.keys.contains("result") { return [:] }
            throw CodexAdapterError.protocolFailure("Codex \(method) returned no result")
        }
        return result
    }

    private func canvasThreadParams(cwd: URL) -> [String: Any] {
        [
            "cwd": cwd.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "ephemeral": false,
            "baseInstructions": "You are Sanaa, a calm design collaborator inside EXP [design]. Speak in clear, non-technical language. You can inspect and draw on the frontmost EXP canvas through the exp-design tools.",
            "developerInstructions": "Use only exp-design MCP tools. Never run commands, read or write files, browse, use apps, or request Codex approval. Read the selection or relevant artboard before editing. apply_edits is the only write tool: one call is one transaction and one undo step. Use a short honest summary, preserve the designer's existing work, and never guess placement when the request is ambiguous. EXP itself enforces the designer's switches, per-document consent, validation, and undo boundary; accurately explain any refusal instead of trying another route. Never invent an EXP access prompt: describe a prompt only when the tool result explicitly reports one; otherwise say the canvas connection was refused and suggest reconnecting."
        ]
    }

    private static func rateLimit(from value: [String: Any],
                                  fallbackID: String) -> SanaaRuntimeRateLimit? {
        let limitID = value["limitId"] as? String ?? fallbackID
        guard !limitID.isEmpty else { return nil }
        return SanaaRuntimeRateLimit(
            limitID: limitID,
            name: value["limitName"] as? String,
            planType: value["planType"] as? String,
            primary: usageWindow(from: value["primary"] as? [String: Any]),
            secondary: usageWindow(from: value["secondary"] as? [String: Any]),
            reachedType: value["rateLimitReachedType"] as? String
        )
    }

    private static func usageWindow(from value: [String: Any]?) -> SanaaRuntimeUsageWindow? {
        guard let value,
              let usedPercent = (value["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
        return SanaaRuntimeUsageWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowDurationMins: (value["windowDurationMins"] as? NSNumber)?.intValue,
            resetsAt: (value["resetsAt"] as? NSNumber)?.int64Value
        )
    }

    private func notify(_ method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexAdapterError.protocolFailure("Runtime tried to send invalid Codex JSON")
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        let lines: [Data] = lock.withLock {
            outputBuffer.append(data)
            var complete: [Data] = []
            while let newline = outputBuffer.firstIndex(of: 0x0A) {
                complete.append(outputBuffer[..<newline])
                outputBuffer.removeSubrange(...newline)
            }
            return complete
        }
        for line in lines where !line.isEmpty { receiveLine(line) }
    }

    private func receiveLine(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let message = value as? [String: Any] else {
            notificationHandler?(.disconnected(message: "Codex emitted invalid JSON"))
            return
        }

        if let method = message["method"] as? String {
            if message["id"] != nil {
                let params = message["params"] as? [String: Any] ?? [:]
                let turnID = params["turnId"] as? String
                notificationHandler?(.serverRequest(method: method, turnID: turnID))
                rejectServerRequest(message)
            } else {
                receiveNotification(method, params: message["params"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let id = (message["id"] as? NSNumber)?.intValue else { return }
        let waiter = lock.withLock { pending.removeValue(forKey: id) }
        waiter?.message = message
        waiter?.semaphore.signal()
    }

    private func receiveNotification(_ method: String, params: [String: Any]) {
        switch method {
        case "item/agentMessage/delta":
            guard let turnID = params["turnId"] as? String,
                  let delta = params["delta"] as? String else { return }
            notificationHandler?(.assistantDelta(turnID: turnID, text: delta))
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = turn["id"] as? String,
                  let status = turn["status"] as? String else { return }
            notificationHandler?(.turnCompleted(turnID: turnID, status: status))
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any],
                  let type = item["type"] as? String,
                  Self.isToolItem(type) else { return }
            let turnID = params["turnId"] as? String
            let itemID = item["id"] as? String
            let tool = item["tool"] as? String
                ?? item["name"] as? String
                ?? type
            if type == "mcpToolCall", item["server"] as? String != "exp-design" {
                notificationHandler?(.disconnected(message: "Sanaa refused a tool outside EXP's canvas allowlist."))
                // Termination is deliberately asynchronous from the adapter's
                // stdout callback; `stop()` waits for exit and can otherwise
                // block the pipe callback that Codex is trying to finish.
                if process.isRunning { process.terminate() }
                return
            }
            let summary = Self.toolSummary(tool: tool, item: item)
            if method == "item/started" {
                notificationHandler?(.toolStarted(turnID: turnID, itemID: itemID,
                                                  tool: tool, summary: summary))
            } else {
                notificationHandler?(.toolCompleted(turnID: turnID, itemID: itemID,
                                                    tool: tool, summary: summary,
                                                    status: item["status"] as? String))
            }
        default:
            break
        }
    }

    private static func isToolItem(_ type: String) -> Bool {
        switch type {
        case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall",
             "webSearch", "imageGeneration", "computerUse":
            return true
        default:
            return false
        }
    }

    private static func toolSummary(tool: String, item: [String: Any]) -> String {
        if tool == "apply_edits",
           let arguments = item["arguments"] as? [String: Any],
           let summary = arguments["summary"] as? String,
           !summary.isEmpty {
            return summary
        }
        switch tool {
        case "get_orientation": return "Learning how this document is organized"
        case "list_artboards": return "Looking over the artboards"
        case "get_artboard": return "Looking at an artboard"
        case "get_selection": return "Looking at the selection"
        case "get_node": return "Looking at a layer"
        case "get_tokens": return "Looking at the design language"
        case "apply_edits": return "Designing on the canvas"
        default: return tool
        }
    }

    /// MCP execution is owned by Codex and reaches only the configured exp-mcp
    /// process. The runtime still never approves or services a host-initiated
    /// request, so tool/permission drift cannot become action.
    private func rejectServerRequest(_ message: [String: Any]) {
        guard let id = message["id"] else { return }
        try? write([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": -32601,
                "message": "EXP Sanaa Runtime refuses host tool and approval requests outside its canvas-only MCP route"
            ]
        ])
    }

    private func responseString(_ root: [String: Any], path: String...) throws -> String {
        var value: Any = root
        for key in path {
            guard let dictionary = value as? [String: Any], let next = dictionary[key] else {
                throw CodexAdapterError.protocolFailure("Codex response omitted \(path.joined(separator: "."))")
            }
            value = next
        }
        guard let string = value as? String else {
            throw CodexAdapterError.protocolFailure("Codex response field \(path.joined(separator: ".")) was not text")
        }
        return string
    }

    private func processTerminated(status: Int32) {
        let intentional = lock.withLock { stoppedIntentionally }
        failPending(message: "Codex app-server exited with status \(status)")
        guard !intentional else { return }
        let detail = stderrText().trimmingCharacters(in: .whitespacesAndNewlines)
        notificationHandler?(.disconnected(message: detail.isEmpty
            ? "Codex app-server exited with status \(status)"
            : "Codex app-server exited: \(detail)"))
    }

    private func failPending(message: String) {
        let waiters = lock.withLock { () -> [CodexPendingResponse] in
            let values = Array(pending.values)
            pending.removeAll()
            return values
        }
        for waiter in waiters {
            waiter.message = [
                "jsonrpc": "2.0",
                "error": ["code": -32000, "message": message]
            ]
            waiter.semaphore.signal()
        }
    }

    private func stderrText() -> String {
        lock.withLock { String(data: errorBuffer, encoding: .utf8) ?? "" }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

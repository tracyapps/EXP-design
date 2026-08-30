#!/usr/bin/env swift

// Sanaa Runtime spike: prove the Codex app-server conversation transport
// without linking it into EXP or touching an EXP document.

import Foundation

private enum ProbeError: LocalizedError {
    case usage(String)
    case unavailable(String)
    case protocolFailure(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .unavailable(let message),
             .protocolFailure(let message), .timedOut(let message):
            return message
        }
    }
}

private struct Options {
    var codexPath: String?
    var timeout: TimeInterval = 90
    var keepThread = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--codex":
                index += 1
                guard index < arguments.count else {
                    throw ProbeError.usage("--codex needs an executable path")
                }
                options.codexPath = arguments[index]
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let seconds = TimeInterval(arguments[index]), seconds > 0 else {
                    throw ProbeError.usage("--timeout needs a positive number of seconds")
                }
                options.timeout = seconds
            case "--keep-thread":
                options.keepThread = true
            case "--help", "-h":
                print(Self.help)
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.usage("Unknown argument: \(arguments[index])\n\n\(Self.help)")
            }
            index += 1
        }
        return options
    }

    static let help = """
    Usage: xcrun swift scripts/sanaa_runtime_probe.swift [options]

      --codex PATH     Use this Codex executable instead of searching PATH.
      --timeout SEC    Timeout per request/turn (default: 90).
      --keep-thread    Leave the probe thread in Codex history for inspection.

    The probe uses an empty temporary working directory, read-only sandboxing,
    approvalPolicy=never, and text-only instructions. It never connects to EXP.
    """
}

private final class PendingResponse: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var message: [String: Any]?
}

private final class CodexAppServer: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var nextID = 1
    private var pending: [Int: PendingResponse] = [:]
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var completedTurns: [String: String] = [:]
    private var turnWaiters: [String: DispatchSemaphore] = [:]
    private var firstDeltaWaiters: [String: DispatchSemaphore] = [:]
    private var streamedText: [String: String] = [:]
    private var unexpectedServerRequest: String?

    init(codexPath: String, cwd: URL, timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
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
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? input.fileHandleForWriting.close()
    }

    var isRunning: Bool { process.isRunning }

    func initialize() throws {
        _ = try request("initialize", params: [
            "clientInfo": [
                "name": "exp-sanaa-runtime-probe",
                "title": "EXP Sanaa Runtime Probe",
                "version": "0.1.0"
            ],
            "capabilities": ["experimentalApi": false]
        ])
        try notify("initialized", params: [:])
    }

    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        let waiter = PendingResponse()
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
            throw ProbeError.timedOut("Timed out waiting for \(method)")
        }
        guard let message = waiter.message else {
            throw ProbeError.protocolFailure("\(method) returned no JSON-RPC message")
        }
        if let error = message["error"] as? [String: Any] {
            let detail = error["message"] as? String ?? String(describing: error)
            throw ProbeError.protocolFailure("\(method) failed: \(detail)")
        }
        guard let result = message["result"] as? [String: Any] else {
            // Several successful methods intentionally return an empty/null result.
            if message.keys.contains("result") { return [:] }
            throw ProbeError.protocolFailure("\(method) returned no result")
        }
        return result
    }

    func notify(_ method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    func waitForTurn(_ turnID: String) throws -> String {
        let semaphore = lock.withLock { () -> DispatchSemaphore? in
            if completedTurns[turnID] != nil { return nil }
            let waiter = turnWaiters[turnID] ?? DispatchSemaphore(value: 0)
            turnWaiters[turnID] = waiter
            return waiter
        }
        if let semaphore,
           semaphore.wait(timeout: .now() + timeout) != .success {
            throw ProbeError.timedOut("Timed out waiting for turn \(turnID)")
        }
        return try lock.withLock {
            if let unexpectedServerRequest {
                throw ProbeError.protocolFailure(unexpectedServerRequest)
            }
            guard let status = completedTurns[turnID] else {
                throw ProbeError.protocolFailure("Turn \(turnID) completed without a status")
            }
            return status
        }
    }

    func waitForFirstDelta(_ turnID: String) throws {
        let semaphore = lock.withLock { () -> DispatchSemaphore? in
            if !(streamedText[turnID] ?? "").isEmpty { return nil }
            let waiter = firstDeltaWaiters[turnID] ?? DispatchSemaphore(value: 0)
            firstDeltaWaiters[turnID] = waiter
            return waiter
        }
        if let semaphore,
           semaphore.wait(timeout: .now() + timeout) != .success {
            throw ProbeError.timedOut("Timed out waiting for the first streamed delta from turn \(turnID)")
        }
    }

    func text(for turnID: String) -> String {
        lock.withLock { streamedText[turnID] ?? "" }
    }

    func stderrText() -> String {
        lock.withLock { String(data: errorBuffer, encoding: .utf8) ?? "" }
    }

    private func write(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProbeError.protocolFailure("Probe tried to send invalid JSON")
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
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            lock.withLock {
                unexpectedServerRequest = "App server emitted invalid JSON: \(raw)"
            }
            return
        }

        if let method = message["method"] as? String {
            if message["id"] != nil {
                lock.withLock {
                    unexpectedServerRequest = "App server requested \(method); the text-only probe must not request tools or approvals."
                }
                return
            }
            receiveNotification(method, params: message["params"] as? [String: Any] ?? [:])
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
            let waiter = lock.withLock { () -> DispatchSemaphore? in
                streamedText[turnID, default: ""] += delta
                return firstDeltaWaiters.removeValue(forKey: turnID)
            }
            waiter?.signal()
            FileHandle.standardOutput.write(Data(delta.utf8))
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = turn["id"] as? String,
                  let status = turn["status"] as? String else { return }
            let waiter = lock.withLock { () -> DispatchSemaphore? in
                completedTurns[turnID] = status
                return turnWaiters.removeValue(forKey: turnID)
            }
            waiter?.signal()
        default:
            break
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func findCodex(override: String?) throws -> String {
    if let override {
        guard FileManager.default.isExecutableFile(atPath: override) else {
            throw ProbeError.unavailable("Codex is not executable at \(override)")
        }
        return override
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in path.split(separator: ":") {
        let candidate = String(directory) + "/codex"
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    throw ProbeError.unavailable("Codex was not found in PATH. Install it or pass --codex PATH.")
}

private func string(_ object: [String: Any], at keys: String...) throws -> String {
    var value: Any = object
    for key in keys {
        guard let dictionary = value as? [String: Any], let next = dictionary[key] else {
            throw ProbeError.protocolFailure("Missing response field: \(keys.joined(separator: "."))")
        }
        value = next
    }
    guard let result = value as? String else {
        throw ProbeError.protocolFailure("Response field is not text: \(keys.joined(separator: "."))")
    }
    return result
}

private func startTurn(_ client: CodexAppServer, threadID: String, prompt: String) throws -> String {
    let response = try client.request("turn/start", params: [
        "threadId": threadID,
        "input": [["type": "text", "text": prompt]]
    ])
    return try string(response, at: "turn", "id")
}

private func writeStdout(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

private func run() throws {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let codexPath = try findCodex(override: options.codexPath)
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("exp-sanaa-runtime-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }

    print("Sanaa Runtime probe")
    print("Codex: \(codexPath)")
    print("Safety: empty temporary workspace, read-only sandbox, no approvals, no EXP connection\n")

    var activeClient: CodexAppServer? = CodexAppServer(codexPath: codexPath, cwd: temporary,
                                                       timeout: options.timeout)
    var threadIDForCleanup: String?
    defer {
        if !options.keepThread, let threadIDForCleanup, let activeClient,
           activeClient.isRunning {
            _ = try? activeClient.request("thread/delete", params: ["threadId": threadIDForCleanup])
        }
        activeClient?.stop()
    }
    try activeClient!.start()
    try activeClient!.initialize()
    print("PASS  initialize")

    let account = try activeClient!.request("account/read", params: ["refreshToken": false])
    // `requiresOpenaiAuth` describes the provider's auth requirement; it can be
    // true while a valid ChatGPT account is already present. The nullable
    // account object is the signed-in state.
    guard account["account"] is [String: Any] else {
        throw ProbeError.unavailable("Codex app-server is not signed in. Sign in with Codex, then rerun the probe.")
    }
    print("PASS  account available (identity intentionally not printed)")

    let threadResponse = try activeClient!.request("thread/start", params: [
        "cwd": temporary.path,
        "approvalPolicy": "never",
        "sandbox": "read-only",
        "ephemeral": false,
        "developerInstructions": "This is a conversation transport probe. Reply in plain text only. Do not call tools, run commands, read files, use the network, or modify anything."
    ])
    let threadID = try string(threadResponse, at: "thread", "id")
    threadIDForCleanup = threadID
    print("PASS  thread/start")

    writeStdout("STREAM  ")
    let streamTurn = try startTurn(
        activeClient!, threadID: threadID,
        prompt: "Remember the token ORCHID-72 for the next turn. Reply with exactly STREAM_OK."
    )
    let streamStatus = try activeClient!.waitForTurn(streamTurn)
    print("")
    guard streamStatus == "completed", activeClient!.text(for: streamTurn).contains("STREAM_OK") else {
        throw ProbeError.protocolFailure("Streaming turn did not complete with STREAM_OK (status: \(streamStatus))")
    }
    print("PASS  streamed assistant deltas")

    writeStdout("CANCEL  ")
    let cancelTurn = try startTurn(
        activeClient!, threadID: threadID,
        prompt: "Write 200 detailed paragraphs comparing distinct approaches to native desktop agent architecture. Number every paragraph and do not summarize."
    )
    try activeClient!.waitForFirstDelta(cancelTurn)
    _ = try activeClient!.request("turn/interrupt", params: ["threadId": threadID, "turnId": cancelTurn])
    let cancelStatus = try activeClient!.waitForTurn(cancelTurn)
    print("")
    guard cancelStatus == "interrupted" else {
        throw ProbeError.protocolFailure("Cancelled turn ended as \(cancelStatus), expected interrupted")
    }
    print("PASS  turn/interrupt")

    activeClient!.stop()
    activeClient = nil

    let resumed = CodexAppServer(codexPath: codexPath, cwd: temporary, timeout: options.timeout)
    activeClient = resumed
    try resumed.start()
    try resumed.initialize()
    _ = try resumed.request("thread/resume", params: [
        "threadId": threadID,
        "cwd": temporary.path,
        "approvalPolicy": "never",
        "sandbox": "read-only",
        "developerInstructions": "This is a conversation transport probe. Reply in plain text only. Do not call tools, run commands, read files, use the network, or modify anything."
    ])
    print("PASS  thread/resume after app-server restart")

    writeStdout("RESUME  ")
    let resumeTurn = try startTurn(
        resumed, threadID: threadID,
        prompt: "What token did I ask you to remember? Reply with only that token."
    )
    let resumeStatus = try resumed.waitForTurn(resumeTurn)
    print("")
    guard resumeStatus == "completed", resumed.text(for: resumeTurn).contains("ORCHID-72") else {
        throw ProbeError.protocolFailure("Resumed thread did not retain its earlier context")
    }
    print("PASS  resumed conversation retained context")

    if options.keepThread {
        print("KEEP  Codex thread \(threadID)")
    } else {
        _ = try resumed.request("thread/delete", params: ["threadId": threadID])
        threadIDForCleanup = nil
        print("PASS  cleaned up probe thread")
    }

    print("\nRESULT  7/7 passed — the Codex app-server transport is viable for Sanaa.")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\nFAIL  \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

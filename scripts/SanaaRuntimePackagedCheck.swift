import Foundation

private enum CheckError: LocalizedError {
    case usage(String)
    case failed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .failed(let message), .timedOut(let message): return message
        }
    }
}

private struct CheckOptions {
    var runtimePath: String
    var codexPath: String
    var timeout: TimeInterval = 90
    var canvasRead = false
    var knowledgeRead = false
    var knowledgeReadOnly = false
    var factsRead = false
    var factsReadOnly = false

    static func parse(_ arguments: [String]) throws -> CheckOptions {
        var runtimePath: String?
        var codexPath: String?
        var timeout: TimeInterval = 90
        var canvasRead = false
        var knowledgeRead = false
        var knowledgeReadOnly = false
        var factsRead = false
        var factsReadOnly = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--runtime":
                index += 1
                guard index < arguments.count else { throw CheckError.usage("--runtime needs a path") }
                runtimePath = arguments[index]
            case "--codex":
                index += 1
                guard index < arguments.count else { throw CheckError.usage("--codex needs a path") }
                codexPath = arguments[index]
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]), value > 0 else {
                    throw CheckError.usage("--timeout needs positive seconds")
                }
                timeout = value
            case "--canvas-read":
                canvasRead = true
            case "--knowledge-read":
                knowledgeRead = true
            case "--knowledge-read-only":
                knowledgeRead = true
                knowledgeReadOnly = true
            case "--facts-read":
                factsRead = true
            case "--facts-read-only":
                factsRead = true
                factsReadOnly = true
            default:
                throw CheckError.usage("Unknown argument: \(arguments[index])")
            }
            index += 1
        }
        guard let runtimePath, let codexPath else {
            throw CheckError.usage("Usage: packaged-check --runtime PATH --codex PATH [--timeout SEC] [--canvas-read] [--knowledge-read|--knowledge-read-only] [--facts-read|--facts-read-only]")
        }
        return CheckOptions(runtimePath: runtimePath, codexPath: codexPath,
                            timeout: timeout, canvasRead: canvasRead,
                            knowledgeRead: knowledgeRead,
                            knowledgeReadOnly: knowledgeReadOnly,
                            factsRead: factsRead, factsReadOnly: factsReadOnly)
    }
}

private final class RuntimeHarness: @unchecked Sendable {
    let sessionID = UUID().uuidString
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let condition = NSCondition()
    private var buffer = Data()
    private(set) var events: [SanaaRuntimeEvent] = []

    init(runtimePath: String, stateDirectory: URL) {
        process.executableURL = URL(fileURLWithPath: runtimePath)
        process.arguments = ["--state-directory", stateDirectory.path, "--allow-test-parent"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receive(data)
        }
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        try process.run()
    }

    @discardableResult
    func send(_ kind: SanaaRuntimeCommandKind,
              hostExecutablePath: String? = nil,
              conversationID: String? = nil,
              text: String? = nil,
              protocolVersion: Int = SanaaRuntimeProtocol.version,
              sessionID overrideSessionID: String? = nil) throws -> String {
        var command = SanaaRuntimeCommand(sessionID: overrideSessionID ?? sessionID,
                                          kind: kind,
                                          hostExecutablePath: hostExecutablePath,
                                          conversationID: conversationID,
                                          text: text)
        command.protocolVersion = protocolVersion
        var data = try encoder.encode(command)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
        return command.requestID
    }

    func waitFor(kind: SanaaRuntimeEventKind,
                 requestID: String? = nil,
                 timeout: TimeInterval) throws -> SanaaRuntimeEvent {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let match = events.first(where: {
                $0.kind == kind && (requestID == nil || $0.requestID == requestID)
            }) {
                return match
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 || !condition.wait(until: Date().addingTimeInterval(remaining)) {
                throw CheckError.timedOut("Timed out waiting for runtime event \(kind.rawValue)")
            }
        }
    }

    func waitForFailure(code: SanaaRuntimeErrorCode,
                        requestID: String? = nil,
                        timeout: TimeInterval) throws -> SanaaRuntimeEvent {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let match = events.first(where: {
                $0.kind == .failed && $0.failure?.code == code
                    && (requestID == nil || $0.requestID == requestID)
            }) {
                return match
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 || !condition.wait(until: Date().addingTimeInterval(remaining)) {
                throw CheckError.timedOut("Timed out waiting for failure \(code.rawValue)")
            }
        }
    }

    func streamedText(turnID: String) -> String {
        condition.withLock {
            events.compactMap { event in
                event.kind == .assistantDelta && event.turnID == turnID ? event.text : nil
            }.joined()
        }
    }

    func toolEventCount(turnID: String) -> Int {
        condition.withLock {
            events.filter {
                $0.turnID == turnID && ($0.kind == .toolRequest
                    || $0.kind == .toolResult || $0.kind == .approvalRequired)
            }.count
        }
    }

    func eventCount(kind: SanaaRuntimeEventKind, turnID: String) -> Int {
        condition.withLock {
            events.filter { $0.turnID == turnID && $0.kind == kind }.count
        }
    }

    func toolStatuses(kind: SanaaRuntimeEventKind, turnID: String) -> [String] {
        condition.withLock {
            events.compactMap { event in
                event.turnID == turnID && event.kind == kind ? event.status : nil
            }
        }
    }

    func terminate() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? input.fileHandleForWriting.close()
    }

    func shutdown() {
        _ = try? send(.shutdown)
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.waitUntilExit() }
        output.fileHandleForReading.readabilityHandler = nil
    }

    func stderrText() -> String {
        guard let data = try? errors.fileHandleForReading.readToEnd(), !data.isEmpty else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func receive(_ data: Data) {
        condition.lock()
        buffer.append(data)
        var decoded: [SanaaRuntimeEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let event = try? decoder.decode(SanaaRuntimeEvent.self, from: line) {
                decoded.append(event)
            }
        }
        events.append(contentsOf: decoded)
        condition.broadcast()
        condition.unlock()
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

@main
private enum SanaaRuntimePackagedCheck {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\nFAIL  \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let options = try CheckOptions.parse(Array(CommandLine.arguments.dropFirst()))
        guard FileManager.default.isExecutableFile(atPath: options.runtimePath) else {
            throw CheckError.failed("Runtime is not executable at \(options.runtimePath)")
        }
        guard FileManager.default.isExecutableFile(atPath: options.codexPath) else {
            throw CheckError.failed("Codex is not executable at \(options.codexPath)")
        }

        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exp-sanaa-packaged-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        print("Sanaa Runtime packaged IPC check")
        print("Runtime: \(options.runtimePath)")
        print("Safety: isolated Codex home, empty runtime workspace, EXP-only canvas allowlist\n")

        try checkNegativeContract(options: options, stateDirectory: stateDirectory)

        var harness = RuntimeHarness(runtimePath: options.runtimePath, stateDirectory: stateDirectory)
        try harness.start()
        var conversationID: String?
        defer {
            if harness.isRunning, let conversationID {
                _ = try? harness.send(.deleteConversation, conversationID: conversationID)
            }
            if harness.isRunning { harness.shutdown() }
        }

        let hello = try harness.send(.hello)
        _ = try harness.waitFor(kind: .ready, requestID: hello, timeout: options.timeout)
        let connect = try harness.send(.connect, hostExecutablePath: options.codexPath)
        _ = try harness.waitFor(kind: .hostReady, requestID: connect, timeout: options.timeout)
        print("PASS  1/7 packaged session bind + Codex initialize")

        let account = try harness.waitFor(kind: .accountStatus,
                                          requestID: connect,
                                          timeout: options.timeout)
        guard account.accountAvailable == true else { throw CheckError.failed("Codex account is unavailable") }
        let refresh = try harness.send(.refreshAccountStatus)
        let refreshedAccount = try harness.waitFor(kind: .accountStatus,
                                                   requestID: refresh,
                                                   timeout: options.timeout)
        guard refreshedAccount.accountAvailable == true else {
            throw CheckError.failed("Codex account refresh reported unavailable")
        }
        let optionalDetails = [refreshedAccount.account != nil,
                               refreshedAccount.rateLimits != nil,
                               refreshedAccount.usageSummary != nil]
            .filter { $0 }.count
        print("PASS  2/7 signed-in account + explicit status refresh (\(optionalDetails)/3 optional detail surfaces returned; identity intentionally not printed)")

        let start = try harness.send(.startConversation)
        let started = try harness.waitFor(kind: .conversationStarted,
                                          requestID: start,
                                          timeout: options.timeout)
        guard let startedID = started.conversationID else {
            throw CheckError.failed("Runtime started a conversation without an id")
        }
        conversationID = startedID
        print("PASS  3/7 restricted conversation start")

        if options.canvasRead {
            let read = try harness.send(
                .sendMessage,
                conversationID: startedID,
                text: "Use exp-design list_artboards, then use get_artboard on the first returned artboard id. After both calls succeed, reply with exactly CANVAS_READ_OK."
            )
            let readUser = try harness.waitFor(kind: .userMessage,
                                               requestID: read,
                                               timeout: options.timeout)
            guard let readTurnID = readUser.turnID else {
                throw CheckError.failed("Canvas read turn has no id")
            }
            _ = try harness.waitFor(kind: .completed, requestID: read, timeout: options.timeout)
            let requestStatuses = harness.toolStatuses(kind: .toolRequest, turnID: readTurnID)
            guard requestStatuses.contains("list_artboards"),
                  requestStatuses.contains("get_artboard"),
                  harness.eventCount(kind: .toolResult, turnID: readTurnID) >= 2,
                  harness.eventCount(kind: .approvalRequired, turnID: readTurnID) == 0,
                  harness.streamedText(turnID: readTurnID).contains("CANVAS_READ_OK") else {
                throw CheckError.failed(
                    "Canvas read was not pre-approved (requests=\(requestStatuses), approvals=\(harness.eventCount(kind: .approvalRequired, turnID: readTurnID)))"
                )
            }
            print("PASS  canvas read: list_artboards → get_artboard ran with no invisible approval boundary")
        }

        if options.knowledgeRead {
            let read = try harness.send(
                .sendMessage,
                conversationID: startedID,
                text: "Call exp-design get_design_guidance with module index. Find the knowledge-pack version stated in its opening paragraph. Reply with exactly KNOWLEDGE_READ_OK followed by a colon and the digits-only semantic version (omit any leading v). Do not infer or guess the version if the tool is unavailable."
            )
            let readUser = try harness.waitFor(kind: .userMessage,
                                               requestID: read,
                                               timeout: options.timeout)
            guard let readTurnID = readUser.turnID else {
                throw CheckError.failed("Knowledge resource-read turn has no id")
            }
            _ = try harness.waitFor(kind: .completed, requestID: read, timeout: options.timeout)
            let answer = harness.streamedText(turnID: readTurnID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let requestStatuses = harness.toolStatuses(kind: .toolRequest, turnID: readTurnID)
            guard requestStatuses.contains("get_design_guidance"),
                  harness.eventCount(kind: .toolResult, turnID: readTurnID) >= 1,
                  harness.eventCount(kind: .approvalRequired, turnID: readTurnID) == 0,
                  answer == "KNOWLEDGE_READ_OK:2.0.0" else {
                throw CheckError.failed("Packaged Codex thread could not read the knowledge index (requests=\(requestStatuses), approvals=\(harness.eventCount(kind: .approvalRequired, turnID: readTurnID)), answer=\(answer))")
            }
            print("PASS  knowledge read: packaged Codex thread called get_design_guidance with no approval boundary")
            if options.knowledgeReadOnly {
                print("\nRESULT  FEAT-054 packaged knowledge-resource gate passed.")
                return
            }
        }

        if options.factsRead {
            let read = try harness.send(
                .sendMessage,
                conversationID: startedID,
                text: "Call exp-design list_artboards. Then call exp-design get_design_facts with artboardId set to the first returned artboard id. If and only if the facts result has schemaVersion 1 and interpretation exactly measured facts, not verdicts, reply with exactly FACTS_READ_OK:1. Do not infer or guess if either tool is unavailable."
            )
            let readUser = try harness.waitFor(kind: .userMessage,
                                               requestID: read,
                                               timeout: options.timeout)
            guard let readTurnID = readUser.turnID else {
                throw CheckError.failed("Facts read turn has no id")
            }
            _ = try harness.waitFor(kind: .completed, requestID: read,
                                    timeout: options.timeout)
            let answer = harness.streamedText(turnID: readTurnID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let requestStatuses = harness.toolStatuses(kind: .toolRequest,
                                                       turnID: readTurnID)
            guard requestStatuses.contains("list_artboards"),
                  requestStatuses.contains("get_design_facts"),
                  harness.eventCount(kind: .toolResult, turnID: readTurnID) >= 2,
                  harness.eventCount(kind: .approvalRequired, turnID: readTurnID) == 0,
                  answer == "FACTS_READ_OK:1" else {
                throw CheckError.failed("Packaged Codex thread could not read measured design facts (requests=\(requestStatuses), approvals=\(harness.eventCount(kind: .approvalRequired, turnID: readTurnID)), answer=\(answer))")
            }
            print("PASS  facts read: list_artboards → get_design_facts ran with no approval boundary")
            if options.factsReadOnly {
                print("\nRESULT  FEAT-055 packaged computed-facts gate passed.")
                return
            }
        }

        let stream = try harness.send(
            .sendMessage,
            conversationID: startedID,
            text: "Remember the token ORCHID-72. Reply with exactly STREAM_OK."
        )
        let user = try harness.waitFor(kind: .userMessage, requestID: stream, timeout: options.timeout)
        guard let streamTurnID = user.turnID else { throw CheckError.failed("Stream turn has no id") }
        let streamDone = try harness.waitFor(kind: .completed,
                                             requestID: stream,
                                             timeout: options.timeout)
        guard streamDone.status == "completed",
              harness.streamedText(turnID: streamTurnID).contains("STREAM_OK"),
              harness.toolEventCount(turnID: streamTurnID) == 0 else {
            throw CheckError.failed("Stream did not complete without an unexpected tool call")
        }
        print("PASS  4/7 normalized assistant deltas, with no tool/approval events")

        let long = try harness.send(
            .sendMessage,
            conversationID: startedID,
            text: "Write 200 detailed numbered paragraphs about native desktop agent architecture."
        )
        let longUser = try harness.waitFor(kind: .userMessage, requestID: long, timeout: options.timeout)
        guard let longTurnID = longUser.turnID else { throw CheckError.failed("Stop turn has no id") }
        _ = try harness.waitFor(kind: .assistantDelta, requestID: long, timeout: options.timeout)
        let stop = try harness.send(.stop, conversationID: startedID)
        _ = stop
        let interrupted = try harness.waitFor(kind: .interrupted,
                                              requestID: long,
                                              timeout: options.timeout)
        guard interrupted.status == "interrupted",
              harness.toolEventCount(turnID: longTurnID) == 0 else {
            throw CheckError.failed("Stop did not interrupt the exact active turn")
        }
        print("PASS  5/7 Stop interrupted the exact active turn")

        harness.terminate()
        harness = RuntimeHarness(runtimePath: options.runtimePath, stateDirectory: stateDirectory)
        try harness.start()
        let secondHello = try harness.send(.hello)
        _ = try harness.waitFor(kind: .ready, requestID: secondHello, timeout: options.timeout)
        let secondConnect = try harness.send(.connect, hostExecutablePath: options.codexPath)
        _ = try harness.waitFor(kind: .accountStatus, requestID: secondConnect, timeout: options.timeout)
        let resume = try harness.send(.resumeConversation, conversationID: startedID)
        _ = try harness.waitFor(kind: .conversationResumed,
                                requestID: resume,
                                timeout: options.timeout)
        print("PASS  6/7 helper loss + new helper/Codex process resumed the thread")

        let recall = try harness.send(
            .sendMessage,
            conversationID: startedID,
            text: "What token did I ask you to remember? Reply with only that token."
        )
        let recallUser = try harness.waitFor(kind: .userMessage,
                                             requestID: recall,
                                             timeout: options.timeout)
        guard let recallTurnID = recallUser.turnID else { throw CheckError.failed("Recall turn has no id") }
        _ = try harness.waitFor(kind: .completed, requestID: recall, timeout: options.timeout)
        guard harness.streamedText(turnID: recallTurnID).contains("ORCHID-72"),
              harness.toolEventCount(turnID: recallTurnID) == 0 else {
            throw CheckError.failed("Resumed conversation lost context or made an unexpected tool call")
        }
        let delete = try harness.send(.deleteConversation, conversationID: startedID)
        _ = try harness.waitFor(kind: .conversationDeleted,
                                requestID: delete,
                                timeout: options.timeout)
        conversationID = nil
        harness.shutdown()
        print("PASS  7/7 retained context and deleted the exact probe conversation")
        print("\nRESULT  7/7 packaged IPC contract passed; negative trust/protocol gates 4/4 passed.")
    }

    private static func checkNegativeContract(options: CheckOptions,
                                              stateDirectory: URL) throws {
        var harness = RuntimeHarness(runtimePath: options.runtimePath, stateDirectory: stateDirectory)
        try harness.start()
        let hello = try harness.send(.hello)
        _ = try harness.waitFor(kind: .ready, requestID: hello, timeout: options.timeout)
        let badVersion = try harness.send(.connect,
                                          hostExecutablePath: options.codexPath,
                                          protocolVersion: SanaaRuntimeProtocol.version + 1)
        _ = try harness.waitForFailure(code: .invalidProtocol,
                                       requestID: badVersion,
                                       timeout: options.timeout)
        harness.shutdown()
        print("PASS  negative: unsupported EXP protocol refused")

        harness = RuntimeHarness(runtimePath: options.runtimePath, stateDirectory: stateDirectory)
        try harness.start()
        let secondHello = try harness.send(.hello)
        _ = try harness.waitFor(kind: .ready, requestID: secondHello, timeout: options.timeout)
        let wrongSession = try harness.send(.connect,
                                            hostExecutablePath: options.codexPath,
                                            sessionID: "wrong-session")
        _ = try harness.waitForFailure(code: .unauthenticated,
                                       requestID: wrongSession,
                                       timeout: options.timeout)
        harness.terminate()
        print("PASS  negative: cross-session message refused")

        harness = RuntimeHarness(runtimePath: options.runtimePath, stateDirectory: stateDirectory)
        try harness.start()
        let thirdHello = try harness.send(.hello)
        _ = try harness.waitFor(kind: .ready, requestID: thirdHello, timeout: options.timeout)
        let missing = try harness.send(.connect,
                                       hostExecutablePath: "/definitely/missing/exp-codex")
        _ = try harness.waitForFailure(code: .hostMissing,
                                       requestID: missing,
                                       timeout: options.timeout)
        let untrusted = try harness.send(.connect, hostExecutablePath: "/bin/echo")
        _ = try harness.waitForFailure(code: .hostLaunchFailed,
                                       requestID: untrusted,
                                       timeout: options.timeout)
        harness.shutdown()
        print("PASS  negative: missing host reported recoverably")
        print("PASS  negative: non-OpenAI executable refused before launch\n")
    }
}

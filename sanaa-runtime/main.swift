import Darwin
import Foundation
import Security

private enum RuntimeLaunchError: LocalizedError {
    case usage(String)
    case parentRejected(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .parentRejected(let message): return message
        }
    }
}

private struct RuntimeOptions {
    var stateDirectory: URL
    var allowTestParent = false

    static func parse(_ arguments: [String]) throws -> RuntimeOptions {
        var stateDirectory: URL?
        var allowTestParent = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--state-directory":
                index += 1
                guard index < arguments.count else {
                    throw RuntimeLaunchError.usage("--state-directory needs an absolute path")
                }
                let path = arguments[index]
                guard path.hasPrefix("/") else {
                    throw RuntimeLaunchError.usage("--state-directory must be absolute")
                }
                stateDirectory = URL(fileURLWithPath: path, isDirectory: true)
            case "--allow-test-parent":
                #if DEBUG
                allowTestParent = true
                #else
                throw RuntimeLaunchError.usage("--allow-test-parent is unavailable in Release builds")
                #endif
            case "--help", "-h":
                print("Usage: sanaa-runtime --state-directory PATH")
                exit(EXIT_SUCCESS)
            default:
                throw RuntimeLaunchError.usage("Unknown argument: \(arguments[index])")
            }
            index += 1
        }
        guard let stateDirectory else {
            throw RuntimeLaunchError.usage("--state-directory is required")
        }
        return RuntimeOptions(stateDirectory: stateDirectory, allowTestParent: allowTestParent)
    }
}

private final class RuntimeEventWriter: @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let lock = NSLock()

    init() {
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func send(_ event: SanaaRuntimeEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)
        try? FileHandle.standardOutput.write(contentsOf: data)
    }
}

private final class SanaaRuntimeServer: @unchecked Sendable {
    private let options: RuntimeOptions
    private let writer = RuntimeEventWriter()
    private let decoder = JSONDecoder()
    private let stateLock = NSLock()
    private var authenticatedSessionID: String?
    private var adapter: CodexAppServerAdapter?
    private var conversationID: String?
    private var activeTurnID: String?
    private var requestIDsByTurn: [String: String] = [:]
    private var shouldExit = false

    init(options: RuntimeOptions) throws {
        self.options = options
        try FileManager.default.createDirectory(
            at: options.stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try options.stateDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RuntimeLaunchError.usage("Sanaa Runtime state path must be a real directory")
        }
    }

    func run() {
        while !shouldExit, let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let command = try decoder.decode(SanaaRuntimeCommand.self, from: data)
                handle(command)
            } catch {
                sendFailure(sessionID: authenticatedSessionID ?? "unbound",
                            requestID: nil,
                            code: .invalidRequest,
                            message: "Sanaa Runtime received malformed JSON: \(error.localizedDescription)",
                            recoverable: true)
            }
        }
        shutdownHost()
    }

    private func handle(_ command: SanaaRuntimeCommand) {
        guard command.protocolVersion == SanaaRuntimeProtocol.version else {
            sendFailure(sessionID: command.sessionID,
                        requestID: command.requestID,
                        code: .invalidProtocol,
                        message: "EXP runtime protocol \(command.protocolVersion) is unsupported; this helper requires \(SanaaRuntimeProtocol.version).",
                        recoverable: false)
            return
        }

        if authenticatedSessionID == nil {
            guard command.kind == .hello, !command.sessionID.isEmpty else {
                sendFailure(sessionID: command.sessionID,
                            requestID: command.requestID,
                            code: .unauthenticated,
                            message: "The first runtime command must bind an EXP session.",
                            recoverable: false)
                shouldExit = true
                return
            }
            authenticatedSessionID = command.sessionID
            writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                          requestID: command.requestID,
                                          kind: .ready,
                                          host: "runtime",
                                          hostVersion: "0.1.0"))
            return
        }

        guard authenticatedSessionID == command.sessionID else {
            sendFailure(sessionID: command.sessionID,
                        requestID: command.requestID,
                        code: .unauthenticated,
                        message: "This message does not belong to the bound EXP session.",
                        recoverable: false)
            shouldExit = true
            return
        }

        do {
            switch command.kind {
            case .hello:
                throw RuntimeCommandError(.invalidRequest, "The runtime session is already bound.")
            case .connect:
                try connect(command)
            case .startConversation:
                try startConversation(command)
            case .sendMessage:
                try sendMessage(command)
            case .stop:
                try stopTurn(command)
            case .resumeConversation:
                try resumeConversation(command)
            case .deleteConversation:
                try deleteConversation(command)
            case .refreshAccountStatus:
                _ = try sendAccountStatus(command, through: connectedHost())
            case .shutdown:
                shouldExit = true
            }
        } catch let error as RuntimeCommandError {
            sendFailure(sessionID: command.sessionID,
                        requestID: command.requestID,
                        code: error.code,
                        message: error.message,
                        recoverable: error.recoverable)
        } catch {
            sendFailure(sessionID: command.sessionID,
                        requestID: command.requestID,
                        code: mapErrorCode(error),
                        message: error.localizedDescription,
                        recoverable: true)
        }
    }

    private func connect(_ command: SanaaRuntimeCommand) throws {
        shutdownHost()
        let executable = try findCodex(override: command.hostExecutablePath)
        let codexHome = try prepareIsolatedCodexHome()
        let expMCPPath = try bundledEXPMCPPath()
        let host = CodexAppServerAdapter(executablePath: executable,
                                         currentDirectory: try workspaceDirectory(),
                                         codexHome: codexHome,
                                         expMCPPath: expMCPPath)
        host.notificationHandler = { [weak self] notification in
            self?.receive(notification)
        }
        try host.start()
        do {
            let version = try host.initialize()
            stateLock.withLock { adapter = host }
            writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                          requestID: command.requestID,
                                          kind: .hostReady,
                                          host: "codex",
                                          hostVersion: version))
            let available = try sendAccountStatus(command, through: host)
            if !available {
                throw RuntimeCommandError(.signedOut,
                                          "Codex is installed but not signed in. Sign in with Codex, then reconnect.")
            }
        } catch {
            host.stop()
            stateLock.withLock { adapter = nil }
            throw error
        }
    }

    /// Account details are informative, not a new trust boundary. Optional usage
    /// surfaces may be unavailable for API-key or provider-backed accounts, so a
    /// missing bucket never prevents a valid signed-in conversation.
    @discardableResult
    private func sendAccountStatus(_ command: SanaaRuntimeCommand,
                                   through host: CodexAppServerAdapter) throws -> Bool {
        let status = try host.accountStatus()
        let limits = try? host.rateLimits()
        let usage = try? host.usageSummary()
        writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                      requestID: command.requestID,
                                      kind: .accountStatus,
                                      host: "codex",
                                      accountAvailable: status.available,
                                      account: status.account,
                                      rateLimits: limits,
                                      usageSummary: usage))
        return status.available
    }

    private func startConversation(_ command: SanaaRuntimeCommand) throws {
        let host = try connectedHost()
        let id = try host.startConversation(cwd: workspaceDirectory())
        stateLock.withLock {
            conversationID = id
            activeTurnID = nil
        }
        writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                      requestID: command.requestID,
                                      kind: .conversationStarted,
                                      host: "codex",
                                      conversationID: id))
    }

    private func sendMessage(_ command: SanaaRuntimeCommand) throws {
        let text = command.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw RuntimeCommandError(.invalidRequest, "A Sanaa message cannot be empty.")
        }
        let host = try connectedHost()
        let id = try currentConversation(command.conversationID)
        guard stateLock.withLock({ activeTurnID == nil }) else {
            throw RuntimeCommandError(.invalidRequest, "Sanaa is already replying. Stop that turn before sending another message.")
        }
        let turnID = try host.startTurn(conversationID: id, text: text)
        stateLock.withLock {
            activeTurnID = turnID
            requestIDsByTurn[turnID] = command.requestID
        }
        writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                      requestID: command.requestID,
                                      kind: .userMessage,
                                      host: "codex",
                                      conversationID: id,
                                      turnID: turnID,
                                      text: text))
    }

    private func stopTurn(_ command: SanaaRuntimeCommand) throws {
        let host = try connectedHost()
        let id = try currentConversation(command.conversationID)
        guard let turnID = stateLock.withLock({ activeTurnID }) else {
            throw RuntimeCommandError(.noActiveTurn, "There is no active Sanaa reply to stop.")
        }
        try host.interrupt(conversationID: id, turnID: turnID)
    }

    private func resumeConversation(_ command: SanaaRuntimeCommand) throws {
        let host = try connectedHost()
        guard let id = command.conversationID, !id.isEmpty else {
            throw RuntimeCommandError(.noConversation, "A conversation id is required to reconnect.")
        }
        try host.resumeConversation(id, cwd: workspaceDirectory())
        stateLock.withLock {
            conversationID = id
            activeTurnID = nil
        }
        writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                      requestID: command.requestID,
                                      kind: .conversationResumed,
                                      host: "codex",
                                      conversationID: id))
    }

    private func deleteConversation(_ command: SanaaRuntimeCommand) throws {
        let host = try connectedHost()
        let id = try currentConversation(command.conversationID)
        guard stateLock.withLock({ activeTurnID == nil }) else {
            throw RuntimeCommandError(.invalidRequest, "Stop the active reply before deleting its conversation.")
        }
        try host.deleteConversation(id)
        stateLock.withLock {
            conversationID = nil
            requestIDsByTurn.removeAll()
        }
        writer.send(SanaaRuntimeEvent(sessionID: command.sessionID,
                                      requestID: command.requestID,
                                      kind: .conversationDeleted,
                                      host: "codex",
                                      conversationID: id))
    }

    private func receive(_ notification: CodexHostNotification) {
        guard let sessionID = stateLock.withLock({ authenticatedSessionID }) else { return }
        switch notification {
        case .assistantDelta(let turnID, let text):
            let values = stateLock.withLock {
                (requestIDsByTurn[turnID], conversationID)
            }
            writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                          requestID: values.0,
                                          kind: .assistantDelta,
                                          host: "codex",
                                          conversationID: values.1,
                                          turnID: turnID,
                                          text: text))
        case .toolStarted(let turnID, _, let tool, let summary):
            let requestID = turnID.flatMap { id in stateLock.withLock { requestIDsByTurn[id] } }
            writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                          requestID: requestID,
                                          kind: .toolRequest,
                                          host: "codex",
                                          conversationID: stateLock.withLock { conversationID },
                                          turnID: turnID,
                                          text: summary,
                                          status: tool))
        case .toolCompleted(let turnID, _, let tool, let summary, let status):
            let requestID = turnID.flatMap { id in stateLock.withLock { requestIDsByTurn[id] } }
            writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                          requestID: requestID,
                                          kind: .toolResult,
                                          host: "codex",
                                          conversationID: stateLock.withLock { conversationID },
                                          turnID: turnID,
                                          text: summary,
                                          status: status ?? tool))
        case .turnCompleted(let turnID, let status):
            let values = stateLock.withLock { () -> (String?, String?) in
                let requestID = requestIDsByTurn.removeValue(forKey: turnID)
                if activeTurnID == turnID { activeTurnID = nil }
                return (requestID, conversationID)
            }
            let kind: SanaaRuntimeEventKind = status == "interrupted" ? .interrupted : .completed
            writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                          requestID: values.0,
                                          kind: kind,
                                          host: "codex",
                                          conversationID: values.1,
                                          turnID: turnID,
                                          status: status))
        case .serverRequest(let method, let turnID):
            let requestID = turnID.flatMap { id in stateLock.withLock { requestIDsByTurn[id] } }
            writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                          requestID: requestID,
                                          kind: method.contains("requestApproval") ? .approvalRequired : .toolRequest,
                                          host: "codex",
                                          conversationID: stateLock.withLock { conversationID },
                                          turnID: turnID,
                                          text: method,
                                          failure: SanaaRuntimeFailure(
                                            code: .unexpectedHostRequest,
                                            message: "The canvas-only runtime refused host request \(method).",
                                            recoverable: false
                                          )))
        case .disconnected(let message):
            stateLock.withLock {
                adapter = nil
                activeTurnID = nil
            }
            sendFailure(sessionID: sessionID,
                        requestID: nil,
                        code: .hostDisconnected,
                        message: message,
                        recoverable: true)
        }
    }

    private func connectedHost() throws -> CodexAppServerAdapter {
        guard let host = stateLock.withLock({ adapter }), host.isRunning else {
            throw RuntimeCommandError(.hostDisconnected, "Codex is not connected. Reconnect and try again.")
        }
        return host
    }

    private func currentConversation(_ requested: String?) throws -> String {
        let current = stateLock.withLock { conversationID }
        if let requested, requested != current {
            throw RuntimeCommandError(.noConversation, "The requested conversation is not active in this runtime.")
        }
        guard let current else {
            throw RuntimeCommandError(.noConversation, "Start or resume a Sanaa conversation first.")
        }
        return current
    }

    private func workspaceDirectory() throws -> URL {
        let directory = options.stateDirectory.appendingPathComponent("runtime-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// Codex needs the account's existing sign-in but must not inherit the
    /// account's normal config, plugins, MCP servers, rules, or session history.
    /// A private CODEX_HOME holds Sanaa's state and exposes only auth.json through
    /// a narrow symlink to the already-approved account login.
    private func prepareIsolatedCodexHome() throws -> URL {
        let directory = options.stateDirectory.appendingPathComponent("Codex Host", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RuntimeCommandError(.hostLaunchFailed,
                                      "Sanaa's private Codex state path is invalid.",
                                      recoverable: false)
        }

        guard let record = getpwuid(getuid()), let homePointer = record.pointee.pw_dir else {
            throw RuntimeCommandError(.signedOut, "Sanaa could not locate the current Codex account.")
        }
        let accountHome = String(cString: homePointer)
        let source = URL(fileURLWithPath: accountHome, isDirectory: true)
            .appendingPathComponent(".codex/auth.json", isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw RuntimeCommandError(.signedOut,
                                      "Codex is installed but not signed in. Sign in with Codex, then reconnect.")
        }

        let destination = directory.appendingPathComponent("auth.json", isDirectory: false)
        if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path) {
            guard URL(fileURLWithPath: existing).standardizedFileURL == source.standardizedFileURL else {
                throw RuntimeCommandError(.hostLaunchFailed,
                                          "Sanaa's private Codex authentication link is invalid.",
                                          recoverable: false)
            }
        } else if FileManager.default.fileExists(atPath: destination.path) {
            throw RuntimeCommandError(.hostLaunchFailed,
                                      "Sanaa's private Codex authentication path is invalid.",
                                      recoverable: false)
        } else {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
        }
        return directory
    }

    /// Resolve only the signed sibling copied into EXP.app/Contents/Helpers.
    /// Codex launches this stdio relay; it has no design logic and can reach the
    /// document only through EXP's existing current-user 0600 Unix socket.
    private func bundledEXPMCPPath() throws -> String {
        let runtimeURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidate = runtimeURL.deletingLastPathComponent()
            .appendingPathComponent("exp-mcp", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw RuntimeCommandError(.helperUnavailable,
                                      "EXP's bundled canvas bridge is missing.",
                                      recoverable: false)
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RuntimeCommandError(.helperUnavailable,
                                      "EXP's bundled canvas bridge is invalid.",
                                      recoverable: false)
        }
        #if DEBUG
        if options.allowTestParent { return candidate.path }
        #endif
        try validateSignedExecutable(
            at: candidate.path,
            requirementText: "identifier \"exp-mcp\" and anchor apple generic and certificate leaf[subject.OU] = \"65LD7TZAL3\"",
            failure: "EXP's bundled canvas bridge failed its code-signing check."
        )
        return candidate.path
    }

    private func shutdownHost() {
        let host = stateLock.withLock { () -> CodexAppServerAdapter? in
            let value = adapter
            adapter = nil
            activeTurnID = nil
            return value
        }
        host?.notificationHandler = nil
        host?.stop()
    }

    private func findCodex(override: String?) throws -> String {
        if let override {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw RuntimeCommandError(.hostMissing, "Codex is not executable at \(override).")
            }
            try validateCodex(at: override)
            return override
        }

        #if arch(arm64)
        let package = "@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
        #elseif arch(x86_64)
        let package = "@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex"
        #else
        let package = ""
        #endif

        let roots = [
            "/usr/local/lib/node_modules/@openai/codex/node_modules",
            "/opt/homebrew/lib/node_modules/@openai/codex/node_modules"
        ]
        var rejectedInstalledHost = false
        for root in roots where !package.isEmpty {
            let candidate = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(package)
                .path
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            do {
                try validateCodex(at: candidate)
                return candidate
            } catch {
                rejectedInstalledHost = true
            }
        }
        if rejectedInstalledHost {
            throw RuntimeCommandError(.hostLaunchFailed,
                                      "The installed Codex host failed Sanaa Runtime's code-signing check.",
                                      recoverable: false)
        }
        throw RuntimeCommandError(.hostMissing,
                                  "Codex was not found. Install Codex or choose its executable, then reconnect.")
    }

    /// The runtime executes only the native host shipped by OpenAI. This avoids
    /// treating an npm shim or a same-named PATH entry as trusted code.
    private func validateCodex(at path: String) throws {
        try validateSignedExecutable(
            at: path,
            requirementText: "identifier \"codex\" and anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\"",
            failure: "Codex failed Sanaa Runtime's OpenAI code-signing check."
        )
    }

    private func validateSignedExecutable(at path: String,
                                          requirementText: String,
                                          failure: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw RuntimeCommandError(.hostLaunchFailed,
                                      "An executable could not be inspected before launch.",
                                      recoverable: false)
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                requirement
              ) == errSecSuccess else {
            throw RuntimeCommandError(.hostLaunchFailed, failure, recoverable: false)
        }
    }

    private func mapErrorCode(_ error: Error) -> SanaaRuntimeErrorCode {
        guard let error = error as? CodexAdapterError else { return .internalFailure }
        switch error {
        case .unavailable: return .hostLaunchFailed
        case .protocolFailure: return .unsupportedHostProtocol
        case .timedOut: return .timedOut
        case .disconnected: return .hostDisconnected
        }
    }

    private func sendFailure(sessionID: String,
                             requestID: String?,
                             code: SanaaRuntimeErrorCode,
                             message: String,
                             recoverable: Bool) {
        writer.send(SanaaRuntimeEvent(sessionID: sessionID,
                                      requestID: requestID,
                                      kind: .failed,
                                      failure: SanaaRuntimeFailure(code: code,
                                                                   message: message,
                                                                   recoverable: recoverable)))
    }
}

private struct RuntimeCommandError: LocalizedError {
    var code: SanaaRuntimeErrorCode
    var message: String
    var recoverable: Bool

    init(_ code: SanaaRuntimeErrorCode, _ message: String, recoverable: Bool = true) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }

    var errorDescription: String? { message }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// Release helpers only accept EXP as their parent. The Debug-only probe flag
/// exists so the contract script can launch the built artifact from a shell;
/// the bypass is compiled out of Release entirely.
private func validateParent(allowTestParent: Bool) throws {
    #if DEBUG
    if allowTestParent { return }
    #endif

    var requirement: SecRequirement?
    let requirementText = "identifier \"tapps.EXP--design-\" and anchor apple generic and certificate leaf[subject.OU] = \"65LD7TZAL3\""
    guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
          let requirement else {
        throw RuntimeLaunchError.parentRejected("Sanaa Runtime could not construct its EXP code requirement.")
    }

    let attributes = [kSecGuestAttributePid as String: NSNumber(value: getppid())] as CFDictionary
    var parentCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &parentCode) == errSecSuccess,
          let parentCode,
          SecCodeCheckValidity(parentCode,
                               SecCSFlags(rawValue: kSecCSStrictValidate),
                               requirement) == errSecSuccess else {
        throw RuntimeLaunchError.parentRejected("Sanaa Runtime refused a parent that is not signed EXP.")
    }
}

do {
    let options = try RuntimeOptions.parse(Array(CommandLine.arguments.dropFirst()))
    try validateParent(allowTestParent: options.allowTestParent)
    try SanaaRuntimeServer(options: options).run()
} catch {
    FileHandle.standardError.write(Data("sanaa-runtime: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

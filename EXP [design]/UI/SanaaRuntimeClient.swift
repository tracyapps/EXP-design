//
//  SanaaRuntimeClient.swift
//  EXP [design]
//
//  App-side owner of the bundled runtime process. Panel/activity code consumes
//  normalized `SanaaRuntimeEvent` values from here and never talks to Codex.
//

import Foundation
import Observation
import Security

@MainActor
@Observable
final class SanaaRuntimeClient {
    enum State: Equatable {
        case stopped
        case launching
        case ready
        case connected
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var conversationID: String?
    private(set) var activeTurnID: String?
    private(set) var accountAvailable = false
    private(set) var lastFailure: SanaaRuntimeFailure?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var output: Pipe?
    @ObservationIgnored private var errorPipe: Pipe?
    @ObservationIgnored private var relay: SanaaRuntimeClientRelay?
    @ObservationIgnored private var outputBuffer = Data()
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private var sessionID = UUID().uuidString
    @ObservationIgnored private var stoppingIntentionally = false
    @ObservationIgnored var eventHandler: ((SanaaRuntimeEvent) -> Void)?

    var isRunning: Bool { process?.isRunning == true }

    func launch() throws {
        guard !isRunning else { return }
        state = .launching
        lastFailure = nil
        stoppingIntentionally = false
        sessionID = UUID().uuidString
        outputBuffer.removeAll(keepingCapacity: true)

        let helperURL = try bundledHelperURL()
        try validateBundledHelper(at: helperURL)
        let stateDirectory = try runtimeStateDirectory()

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = helperURL
        process.arguments = ["--state-directory", stateDirectory.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let relay = SanaaRuntimeClientRelay(client: self)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            relay.receive(data)
        }
        process.terminationHandler = { process in
            relay.terminated(status: process.terminationStatus)
        }
        self.process = process
        self.input = input
        self.output = output
        self.errorPipe = errors
        self.relay = relay

        do {
            try process.run()
            _ = try send(.hello)
        } catch {
            tearDownProcess()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    func connect(codexPath: String? = nil) throws -> String {
        try ensureRunning()
        return try send(.connect, hostExecutablePath: codexPath)
    }

    @discardableResult
    func startConversation() throws -> String {
        try ensureRunning()
        return try send(.startConversation)
    }

    @discardableResult
    func sendMessage(_ text: String) throws -> String {
        try ensureRunning()
        return try send(.sendMessage, conversationID: conversationID, text: text)
    }

    @discardableResult
    func stop() throws -> String {
        try ensureRunning()
        return try send(.stop, conversationID: conversationID)
    }

    @discardableResult
    func resumeConversation(_ id: String) throws -> String {
        try ensureRunning()
        return try send(.resumeConversation, conversationID: id)
    }

    @discardableResult
    func deleteConversation() throws -> String {
        try ensureRunning()
        return try send(.deleteConversation, conversationID: conversationID)
    }

    @discardableResult
    func refreshAccountStatus() throws -> String {
        try ensureRunning()
        return try send(.refreshAccountStatus)
    }

    func shutdown() {
        guard isRunning else {
            tearDownProcess()
            state = .stopped
            return
        }
        stoppingIntentionally = true
        _ = try? send(.shutdown)
        try? input?.fileHandleForWriting.close()
        process?.waitUntilExit()
        tearDownProcess()
        state = .stopped
    }

    private func send(_ kind: SanaaRuntimeCommandKind,
                      hostExecutablePath: String? = nil,
                      conversationID: String? = nil,
                      text: String? = nil) throws -> String {
        let command = SanaaRuntimeCommand(sessionID: sessionID,
                                          kind: kind,
                                          hostExecutablePath: hostExecutablePath,
                                          conversationID: conversationID,
                                          text: text)
        var data = try encoder.encode(command)
        data.append(0x0A)
        guard let input else {
            throw ClientError.helperUnavailable("Sanaa Runtime has no input channel.")
        }
        try input.fileHandleForWriting.write(contentsOf: data)
        return command.requestID
    }

    fileprivate func receive(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let event = try decoder.decode(SanaaRuntimeEvent.self, from: line)
                guard event.protocolVersion == SanaaRuntimeProtocol.version,
                      event.sessionID == sessionID else {
                    throw ClientError.invalidProtocol("Sanaa Runtime returned an event for an invalid protocol session.")
                }
                apply(event)
                eventHandler?(event)
            } catch {
                lastFailure = SanaaRuntimeFailure(code: .invalidProtocol,
                                                  message: error.localizedDescription,
                                                  recoverable: false)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ event: SanaaRuntimeEvent) {
        switch event.kind {
        case .ready:
            state = .ready
        case .hostReady:
            state = .connected
        case .accountStatus:
            accountAvailable = event.accountAvailable == true
        case .conversationStarted, .conversationResumed:
            conversationID = event.conversationID
        case .userMessage:
            activeTurnID = event.turnID
        case .interrupted, .completed:
            if activeTurnID == event.turnID { activeTurnID = nil }
        case .conversationDeleted:
            conversationID = nil
            activeTurnID = nil
        case .failed:
            lastFailure = event.failure
            if event.failure?.recoverable == false {
                state = .failed(event.failure?.message ?? "Sanaa Runtime failed.")
            }
        case .assistantDelta, .toolRequest, .toolResult, .approvalRequired:
            break
        }
    }

    private func ensureRunning() throws {
        guard isRunning else {
            throw ClientError.helperUnavailable("Sanaa Runtime is not running.")
        }
    }

    fileprivate func runtimeTerminated(status: Int32) {
        guard !stoppingIntentionally else { return }
        let detail: String = {
            guard let errorPipe,
                  let data = try? errorPipe.fileHandleForReading.readToEnd(),
                  !data.isEmpty else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }()
        let message = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = message.isEmpty
            ? "Sanaa Runtime exited with status \(status)."
            : message
        state = .failed(final)
        lastFailure = SanaaRuntimeFailure(code: .helperUnavailable,
                                          message: final,
                                          recoverable: true)
        tearDownProcess()
    }

    private func tearDownProcess() {
        output?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        process = nil
        input = nil
        output = nil
        errorPipe = nil
        relay = nil
    }

    private func bundledHelperURL() throws -> URL {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(SanaaRuntimeProtocol.helperName)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ClientError.helperUnavailable("The bundled Sanaa Runtime is missing.")
        }
        return url
    }

    private func runtimeStateDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let directory = base.appendingPathComponent("Sanaa Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// The pipe is private to this parent/child pair; code-signing validation
    /// authenticates which helper received it before any session is bound.
    private func validateBundledHelper(at url: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw ClientError.helperUnavailable("Sanaa Runtime could not be inspected before launch.")
        }
        var requirement: SecRequirement?
        // Command-line tool targets use their Mach-O product name as the
        // designated identifier even when Xcode also emits an application-id
        // entitlement. Pair the exact name with EXP's team and bundled path.
        let text = "identifier \"sanaa-runtime\" and anchor apple generic and certificate leaf[subject.OU] = \"65LD7TZAL3\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                requirement
              ) == errSecSuccess else {
            throw ClientError.helperUnavailable("Sanaa Runtime failed EXP's code-signing check.")
        }
    }
}

/// Foundation invokes pipe and process callbacks off the main actor. This tiny
/// relay is the explicit hop back to the actor-isolated observable client.
private nonisolated final class SanaaRuntimeClientRelay: @unchecked Sendable {
    weak var client: SanaaRuntimeClient?

    init(client: SanaaRuntimeClient) {
        self.client = client
    }

    func receive(_ data: Data) {
        guard let client else { return }
        Task { @MainActor in client.receive(data) }
    }

    func terminated(status: Int32) {
        guard let client else { return }
        Task { @MainActor in client.runtimeTerminated(status: status) }
    }
}

private enum ClientError: LocalizedError {
    case helperUnavailable(String)
    case invalidProtocol(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable(let message), .invalidProtocol(let message): return message
        }
    }
}

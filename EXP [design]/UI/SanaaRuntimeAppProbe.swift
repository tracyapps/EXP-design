#if DEBUG
import AppKit
import Darwin
import Foundation

/// Opt-in Debug receipt for the boundary the shell probe cannot exercise: the
/// sandboxed, signed EXP process validating and launching its signed helper.
/// It is inert unless `EXP_SANAA_RUNTIME_PROBE=1` is present at app launch.
@MainActor
enum SanaaRuntimeAppProbe {
    private static var client: SanaaRuntimeClient?
    private static var conversationID: String?
    private static var streamedText = ""
    private static var toolRequests: [String] = []
    private static var toolResults = 0
    private static var approvalRequests = 0
    private static var canvasRead = false
    private static var finished = false

    static func startIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["EXP_SANAA_RUNTIME_PROBE"] == "1" else { return false }
        canvasRead = environment["EXP_SANAA_CANVAS_READ_PROBE"] == "1"
        DispatchQueue.main.async {
            run(codexPath: environment["EXP_SANAA_CODEX_PATH"])
        }
        return true
    }

    private static func run(codexPath: String?) {
        let runtime = SanaaRuntimeClient()
        client = runtime
        runtime.eventHandler = { event in handle(event, codexPath: codexPath) }
        do {
            try runtime.launch()
        } catch {
            finish("FAIL  sandboxed EXP could not launch Sanaa Runtime: \(error.localizedDescription)", success: false)
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(120))
            guard !finished else { return }
            finish("FAIL  sandboxed EXP runtime probe timed out", success: false)
        }
    }

    private static func handle(_ event: SanaaRuntimeEvent, codexPath: String?) {
        guard !finished, let client else { return }
        do {
            switch event.kind {
            case .ready:
                _ = try client.connect(codexPath: codexPath)
            case .accountStatus:
                guard event.accountAvailable == true else {
                    finish("FAIL  Codex is not signed in for the sandboxed EXP probe", success: false)
                    return
                }
                _ = try client.startConversation()
            case .conversationStarted:
                conversationID = event.conversationID
                let prompt = canvasRead
                    ? "Use exp-design list_artboards, then get_artboard on the first returned id. After both succeed, reply exactly CANVAS_READ_OK."
                    : "Reply with exactly SANAA_APP_IPC_OK."
                _ = try client.sendMessage(prompt)
            case .assistantDelta:
                streamedText += event.text ?? ""
            case .toolRequest:
                if let status = event.status { toolRequests.append(status) }
            case .toolResult:
                toolResults += 1
            case .approvalRequired:
                approvalRequests += 1
            case .completed:
                if canvasRead {
                    guard event.status == "completed",
                          streamedText.contains("CANVAS_READ_OK"),
                          toolRequests.contains("list_artboards"),
                          toolRequests.contains("get_artboard"),
                          toolResults >= 2,
                          approvalRequests == 0 else {
                        finish("FAIL  sandboxed EXP canvas read crossed an approval boundary", success: false)
                        return
                    }
                } else {
                    guard event.status == "completed",
                          streamedText.contains("SANAA_APP_IPC_OK"),
                          toolRequests.isEmpty,
                          toolResults == 0,
                          approvalRequests == 0 else {
                        finish("FAIL  sandboxed EXP generic stream made an unexpected tool call", success: false)
                        return
                    }
                }
                _ = try client.deleteConversation()
            case .conversationDeleted:
                conversationID = nil
                let receipt = canvasRead
                    ? "RESULT  sandboxed signed EXP canvas reads ran without host approval"
                    : "RESULT  sandboxed signed EXP → signed helper → Codex stream passed"
                finish(receipt, success: true)
            case .failed:
                finish("FAIL  \(event.failure?.message ?? "Sanaa Runtime failed")", success: false)
            case .hostReady, .conversationResumed, .userMessage, .interrupted:
                break
            }
        } catch {
            finish("FAIL  sandboxed EXP runtime probe: \(error.localizedDescription)", success: false)
        }
    }

    private static func finish(_ message: String, success: Bool) {
        guard !finished else { return }
        finished = true
        if !success, conversationID != nil {
            _ = try? client?.deleteConversation()
        }
        client?.shutdown()
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        fflush(stdout)
        Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

/// End-to-end Debug receipt for the app-facing activity seam used by
/// `SanaaPanel`. Launch with `EXP_SANAA_ACTIVITY_PROBE=1` and the temporary
/// argument-domain preference `-exp.sanaa.enabled YES`.
@MainActor
enum SanaaActivityAppProbe {
    static func startIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["EXP_SANAA_ACTIVITY_PROBE"] == "1" else {
            return false
        }
        DispatchQueue.main.async {
            Task { await run() }
        }
        return true
    }

    private static func run() async {
        let activity = SanaaActivityController.shared
        activity.activate()
        guard await waitUntil({ activity.phase == .ready }, seconds: 30) else {
            finish("FAIL  Sanaa activity controller did not become ready", success: false)
            return
        }

        let prompt = "Reply with exactly SANAA_ACTIVITY_OK."
        activity.draft = prompt
        activity.sendDraft()
        guard await waitUntil({
            activity.phase == .ready
                && activity.transcript.contains {
                    $0.kind == .assistant && $0.text.contains("SANAA_ACTIVITY_OK")
                }
        }, seconds: 120) else {
            finish("FAIL  Sanaa activity transcript did not complete", success: false)
            return
        }

        let designerMessages = activity.transcript.filter { $0.kind == .designer }
        let assistantMessages = activity.transcript.filter { $0.kind == .assistant }
        guard designerMessages.count == 1,
              designerMessages[0].text == prompt,
              assistantMessages.count == 1,
              activity.draft.isEmpty,
              activity.transcript.first?.kind == .designer else {
            finish("FAIL  Sanaa activity transcript order or composer state is invalid", success: false)
            return
        }

        activity.disable()
        guard activity.phase == .off,
              activity.transcript.isEmpty,
              activity.draft.isEmpty,
              activity.conversationID == nil else {
            finish("FAIL  disabling Sanaa did not clear its session", success: false)
            return
        }
        finish("RESULT  signed Sanaa activity Send → stream → transcript → clear passed", success: true)
    }

    private static func waitUntil(_ predicate: () -> Bool, seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return predicate()
    }

    private static func finish(_ message: String, success: Bool) {
        if !success { SanaaActivityController.shared.disable() }
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        fflush(stdout)
        Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
#endif

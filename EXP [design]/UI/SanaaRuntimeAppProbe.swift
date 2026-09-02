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

/// Pure FEAT-050 contract receipt. It runs inside the Debug app so it exercises
/// the exact prompt composer and activity-controller types shipped in the target,
/// without opening a document or contacting an agent host.
@MainActor
enum SanaaPromptAppProbe {
    static func startIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["EXP_SANAA_PROMPT_PROBE"] == "1" else {
            return false
        }
        DispatchQueue.main.async { run() }
        return true
    }

    private static func run() {
        let pageID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let context = SanaaPromptContext(
            pageID: pageID,
            pageName: "Pricing",
            nodes: [.init(id: nodeID, name: "Price")],
            selectedArtboards: [],
            parentArtboards: [.init(id: boardID, name: "Pricing card")])

        let duplicate = SanaaPromptComposer.complete(context, duplicate: true)
        let direct = SanaaPromptComposer.complete(context, duplicate: false)
        let variations = SanaaPromptComposer.variations(context, count: 4, newPage: true)
        let repetitive = SanaaPromptComposer.repetitive(context, task: "Rename every price layer")
        let critique = SanaaPromptComposer.critique(context)
        let directions = SanaaPromptComposer.directions(context)
        let required = [pageID, nodeID, boardID].map(\.uuidString)
        guard required.allSatisfy({ duplicate.contains($0) }),
              required.allSatisfy({ critique.contains($0) && directions.contains($0) }),
              duplicate.contains("besideOriginal"),
              direct.contains("in-place consent"),
              variations.contains("4 genuinely different variations"),
              variations.contains("newPage"),
              repetitive.contains("Rename every price layer"),
              repetitive.contains("requires the designer's consent"),
              critique.contains("get_design_facts with no arguments before writing or reasoning"),
              critique.contains("critique-framework"),
              critique.contains("Couldn't assess"),
              critique.contains("Overview of no more than four short bullets"),
              critique.contains("descriptive Markdown links"),
              critique.contains("short Next steps section"),
              critique.contains("Do not call apply_edits or change the canvas"),
              directions.contains("get_design_facts with no arguments before analyzing or proposing"),
              directions.contains("directions, anti-generic"),
              directions.contains("Overview of no more than four short bullets"),
              directions.contains("descriptive Markdown links"),
              directions.contains("at least three named design axes"),
              directions.contains("Do not call apply_edits or change the canvas") else {
            finish("FAIL  FEAT-050 prompt composition lost ids, placement, consent, facts, or guidance language",
                   success: false)
            return
        }

        let activity = SanaaActivityController.shared
        let revision = activity.draftFocusRevision
        activity.prepareDraft(duplicate)
        guard activity.draft == duplicate,
              activity.draftFocusRevision == revision + 1 else {
            finish("FAIL  FEAT-050 did not place and focus the editable Sanaa draft",
                   success: false)
            return
        }
        activity.disable()
        finish("RESULT  FEAT-050 base + facts-first amendment prompt contracts passed",
               success: true)
    }

    private static func finish(_ message: String, success: Bool) {
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        fflush(stdout)
        Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

/// Pure FEAT-061 presentation receipt. This stays inside the app target so the
/// check exercises the exact parser used by both the compact card and reader.
@MainActor
enum SanaaResponseAppProbe {
    static func startIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["EXP_SANAA_RESPONSE_PROBE"] == "1" else {
            return false
        }
        DispatchQueue.main.async { run() }
        return true
    }

    private static func run() {
        let markdown = """
        # Checkout critique

        ## Overview
        - The hierarchy is clear.
        - Two contrast decisions need review.

        ## Measured findings
        1. **S1 — Logo contrast:** node DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF. See [WCAG contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

        > Keyboard behavior could not be assessed.

        ```swift
        let safe = true
        ```

        ```exp-response
        {"version":1,"findings":[{"label":"S1","title":"Logo contrast","elements":[{"nodeID":"DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF","name":"Logo","instancePath":[]}],"followUp":"Explore S1 without changing the canvas."}],"choices":[{"label":"Explore contrast","prompt":"Explore S1 without changing the canvas."}]}
        ```
        """
        let preview = SanaaMarkdownPresentation.previewSource(markdown)
        let blocks = SanaaMarkdownPresentation.blocks(markdown)
        let structured = SanaaStructuredResponse.parse(markdown)
        let malformed = SanaaStructuredResponse.parse("""
        # Kept visible
        ```exp-response
        {"version":1,"findings":[{"label":"S1","title":"Broken","elements":[{"nodeID":"not-a-uuid"}]}]}
        ```
        """)
        guard SanaaMarkdownPresentation.title(markdown) == "Checkout critique",
              preview.contains("hierarchy is clear"),
              !preview.contains("DEADBEEF"),
              blocks.contains(where: { $0.kind == .heading(2) && $0.text == "Overview" }),
              blocks.contains(where: {
                  if case .orderedItem("1.") = $0.kind { return $0.text.contains("S1") }
                  return false
              }),
              blocks.contains(where: { $0.kind == .quote }),
              blocks.contains(where: { $0.kind == .code && $0.text.contains("safe") }),
              structured.findings.count == 1,
              structured.findings[0].elements[0].uuid?.uuidString == "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF",
              structured.choices.map(\.label) == ["Explore contrast"],
              !structured.markdown.contains("exp-response"),
              !blocks.contains(where: { $0.kind == .code && $0.text.contains("nodeID") }),
              malformed.findings.isEmpty && malformed.choices.isEmpty,
              malformed.markdown.contains("not-a-uuid"),
              SanaaMarkdownPresentation.isSafeExternalLink(URL(string: "https://www.w3.org")!),
              SanaaMarkdownPresentation.isSafeExternalLink(URL(string: "mailto:hello@example.com")!),
              !SanaaMarkdownPresentation.isSafeExternalLink(URL(fileURLWithPath: "/tmp/private")),
              !SanaaMarkdownPresentation.isSafeExternalLink(URL(string: "exp://apply-edits")!) else {
            finish("FAIL  FEAT-061 Markdown, structured-action, or safe-link contract regressed",
                   success: false)
            return
        }
        finish("RESULT  FEAT-061 compact preview, Markdown blocks, safe links, and validated structured actions passed",
               success: true)
    }

    private static func finish(_ message: String, success: Bool) {
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        fflush(stdout)
        Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
#endif

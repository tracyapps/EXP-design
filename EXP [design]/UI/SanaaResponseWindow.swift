//
//  SanaaResponseWindow.swift
//  EXP [design]
//
//  FEAT-061 — a compact Markdown-aware transcript preview and a normal,
//  resizable reading window for every assistant response. The reader is native
//  SwiftUI/AppKit: Markdown can style text and carry safe external links, but it
//  never becomes executable HTML or an embedded browser.
//

import AppKit
import SwiftUI

struct SanaaStructuredResponse: Equatable {
    struct Element: Codable, Equatable, Identifiable {
        var nodeID: String
        var name: String?
        var instancePath: [String]?

        var id: String { ([nodeID] + (instancePath ?? [])).joined(separator: ":") }
        var uuid: UUID? { UUID(uuidString: nodeID) }
        var instanceUUIDs: [UUID] {
            (instancePath ?? []).compactMap(UUID.init(uuidString:))
        }
    }

    struct Finding: Codable, Equatable, Identifiable {
        var label: String
        var title: String
        var elements: [Element]
        var followUp: String?

        var id: String { label }
    }

    struct Choice: Codable, Equatable, Identifiable {
        var label: String
        var prompt: String

        var id: String { label + "\u{0}" + prompt }
    }

    private struct Payload: Codable {
        var version: Int
        var findings: [Finding]?
        var choices: [Choice]?
    }

    var markdown: String
    var findings: [Finding]
    var choices: [Choice]

    static func parse(_ source: String) -> SanaaStructuredResponse {
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "```exp-response"
        }), let end = lines.indices.dropFirst(start + 1).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == "```"
        }) else {
            return SanaaStructuredResponse(markdown: source, findings: [], choices: [])
        }
        let data = Data(lines[(start + 1)..<end].joined(separator: "\n").utf8)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1,
              valid(payload) else {
            // Invalid metadata remains visible as ordinary code. Silent partial
            // interpretation would make an action appear to mean more than it does.
            return SanaaStructuredResponse(markdown: source, findings: [], choices: [])
        }
        var visible = lines
        visible.removeSubrange(start...end)
        while visible.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            visible.removeLast()
        }
        return SanaaStructuredResponse(
            markdown: visible.joined(separator: "\n"),
            findings: payload.findings ?? [],
            choices: payload.choices ?? [])
    }

    private static func valid(_ payload: Payload) -> Bool {
        let findings = payload.findings ?? []
        let choices = payload.choices ?? []
        guard findings.count <= 20, choices.count <= 10,
              Set(findings.map { $0.label.lowercased() }).count == findings.count else {
            return false
        }
        for finding in findings {
            guard nonempty(finding.label, max: 40), nonempty(finding.title, max: 160),
                  finding.elements.count <= 20,
                  finding.followUp.map({ nonempty($0, max: 2_000) }) ?? true else { return false }
            for element in finding.elements {
                guard element.uuid != nil,
                      element.name.map({ nonempty($0, max: 160) }) ?? true,
                      element.instancePath?.count ?? 0 <= 16,
                      element.instancePath?.allSatisfy({ UUID(uuidString: $0) != nil }) ?? true
                else { return false }
            }
        }
        return choices.allSatisfy {
            nonempty($0.label, max: 100) && nonempty($0.prompt, max: 2_000)
        }
    }

    private static func nonempty(_ value: String, max: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= max
    }
}

enum SanaaMarkdownPresentation {
    enum BlockKind: Equatable {
        case heading(Int)
        case paragraph
        case unorderedItem
        case orderedItem(String)
        case quote
        case code
    }

    struct Block: Identifiable, Equatable {
        let id: Int
        let kind: BlockKind
        let text: String
    }

    static func previewSource(_ source: String) -> String {
        let lines = SanaaStructuredResponse.parse(source).markdown.components(separatedBy: .newlines)
        if let overview = lines.firstIndex(where: { headingText($0)?.lowercased() == "overview" }) {
            let body = lines.dropFirst(overview + 1).prefix { headingText($0) == nil }
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(1_600)) }
        }

        let fallback = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .map { headingText($0) ?? $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(fallback.prefix(1_600))
    }

    static func title(_ source: String) -> String {
        for line in SanaaStructuredResponse.parse(source).markdown.components(separatedBy: .newlines) {
            if let heading = headingText(line), !heading.isEmpty { return heading }
        }
        return "Sanaa response"
    }

    static func blocks(_ source: String) -> [Block] {
        let lines = SanaaStructuredResponse.parse(source).markdown.components(separatedBy: .newlines)
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        func append(_ kind: BlockKind, _ text: String) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            result.append(Block(id: result.count, kind: kind, text: cleaned))
        }

        func flushParagraph() {
            append(.paragraph, paragraph.joined(separator: " "))
            paragraph.removeAll(keepingCapacity: true)
        }

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    append(.code, code.joined(separator: "\n"))
                    code.removeAll(keepingCapacity: true)
                } else {
                    flushParagraph()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(raw)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let (level, heading) = heading(trimmed) {
                flushParagraph()
                append(.heading(level), heading)
                continue
            }
            if let item = unorderedItem(trimmed) {
                flushParagraph()
                append(.unorderedItem, item)
                continue
            }
            if let (marker, item) = orderedItem(trimmed) {
                flushParagraph()
                append(.orderedItem(marker), item)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                append(.quote, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            paragraph.append(trimmed)
        }
        if inCode { append(.code, code.joined(separator: "\n")) }
        flushParagraph()
        return result
    }

    static func inline(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    static func isSafeExternalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func headingText(_ line: String) -> String? {
        heading(line.trimmingCharacters(in: .whitespaces))?.1
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " else { return nil }
        return (hashes, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let marker = String(line[..<dot])
        guard marker.allSatisfy(\.isNumber) else { return nil }
        let after = line.index(after: dot)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return (marker + ".", String(line[line.index(after: after)...]))
    }
}

struct SanaaResponsePreview: View {
    let source: String
    let isStreaming: Bool

    var body: some View {
        Text(SanaaMarkdownPresentation.inline(
            SanaaMarkdownPresentation.previewSource(source)))
            .font(.system(size: EXPType.small))
            .foregroundStyle(EXPColor.textPrimary)
            .lineLimit(isStreaming ? 6 : 7)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, safeOpenURL)
    }

    private var safeOpenURL: OpenURLAction { SanaaExternalLink.openAction }
}

struct SanaaResponseChoices: View {
    let choices: [SanaaStructuredResponse.Choice]
    var isEnabled = true
    @State private var activity = SanaaActivityController.shared

    var body: some View {
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: EXPMetric.sm) {
                Text("Choose a next step")
                    .font(.system(size: EXPType.mini, weight: .semibold))
                    .foregroundStyle(EXPColor.textSecondary)
                ForEach(choices) { choice in
                    Button(choice.label) {
                        activity.useResponseSuggestion(choice.prompt)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isEnabled)
                    .accessibilityHint("Places this choice in the Sanaa composer for review; it does not send it")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SanaaMarkdownDocument: View {
    let source: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: EXPMetric.md) {
            ForEach(SanaaMarkdownPresentation.blocks(source)) { block in
                row(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, SanaaExternalLink.openAction)
    }

    @ViewBuilder
    private func row(_ block: SanaaMarkdownPresentation.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(SanaaMarkdownPresentation.inline(block.text))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .semibold : .medium))
                .foregroundStyle(EXPColor.textPrimary)
                .padding(.top, level <= 2 ? EXPMetric.md : EXPMetric.xs)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            inlineText(block.text)
        case .unorderedItem:
            HStack(alignment: .firstTextBaseline, spacing: EXPMetric.sm) {
                Text("•").accessibilityHidden(true)
                inlineText(block.text)
            }
        case .orderedItem(let marker):
            HStack(alignment: .firstTextBaseline, spacing: EXPMetric.sm) {
                Text(marker)
                    .font(.system(size: EXPType.small, design: .monospaced))
                    .foregroundStyle(EXPColor.textSecondary)
                    .accessibilityHidden(true)
                inlineText(block.text)
            }
        case .quote:
            HStack(alignment: .top, spacing: EXPMetric.md) {
                Capsule()
                    .fill(EXPColor.accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                inlineText(block.text)
                    .foregroundStyle(EXPColor.textSecondary)
            }
        case .code:
            ScrollView(.horizontal) {
                Text(block.text)
                    .font(.system(size: EXPType.small, design: .monospaced))
                    .foregroundStyle(EXPColor.textPrimary)
                    .padding(EXPMetric.md)
            }
            .background(EXPColor.surfaceField,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard,
                                             style: .continuous))
            .accessibilityLabel("Code: \(block.text)")
        }
    }

    private func inlineText(_ source: String) -> some View {
        Text(SanaaMarkdownPresentation.inline(source))
            .font(.system(size: EXPType.small))
            .foregroundStyle(EXPColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return EXPType.xxl
        case 2: return EXPType.xl
        case 3: return EXPType.md
        default: return EXPType.base
        }
    }
}

@MainActor
private struct SanaaFindingRail: View {
    let entryID: UUID
    let findings: [SanaaStructuredResponse.Finding]
    let isEnabled: Bool
    @State private var activity = SanaaActivityController.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: EXPMetric.md) {
                Text("Findings")
                    .font(.system(size: EXPType.base, weight: .semibold))
                    .foregroundStyle(EXPColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(findings.enumerated()), id: \.element.id) { findingIndex, finding in
                    findingRow(finding, findingIndex: findingIndex)
                }
            }
            .padding(EXPMetric.md)
        }
        .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)
        .background(EXPColor.surfacePanelSolid)
    }

    private func findingRow(_ finding: SanaaStructuredResponse.Finding,
                            findingIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: EXPMetric.sm) {
            Text(finding.label)
                .font(.system(size: EXPType.mini, weight: .bold, design: .monospaced))
                .foregroundStyle(EXPColor.accent)
            Text(finding.title)
                .font(.system(size: EXPType.small, weight: .medium))
                .foregroundStyle(EXPColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(finding.elements.enumerated()), id: \.element.id) { elementIndex, element in
                Button {
                    activity.showResponseElements([element], entryID: entryID)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: EXPMetric.sm) {
                        Text(elementAlias(findingIndex: findingIndex,
                                          elementIndex: elementIndex))
                            .font(.system(size: EXPType.micro, weight: .semibold,
                                          design: .monospaced))
                            .foregroundStyle(EXPColor.textSecondary)
                        Text(activity.responseElementName(element, entryID: entryID))
                            .font(.system(size: EXPType.mini))
                            .lineLimit(2)
                            .foregroundStyle(EXPColor.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "scope")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, EXPMetric.xs)
                .disabled(!isEnabled
                          || !activity.canShowResponseElements([element], entryID: entryID))
                .help("Highlight \(element.nodeID) on the original canvas")
                .accessibilityLabel("\(elementAlias(findingIndex: findingIndex, elementIndex: elementIndex)), \(activity.responseElementName(element, entryID: entryID))")
                .accessibilityHint("Highlights this exact layer on the original canvas")
                .contextMenu {
                    Button("Copy full element ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(element.nodeID, forType: .string)
                    }
                }
            }
            if finding.elements.count > 1 {
                Button("Show all \(finding.elements.count)") {
                    activity.showResponseElements(finding.elements, entryID: entryID)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!isEnabled
                          || !activity.canShowResponseElements(finding.elements,
                                                               entryID: entryID))
                .accessibilityHint("Highlights every referenced layer in this finding")
            }
            if let followUp = finding.followUp {
                Button("Explore \(finding.label)") {
                    activity.useResponseSuggestion(followUp)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityHint("Places a focused follow-up in the Sanaa composer for review")
            }
        }
        .padding(EXPMetric.sm)
        .background(EXPColor.surfaceField,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard,
                                         style: .continuous))
    }

    private func elementAlias(findingIndex: Int, elementIndex: Int) -> String {
        let preceding = findings.prefix(findingIndex).reduce(0) { $0 + $1.elements.count }
        return "L\(preceding + elementIndex + 1)"
    }
}

private enum SanaaExternalLink {
    static var openAction: OpenURLAction {
        OpenURLAction { url in
            guard SanaaMarkdownPresentation.isSafeExternalLink(url) else {
                NSSound.beep()
                return .discarded
            }
            NSWorkspace.shared.open(url)
            return .handled
        }
    }
}

@MainActor
private struct SanaaResponseReader: View {
    let entryID: UUID
    @State private var activity = SanaaActivityController.shared
    @AccessibilityFocusState private var titleFocused: Bool

    private var entry: SanaaTranscriptEntry? {
        activity.transcriptEntry(id: entryID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let entry {
                let response = SanaaStructuredResponse.parse(entry.text)
                header(entry)
                Divider()
                HStack(spacing: 0) {
                    if !response.findings.isEmpty {
                        SanaaFindingRail(entryID: entryID, findings: response.findings,
                                         isEnabled: !entry.isStreaming)
                        Divider()
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: EXPMetric.xl) {
                            SanaaMarkdownDocument(source: response.markdown)
                            SanaaResponseChoices(choices: response.choices,
                                                 isEnabled: !entry.isStreaming)
                        }
                        .padding(EXPMetric.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Response unavailable",
                    systemImage: "text.page.slash",
                    description: Text("This Sanaa session was cleared or disabled."))
            }
        }
        .background(EXPColor.surfaceWindow)
        .onAppear { titleFocused = true }
    }

    private func header(_ entry: SanaaTranscriptEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EXPMetric.md) {
            VStack(alignment: .leading, spacing: EXPMetric.xs) {
                Text(SanaaMarkdownPresentation.title(entry.text))
                    .font(.system(size: EXPType.xl, weight: .semibold))
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(2)
                    .accessibilityFocused($titleFocused)
                HStack(spacing: EXPMetric.sm) {
                    Text(entry.timestamp, style: .time)
                    if entry.isStreaming {
                        Label("Sanaa is still replying", systemImage: "ellipsis")
                    }
                }
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textSecondary)
            }
            Spacer(minLength: EXPMetric.md)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Label("Copy response", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .accessibilityHint("Copies the original Markdown response")
        }
        .padding(EXPMetric.lg)
        .background(EXPColor.surfaceToolbar)
    }
}

@MainActor
final class SanaaResponseWindowManager: NSObject, NSWindowDelegate {
    static let shared = SanaaResponseWindowManager()

    private final class Origin {
        weak var window: NSWindow?
        weak var responder: NSResponder?

        init(window: NSWindow?, responder: NSResponder?) {
            self.window = window
            self.responder = responder
        }
    }

    private var controllers: [UUID: NSWindowController] = [:]
    private var origins: [UUID: Origin] = [:]
    private var closingAll = false

    func open(entryID: UUID) {
        if let window = controllers[entryID]?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let originWindow = NSApp.keyWindow
        let origin = Origin(window: originWindow, responder: originWindow?.firstResponder)
        let host = NSHostingController(rootView: SanaaResponseReader(entryID: entryID))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Sanaa Response"
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 400)
        window.setContentSize(NSSize(width: 780, height: 760))
        window.center()
        window.delegate = self

        let controller = NSWindowController(window: window)
        controllers[entryID] = controller
        origins[entryID] = origin
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        closingAll = true
        // `close()` synchronously calls the delegate, which removes its entry.
        // Iterate a snapshot rather than mutating the dictionary's live values view.
        for controller in Array(controllers.values) { controller.close() }
        controllers.removeAll()
        origins.removeAll()
        closingAll = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entryID = controllers.first(where: { $0.value.window === window })?.key else { return }
        controllers[entryID] = nil
        let origin = origins.removeValue(forKey: entryID)
        guard !closingAll, let originWindow = origin?.window else { return }
        originWindow.makeKeyAndOrderFront(nil)
        if let responder = origin?.responder { originWindow.makeFirstResponder(responder) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = managedWindow(from: notification) else { return }
        // Panel trays intentionally live at `.floating`. Raise the response reader
        // to their level only while the person is actively reading it; transient
        // menus and popovers remain above both at `.popUpMenu`.
        window.level = .floating
        window.orderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = managedWindow(from: notification) else { return }
        window.level = .normal
    }

    private func managedWindow(from notification: Notification) -> NSWindow? {
        guard let window = notification.object as? NSWindow,
              controllers.values.contains(where: { $0.window === window }) else { return nil }
        return window
    }
}

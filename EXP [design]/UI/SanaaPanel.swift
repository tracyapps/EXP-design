//
//  SanaaPanel.swift
//  EXP [design]
//
//  FEAT-049 — the dedicated, chronological Sanaa conversation panel. The
//  Canvas work routes through EXP's restricted MCP bridge and appears here as
//  calm activity rather than host-specific technical output.
//

import SwiftUI

@MainActor
struct SanaaPanel: View {
    @State private var activity = SanaaActivityController.shared
    @AppStorage(SanaaPreferences.enabled) private var sanaaEnabled = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtBottom = true
    @State private var hasNewUpdate = false
    @State private var showDelayedWork = false
    @FocusState private var composerFocused: Bool

    private let bottomID = "sanaa-transcript-bottom"

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EXPColor.surfaceWindow)
        .onAppear { activity.activate() }
        .onChange(of: sanaaEnabled) { _, enabled in
            if enabled { activity.activate() } else { activity.disable() }
        }
        .task(id: activity.workActivity) {
            showDelayedWork = false
            guard activity.workActivity != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            guard !Task.isCancelled, activity.workActivity != nil else { return }
            showDelayedWork = true
        }
        .onChange(of: activity.draftFocusRevision) { _, _ in
            composerFocused = true
        }
    }

    private var statusBar: some View {
        HStack(spacing: EXPMetric.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(activity.statusText)
                .font(.system(size: EXPType.mini))
                .foregroundStyle(activity.phase == .failed
                                 ? EXPColor.textPrimary : EXPColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: EXPMetric.sm)
            if activity.phase == .failed || activity.phase == .idle {
                Button("Reconnect") { activity.reconnect() }
                    .buttonStyle(.borderless)
                    .font(.system(size: EXPType.mini, weight: .medium))
                    .accessibilityHint("Tries the signed local Sanaa Runtime again")
            }
            Button {
                UserDefaults.standard.set("sanaa", forKey: AppPreferences.requestedSettingsPane)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Agent settings")
            .accessibilityHint("Opens connection, permission, and usage settings")
        }
        .padding(.horizontal, EXPMetric.md)
        .padding(.vertical, EXPMetric.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EXPColor.surfaceToolbar)
    }

    private var statusColor: Color {
        switch activity.phase {
        case .ready: return .green
        case .replying, .stopping, .connecting: return EXPColor.accent
        case .failed: return .orange
        case .off, .idle: return EXPColor.textTertiary
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: EXPMetric.md) {
                        if activity.transcript.isEmpty { emptyState }
                        ForEach(activity.transcript) { entry in
                            transcriptRow(entry)
                        }
                        if showDelayedWork, let workActivity = activity.workActivity {
                            SanaaWorkIndicator(activity: workActivity)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(EXPMetric.md)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height <= geometry.containerSize.height + 1
                        || geometry.visibleRect.maxY >= geometry.contentSize.height - 24
                } action: { _, atBottom in
                    isAtBottom = atBottom
                    if atBottom { hasNewUpdate = false }
                }
                if hasNewUpdate {
                    Button {
                        scrollToBottom(proxy)
                    } label: {
                        Label("New update", systemImage: "arrow.down")
                            .font(.system(size: EXPType.mini, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(EXPMetric.md)
                    .accessibilityHint("Moves to the newest Sanaa message")
                }
            }
            .onChange(of: activity.transcriptRevision) { _, _ in
                if isAtBottom { scrollToBottom(proxy) }
                else { hasNewUpdate = true }
            }
            .onChange(of: showDelayedWork) { _, isVisible in
                guard isVisible else { return }
                if isAtBottom { scrollToBottom(proxy) }
                else { hasNewUpdate = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: EXPMetric.md) {
            Label("Conversation", systemImage: "message.and.waveform")
                .font(.system(size: EXPType.base, weight: .medium))
                .foregroundStyle(EXPColor.textPrimary)
            Text("Type here and Sanaa will reply through your signed-in local Codex account. EXP ships no language model or API key.")
                .font(.system(size: EXPType.small))
                .foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("With Agent access on, Sanaa can look at this canvas and draw. Your drawing switch, per-document consent, and one-step Undo still apply.",
                  systemImage: "paintbrush")
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up Sanaa…") {
                UserDefaults.standard.set("sanaa", forKey: AppPreferences.requestedSettingsPane)
                openSettings()
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens the guided local-assistant connection walkthrough")
        }
        .padding(EXPMetric.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EXPColor.surfacePanelSolid,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard, style: .continuous))
    }

    @ViewBuilder
    private func transcriptRow(_ entry: SanaaTranscriptEntry) -> some View {
        if let receipt = entry.receipt {
            appliedBatchRow(receipt)
        } else {
            VStack(alignment: .leading, spacing: EXPMetric.xs) {
                HStack(spacing: EXPMetric.sm) {
                    Text(author(for: entry.kind))
                        .font(.system(size: EXPType.mini, weight: .medium))
                        .foregroundStyle(EXPColor.textSecondary)
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: EXPType.micro))
                        .foregroundStyle(EXPColor.textTertiary)
                    if entry.isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Sanaa is still replying")
                    }
                }
                if entry.kind == .assistant {
                    let response = SanaaStructuredResponse.parse(entry.text)
                    SanaaResponsePreview(source: entry.text, isStreaming: entry.isStreaming)
                    if !entry.isStreaming {
                        SanaaResponseChoices(choices: Array(response.choices.prefix(4)))
                    }
                    Button {
                        SanaaResponseWindowManager.shared.open(entryID: entry.id)
                    } label: {
                        Label("Open full response", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: EXPType.mini, weight: .medium))
                    .accessibilityHint("Opens this response in a resizable Markdown reader window")
                } else {
                    Text(entry.text)
                        .font(.system(size: EXPType.small))
                        .foregroundStyle(entry.kind == .status
                                         ? EXPColor.textSecondary : EXPColor.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EXPMetric.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(for: entry.kind),
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard, style: .continuous))
            .accessibilityElement(children: entry.kind == .assistant ? .contain : .combine)
            .accessibilityLabel(entry.kind == .assistant
                                ? "Sanaa response"
                                : "\(author(for: entry.kind)): \(entry.text)")
        }
    }

    private func appliedBatchRow(_ receipt: SanaaAppliedBatchReceipt) -> some View {
        VStack(alignment: .leading, spacing: EXPMetric.sm) {
            HStack(spacing: EXPMetric.sm) {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: EXPType.mini, weight: .semibold))
                    .foregroundStyle(EXPColor.textPrimary)
                Spacer(minLength: EXPMetric.sm)
                Text(receipt.timestamp, style: .time)
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
            }
            Text(receipt.summary)
                .font(.system(size: EXPType.small, weight: .medium))
                .foregroundStyle(EXPColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(receipt.client) · \(receipt.pageDescription)")
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textSecondary)
                .lineLimit(2)
            HStack(spacing: EXPMetric.sm) {
                Button("Select changes") { activity.selectChanges(receipt) }
                    .controlSize(.small)
                    .disabled(!activity.canAct(on: receipt))
                    .accessibilityHint("Selects the layers or artboards changed by this Sanaa batch")
                Button("Go there") { activity.goToChanges(receipt) }
                    .controlSize(.small)
                    .disabled(!activity.canAct(on: receipt))
                    .accessibilityHint("Selects Sanaa's changes and brings them into view")
            }
        }
        .padding(EXPMetric.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EXPColor.accentSubtle,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sanaa applied \(receipt.summary) on \(receipt.pageDescription)")
    }

    private func author(for kind: SanaaTranscriptEntry.Kind) -> String {
        switch kind {
        case .designer: return "You"
        case .assistant: return "Sanaa"
        case .status: return "Runtime"
        case .appliedBatch: return "Sanaa"
        }
    }

    private func background(for kind: SanaaTranscriptEntry.Kind) -> Color {
        switch kind {
        case .designer: return EXPColor.accentSubtle
        case .assistant: return EXPColor.surfacePanelSolid
        case .status: return EXPColor.rowHover
        case .appliedBatch: return EXPColor.accentSubtle
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: EXPMetric.sm) {
            if activity.conversationAgents.count > 1 {
                HStack(spacing: EXPMetric.sm) {
                    Text("Agent")
                        .font(.system(size: EXPType.mini))
                        .foregroundStyle(EXPColor.textSecondary)
                    Picker("Agent", selection: $activity.selectedAgentID) {
                        ForEach(activity.conversationAgents) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .accessibilityHint("Chooses which supported conversation runtime receives this message")
                    Spacer(minLength: 0)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $activity.draft)
                    .focused($composerFocused)
                    .font(.system(size: EXPType.small))
                    .scrollContentBackground(.hidden)
                    .padding(EXPMetric.xs)
                    .frame(minHeight: 58, maxHeight: 110)
                    .accessibilityLabel("Message Sanaa")
                    .accessibilityHint("Type a message, then choose Send or press Command Return")
                if activity.draft.isEmpty {
                    Text("Message Sanaa…")
                        .font(.system(size: EXPType.small))
                        .foregroundStyle(EXPColor.textTertiary)
                        .padding(.horizontal, EXPMetric.sm + 1)
                        .padding(.vertical, EXPMetric.sm + 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(EXPColor.surfaceField,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                    .strokeBorder(EXPColor.borderStrong, lineWidth: EXPMetric.strokeHairline)
            }

            HStack(spacing: EXPMetric.sm) {
                Text("⌘↩︎ to send")
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                Spacer()
                if activity.canCopyFallback {
                    Button(activity.copiedDraft ? "Copied" : "Copy for my agent") {
                        activity.copyDraftFallback()
                    }
                    .controlSize(.small)
                    .accessibilityHint("Copies the draft because the supported local runtime is unavailable")
                }
                if activity.isResponding {
                    Button("Stop", role: .cancel) { activity.stopReply() }
                        .controlSize(.small)
                        .disabled(activity.phase == .stopping)
                        .accessibilityHint("Interrupts only the active Sanaa reply")
                } else {
                    Button("Send") { activity.sendDraft() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!activity.canSend)
                        .accessibilityHint("Sends this message to the supported local runtime")
                }
            }
        }
        .padding(EXPMetric.md)
        .background(EXPColor.surfaceToolbar)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        hasNewUpdate = false
        if reduceMotion {
            proxy.scrollTo(bottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }
}

/// A quiet, delayed acknowledgement for time before the first visible text.
/// Reduce Motion keeps all three dots present without temporal animation.
private struct SanaaWorkIndicator: View {
    let activity: SanaaActivityController.WorkActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeDot = 0

    var body: some View {
        VStack(alignment: .leading, spacing: EXPMetric.xs) {
            Text("Sanaa")
                .font(.system(size: EXPType.mini, weight: .medium))
                .foregroundStyle(EXPColor.textSecondary)
            HStack(spacing: EXPMetric.sm) {
                if activity != .thinking {
                    Label(activity == .designing ? "Designing" : "Working",
                          systemImage: activity == .designing ? "paintbrush.pointed.fill" : "sparkles")
                        .font(.system(size: EXPType.mini, weight: .medium))
                        .foregroundStyle(EXPColor.textSecondary)
                }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(EXPColor.textSecondary)
                            .frame(width: 5, height: 5)
                            .opacity(dotOpacity(at: index))
                            .scaleEffect(dotScale(at: index))
                    }
                }
                .frame(height: 9)
            }
            .padding(.horizontal, EXPMetric.md)
            .padding(.vertical, EXPMetric.sm)
            .background(EXPColor.surfacePanelSolid,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusCard, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.accessibilityLabel)
        .accessibilityHint("Waiting for Sanaa's first response text")
        .task(id: reduceMotion) {
            activeDot = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(320))
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }

    private func dotOpacity(at index: Int) -> Double {
        reduceMotion ? 0.65 : (index == activeDot ? 1 : 0.28)
    }

    private func dotScale(at index: Int) -> CGFloat {
        reduceMotion || index != activeDot ? 1 : 1.22
    }
}

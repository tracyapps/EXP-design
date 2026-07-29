//
//  HandoffPanel.swift
//  EXP [design]
//
//  v2.1 Chunk F2 — one practical home for visual exports, inspectable handoff
//  artifacts, and the deliberately opt-in read-only local agent bridge.
//

import SwiftUI
import AppKit

@MainActor
struct HandoffPanel: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @State private var bridge = AgentBridgeController.shared
    @State private var setupKind = AgentSetupKind.claudeCode
    @State private var copiedLabel: String?

    private enum AgentSetupKind: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case claudeDesktop = "Claude Desktop"
        case stdioJSON = "stdio JSON"
        case helperPath = "Helper path"
        var id: Self { self }
    }

    private var activeArtboardCount: Int {
        document.model.page(for: app.activeCanvasPageID)?.artboards.count ?? 0
    }

    private var selectedExportCount: Int {
        if !app.selectedArtboardIDs.isEmpty { return app.selectedArtboardIDs.count }
        return activeArtboardCount > 0 ? 1 : 0
    }

    private var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/exp-mcp").path
    }

    private var setupText: String {
        switch setupKind {
        case .claudeCode:
            let escaped = helperPath.replacingOccurrences(of: "'", with: "'\\''")
            return "claude mcp add --scope user exp-design -- '\(escaped)'"
        case .claudeDesktop, .stdioJSON:
            let object: [String: Any] = [
                "mcpServers": [
                    "exp-design": ["command": helperPath, "args": []]
                ]
            ]
            guard let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
            ) else { return helperPath }
            return String(data: data, encoding: .utf8) ?? helperPath
        case .helperPath:
            return helperPath
        }
    }

    private var setupNote: String? {
        switch setupKind {
        case .claudeDesktop:
            return "Manual local-server configuration. Claude Desktop may also offer extension-based installation for packaged servers."
        case .stdioJSON:
            return "Use this with any MCP host that accepts a stdio server configuration."
        default:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EXPMetric.lg) {
                handoffSection("Export", icon: "square.and.arrow.up") {
                    Text("Render the current target or every artboard on this page as PNG, JPEG, PDF, or SVG.")
                        .handoffDetail()
                    panelAction(selectedExportCount > 1
                                ? "Export \(selectedExportCount) Selected Artboards…"
                                : "Export Current Artboard…",
                                icon: "square.and.arrow.up") {
                        sendCanvasAction("exportSelectedArtboard:")
                    }
                    .disabled(selectedExportCount == 0)
                    .accessibilityHint("Opens the format and destination chooser")
                    panelAction("Export All \(activeArtboardCount) Artboards…",
                                icon: "square.grid.2x2") {
                        sendCanvasAction("exportAllArtboards:")
                    }
                    .disabled(activeArtboardCount == 0)
                    .accessibilityHint("Exports every artboard on the active canvas page")
                }

                Divider()

                handoffSection("Package", icon: "shippingbox") {
                    Text("Create editable, developer-facing artifacts without changing the document.")
                        .handoffDetail()
                    panelAction("Handoff Package…", icon: "shippingbox") {
                        sendCanvasAction("exportHandoffPackage:")
                    }
                    .accessibilityHint("Exports design JSON, tokens, semantic HTML, a manifest, and an orientation guide")
                    panelAction("Semantic HTML…", icon: "chevron.left.forwardslash.chevron.right") {
                        sendCanvasAction("exportSemanticHTMLAction:")
                    }
                    panelAction("Design Tokens…", icon: "curlybraces") {
                        sendCanvasAction("exportDesignTokensAction:")
                    }
                }

                Divider()

                handoffSection("Agent", icon: "terminal") {
                    Toggle("Allow local agent access", isOn: Binding(
                        get: { bridge.isEnabled },
                        set: { bridge.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .accessibilityHint("Starts or stops EXP's read-only local connection")

                    agentStatus

                    Text("Off by default. The bridge accepts read-only requests from your macOS user through a local socket; EXP does not open a network port or send document data on its own. A connected agent may process requested content according to that agent's provider and privacy settings.")
                        .handoffDetail()

                    if bridge.isEnabled {
                        Picker("Setup for", selection: $setupKind) {
                            ForEach(AgentSetupKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                        }
                        .pickerStyle(.menu)

                        Text(setupText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(EXPColor.textSecondary)
                            .textSelection(.enabled)
                            .padding(EXPMetric.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(EXPColor.surfaceField,
                                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusField))
                            .accessibilityLabel("Agent setup command")

                        if let setupNote {
                            Text(setupNote).handoffDetail()
                        }

                        panelAction(copiedLabel == "setup" ? "Copied Setup" : "Copy Setup",
                                    icon: copiedLabel == "setup" ? "checkmark" : "doc.on.doc") {
                            copy(setupText, label: "setup")
                        }

                        if bridge.connectionCount > 0 {
                            panelAction(copiedLabel == "selection" ? "Selection Prompt Copied" : "Copy Selection Prompt",
                                        icon: copiedLabel == "selection" ? "checkmark" : "scope") {
                                copy("Use EXP [design]'s get_selection tool to inspect my current selection. Preserve EXP node IDs when referring to layers or components.", label: "selection")
                            }
                            .accessibilityHint("Copies a prompt that asks the connected agent to read the current EXP selection")
                        }
                    }
                }
            }
            .padding(EXPMetric.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func handoffSection<Content: View>(_ title: String, icon: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EXPMetric.sm) {
            HStack(spacing: EXPMetric.sm) {
                Image(systemName: icon)
                    .foregroundStyle(EXPColor.textTertiary)
                    .accessibilityHidden(true)
                Text(title).expSectionLabel()
            }
            .accessibilityElement(children: .combine)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var agentStatus: some View {
        HStack(spacing: EXPMetric.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.callout.weight(.medium))
                .foregroundStyle(EXPColor.textPrimary)
            Spacer(minLength: 0)
            if bridge.connectionCount > 0 {
                Text("READ ONLY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EXPColor.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(EXPColor.borderSoft))
                    .accessibilityLabel("Read-only access")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent status: \(statusText)\(bridge.connectionCount > 0 ? ", read only" : "")")
    }

    private func panelAction(_ title: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: EXPMetric.sm) {
                Image(systemName: icon)
                    .frame(width: 13)
                    .foregroundStyle(EXPColor.textSecondary)
                    .accessibilityHidden(true)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.expCompact(fillsWidth: true))
        .accessibilityLabel(title)
    }

    private var statusColor: Color {
        if !bridge.isEnabled || !bridge.isRunning { return EXPColor.textTertiary }
        return EXPColor.accent
    }

    private var statusText: String {
        if let error = bridge.lastError { return "Unavailable — \(error)" }
        guard bridge.isEnabled, bridge.isRunning else { return "Off" }
        guard bridge.connectionCount > 0 else { return "Ready for a local connection" }
        if let clientName = bridge.clientName { return "Connected to \(clientName)" }
        return bridge.connectionCount == 1 ? "1 agent connected" : "\(bridge.connectionCount) agents connected"
    }

    private func copy(_ string: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedLabel = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedLabel == label { copiedLabel = nil }
        }
    }
}

private extension View {
    func handoffDetail() -> some View {
        font(.caption)
            .foregroundStyle(EXPColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

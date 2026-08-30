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
    @Environment(\.openSettings) private var openSettings
    @State private var bridge = AgentBridgeController.shared
    // Read through @AppStorage rather than SanaaPreferences directly so the access
    // capsule updates the moment the designer changes a switch in Settings.
    @AppStorage(SanaaPreferences.enabled) private var sanaaEnabled = false
    @AppStorage(SanaaPreferences.writeEnabled) private var sanaaWriteEnabled = false

    private var activeArtboardCount: Int {
        document.model.page(for: app.activeCanvasPageID)?.artboards.count ?? 0
    }

    private var selectedExportCount: Int {
        if !app.selectedArtboardIDs.isEmpty { return app.selectedArtboardIDs.count }
        return activeArtboardCount > 0 ? 1 : 0
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
                    panelAction("Send Current Artboard to CodePen…",
                                icon: "safari") {
                        sendCanvasAction("exportCurrentArtboardToCodePen:")
                    }
                    .disabled(selectedExportCount != 1)
                    .accessibilityHint("Opens a local review page before sending semantic HTML and CSS to a new CodePen Pen")
                    panelAction("Design Tokens…", icon: "curlybraces") {
                        sendCanvasAction("exportDesignTokensAction:")
                    }
                }

                Divider()

                handoffSection("Agent", icon: "terminal") {
                    agentStatus
                    Text("Connection setup, permissions, connected agents, and available account usage now live together in Settings.")
                        .handoffDetail()
                    panelAction("Manage Agent Connections…", icon: "gearshape") {
                        UserDefaults.standard.set("sanaa", forKey: AppPreferences.requestedSettingsPane)
                        openSettings()
                    }
                    .accessibilityHint("Opens Sanaa and agent connection settings")
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
                Text(accessCapsule)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EXPColor.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(EXPColor.borderSoft))
                    .accessibilityLabel(accessDescription)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent status: \(statusText)\(bridge.connectionCount > 0 ? ", \(accessDescription)" : "")")
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

    /// What a connected agent is allowed to do RIGHT NOW. This capsule is never
    /// decorative: read-only and can-draw are genuinely different permissions, and
    /// the designer should be able to see which one is live without opening
    /// Settings. Text carries the meaning, not colour (WCAG 2.1 AA 1.4.1).
    private var canDraw: Bool { sanaaEnabled && sanaaWriteEnabled }

    private var accessCapsule: String { canDraw ? "CAN DRAW" : "READ ONLY" }

    private var accessDescription: String {
        canDraw ? "can read and draw" : "read-only access"
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

}

private extension View {
    func handoffDetail() -> some View {
        font(.caption)
            .foregroundStyle(EXPColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

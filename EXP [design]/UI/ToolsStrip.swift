//
//  ToolsStrip.swift
//  EXP [design]
//
//  The fixed vertical tool strip on the far left. Per the roadmap, this strip
//  stays pinned to the left of the main window (it is NOT one of the floating/
//  detachable panels) — so it lives outside the HSplitView, at a fixed width.
//
//  It's a thin, self-contained, state-driven view: it only reads/writes
//  `app.tool`. The matching keyboard shortcuts (V / R / O / Esc) are handled in
//  the canvas, which is the first responder.
//
//  Phase 17c: reskinned onto DesignTokens + the `expGlass(.thin)` rail material.
//  (Tool re-ordering + the new pan/image/component tools are tracked separately —
//  they're functional `Tool`-enum work, not part of this visual pass.)
//

import SwiftUI

struct ToolsStrip: View {
    @Environment(AppState.self) private var app

    /// Tools grouped by purpose, separated by a hairline:
    /// selection · shapes · make · structure.
    ///
    /// Artboard sits alone at the bottom on purpose. It draws a CONTAINER, not a
    /// shape, and grouping it with the shape tools would imply otherwise.
    private let toolGroups: [[Tool]] = [
        [.pan, .select, .node, .knife],
        [.rectangle, .ellipse, .polygon, .line, .pen, .pencil],
        [.text, .image, .component],
        [.artboard]
    ]

    /// Mode tools set `app.tool`; the two ACTION tools fire their canvas action
    /// (via the responder chain) and leave the current tool as-is.
    private func select(_ tool: Tool) {
        switch tool {
        case .image:     sendCanvasAction("placeImageAction:")
        case .component: sendCanvasAction("newEmptyComponentAction:")
        default:         app.tool = tool
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: EXPMetric.xs) {
                ForEach(Array(toolGroups.enumerated()), id: \.offset) { idx, group in
                    if idx > 0 {
                        Rectangle()
                            .fill(EXPColor.hairline)
                            .frame(width: 22, height: EXPMetric.strokeHairline)
                            .padding(.vertical, EXPMetric.xs)
                    }
                    ForEach(group, id: \.self) { tool in
                        ToolButton(tool: tool, isActive: app.tool == tool) { select(tool) }
                    }
                }
            }
            .padding(.vertical, EXPMetric.md)
        }
        .scrollIndicators(.hidden)
        .frame(width: EXPInterfaceAccessibility.shared.showToolbarLabels
               ? 150 * EXPType.scale
               : max(EXPMetric.toolsStripWidth, EXPMetric.controlHLg + 14))
        .frame(maxHeight: .infinity)
        .expGlass(.thin, cornerRadius: 0)
        .overlay(alignment: .trailing) {
            Rectangle().fill(EXPColor.hairline).frame(width: EXPMetric.strokeHairline)
        }
    }
}

private struct ToolButton: View {
    let tool: Tool
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    private var accessibleHint: String {
        var parts: [String] = []
        if tool == .knife {
            parts.append("Click to select; draw across artwork to cut along your stroke. Choose types and layer scope in Properties. Object, Path, Cut with Line opens an editable straight cut preview.")
        }
        if !tool.shortcutKey.isEmpty { parts.append("Keyboard shortcut: \(tool.shortcutKey).") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: EXPType.md, weight: isActive ? .medium : .regular))
                    .frame(width: EXPMetric.controlHLg, height: EXPMetric.controlHLg)
                if EXPInterfaceAccessibility.shared.showToolbarLabels {
                    Text(tool.label).font(.expLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
                .frame(maxWidth: EXPInterfaceAccessibility.shared.showToolbarLabels ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: EXPMetric.radiusTool, style: .continuous)
                        .fill(isActive ? EXPColor.accentSubtle
                              : (hovering ? EXPColor.rowHover : .clear))
                )
                .foregroundStyle(isActive ? EXPColor.accent
                                 : (hovering ? EXPColor.textPrimary : EXPColor.textSecondary))
                .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusTool, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, EXPInterfaceAccessibility.shared.showToolbarLabels ? 6 : 0)
        .onHover { hovering = $0 }
        .animation(EXPMotion.fast, value: hovering)
        .animation(EXPMotion.fast, value: isActive)
        .expTooltip(label: tool.label, shortcut: tool.shortcutKey)   // design tooltip + keycap
        .accessibilityLabel(tool.label)
        .accessibilityHint(accessibleHint)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

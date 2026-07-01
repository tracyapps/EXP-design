//
//  Controls.swift
//  EXP [design]
//
//  Phase 17c — brand interactive controls from the design system: EXPSegmented
//  (the accent-fill pill toggle) and EXPButtonStyle (primary / secondary / ghost).
//  App-target-only chrome; uses DesignTokens.
//

import SwiftUI

// MARK: - Segmented control =================================================

/// The design-system `SegmentedControl`: an inset `surface-field` groove with a
/// gap-2 track; the selected segment is an accent fill (medium weight, on-accent
/// text), the rest are light `text-secondary`. Generic over a `Hashable` value.
///
///     EXPSegmented(selection: $box, segments: [
///         .init(value: .auto,  label: "Auto width"),
///         .init(value: .fixed, label: "Text box"),
///     ])
struct EXPSegmented<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        var label: String? = nil
        var icon: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let segments: [Segment]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { seg in
                let sel = seg.value == selection
                Button { selection = seg.value } label: {
                    HStack(spacing: 5) {
                        if let icon = seg.icon { Image(systemName: icon).font(.system(size: 11)) }
                        if let label = seg.label { Text(label) }
                    }
                    .font(.system(size: 12, weight: sel ? .medium : .light))
                    .foregroundStyle(sel ? EXPColor.accentForeground : EXPColor.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 20)
                    .background(sel ? EXPColor.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl - 2, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusControl - 2, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(EXPColor.surfaceField,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusControl, style: .continuous)
            .strokeBorder(EXPColor.borderSoft, lineWidth: EXPMetric.strokeHairline))
        .animation(EXPMotion.fast, value: selection)
    }
}

// MARK: - Button style ======================================================

/// The design-system `Button`: primary = accent fill, secondary = neutral glass,
/// ghost = borderless hover wash. Radius 8, medium weight, subtle press-shrink.
/// Usage: `Button("Add") { … }.buttonStyle(.exp())` or `.exp(.secondary)`.
struct EXPButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost }
    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> Body {
        // Hover state must live in a real view (not the style struct).
        Body(configuration: configuration, variant: variant)
    }

    internal struct Body: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        @State private var hovering = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.system(size: EXPType.base, weight: .medium))
                .foregroundStyle(fg)
                .padding(.horizontal, EXPMetric.lg)
                .frame(height: EXPMetric.controlHLg)
                .background(bg(pressed: pressed),
                            in: RoundedRectangle(cornerRadius: EXPMetric.radiusButton, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusButton, style: .continuous)
                    .strokeBorder(border, lineWidth: EXPMetric.strokeHairline))
                .scaleEffect(pressed ? 0.985 : 1)
                .onHover { hovering = $0 }
                .animation(EXPMotion.fast, value: hovering)
                .animation(EXPMotion.fast, value: pressed)
        }

        private var fg: Color {
            switch variant {
            case .primary:           return EXPColor.accentForeground
            case .secondary, .ghost: return EXPColor.textPrimary
            }
        }
        private func bg(pressed: Bool) -> Color {
            switch variant {
            case .primary:   return pressed ? EXPColor.accentPress : (hovering ? EXPColor.accentHover : EXPColor.accent)
            case .secondary: return hovering ? EXPColor.rowActive : EXPColor.surfaceField
            case .ghost:     return hovering ? EXPColor.rowHover : .clear
            }
        }
        private var border: Color {
            switch variant {
            case .primary:   return EXPColor.borderStrong
            case .secondary: return EXPColor.borderGlass
            case .ghost:     return .clear
            }
        }
    }
}

extension ButtonStyle where Self == EXPButtonStyle {
    static func exp(_ variant: EXPButtonStyle.Variant = .primary) -> EXPButtonStyle {
        EXPButtonStyle(variant: variant)
    }
}

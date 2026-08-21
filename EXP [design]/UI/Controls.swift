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
        /// VoiceOver name when the segment is icon-only (falls back to `label`).
        var accessibilityLabel: String? = nil
        /// Sighted hover help; accessibility always uses the stable name above.
        var help: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let segments: [Segment]
    @FocusState private var focusedValue: Value?
    @ScaledMetric(relativeTo: .caption) private var segmentFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var segmentHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { seg in
                let sel = seg.value == selection
                Button {
                    selection = seg.value
                    focusedValue = seg.value
                } label: {
                    HStack(spacing: 5) {
                        if let icon = seg.icon { Image(systemName: icon).font(.system(size: 11)) }
                        if let label = seg.label { Text(label) }
                    }
                    .font(.system(size: segmentFontSize, weight: sel ? .medium : .light))
                    .foregroundStyle(sel ? EXPColor.accentForeground : EXPColor.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: segmentHeight)
                    .background(sel ? EXPColor.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl - 2, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusControl - 2, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable(sel)
                .focused($focusedValue, equals: seg.value)
                .onMoveCommand { move(from: seg.value, direction: $0) }
                .help(seg.help ?? seg.accessibilityLabel ?? seg.label ?? "")
                .accessibilityLabel(seg.accessibilityLabel ?? seg.label ?? "")
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(EXPColor.surfaceField,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusControl, style: .continuous)
            .strokeBorder(EXPColor.borderSoft, lineWidth: EXPMetric.strokeHairline))
        .animation(EXPMotion.fast, value: selection)
    }

    private func move(from value: Value, direction: MoveCommandDirection) {
        guard direction == .left || direction == .right
                || direction == .up || direction == .down,
              let index = segments.firstIndex(where: { $0.value == value }),
              !segments.isEmpty else { return }
        let delta = (direction == .right || direction == .down) ? 1 : -1
        let next = segments[(index + delta + segments.count) % segments.count].value
        selection = next
        focusedValue = next
    }
}

// MARK: - Dropdown chrome ==================================================

private struct EXPDropdownChrome: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .frame(minHeight: EXPMetric.controlH)
            .background(hovering ? EXPColor.surfaceFieldFocus : EXPColor.surfaceField,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusField,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                .strokeBorder(EXPColor.borderControl, lineWidth: EXPMetric.strokeHairline))
            .onHover { hovering = $0 }
            .animation(EXPMotion.fast, value: hovering)
    }
}

extension View {
    /// Shared boundary/hover treatment for custom popup and menu labels.
    func expDropdownChrome() -> some View { modifier(EXPDropdownChrome()) }
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

// MARK: - Compact panel action button ======================================

/// The dense secondary action used inside dock panels. Dialogs keep the larger
/// `EXPButtonStyle`; repeated panel actions use the same 24pt control height and
/// mini label rhythm as Design Language and the panel toolbars.
struct EXPCompactButtonStyle: ButtonStyle {
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, fillsWidth: fillsWidth)
    }

    internal struct Body: View {
        let configuration: ButtonStyleConfiguration
        let fillsWidth: Bool
        @State private var hovering = false
        @ScaledMetric(relativeTo: .caption) private var controlHeight: CGFloat = EXPMetric.controlH
        @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = EXPType.mini

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(EXPColor.textPrimary)
                .padding(.horizontal, 9)
                .frame(maxWidth: fillsWidth ? .infinity : nil,
                       minHeight: controlHeight,
                       maxHeight: controlHeight,
                       alignment: fillsWidth ? .leading : .center)
                .background(configuration.isPressed ? EXPColor.rowActive
                            : (hovering ? EXPColor.rowHover : EXPColor.surfaceField),
                            in: RoundedRectangle(cornerRadius: EXPMetric.radiusButton,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusButton, style: .continuous)
                    .strokeBorder(EXPColor.borderGlass, lineWidth: EXPMetric.strokeHairline))
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .onHover { hovering = $0 }
                .animation(EXPMotion.fast, value: hovering)
                .animation(EXPMotion.fast, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == EXPCompactButtonStyle {
    static func expCompact(fillsWidth: Bool = false) -> EXPCompactButtonStyle {
        EXPCompactButtonStyle(fillsWidth: fillsWidth)
    }
}

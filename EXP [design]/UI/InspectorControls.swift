import SwiftUI
import AppKit

/// The position of the accent mark conveys the side without consuming a label
/// column. The field still has a full name for VoiceOver, Voice Control and help.
enum EXPFieldEdge {
    case top, right, bottom, left
    var alignment: Alignment {
        switch self { case .top: .top; case .right: .trailing; case .bottom: .bottom; case .left: .leading }
    }
    var isHorizontal: Bool { self == .top || self == .bottom }
}

struct EXPEdgeField: View {
    let name: String
    let edge: EXPFieldEdge
    @Binding var value: Double
    /// The Design Language token control for this field (FEAT-089b). nil when
    /// the document has no spacing tokens, so the field is exactly as before.
    var token: EXPTokenButton? = nil

    private var spokenName: String {
        guard let token else { return name }
        switch token.state {
        case .unlinked: return name
        case .linked(let tokenName): return "\(name), linked to \(tokenName)"
        case .missing: return "\(name), linked to a missing token"
        }
    }

    var body: some View {
        HStack(spacing: 1) {
            field
            if let token { token }
        }
    }

    private var field: some View {
        TextField(name, value: $value, format: .number.precision(.fractionLength(0)))
            .labelsHidden().textFieldStyle(.exp)
            .multilineTextAlignment(.trailing).monospacedDigit()
            .frame(minWidth: 44 * EXPType.scale, maxWidth: .infinity)
            .numericStepping($value, min: 0)
            .overlay(alignment: edge.alignment) {
                Rectangle().fill(EXPColor.accent)
                    .frame(width: edge.isHorizontal ? nil : 3,
                           height: edge.isHorizontal ? 3 : nil)
                    .padding(edge.isHorizontal ? .horizontal : .vertical, 5)
                    .offset(x: edge == .left ? -3 : (edge == .right ? 3 : 0),
                            y: edge == .top ? -3 : (edge == .bottom ? 3 : 0))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .padding(3)
            .expFieldTip(name)
            .accessibilityLabel(spokenName)
    }
}

// MARK: - Design Language token control (FEAT-089b)

/// One token offered by a field's token menu.
struct EXPTokenChoice: Identifiable {
    let id: UUID
    let name: String
    let group: String
    /// The value as authored, plus the resolved number when they differ.
    let valueText: String
    /// What the token measures for the selected layer; nil when it can't be
    /// measured there (a viewport unit with no artboard, a grid track, …).
    let resolved: NumericTokenValue?
}

/// Native text-field parsing for fixed radii and percentages in the current locale.
struct EXPCornerRadiusFormat: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: NumericTokenValue) -> String {
        switch value {
        case .points(let points): return Double(points).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
        case .percentage(let percent): return Double(percent).formatted(.number.grouping(.never).precision(.fractionLength(0...2))) + "%"
        }
    }

    struct Strategy: ParseStrategy {
        func parse(_ value: String) throws -> NumericTokenValue {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPercent = text.hasSuffix("%")
            let number = (hasPercent ? String(text.dropLast()) : text).trimmingCharacters(in: .whitespaces)
            let parsed = try FloatingPointFormatStyle<Double>.number.parseStrategy.parse(number)
            guard parsed.isFinite, !hasPercent || (0...1_000_000).contains(parsed) else { throw CocoaError(.formatting) }
            return hasPercent ? .percentage(CGFloat(parsed)) : .points(CGFloat(parsed))
        }
    }
}

enum EXPTokenLinkState: Equatable {
    case unlinked
    case linked(String)
    case missing
}

/// The small button at a number field's trailing edge: shows whether the field
/// is linked to a token, and opens the menu that links, relinks or clears it.
/// State is carried by the glyph's SHAPE and by words, never by color alone.
struct EXPTokenButton: View {
    let kind: DLDimensionKind
    let fieldName: String
    let state: EXPTokenLinkState
    let linkedID: UUID?
    let choices: [EXPTokenChoice]
    let currentValue: Double
    let onSelect: (UUID?) -> Void
    @Environment(\.openWindow) private var openWindow

    private var symbol: String {
        switch state {
        case .unlinked: return "ellipsis"
        case .linked: return "link"
        case .missing: return "exclamationmark.triangle"
        }
    }
    private var summary: String {
        switch state {
        case .unlinked: return "\(fieldName) token: none"
        case .linked(let name): return "\(fieldName) token: \(name)"
        case .missing: return "\(fieldName) token: missing. Choose another token or None."
        }
    }
    private var groups: [(name: String, items: [EXPTokenChoice])] {
        var order: [String] = []
        var buckets: [String: [EXPTokenChoice]] = [:]
        for choice in choices {
            if buckets[choice.group] == nil { order.append(choice.group) }
            buckets[choice.group, default: []].append(choice)
        }
        return order.map { (name: $0, items: buckets[$0] ?? []) }
    }
    private func title(_ choice: EXPTokenChoice) -> String {
        let name = choice.name.isEmpty ? "Unnamed" : choice.name
        return choice.resolved == nil
            ? "\(name) — \(choice.valueText), can’t be measured here"
            : "\(name) — \(choice.valueText)"
    }

    var body: some View {
        Menu {
            Button(state == .missing ? "Clear Missing Link" : "None") { onSelect(nil) }
                .disabled(state == .unlinked)
            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.items) { choice in
                        Button { onSelect(choice.id) } label: {
                            if choice.id == linkedID { Label(title(choice), systemImage: "checkmark") }
                            else { Text(title(choice)) }
                        }
                        .disabled(choice.resolved == nil)
                    }
                }
            }
            Divider()
            Button("New \(kind.rawValue) Token…") {
                kind.newTokenAction(startingWith: currentValue.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))
            }
            Button("Manage Tokens…") {
                UserDefaults.standard.set(false, forKey: AppPreferences.showDesignLanguageCode)
                UserDefaults.standard.set("designLanguage", forKey: AppPreferences.requestedSettingsPane)
                openWindow(id: SettingsWindow.sceneID)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(state == .unlinked ? EXPColor.textTertiary : EXPColor.accent)
        .help(summary)
        .accessibilityLabel(summary)
    }
}

/// The token name shown beside or beneath linked fields.
struct EXPTokenChip: View {
    let text: String
    var missing = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: missing ? "exclamationmark.triangle" : "link")
                .font(.system(size: 8, weight: .semibold))
                .accessibilityHidden(true)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: EXPType.micro))
        .padding(.horizontal, 5).padding(.vertical, 2)
        .foregroundStyle(missing ? EXPColor.textPrimary : EXPColor.accent)
        .background(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(missing ? EXPColor.textTertiary : EXPColor.accent.opacity(0.6),
                          style: StrokeStyle(lineWidth: 1, dash: missing ? [3, 2] : [])))
        .help(text)
    }
}

/// Small native vector glyphs: the filled region is the result of each operation.
/// No bundled font, bitmap or third-party icon license is needed.
struct EXPPathfinderIcon: View {
    enum Operation { case unite, subtract, intersect, exclude }
    let operation: Operation

    private let a = CGRect(x: 2, y: 2, width: 11, height: 11)
    private let b = CGRect(x: 8, y: 8, width: 11, height: 11)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 21, y: size.height / 21)
            var outlines = Path(); outlines.addRect(a); outlines.addRect(b)
            context.stroke(outlines, with: .color(EXPColor.textSecondary.opacity(0.5)), lineWidth: 1)
            var result = Path()
            switch operation {
            case .unite:
                result.addLines([CGPoint(x: 2, y: 2), CGPoint(x: 13, y: 2), CGPoint(x: 13, y: 8),
                                 CGPoint(x: 19, y: 8), CGPoint(x: 19, y: 19), CGPoint(x: 8, y: 19),
                                 CGPoint(x: 8, y: 13), CGPoint(x: 2, y: 13)])
                result.closeSubpath()
            case .subtract:
                result.addLines([CGPoint(x: 2, y: 2), CGPoint(x: 13, y: 2), CGPoint(x: 13, y: 8),
                                 CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 13), CGPoint(x: 2, y: 13)])
                result.closeSubpath()
            case .intersect: result.addRect(a.intersection(b))
            case .exclude: result.addRect(a); result.addRect(b)
            }
            context.fill(result, with: .foreground, style: FillStyle(eoFill: operation == .exclude))
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

/// Presentation-only notes in Properties. Critical warnings and control labels
/// remain unconditional; hiding these notes never hides the controls themselves.
struct EXPPanelHelp: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if EXPInterfaceAccessibility.shared.showGuidance {
            Text(text).font(.expLabel).foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

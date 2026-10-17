import SwiftUI

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

    var body: some View {
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
            .accessibilityLabel(name)
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

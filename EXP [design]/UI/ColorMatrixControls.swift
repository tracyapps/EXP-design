import SwiftUI

/// Narrow-inspector editor; exact values remain editable beyond the slider range.
struct ColorMatrixControls: View {
    let effect: Effect
    var change: (Effect) -> Void
    var gesture: (Bool) -> Void
    @State private var advanced = false

    private func update(_ body: (inout Effect) -> Void) {
        var next = effect; body(&next)
        guard next.colorMatrix != effect.colorMatrix || next.duotone != effect.duotone else { return }
        change(next)
    }
    private var mode: Binding<Bool> {
        Binding(get: { effect.duotone != nil }, set: { value in
            update {
                $0.colorMatrix = effect.effectiveMatrix
                $0.duotone = value ? DuotoneSettings() : nil
            }
        })
    }
    private func swatch(_ shadows: Bool) -> Binding<RGBAColor> {
        Binding(get: { let d = effect.duotone ?? DuotoneSettings(); return shadows ? d.shadows : d.highlights }, set: { value in
            update {
                var d = $0.duotone ?? DuotoneSettings()
                if shadows { d.shadows = value } else { d.highlights = value }
                $0.duotone = d; $0.colorMatrix = d.matrix
            }
        })
    }
    private var strength: Binding<Double> {
        Binding(get: { effect.duotone?.strength ?? 1 }, set: { value in
            guard value.isFinite else { return }
            update {
                var d = $0.duotone ?? DuotoneSettings(); d.strength = min(1, max(0, value))
                $0.duotone = d; $0.colorMatrix = d.matrix
            }
        })
    }
    private func coefficient(_ index: Int) -> Binding<Double> {
        Binding(get: { effect.effectiveMatrix.values[index] }, set: { value in
            guard let m = try? effect.effectiveMatrix.setting(index, to: value) else { return }
            update { $0.duotone = nil; $0.colorMatrix = m }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Color treatment", selection: mode) {
                Text("Duotone").tag(true); Text("Matrix").tag(false)
            }
            .accessibilityLabel("Color treatment")
            .help(Text(verbatim: "Color Matrix is applied after other effects, before opacity and blending. Preview is limited to 4 MP; PNG/PDF filter regions above 16 MP cannot export. SVG retains exact values."))
            if effect.duotone != nil {
                ColorWell(label: "Shadows", color: swatch(true), supportsOpacity: false, onEditingChanged: gesture)
                ColorWell(label: "Highlights", color: swatch(false), supportsOpacity: false, onEditingChanged: gesture)
                Text("Strength").font(.caption).foregroundStyle(EXPColor.textSecondary)
                HStack {
                    Slider(value: strength, in: 0...1, onEditingChanged: gesture)
                        .accessibilityLabel("Duotone strength")
                    TextField("Duotone strength", value: strength, format: .number.precision(.fractionLength(0...3)))
                        .textFieldStyle(.exp).frame(minWidth: 58, maxWidth: 80)
                        .numericStepping(strength, min: 0, max: 1, step: 0.01)
                        .accessibilityLabel("Duotone strength")
                }
            }
            Button("Reset to Identity") { sendCanvasAction("resetColorMatrixAction:", from: effect.id as NSUUID) }
                .buttonStyle(.bordered)
            DisclosureGroup("Advanced: 20 coefficients", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Working color space", selection: Binding(get: { effect.effectiveMatrix.workingSpace }, set: { value in
                        update { var m = $0.effectiveMatrix; m.workingSpace = value; $0.duotone = nil; $0.colorMatrix = m }
                    })) {
                        Text("sRGB").tag(ColorMatrix.WorkingSpace.sRGB)
                        Text("Linear RGB").tag(ColorMatrix.WorkingSpace.linearRGB)
                    }
                    Text("Editing a coefficient switches to Matrix. Sliders cover −2 to 2; numeric fields keep exact values beyond that range.")
                        .font(.caption).foregroundStyle(EXPColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(0..<4, id: \.self) { row in
                        Text(["Red", "Green", "Blue", "Alpha"][row] + " output")
                            .font(.caption.weight(.semibold))
                        ForEach(0..<5, id: \.self) { col in
                            let label = ["Red", "Green", "Blue", "Alpha"][row] + " output " + (col == 4 ? "offset" : "from " + ["Red", "Green", "Blue", "Alpha"][col])
                            let exact = coefficient(row * 5 + col)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label).font(.caption).foregroundStyle(EXPColor.textSecondary)
                                    .accessibilityHidden(true)
                                HStack(spacing: 6) {
                                    Slider(value: Binding(get: { min(2, max(-2, exact.wrappedValue)) }, set: { exact.wrappedValue = $0 }),
                                           in: -2...2, onEditingChanged: gesture)
                                        .accessibilityLabel(Text(label))
                                    TextField(label, value: exact, format: .number.precision(.significantDigits(1...17)))
                                        .textFieldStyle(.exp).frame(minWidth: 64, maxWidth: 100)
                                        .multilineTextAlignment(.trailing)
                                        .numericStepping(exact, step: 0.01)
                                        .accessibilityLabel(Text(label))
                                }
                            }
                        }
                    }
                }.padding(.top, 6)
            }
            if let message = effect.matrixValidationMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { gesture(false) }
    }
}

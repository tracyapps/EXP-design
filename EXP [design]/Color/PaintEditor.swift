//
//  PaintEditor.swift
//  EXP [design]
//
//  The fill editor: a swatch (`PaintWell`) that opens a popover for editing a
//  `Paint` — Solid / Linear / Radial. Solid reuses `ColorPopover`; gradients get
//  a stop bar (click to add, drag to move, select to recolor, delete) plus an
//  angle control for linear.
//

import SwiftUI

// MARK: - Swatch button

struct PaintWell: View {
    let label: String
    @Binding var paint: Paint
    var supportsOpacity: Bool = true

    @State private var showing = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.callout)
            Spacer(minLength: 8)
            Button { showing.toggle() } label: {
                PaintSwatch(paint: paint).frame(width: 40, height: 18)
            }
            .buttonStyle(.plain)
            .help("Edit \(label.lowercased())")
            .popover(isPresented: $showing, arrowEdge: .leading) {
                PaintEditor(paint: $paint, supportsOpacity: supportsOpacity)
                    .frame(width: 250)
                    .padding(12)
            }
        }
    }
}

struct PaintSwatch: View {
    let paint: Paint

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
        ZStack {
            Checkerboard().clipShape(shape)
            switch paint {
            case .solid(let c):
                shape.fill(c.swiftUI)
            case .gradient(let g):
                gradientView(g, shape: shape)
            }
        }
        .overlay(shape.strokeBorder(EXPColor.borderSoft))
        .contentShape(shape)
    }

    @ViewBuilder private func gradientView(_ g: GradientFill,
                                           shape: RoundedRectangle) -> some View {
        let stops = g.sortedStops.map { Gradient.Stop(color: $0.color.swiftUI, location: $0.position) }
        switch g.kind {
        case .linear:
            let a = g.angle * .pi / 180
            shape.fill(LinearGradient(
                stops: stops,
                startPoint: UnitPoint(x: 0.5 - cos(a) / 2, y: 0.5 - sin(a) / 2),
                endPoint: UnitPoint(x: 0.5 + cos(a) / 2, y: 0.5 + sin(a) / 2)))
        case .radial:
            shape.fill(RadialGradient(stops: stops, center: .center,
                                      startRadius: 0, endRadius: 22))
        }
    }
}

// MARK: - Editor

struct PaintEditor: View {
    @Binding var paint: Paint
    var supportsOpacity: Bool

    @State private var selectedStopID: UUID?

    private enum Mode: Int { case solid, linear, radial }
    private var mode: Mode {
        switch paint {
        case .solid: return .solid
        case .gradient(let g): return g.kind == .linear ? .linear : .radial
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: modeBinding) {
                Text("Solid").tag(Mode.solid)
                Text("Linear").tag(Mode.linear)
                Text("Radial").tag(Mode.radial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch paint {
            case .solid:
                ColorPopover(color: solidBinding, supportsOpacity: supportsOpacity)
            case .gradient:
                gradientEditor
            }
        }
        .onAppear {
            if selectedStopID == nil, case .gradient(let g) = paint { selectedStopID = g.stops.first?.id }
        }
    }

    // MARK: Solid

    private var solidBinding: Binding<RGBAColor> {
        Binding(get: { paint.representativeColor },
                set: { paint = .solid($0) })
    }

    // MARK: Gradient

    @ViewBuilder
    private var gradientEditor: some View {
        GradientBar(gradient: gradientBinding, selectedID: $selectedStopID)
            .frame(height: 26)

        // Selected-stop controls
        if let id = selectedStopID, let idx = gradientBinding.wrappedValue.stops.firstIndex(where: { $0.id == id }) {
            HStack(spacing: 8) {
                ColorWell(label: "Stop", color: stopColorBinding(idx), supportsOpacity: supportsOpacity)
                Button {
                    deleteStop(id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(gradientBinding.wrappedValue.stops.count <= 2)
                    .help("Delete stop")
            }
            HStack(spacing: 6) {
                Text("Pos").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: stopPositionBinding(idx), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 52).multilineTextAlignment(.trailing)
                Text("%").foregroundStyle(EXPColor.textSecondary)
                Spacer()
            }
        }

        if mode == .linear {
            HStack(spacing: 6) {
                Text("Angle").foregroundStyle(EXPColor.textSecondary).font(.callout)
                Slider(value: angleBinding, in: 0...360)
                TextField("", value: angleBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 48).multilineTextAlignment(.trailing)
                Text("°").foregroundStyle(EXPColor.textSecondary)
            }
        }
    }

    private var gradientBinding: Binding<GradientFill> {
        Binding(
            get: { paint.gradientValue ?? GradientFill() },
            set: { paint = .gradient($0) }
        )
    }

    private func stopColorBinding(_ i: Int) -> Binding<RGBAColor> {
        Binding(
            get: { gradientBinding.wrappedValue.stops[safe: i]?.color ?? .white },
            set: { c in var g = gradientBinding.wrappedValue; guard g.stops.indices.contains(i) else { return }
                g.stops[i].color = c; gradientBinding.wrappedValue = g }
        )
    }
    private func stopPositionBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { (gradientBinding.wrappedValue.stops[safe: i]?.position ?? 0) * 100 },
            set: { v in var g = gradientBinding.wrappedValue; guard g.stops.indices.contains(i) else { return }
                g.stops[i].position = min(1, max(0, v / 100)); gradientBinding.wrappedValue = g }
        )
    }
    private var angleBinding: Binding<Double> {
        Binding(get: { gradientBinding.wrappedValue.angle },
                set: { var g = gradientBinding.wrappedValue; g.angle = $0; gradientBinding.wrappedValue = g })
    }

    private func deleteStop(_ id: UUID) {
        var g = gradientBinding.wrappedValue
        guard g.stops.count > 2 else { return }
        g.stops.removeAll { $0.id == id }
        gradientBinding.wrappedValue = g
        selectedStopID = g.stops.first?.id
    }

    // MARK: Mode switching (converts the Paint)

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .solid:
                    paint = .solid(paint.representativeColor)
                case .linear, .radial:
                    var g = paint.gradientValue ?? seededGradient(from: paint.representativeColor)
                    g.kind = (newMode == .linear) ? .linear : .radial
                    paint = .gradient(g)
                    if selectedStopID == nil { selectedStopID = g.stops.first?.id }
                }
            }
        )
    }

    private func seededGradient(from c: RGBAColor) -> GradientFill {
        let lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        let other: RGBAColor = lum > 0.5 ? .black : .white
        return GradientFill(kind: .linear,
                            stops: [GradientStop(color: c, position: 0),
                                    GradientStop(color: other, position: 1)],
                            angle: 90)
    }
}

// MARK: - Gradient stop bar

private struct GradientBar: View {
    @Binding var gradient: GradientFill
    @Binding var selectedID: UUID?
    @State private var dragID: UUID?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: EXPMetric.radiusField)
                    .fill(LinearGradient(stops: swiftUIStops, startPoint: .leading, endPoint: .trailing))
                    .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusField)))
                    .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusField).strokeBorder(EXPColor.borderSoft))

                ForEach(gradient.stops) { stop in
                    marker(stop, at: stop.position * w)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let pos = clampD(Double(v.location.x / max(1, w)))
                        if dragID == nil {
                            if let near = nearestStop(to: pos, within: 0.05) { dragID = near }
                            else { dragID = addStop(at: pos) }
                            selectedID = dragID
                        }
                        setPosition(dragID!, pos)
                    }
                    .onEnded { _ in dragID = nil }
            )
        }
    }

    private func marker(_ stop: GradientStop, at x: CGFloat) -> some View {
        Circle()
            .fill(stop.color.swiftUI)
            .overlay(Circle().strokeBorder(selectedID == stop.id ? EXPColor.accent : .white, lineWidth: 2))
            .frame(width: 14, height: 14)
            .offset(x: x - 7, y: 6)
            .shadow(radius: 1)
    }

    private var swiftUIStops: [Gradient.Stop] {
        gradient.sortedStops.map { Gradient.Stop(color: $0.color.swiftUI, location: $0.position) }
    }

    private func nearestStop(to pos: Double, within tol: Double) -> UUID? {
        gradient.stops.min(by: { abs($0.position - pos) < abs($1.position - pos) })
            .flatMap { abs($0.position - pos) <= tol ? $0.id : nil }
    }

    @discardableResult
    private func addStop(at pos: Double) -> UUID {
        let color = interpolatedColor(at: pos)
        let stop = GradientStop(color: color, position: pos)
        gradient.stops.append(stop)
        return stop.id
    }

    private func setPosition(_ id: UUID, _ pos: Double) {
        guard let i = gradient.stops.firstIndex(where: { $0.id == id }) else { return }
        gradient.stops[i].position = pos
    }

    private func interpolatedColor(at pos: Double) -> RGBAColor {
        let s = gradient.sortedStops
        guard let first = s.first else { return .white }
        if pos <= first.position { return first.color }
        guard let last = s.last else { return first.color }
        if pos >= last.position { return last.color }
        for i in 1..<s.count where s[i].position >= pos {
            let a = s[i - 1], b = s[i]
            let t = (pos - a.position) / max(0.0001, b.position - a.position)
            return RGBAColor(r: a.color.r + (b.color.r - a.color.r) * t,
                             g: a.color.g + (b.color.g - a.color.g) * t,
                             b: a.color.b + (b.color.b - a.color.b) * t,
                             a: a.color.a + (b.color.a - a.color.a) * t)
        }
        return last.color
    }
}

private func clampD(_ v: Double) -> Double { min(1, max(0, v)) }

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

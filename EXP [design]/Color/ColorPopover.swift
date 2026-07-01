//
//  ColorPopover.swift
//  EXP [design]
//
//  A custom inline color picker shown in a popover anchored at each swatch (no
//  detached macOS color panel). Saturation–brightness field + hue/alpha sliders +
//  screen eyedropper, plus an editable code field that round-trips any of
//  HEX / RGB(A) / HSL / LCH / OKLCH with click-to-copy.
//
//  The model stays sRGB `RGBAColor`; OKLCH/LCH typed in are converted back to
//  sRGB (gamut-clamped) by ColorMath.
//

import SwiftUI
import AppKit

extension RGBAColor {
    /// sRGB SwiftUI Color (UI only; the model stays UI-free).
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - The swatch button that opens the picker

struct ColorWell: View {
    let label: String
    @Binding var color: RGBAColor
    var supportsOpacity: Bool = true

    @State private var showing = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.callout)
            Spacer(minLength: 8)
            Button { showing.toggle() } label: {
                SwatchView(color: color)
                    .frame(width: 40, height: 18)
            }
            .buttonStyle(.plain)
            .help("Edit \(label.lowercased())")
            .popover(isPresented: $showing, arrowEdge: .leading) {
                ColorPopover(color: $color, supportsOpacity: supportsOpacity)
                    .frame(width: 244)
                    .padding(12)
            }
        }
    }
}

/// A color chip over a checkerboard (so alpha reads), with a hairline border.
struct SwatchView: View {
    let color: RGBAColor
    var body: some View {
        RoundedRectangle(cornerRadius: EXPMetric.radiusDrop)
            .fill(color.swiftUI)
            .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusDrop)))
            .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusDrop).strokeBorder(EXPColor.borderSoft))
    }
}

// MARK: - Popover

struct ColorPopover: View {
    @Binding var color: RGBAColor
    var supportsOpacity: Bool

    @State private var h = 0.0     // 0…360
    @State private var s = 0.0     // 0…1
    @State private var b = 1.0     // 0…1
    @State private var a = 1.0
    @State private var format: ColorFormat = .hex
    @State private var code = ""
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 10) {
            SVField(hue: h, sat: $s, bri: $b, onEdit: pushColor)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))

            HueSlider(hue: $h, onEdit: pushColor).frame(height: 14)

            if supportsOpacity {
                AlphaSlider(hue: h, sat: s, bri: b, alpha: $a, onEdit: pushColor).frame(height: 14)
            }

            HStack(spacing: 6) {
                Picker("", selection: $format) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 84)
                .onChange(of: format) { _, _ in refreshCode() }

                TextField("", text: $code)
                    .textFieldStyle(.exp)
                    .font(.system(.callout, design: .monospaced))
                    .onSubmit(commitCode)

                Button(action: copyCode) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy \(format.rawValue)")
            }

            HStack {
                Button(action: sampleScreen) { Label("Pick", systemImage: "eyedropper") }
                    .buttonStyle(.borderless)
                    .help("Eyedropper")
                Spacer()
                Text(format == .oklch ? "OKLCH authoring" : " ")
                    .font(.caption2).foregroundStyle(EXPColor.textSecondary)
            }
        }
        .onAppear { loadFromColor(); installKeyMonitor() }
        .onDisappear(perform: removeKeyMonitor)
    }

    // MARK: Keyboard eyedropper

    /// While the popover is open, plain `i` triggers the screen eyedropper — even
    /// when the code field has focus. Safe to swallow there: a color code (hex /
    /// rgb / hsl / lch / oklch) never contains the letter `i`, so keyboard-first
    /// designers get an uninterrupted pick. ⌘/⌃/⌥+i are left for the system.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            if mods.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "i" {
                sampleScreen()
                return nil   // consume
            }
            return event
        }
    }
    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: state sync

    private func loadFromColor() {
        let (hh, ss, bb) = ColorMath.rgbToHSB(color.r, color.g, color.b)
        if ss != 0 { h = hh }            // keep hue stable on grays
        s = ss; b = bb; a = color.a
        refreshCode()
    }

    /// User moved a slider/field → write the model from HSB+alpha.
    private func pushColor() {
        let (r, g, bl) = ColorMath.hsbToRGB(h, s, b)
        color = RGBAColor(r: r, g: g, b: bl, a: supportsOpacity ? a : 1)
        refreshCode()
    }

    private func refreshCode() { code = ColorMath.string(color, format) }

    private func commitCode() {
        guard let c = ColorMath.parse(code, format, currentAlpha: a) else { refreshCode(); return }
        color = c
        loadFromColor()
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private func sampleScreen() {
        NSColorSampler().show { picked in
            guard let ns = picked?.usingColorSpace(.sRGB) else { return }
            color = RGBAColor(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                              b: Double(ns.blueComponent), a: supportsOpacity ? Double(ns.alphaComponent) : 1)
            loadFromColor()
        }
    }
}

// MARK: - Saturation / brightness field

private struct SVField: View {
    var hue: Double
    @Binding var sat: Double
    @Binding var bri: Double
    var onEdit: () -> Void

    private var hueColor: Color {
        let (r, g, b) = ColorMath.hsbToRGB(hue, 1, 1)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white, hueColor], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 3))
                    .frame(width: 12, height: 12)
                    .position(x: sat * geo.size.width, y: (1 - bri) * geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    sat = clamp(v.location.x / geo.size.width)
                    bri = clamp(1 - v.location.y / geo.size.height)
                    onEdit()
                }
            )
        }
    }
}

// MARK: - Hue slider

private struct HueSlider: View {
    @Binding var hue: Double
    var onEdit: () -> Void

    private let stops: [Color] = stride(from: 0.0, through: 360.0, by: 60.0).map {
        let (r, g, b) = ColorMath.hsbToRGB($0, 1, 1)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                .clipShape(Capsule())
                .overlay(thumb(in: geo.size))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { v in
                        hue = clamp(v.location.x / geo.size.width) * 360
                        onEdit()
                    }
                )
        }
    }

    private func thumb(in size: CGSize) -> some View {
        Circle().strokeBorder(.white, lineWidth: 2)
            .background(Circle().fill(Color(.sRGB, red: hsb(hue).0, green: hsb(hue).1, blue: hsb(hue).2)))
            .frame(width: 14, height: 14)
            .position(x: (hue / 360) * size.width, y: size.height / 2)
    }
    private func hsb(_ h: Double) -> (Double, Double, Double) { ColorMath.hsbToRGB(h, 1, 1) }
}

// MARK: - Alpha slider

private struct AlphaSlider: View {
    var hue: Double; var sat: Double; var bri: Double
    @Binding var alpha: Double
    var onEdit: () -> Void

    private var opaque: Color {
        let (r, g, b) = ColorMath.hsbToRGB(hue, sat, bri)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    var body: some View {
        GeometryReader { geo in
            Checkerboard()
                .overlay(LinearGradient(colors: [opaque.opacity(0), opaque], startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .overlay(
                    Circle().strokeBorder(.white, lineWidth: 2)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .frame(width: 14, height: 14)
                        .position(x: alpha * geo.size.width, y: geo.size.height / 2)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { v in
                        alpha = clamp(v.location.x / geo.size.width)
                        onEdit()
                    }
                )
        }
    }
}

// MARK: - Checkerboard (alpha backdrop)

struct Checkerboard: View {
    var square: CGFloat = 5
    var body: some View {
        Canvas { ctx, size in
            for y in stride(from: 0, to: size.height, by: square) {
                for x in stride(from: 0, to: size.width, by: square) {
                    let on = (Int(x / square) + Int(y / square)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: square, height: square)),
                             with: .color(on ? .gray.opacity(0.3) : .white))
                }
            }
        }
    }
}

private func clamp(_ v: CGFloat) -> Double { Double(min(1, max(0, v))) }

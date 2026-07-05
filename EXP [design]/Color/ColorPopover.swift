//
//  ColorPopover.swift
//  EXP [design]
//
//  A custom inline color picker shown in a popover anchored at each swatch (no
//  detached macOS color panel). It is MODE-AWARE (Phase 18b): pick the authoring
//  model that matches how you think — HSB (the 2-D field), HSL, or OKLCH — and the
//  controls change to that model's axes, not just a text field. A screen eyedropper
//  and a round-tripping code field (HEX / RGB / HSL / LCH / OKLCH) are always there,
//  and a WCAG contrast strip (Phase 18c) shows how the color reads on white/black.
//
//  The model stays sRGB `RGBAColor`. OKLCH is authored in a wider space and folded
//  back to sRGB; when a value can't fit the sRGB gamut the picker SAYS SO (clamped)
//  rather than lying about it.
//

import SwiftUI
import AppKit

extension RGBAColor {
    /// sRGB SwiftUI Color (UI only; the model stays UI-free).
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    /// The same color forced opaque — for previews where alpha would mislead.
    var opaqueSwiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
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

/// Which color model the picker's controls author in. The code field can still
/// read/write any `ColorFormat`; this only drives the interactive controls.
enum PickerModel: String, CaseIterable, Identifiable {
    case hsb = "HSB", hsl = "HSL", oklch = "OKLCH"
    var id: String { rawValue }
}

struct ColorPopover: View {
    @Binding var color: RGBAColor
    var supportsOpacity: Bool

    // Authoring model + its per-model channel state. Each set is (re)loaded from
    // `color` on appear and on model switch, so no two representations drift.
    @State private var pmodel: PickerModel = .hsb

    // HSB (the 2-D saturation/brightness field + hue slider)
    @State private var h = 0.0     // 0…360
    @State private var s = 0.0     // 0…1
    @State private var b = 1.0     // 0…1

    // HSL (three axis sliders; S/L kept as 0…100 for readable numbers)
    @State private var hslH = 0.0
    @State private var hslS = 0.0
    @State private var hslL = 0.0

    // OKLCH (perceptual; L 0…1, C ~0…0.4, H 0…360)
    @State private var okL = 0.0
    @State private var okC = 0.0
    @State private var okH = 0.0
    @State private var oklchInGamut = true

    @State private var a = 1.0
    @State private var format: ColorFormat = .hex
    @State private var code = ""
    @State private var keyMonitor: Any?
    @State private var dlMatch: DesignAsset?

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $pmodel) {
                ForEach(PickerModel.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: pmodel) { _, _ in loadFromColor() }

            modelControls

            if supportsOpacity {
                let hsb = ColorMath.rgbToHSB(color.r, color.g, color.b)
                AlphaSlider(hue: hsb.h, sat: hsb.s, bri: hsb.v, alpha: $a, onEdit: pushAlpha)
                    .frame(height: 14)
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

            ContrastStrip(color: color)

            HStack(spacing: 6) {
                Button(action: sampleScreen) { Label("Pick", systemImage: "eyedropper") }
                    .buttonStyle(.borderless)
                    .help("Eyedropper")
                Spacer(minLength: 6)
                designLanguageLink
            }
        }
        .onAppear { loadFromColor(); installKeyMonitor(); refreshDLMatch() }
        .onChange(of: color) { _, _ in refreshDLMatch() }
        .onDisappear(perform: removeKeyMonitor)
    }

    // MARK: Mode-specific controls

    @ViewBuilder private var modelControls: some View {
        switch pmodel {
        case .hsb:
            SVField(hue: h, sat: $s, bri: $b, onEdit: pushHSB)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
            HueSlider(hue: $h, onEdit: pushHSB).frame(height: 14)

        case .hsl:
            VStack(spacing: 8) {
                ChannelSlider(label: "H", value: $hslH, range: 0...360, suffix: "°", onEdit: pushHSL)
                ChannelSlider(label: "S", value: $hslS, range: 0...100, suffix: "%", onEdit: pushHSL)
                ChannelSlider(label: "L", value: $hslL, range: 0...100, suffix: "%", onEdit: pushHSL)
            }
            .padding(.vertical, 2)

        case .oklch:
            VStack(spacing: 8) {
                ChannelSlider(label: "L", value: $okL, range: 0...1,   decimals: 3, onEdit: pushOKLCH)
                ChannelSlider(label: "C", value: $okC, range: 0...0.4, decimals: 3, onEdit: pushOKLCH)
                ChannelSlider(label: "H", value: $okH, range: 0...360, suffix: "°", onEdit: pushOKLCH)
                HStack(spacing: 4) {
                    Image(systemName: oklchInGamut ? "checkmark.circle" : "exclamationmark.triangle.fill")
                    Text(oklchInGamut ? "In sRGB gamut" : "Outside sRGB — clamped to fit")
                }
                .font(.caption2)
                .foregroundStyle(oklchInGamut ? EXPColor.textSecondary : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
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

    /// Recompute every model's channels from the current `color`. Hue is preserved
    /// on achromatic colors (a gray has no meaningful hue) so sliding lightness on
    /// a gray doesn't snap the hue back to red.
    private func loadFromColor() {
        let (hh, ss, bb) = ColorMath.rgbToHSB(color.r, color.g, color.b)
        if ss > 0.0001 { h = hh }
        s = ss; b = bb

        let (lh, ls, ll) = ColorMath.rgbToHSL(color.r, color.g, color.b)
        if ls > 0.0001 { hslH = lh }
        hslS = ls * 100; hslL = ll * 100

        let (ol, oc, oh) = ColorMath.rgbToOKLCH(color.r, color.g, color.b)
        if oc > 0.0001 { okH = oh }
        okL = ol; okC = oc
        oklchInGamut = true          // came from an sRGB color, so it fits

        a = color.a
        refreshCode()
    }

    private func pushHSB() {
        let (r, g, bl) = ColorMath.hsbToRGB(h, s, b)
        color = RGBAColor(r: r, g: g, b: bl, a: supportsOpacity ? a : 1)
        refreshCode()
    }

    private func pushHSL() {
        let (r, g, bl) = ColorMath.hslToRGB(hslH, hslS / 100, hslL / 100)
        color = RGBAColor(r: r, g: g, b: bl, a: supportsOpacity ? a : 1)
        refreshCode()
    }

    private func pushOKLCH() {
        let (rgb, inGamut) = ColorMath.oklchToRGBGamut(okL, okC, okH)
        oklchInGamut = inGamut
        color = RGBAColor(r: rgb.0, g: rgb.1, b: rgb.2, a: supportsOpacity ? a : 1)
        refreshCode()
    }

    private func pushAlpha() {
        color = RGBAColor(r: color.r, g: color.g, b: color.b, a: supportsOpacity ? a : 1)
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

    // MARK: Design Language link (Phase 18 refinement)

    /// Bottom-right of the picker: if the current color is saved in the frontmost
    /// document's design language, show its name + category; otherwise offer to add
    /// it. Reads the active document via PanelHub, so no color well needs plumbing.
    @ViewBuilder private var designLanguageLink: some View {
        if let m = dlMatch {
            HStack(spacing: 5) {
                SwatchView(color: color).frame(width: 18, height: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.name.isEmpty ? "In library" : m.name)
                        .font(.caption2).foregroundStyle(EXPColor.textSecondary).lineLimit(1)
                    let cat = PanelHub.shared.activeDocument?.model.designLanguage.categoryLabel(for: m) ?? ""
                    if !cat.isEmpty {
                        Text(cat).font(.system(size: EXPType.micro))
                            .foregroundStyle(EXPColor.textTertiary).lineLimit(1)
                    }
                }
            }
            .help("This color is saved in your design language")
        } else if PanelHub.shared.activeDocument != nil {
            Button(action: addToDesignLanguage) { Label("Save", systemImage: "plus") }
                .buttonStyle(.borderless)
                .help("Add this color to your design language")
        }
    }

    private func refreshDLMatch() {
        dlMatch = PanelHub.shared.activeDocument?.model.designLanguage.firstAsset(matching: .solid(color))
    }

    private func addToDesignLanguage() {
        guard let doc = PanelHub.shared.activeDocument else { return }
        var model = doc.model
        let paint = Paint.solid(color)
        model.designLanguage.save(paint, provenance: "picker")
        model.designLanguage.remember(paint)
        doc.setModel(model, undoManager: PanelHub.shared.activeUndo, actionName: "Save Color")
        refreshDLMatch()
    }
}

// MARK: - Channel slider (accessible; used by HSL + OKLCH modes)

/// One labeled axis slider with a numeric readout. Uses the native `Slider` on
/// purpose — it's keyboard- and VoiceOver-accessible out of the box. `onEdit` runs
/// only on user interaction (via the setter binding), never when the value is
/// reloaded programmatically, so the modes don't fight each other.
private struct ChannelSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix: String = ""
    var decimals: Int = 0
    var onEdit: () -> Void

    private var readout: String {
        let v = decimals == 0 ? String(Int(value.rounded())) : String(format: "%.\(decimals)f", value)
        return v + suffix
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(EXPColor.textSecondary)
                .frame(width: 12, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { value = $0; onEdit() }), in: range)
                .controlSize(.small)
                .accessibilityLabel(label)
            Text(readout)
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(EXPColor.textSecondary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

// MARK: - Contrast strip (WCAG readout, Phase 18c)

/// Shows how the current color reads as text on white and on black: the WCAG
/// contrast ratio plus the best level it reaches for normal text. A fast, honest
/// nudge toward accessible choices right where the color is picked.
private struct ContrastStrip: View {
    let color: RGBAColor

    var body: some View {
        HStack(spacing: 6) {
            chip(background: .white, label: "on white")
            chip(background: .black, label: "on black")
        }
    }

    private func chip(background: RGBAColor, label: String) -> some View {
        let report = ContrastMath.report(foreground: color, background: background)
        let level = report.level(for: .normalText)
        return HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(background.opaqueSwiftUI)
                Text("A").font(.system(size: 10, weight: .bold)).foregroundStyle(color.opaqueSwiftUI)
            }
            .frame(width: 18, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(EXPColor.borderSoft))

            VStack(alignment: .leading, spacing: 0) {
                Text(report.ratioLabel)
                    .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                Text(level.rawValue)
                    .font(.caption2)
                    .foregroundStyle(level == .fail ? Color.orange : EXPColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(label): \(report.ratioLabel) — normal-text \(level.rawValue)")
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

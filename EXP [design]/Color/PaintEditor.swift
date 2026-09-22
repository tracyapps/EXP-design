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
    /// The owning object's size lets an angle edit preserve the physical length
    /// of an explicitly placed gradient line on non-square objects.
    var gradientSize: CGSize? = nil
    /// Shared with the canvas when this PaintWell edits the selected object.
    var selectedGradientStopID: Binding<UUID?>? = nil

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
                PaintEditor(paint: $paint, supportsOpacity: supportsOpacity,
                            gradientSize: gradientSize,
                            selectedGradientStopID: selectedGradientStopID)
                    .frame(width: 250)
                    .padding(12)
                    .expTransientWindowLevel()
            }
        }
    }
}

/// Renders pattern tiles small, for chrome that shows a `Paint` without owning a
/// document — swatches above all (FEAT-065a).
///
/// Injected through the SwiftUI environment rather than threaded as a parameter:
/// `PaintSwatch(paint:)` has eight call sites across the design-language panel,
/// its settings, its transfer sheet and the paint editor, and most sit inside
/// views that have no business knowing about a document. A default that resolves
/// nothing means a swatch with no provider still paints the fallback colour
/// instead of breaking.
@MainActor
final class PatternPreviewStore {
    /// Shared. Safe because pattern ids are freshly minted UUIDs, so two open
    /// documents cannot collide on one, and every entry re-checks the generation
    /// it was built at.
    static let shared = PatternPreviewStore()

    private var images: [UUID: (generation: Int, image: CGImage)] = [:]
    /// Longest edge of a preview tile, in pixels. Small on purpose: this is a
    /// swatch, and rasterising is cheap enough at this size that a cache miss
    /// during a drag (when `resolveGeneration` bumps every tick) does not matter.
    private let previewPixels: CGFloat = 96

    func image(for ref: PatternRef, document: ExpDocument) -> CGImage? {
        let generation = document.resolveGeneration
        if let hit = images[ref.patternID], hit.generation == generation { return hit.image }
        guard let source = document.model.pattern(for: ref.patternID) else { return nil }
        // FEAT-064. An objectBoundingBox tile has no single size — it is a
        // fraction of whatever shape fills with it. A swatch has no shape, so it
        // renders against a NOMINAL one (square, preview-sized): the motif shows
        // at a plausible scale instead of rasterising at the raw fraction (a
        // 0.25-unit "tile" that would come out a single pixel). The store's key
        // stays the pattern id because the nominal shape is constant.
        var rasterSource = source
        if source.units == .objectBoundingBox {
            let nominal = CGSize(width: 96, height: 96)
            rasterSource.tileSize = CGSize(width: max(1, source.tileSize.width * nominal.width),
                                           height: max(1, source.tileSize.height * nominal.height))
        }
        let longest = max(rasterSource.tileSize.width, rasterSource.tileSize.height)
        guard longest > 0 else { return nil }
        // The SAME rasteriser the canvas and every export path uses, so a swatch
        // can never show something the artwork does not.
        guard let image = ExportRenderView.patternTile(rasterSource, document: document.model,
                                                       scale: max(0.02, previewPixels / longest))
        else { return nil }
        images[ref.patternID] = (generation, image)
        return image
    }
}

/// The document's pattern tiles, for chrome that shows or CHOOSES a pattern
/// without owning a document.
///
/// Carries the list as well as the preview image because FEAT-065b needs both:
/// the paint editor has to offer every available pattern, not just render the one
/// already applied.
struct PatternLibrary {
    var sources: () -> [PatternSource]
    var image: (PatternRef) -> CGImage?

    static let empty = PatternLibrary(sources: { [] }, image: { _ in nil })
}

private struct PatternLibraryKey: EnvironmentKey {
    static let defaultValue = PatternLibrary.empty
}

extension EnvironmentValues {
    var patternLibrary: PatternLibrary {
        get { self[PatternLibraryKey.self] }
        set { self[PatternLibraryKey.self] = newValue }
    }
}

extension View {
    /// Provide the pattern library — previews and the list — below this point.
    func expPatternPreviews(_ document: ExpDocument) -> some View {
        environment(\.patternLibrary, PatternLibrary(
            sources: { document.model.patterns },
            image: { ref in PatternPreviewStore.shared.image(for: ref, document: document) }))
    }
}

struct PaintSwatch: View {
    let paint: Paint
    @Environment(\.patternLibrary) private var patternLibrary

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
        ZStack {
            Checkerboard().clipShape(shape)
            switch paint {
            case .solid(let c):
                shape.fill(c.swiftUI)
            case .gradient(let g):
                gradientView(g, shape: shape)
            case .pattern(let ref):
                // FEAT-065a. Tile the real artwork so a pattern fill is
                // recognisable at swatch size — this used to paint the flat
                // fallback, which made a pattern indistinguishable from a solid
                // until you opened the paint editor.
                if let tile = patternLibrary.image(ref) {
                    GeometryReader { proxy in
                        // Draw the tile at the swatch's HEIGHT and let it repeat
                        // across the width, so a wide swatch shows the motif
                        // repeating rather than one stretched, unreadable copy.
                        let side = max(6, proxy.size.height)
                        Image(decorative: tile, scale: max(0.01, CGFloat(tile.height) / side))
                            .resizable(resizingMode: .tile)
                    }
                    .clipShape(shape)
                    .accessibilityLabel("Pattern fill")
                } else {
                    // No resolver, or a reference with no tile behind it: the
                    // declared fallback, which is what every renderer paints for
                    // that case too.
                    shape.fill(ref.fallback.swiftUI)
                }
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
    var gradientSize: CGSize? = nil
    var selectedGradientStopID: Binding<UUID?>? = nil

    @State private var localSelectedStopID: UUID?
    @Environment(\.patternLibrary) private var patternLibrary

    /// FEAT-065b. True once Pattern is chosen but no tile has been picked yet.
    ///
    /// Choosing the mode must NOT change the paint on its own: a `PatternRef`
    /// needs a real tile to point at, and minting a dangling one would show the
    /// user a broken fill they never asked for. So the segment selects, the picker
    /// appears, and the fill changes when a tile is actually chosen.
    @State private var choosingPattern = false

    private enum Mode: Int { case solid, linear, radial, pattern }
    private var mode: Mode {
        if choosingPattern, !paint.isPattern { return .pattern }
        switch paint {
        case .solid: return .solid
        case .gradient(let g): return g.kind == .linear ? .linear : .radial
        case .pattern: return .pattern
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: modeBinding) {
                Text("Solid").tag(Mode.solid)
                Text("Linear").tag(Mode.linear)
                Text("Radial").tag(Mode.radial)
                // FEAT-065b. ALWAYS present. It used to appear only when the fill
                // already was a pattern — correct while there was no way to choose
                // one, but the moment there is a library to pick from, a tab that
                // comes and goes reads as a bug rather than a rule. Owner: keep the
                // fill tabs consistent on every element.
                Text("Pattern").tag(Mode.pattern)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .solid:
                ColorPopover(color: solidBinding, supportsOpacity: supportsOpacity)
            case .linear, .radial:
                gradientEditor
            case .pattern:
                patternEditor
            }
        }
        .onAppear { validateSelectedStop() }
        .onChange(of: paint) { _, _ in validateSelectedStop() }
    }

    // MARK: Solid

    private var solidBinding: Binding<RGBAColor> {
        Binding(get: { paint.representativeColor },
                set: { paint = .solid($0) })
    }

    // MARK: Gradient

    @ViewBuilder
    private var gradientEditor: some View {
        GradientBar(gradient: gradientBinding, selectedID: activeSelectedStopID)
            .frame(height: 26)

        // Selected-stop controls
        if let id = activeSelectedStopID.wrappedValue,
           let idx = gradientBinding.wrappedValue.stops.firstIndex(where: { $0.id == id }) {
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
                    .numericStepping(stopPositionBinding(idx), min: 0, max: 100)
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
                    // No min/max on purpose: clamping would stop the arrows dead at
                    // 0 and 360. Unclamped, stepping past either end falls through
                    // to the wrapping setter below and comes out the other side.
                    .numericStepping(angleBinding)
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

    private var activeSelectedStopID: Binding<UUID?> {
        Binding(
            get: { selectedGradientStopID?.wrappedValue ?? localSelectedStopID },
            set: { value in
                if let selectedGradientStopID {
                    selectedGradientStopID.wrappedValue = value
                } else {
                    localSelectedStopID = value
                }
            }
        )
    }

    private func validateSelectedStop() {
        guard case .gradient(let gradient) = paint else {
            activeSelectedStopID.wrappedValue = nil
            return
        }
        let selection = activeSelectedStopID.wrappedValue
        if selection == nil || !gradient.stops.contains(where: { $0.id == selection }) {
            activeSelectedStopID.wrappedValue = gradient.sortedStops.first?.id
        }
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
    /// Angle is kept in 0..<360, wrapping rather than clamping, so:
    ///  · typing -45 stores 315 instead of a value the 0...360 slider can't show
    ///  · typing 400 stores 40
    ///  · arrow-stepping down from 0 wraps to 359 instead of stopping
    /// The GETTER wraps too, so a legacy or imported gradient holding a negative
    /// angle displays correctly without rewriting the document to fix it.
    private var angleBinding: Binding<Double> {
        Binding(
            get: {
                let a = gradientBinding.wrappedValue.angle.truncatingRemainder(dividingBy: 360)
                return a < 0 ? a + 360 : a
            },
            set: { v in
                var g = gradientBinding.wrappedValue
                let size = gradientSize ?? CGSize(width: 1, height: 1)
                g = g.settingAngle(v, in: CGRect(origin: .zero, size: size))
                gradientBinding.wrappedValue = g
            }
        )
    }

    private func deleteStop(_ id: UUID) {
        var g = gradientBinding.wrappedValue
        guard g.stops.count > 2 else { return }
        g.stops.removeAll { $0.id == id }
        gradientBinding.wrappedValue = g
        activeSelectedStopID.wrappedValue = g.sortedStops.first?.id
    }

    // MARK: Mode switching (converts the Paint)

    // MARK: Pattern anchoring (FEAT-064)

    /// Anchoring is deliberately NOT a paint property: the tile is shared by
    /// every layer painted with it, so they all re-anchor together. The control
    /// sits beside the pattern's own Edit button and says its scope, rather
    /// than hiding a document-level change inside a per-layer fill picker. It
    /// routes through the canvas action (the pattern id rides in
    /// `representedObject`), so the inspector, the pattern editor header and
    /// the context menu run ONE implementation with one undo name.
    @ViewBuilder private var anchoringControl: some View {
        if let id = paint.patternValue?.patternID,
           patternLibrary.sources().contains(where: { $0.id == id }) {
            HStack(spacing: 6) {
                Text("Anchor").foregroundStyle(EXPColor.textSecondary).font(.callout)
                Picker("Anchor", selection: anchoringBinding) {
                    Text("Document").tag(PatternUnits.userSpaceOnUse)
                    Text("Shape").tag(PatternUnits.objectBoundingBox)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                .accessibilityLabel("Pattern anchoring")
                .accessibilityHint("Anchoring applies to every layer using this pattern")
            }
        }
    }

    private var anchoringBinding: Binding<PatternUnits> {
        Binding(
            get: {
                guard let id = paint.patternValue?.patternID else { return .userSpaceOnUse }
                return patternLibrary.sources().first { $0.id == id }?.units ?? .userSpaceOnUse
            },
            set: { units in
                guard let id = paint.patternValue?.patternID else { return }
                let selector = Selector((units == .objectBoundingBox
                    ? "setPatternUnitsShapeAction:" : "setPatternUnitsDocumentAction:"))
                let item = NSMenuItem(title: "", action: selector, keyEquivalent: "")
                item.representedObject = id
                NSApp.sendAction(selector, to: nil, from: item)
            })
    }

    // MARK: Pattern (FEAT-065b)

    private let patternGrid = [GridItem(.adaptive(minimum: 46, maximum: 70), spacing: 6)]

    @ViewBuilder private var patternEditor: some View {
        let available = patternLibrary.sources()
        VStack(alignment: .leading, spacing: 8) {
            if available.isEmpty {
                // The tab is still here — consistency was the point — but it says
                // why it is empty and how to fill it, rather than showing a dead
                // control that reads as broken.
                Text("No patterns in this document yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Placing an SVG that uses a pattern fill adds its tiles to the Patterns panel.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: patternGrid, spacing: 6) {
                    ForEach(available) { source in
                        let isCurrent = paint.patternValue?.patternID == source.id
                        PaintSwatch(paint: .pattern(source.reference))
                            .frame(height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: EXPMetric.radiusRow,
                                                 style: .continuous)
                                    .strokeBorder(EXPColor.accent, lineWidth: isCurrent ? 2 : 0)
                            )
                            .onTapGesture { paint = .pattern(source.reference) }
                            .help(source.name)
                            .accessibilityLabel(source.name)
                            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                            .accessibilityHint("Fill with this pattern")
                    }
                }
                if paint.isPattern {
                    Button("Edit Pattern…") {
                        NSApp.sendAction(Selector(("editPatternAction:")), to: nil, from: nil)
                    }
                    .accessibilityLabel("Edit this pattern's tile")
                    anchoringControl
                    Text("Edits and anchoring apply everywhere this pattern is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Choose a pattern to fill with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .solid:
                    choosingPattern = false
                    paint = .solid(paint.representativeColor)
                    activeSelectedStopID.wrappedValue = nil
                case .linear, .radial:
                    choosingPattern = false
                    var g = paint.gradientValue ?? seededGradient(from: paint.representativeColor)
                    g.kind = (newMode == .linear) ? .linear : .radial
                    paint = .gradient(g)
                    validateSelectedStop()
                case .pattern:
                    // FEAT-065b. Show the picker; do NOT touch the paint yet. A
                    // `PatternRef` must point at a real tile, so the fill changes
                    // only once one is chosen — and if the user switches back to
                    // Solid without choosing, their original fill is untouched.
                    choosingPattern = true
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
    /// Where the grab landed relative to the stop's own position, so a stop being
    /// dragged does not teleport its centre under the cursor on the first tick.
    @State private var grabOffset: Double = 0

    /// Marker diameter. The visual size; the GRAB radius is deliberately larger.
    private static let markerSize: CGFloat = 14
    /// Half of a 24pt target. The marker reads as 14pt but is grabbable at 24pt,
    /// which is what WCAG 2.2 §2.5.8 Target Size (Minimum) asks for and costs
    /// nothing visually. BUG-026.
    private static let grabRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Inset the usable track by the marker radius so a stop at position 0
            // or 1 sits FULLY inside the bar.
            //
            // BUG-026 root cause: markers were centred at `position * w` and offset
            // by -7, so the 0.0 and 1.0 stops — which every gradient has by default —
            // hung half outside the bar. `.contentShape(Rectangle())` limits the
            // gesture to the bar's own rect, so that overhanging half was VISIBLE BUT
            // NOT CLICKABLE. Clicking the outer half of an end stop did nothing;
            // clicking slightly inward worked. Exactly the owner's report: "the
            // gradient points seem to need to be active slightly off-centre of the
            // actual circle."
            let r = Self.markerSize / 2
            let track = max(1, w - r * 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: EXPMetric.radiusField)
                    .fill(LinearGradient(stops: swiftUIStops, startPoint: .leading, endPoint: .trailing))
                    .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusField)))
                    .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusField).strokeBorder(EXPColor.borderSoft))

                ForEach(gradient.stops) { stop in
                    marker(stop, at: r + CGFloat(stop.position) * track)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let pos = clampD(Double((v.location.x - r) / track))
                        if dragID == nil {
                            // Tolerance in POINTS, converted through the track —
                            // it was a flat 0.05 of the bar's width, so how easy a
                            // stop was to hit changed with the panel width.
                            if let near = nearestStop(to: pos, within: Double(Self.grabRadius / track)) {
                                dragID = near
                                grabOffset = (gradient.stops.first { $0.id == near }?.position ?? pos) - pos
                            } else {
                                dragID = addStop(at: pos)
                                grabOffset = 0
                            }
                            selectedID = dragID
                        }
                        setPosition(dragID!, clampD(pos + grabOffset))
                    }
                    .onEnded { _ in dragID = nil; grabOffset = 0 }
            )
        }
    }

    private func marker(_ stop: GradientStop, at x: CGFloat) -> some View {
        Circle()
            .fill(stop.color.swiftUI)
            .overlay(Circle().strokeBorder(selectedID == stop.id ? EXPColor.accent : .white, lineWidth: 2))
            .frame(width: Self.markerSize, height: Self.markerSize)
            .offset(x: x - Self.markerSize / 2, y: 6)
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

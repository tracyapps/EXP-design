//
//  FontFamilyPicker.swift
//  EXP [design]
//
//  FEAT-008(a). A font list that OPENS ON THE FONT YOU ARE USING.
//
//  The inspector previously used a `Menu` of `Button`s, which dumps you at the
//  top of several hundred families every single time — the owner's daily
//  irritation, and the reason this exists.
//
//  A plain SwiftUI `Picker` would give scroll-to-selection for free, but menu
//  items in a Picker do not reliably render in a custom face, and seeing each
//  family SET IN ITSELF is most of the value of a typeface list in a design tool.
//  So this is a popover + `ScrollViewReader`: previews kept, selection marked,
//  and the list scrolled to the applied face on open.
//
//  It also gives the rest of FEAT-008 somewhere to live — "Fonts used" and
//  "Recent fonts" are filters over THIS list, not a different control.
//

import SwiftUI

struct FontFamilyPicker: View {
    /// Family currently applied, or "" for the system face. May be "Mixed".
    let currentFamily: String
    /// What the collapsed control shows. Usually `currentFamily`, but callers with
    /// a multi-selection pass a fixed label because there is no single value.
    let label: String
    let onPick: (String) -> Void
    /// Called for the System entry, which is a font NAME of "" rather than a family.
    let onPickSystem: () -> Void

    @State private var open = false

    private static let systemRowID = "__exp_system__"
    private static let rowHeight: CGFloat = 24

    private var selectedRowID: String {
        currentFamily.isEmpty ? Self.systemRowID : currentFamily
    }

    private func preview(_ family: String, size: CGFloat) -> Font {
        family == FontCatalog.systemMonospacedFamily
            ? .system(size: size, design: .monospaced)
            : .custom(family, size: size)
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack {
                Text(label).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(EXPColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Typeface")
        .accessibilityValue(label)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        row(id: Self.systemRowID, title: "System",
                            font: .system(size: 13),
                            selected: currentFamily.isEmpty) {
                            onPickSystem()
                        }
                        Divider().padding(.vertical, 2)
                        ForEach(FontCatalog.families, id: \.self) { family in
                            row(id: family, title: family,
                                font: preview(family, size: 13),
                                selected: family == currentFamily) {
                                onPick(family)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 260, height: 320)
                .onAppear {
                    // The entire point: land on what is applied, not on the top of
                    // the alphabet. `.center` rather than `.top` so the neighbours
                    // are visible too — picking a different weight of the same
                    // family, or a sibling face, is the common next move.
                    //
                    // Done TWICE, and the second pass is not superstition. A
                    // `LazyVStack` only builds the rows it currently believes are
                    // visible, and on the first `onAppear` the popover has not been
                    // laid out yet — so scrolling then leaves the rows ABOVE the
                    // target unbuilt, and they render as blank space until a real
                    // scroll forces them into existence. Owner saw exactly that.
                    // The first call gets us roughly there; the async one re-runs
                    // after layout, when the visible window is known and the
                    // surrounding rows actually materialise.
                    proxy.scrollTo(selectedRowID, anchor: .center)
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedRowID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(id: String, title: String, font: Font,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            open = false
        } label: {
            HStack(spacing: 6) {
                // Reserved whether or not it is ticked, so names stay aligned and
                // the list does not jitter as the selection moves.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                Text(title)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(id)
        .background(selected ? EXPColor.accentSubtle2 : Color.clear)
        // VoiceOver announces the state rather than relying on the tick alone.
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

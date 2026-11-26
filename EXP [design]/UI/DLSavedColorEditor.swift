import AppKit
import SwiftUI

enum DLSavedColorEditorMode {
    case document, base, override(UUID)
}

/// Both Design Language surfaces use a draft and commit only on Save.
struct DLSavedColorEditor: View {
    @ObservedObject var document: ExpDocument
    let asset: DesignAsset
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DesignAsset
    @State private var modeID: UUID?
    @State private var tab: DLTokenEditorTab = .value
    @State private var details: DLTokenDetails

    init(document: ExpDocument, asset: DesignAsset, undoManager: UndoManager?,
         startingIn selection: DLSavedColorEditorMode = .document) {
        self.document = document
        self.asset = asset
        self.undoManager = undoManager
        _draft = State(initialValue: asset)
        _details = State(initialValue: Self.details(for: asset, in: document.model.designLanguage))
        let initialMode: UUID?
        switch selection {
        case .document:
            if case .solid = asset.value { initialMode = document.model.designLanguage.colorMode()?.id }
            else { initialMode = nil }
        case .base: initialMode = nil
        case .override(let id): initialMode = id
        }
        _modeID = State(initialValue: initialMode)
    }

    private var language: DesignLanguage { document.model.designLanguage }
    private var originalDetails: DLTokenDetails { Self.details(for: asset, in: language) }
    private var changed: Bool { draft != asset || details != originalDetails }

    private static func details(for asset: DesignAsset, in language: DesignLanguage) -> DLTokenDetails {
        DLTokenDetails(name: asset.name, categoryID: language.category(asset.categoryID)?.id,
                       group: asset.group ?? "", notes: asset.notes, deprecated: asset.deprecated)
    }
    private var preview: Paint { language.paint(for: draft, in: modeID) }
    private var showsModes: Bool {
        if case .solid = draft.value { return language.colorModeSet != nil }
        return false
    }

    private var canSave: Bool {
        language.asset(asset.id) == asset && document.model.libraryTokenLink(forAsset: asset.id)?.writable != false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(asset.name.isEmpty ? asset.value.savedPaintEditLabel : "Edit \(asset.name)")
                .font(.headline)
            DLTokenEditorTabs(valueLabel: valueLabel, selection: $tab)
            if tab == .details {
                DLTokenDetailsFields(details: $details, categories: language.categories) { }
            } else {
                paintFields
            }
            if !canSave {
                Text("This entry changed or became unavailable. Reopen the editor to edit the current entry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset") {
                    draft = asset
                    details = originalDetails
                }
                    .disabled(!changed)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || !changed || !details.hasValidCategory(in: language))
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .expInterfaceTypeSize()
        .environment(\.patternLibrary, PatternLibrary(
            sources: { document.model.patterns },
            image: { PatternPreviewStore.shared.image(for: $0, document: document) }))
    }

    private var valueLabel: String {
        switch asset.value {
        case .solid: "Color"
        case .gradient, .mesh: "Gradient"
        case .pattern: "Pattern"
        }
    }

    @ViewBuilder private var paintFields: some View {
        if showsModes, let set = language.colorModeSet {
            Picker("Edit Color For", selection: $modeID) {
                Text("Base Color").tag(UUID?.none)
                ForEach(set.modes) { mode in Text(mode.name).tag(UUID?.some(mode.id)) }
            }
        }
        PaintSwatch(paint: preview).frame(height: 54)
        if case .solid = draft.value {
            DLSavedColorMenu(language: language, modeID: modeID, excluding: asset.id) { color in
                if let modeID { draft.modeValues[modeID.uuidString] = .color(color) }
                else { draft.value = .solid(color) }
            }
            .disabled(!canSave)
        }
        if let modeID, showsModes {
            modeEditor(modeID)
                .id(modeID)
        } else if !draft.modeValues.isEmpty {
            ColorPopover(color: colorBinding(for: nil), supportsOpacity: true, showsDesignLanguageLink: false)
        } else {
            PaintEditor(paint: $draft.value, supportsOpacity: true, showsDesignLanguageLink: false, editsDraft: true)
        }
        Text("Press Return to apply a typed color code to the preview.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func modeEditor(_ id: UUID) -> some View {
        let key = id.uuidString
        let value = draft.modeValues[key]
        if let alias = value?.aliasTarget {
            Text(language.asset(alias).map { "Uses \($0.name) in this mode" } ?? "Alias unavailable. Using the base color.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            if value == nil {
                Text("Uses the base color until you set a different value.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ColorPopover(color: colorBinding(for: id), supportsOpacity: true, showsDesignLanguageLink: false)
        }
        if value != nil {
            Button("Use Base Color") { draft.modeValues[key] = nil }
        }
    }

    private func colorBinding(for id: UUID?) -> Binding<RGBAColor> {
        Binding(
            get: { language.paint(for: draft, in: id).representativeColor },
            set: { color in
                if let id {
                    let key = id.uuidString
                    if draft.modeValues[key] != nil || color != draft.representativeColor {
                        draft.modeValues[key] = .color(color)
                    }
                } else {
                    draft.value = .solid(color)
                }
            })
    }

    private func save() {
        guard canSave, changed, details.hasValidCategory(in: language) else { return }
        var model = document.model
        guard let index = model.designLanguage.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        var updated = draft
        updated.name = details.trimmedName
        updated.group = details.trimmedGroup.isEmpty ? nil : details.trimmedGroup
        updated.notes = details.notes
        updated.deprecated = details.deprecated
        updated.categoryID = details.categoryID(in: &model.designLanguage)
        model.designLanguage.assets[index] = updated
        document.setModel(model, undoManager: undoManager, actionName: "Edit Saved Paint")
        dismiss()
    }
}

/// The palette lives inside the editor, where the underlying sheet's dimming
/// cannot change the value being picked.
struct DLSavedColorMenu: View {
    let language: DesignLanguage
    let modeID: UUID?
    var excluding: UUID? = nil
    let select: (RGBAColor) -> Void

    private typealias Choice = (asset: DesignAsset, color: RGBAColor)

    var body: some View {
        let choices = language.savedColorChoices(in: modeID, excluding: excluding)
        if !choices.isEmpty {
            Menu("Choose Saved Color") {
                items(choices)
                if modeID != nil {
                    let base = language.savedColorChoices(in: nil, excluding: excluding)
                    if zip(choices, base).contains(where: { $0.0.color != $0.1.color }) {
                        Divider()
                        Menu("Base Colors") { items(base) }
                    }
                }
            }
            .help("Copy a saved color into this draft")
        }
    }

    private func items(_ choices: [Choice]) -> some View {
        ForEach(choices.sorted { $0.asset.name.localizedStandardCompare($1.asset.name) == .orderedAscending },
                id: \.asset.id) { choice in
            let category = language.categoryLabel(for: choice.asset)
            let name = choice.asset.name.isEmpty ? "Unnamed swatch" : choice.asset.name
            let hex = ColorMath.string(choice.color, .hex)
            let title = [name, category, hex].filter { !$0.isEmpty }.joined(separator: " · ")
            Button { select(choice.color) } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(nsImage: Self.swatchIcon(choice.color)).renderingMode(.original)
                }
            }
        }
    }

    private static func swatchIcon(_ color: RGBAColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            PaintRender.nsColor(color).setFill()
            shape.fill()
            NSColor.separatorColor.setStroke()
            shape.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}


extension Paint {
    var savedPaintEditLabel: String {
        switch self {
        case .solid: return "Edit Color…"
        case .gradient, .mesh: return "Edit Gradient…"
        case .pattern: return "Edit Pattern…"
        }
    }
}

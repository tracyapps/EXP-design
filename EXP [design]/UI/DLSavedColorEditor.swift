import SwiftUI

/// Both Design Language surfaces use a draft and commit only on Save.
struct DLSavedColorEditor: View {
    @ObservedObject var document: ExpDocument
    let asset: DesignAsset
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Paint

    init(document: ExpDocument, asset: DesignAsset, undoManager: UndoManager?) {
        self.document = document
        self.asset = asset
        self.undoManager = undoManager
        _draft = State(initialValue: asset.value)
    }

    private var canSave: Bool {
        document.model.designLanguage.asset(asset.id)?.value == asset.value
            && document.model.libraryTokenLink(forAsset: asset.id)?.writable != false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(asset.name.isEmpty ? asset.value.savedPaintEditLabel : "Edit \(asset.name)")
                .font(.headline)
            PaintSwatch(paint: draft).frame(height: 54)
            PaintEditor(paint: $draft, supportsOpacity: true, showsDesignLanguageLink: false, editsDraft: true)
            Text("Press Return to apply a typed color code to the preview.")
                .font(.caption).foregroundStyle(.secondary)
            if !canSave {
                Text("This color changed or became unavailable. Close the picker and reopen it to edit the current value.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset") { draft = asset.value }
                    .disabled(draft == asset.value)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || draft == asset.value)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
        .environment(\.patternLibrary, PatternLibrary(
            sources: { document.model.patterns },
            image: { PatternPreviewStore.shared.image(for: $0, document: document) }))
    }

    private func save() {
        guard canSave, draft != asset.value else { return }
        var model = document.model
        model.designLanguage.setValue(asset.id, to: draft)
        document.setModel(model, undoManager: undoManager, actionName: "Edit Saved Paint")
        dismiss()
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

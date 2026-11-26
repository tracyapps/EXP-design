import SwiftUI

/// Edits a single saved dimension. Save applies the value and metadata as one
/// document edit, using the same ID that the canvas bindings reference.
struct DLDimensionTokenEditor: View {
    @ObservedObject var document: ExpDocument
    let token: DLToken
    let kind: DLDimensionKind
    let undoManager: UndoManager?

    @Environment(\.dismiss) private var dismiss

    @State private var details: DLTokenDetails
    @State private var valueText: String

    init(document: ExpDocument, token: DLToken, kind: DLDimensionKind, undoManager: UndoManager?) {
        self.document = document
        self.token = token
        self.kind = kind
        self.undoManager = undoManager
        _details = State(initialValue: DLTokenDetails(
            name: token.name, categoryID: document.model.designLanguage.category(token.categoryID)?.id,
            group: token.group, notes: token.notes, deprecated: token.deprecated))
        _valueText = State(initialValue: token.value.authoredText)
    }

    private var language: DesignLanguage { document.model.designLanguage }
    private var isCurrent: Bool { language.token(token.id) == token }

    private var editedValue: DLTokenValue? {
        let value = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.value.isEditableLength, value != token.value.authoredText else { return token.value }
        return DLTokenValue.parsingLength(value)
    }

    private var canSave: Bool {
        isCurrent && editedValue != nil && details.hasValidCategory(in: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(kind.rawValue) Token").font(.headline)
            DLTokenDetailsFields(details: $details, categories: language.categories) {
                GridRow {
                    Text("Base Value")
                    valueField
                }
            }

            if !isCurrent {
                Text("This token changed while the editor was open. Reopen it to edit the latest version.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .expInterfaceTypeSize()
    }

    @ViewBuilder private var valueField: some View {
        if token.value.isEditableLength {
            TextField("Base value", text: $valueText, prompt: Text(kind == .radius ? "8px or 50%" : "16px or 1rem"))
                .labelsHidden()
        } else if let alias = token.value.aliasTarget {
            let target = language.token(alias)?.name
            Text(target.map { "Alias of \($0)" } ?? "Alias target unavailable")
                .foregroundStyle(.secondary)
        } else {
            Text("Preserved value").foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard canSave, let value = editedValue else { return }
        var model = document.model
        guard let index = model.designLanguage.tokens.firstIndex(where: { $0.id == token.id }) else { return }
        var updated = token
        updated.name = details.trimmedName.isEmpty ? token.name : details.trimmedName
        updated.group = details.trimmedGroup
        updated.notes = details.notes
        updated.deprecated = details.deprecated
        updated.value = value
        updated.categoryID = details.categoryID(in: &model.designLanguage)
        if updated != token {
            model.designLanguage.tokens[index] = updated
            document.setModel(model, undoManager: undoManager, actionName: "Edit \(kind.rawValue) Token")
        }
        dismiss()
    }
}

extension DLTokenValue {
    var isEditableLength: Bool {
        switch self {
        case .dimension, .number, .raw: true
        case .alias, .color, .preserved: false
        }
    }
}

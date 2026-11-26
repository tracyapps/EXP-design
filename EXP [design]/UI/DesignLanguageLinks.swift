import AppKit
import SwiftUI

extension TokenBindingKey {
    static func appearanceLabel(_ key: String) -> String {
        switch key {
        case fill: return "Fill"
        case stroke: return "Stroke"
        case paddingFill: return "Background Fill"
        case paddingStroke: return "Background Stroke"
        case textColor: return "Text Color"
        case textStroke: return "Text Outline"
        case textStyle: return "Type Style"
        default: return key
        }
    }
}

@MainActor
func deleteDesignLanguageAsset(_ id: UUID, name: String, typeStyle: Bool,
                               document: ExpDocument, undoManager: UndoManager?) {
    let uses = document.model.tokenUseCount(id)
    if uses > 0 {
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "This will unlink \(uses) \(uses == 1 ? "property" : "properties"). Current artwork values will be kept."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    var model = document.model
    guard typeStyle ? model.designLanguage.typeStyle(id) != nil : model.designLanguage.asset(id) != nil else { return }
    model.removeAppearanceAsset(id, typeStyle: typeStyle)
    document.setModel(model, undoManager: undoManager,
                      actionName: typeStyle ? "Delete Type Style" : "Delete Swatch")
}

struct DLMatchingStylesSheet: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var preview = Document.AppearanceMatchPreview()
    @State private var generation: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link Matching Styles").font(.headline)
            Text("\(preview.matches.count) exact matches across this document. Linking keeps their current appearance.")
            if preview.ambiguousCount > 0 {
                Text("\(preview.ambiguousCount) properties match multiple saved styles and will be skipped.")
                    .foregroundStyle(.secondary)
            }
            if !preview.matches.isEmpty {
                let rows = Array(preview.matches.enumerated())
                List(rows, id: \.offset) { row in
                    let match = row.element
                    HStack {
                        Text(match.layer)
                        Spacer()
                        Text(TokenBindingKey.appearanceLabel(match.key))
                            .foregroundStyle(.secondary)
                        Text(match.name.isEmpty ? "Unnamed Swatch" : match.name)
                    }
                }
                .frame(minHeight: 140, idealHeight: 240)
                .accessibilityLabel("Matching layer properties")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Link \(preview.matches.count) Properties") {
                    guard generation == document.resolveGeneration else { refresh(); return }
                    var model = document.model
                    if model.linkMatchingAppearance(preview) {
                        document.setModel(model, undoManager: undoManager, actionName: "Link Matching Styles")
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.matches.isEmpty)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: document.resolveGeneration) { _, _ in refresh() }
        .padding(20)
        .frame(width: 480)
    }

    private func refresh() {
        preview = document.model.matchingAppearanceBindings()
        generation = document.resolveGeneration
    }
}

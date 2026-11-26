import AppKit
import SwiftUI

struct DLTypeStyleEditor: View {
    @ObservedObject var document: ExpDocument
    let style: TypeStyle
    let undoManager: UndoManager?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TypeStyle
    @State private var details: DLTokenDetails
    @State private var tab: DLTokenEditorTab = .value

    init(document: ExpDocument, style: TypeStyle, undoManager: UndoManager?) {
        self.document = document
        self.style = style
        self.undoManager = undoManager
        _draft = State(initialValue: style)
        _details = State(initialValue: Self.details(for: style, in: document.model.designLanguage))
    }

    private var language: DesignLanguage { document.model.designLanguage }
    private var originalDetails: DLTokenDetails { Self.details(for: style, in: language) }
    private var isCurrent: Bool { language.typeStyle(style.id) == style }
    private var changed: Bool { draft != style || details != originalDetails }

    private var canSave: Bool {
        isCurrent && changed && details.hasValidCategory(in: language)
            && draft.fontSize.isFinite && draft.fontSize > 0 && draft.tracking.isFinite
            && (draft.lineHeightUnit == .auto || (draft.lineHeight.isFinite && draft.lineHeight >= 0))
    }

    private static func details(for style: TypeStyle, in language: DesignLanguage) -> DLTokenDetails {
        DLTokenDetails(name: style.name, categoryID: language.category(style.categoryID)?.id,
                       group: style.group ?? "", notes: style.notes, deprecated: style.deprecated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(style.name.isEmpty ? style.fallbackLabel : style.name)").font(.headline)
            DLTokenEditorTabs(valueLabel: "Typography", selection: $tab)

            if tab == .details {
                DLTokenDetailsFields(details: $details, categories: language.categories) { }
            } else {
                typeFields
            }

            if !isCurrent {
                Text("This style changed or became unavailable. Reopen the editor to edit the current style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset") {
                    draft = style
                    details = originalDetails
                }
                .disabled(!changed)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 500)
        .expInterfaceTypeSize()
    }

    private var family: String {
        if FontCatalog.isSystemMonospaced(draft.fontName) { return FontCatalog.systemMonospacedFamily }
        if draft.fontName.isEmpty { return "" }
        return NSFont(name: draft.fontName, size: 12)?.familyName ?? draft.fontName
    }

    private var typeFields: some View {
        let faces = FontCatalog.faces(of: family)
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                Text("Font")
                FontFamilyPicker(currentFamily: family, label: family.isEmpty ? "System" : family,
                                 fontsUsed: { document.model.usedFontFamilies },
                                 onPick: { draft.fontName = FontCatalog.defaultFace(of: $0) ?? draft.fontName },
                                 onPickSystem: { draft.fontName = "" })
            }
            if faces.count > 1 {
                GridRow {
                    Text("Weight / Style")
                    Menu {
                        ForEach(faces) { face in
                            Button(face.faceName) { draft.fontName = face.postScriptName }
                        }
                    } label: {
                        Text(faces.first { $0.postScriptName == draft.fontName }?.faceName ?? draft.fontName)
                    }
                    .accessibilityLabel("Font weight and style")
                }
            }
            GridRow {
                Text("Size")
                TextField("Font size", value: number($draft.fontSize), format: .number.precision(.fractionLength(0...2)))
                    .frame(maxWidth: 110)
            }
            GridRow {
                Text("Line Height")
                HStack {
                    Picker("Line height unit", selection: lineHeightUnit) {
                        Text("Auto").tag(LineHeightUnit.auto)
                        Text("Multiplier (×)").tag(LineHeightUnit.multiple)
                        Text("Points").tag(LineHeightUnit.px)
                        Text("em").tag(LineHeightUnit.em)
                    }
                    if draft.lineHeightUnit != .auto {
                        TextField("Line height", value: number($draft.lineHeight), format: .number.precision(.fractionLength(0...3)))
                            .frame(maxWidth: 95)
                    }
                }
            }
            GridRow {
                Text("Tracking")
                TextField("Tracking", value: number($draft.tracking), format: .number.precision(.fractionLength(0...2)))
                    .frame(maxWidth: 110)
            }
            GridRow {
                Text("Alignment")
                Picker("Alignment", selection: $draft.align) {
                    Text("Left").tag(TextAlign.left)
                    Text("Center").tag(TextAlign.center)
                    Text("Right").tag(TextAlign.right)
                }
                .pickerStyle(.segmented)
            }
            GridRow {
                Text("Case")
                Picker("Letter case", selection: $draft.textCase) {
                    Text("As typed").tag(TextCase.none)
                    Text("Uppercase").tag(TextCase.upper)
                    Text("Lowercase").tag(TextCase.lower)
                    Text("Capitalize each word").tag(TextCase.title)
                    Text("Sentence case").tag(TextCase.sentence)
                }
            }
            GridRow {
                Text("Underline")
                Toggle("Underline", isOn: $draft.underline)
            }
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
    }

    private func number(_ value: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) })
    }

    private var lineHeightUnit: Binding<LineHeightUnit> {
        Binding(get: { draft.lineHeightUnit }, set: { unit in
            var text = TextContent()
            draft.apply(to: &text)
            let converted = text.lineHeightValue(for: text.renderedLineHeightPoints, in: unit)
            draft.lineHeight = max(0, (converted * 1000).rounded() / 1000)
            draft.lineHeightUnit = unit
        })
    }

    private func save() {
        guard canSave else { return }
        var model = document.model
        guard let index = model.designLanguage.typeStyles.firstIndex(where: { $0.id == style.id }) else { return }
        var updated = draft
        updated.name = details.trimmedName
        updated.group = details.trimmedGroup.isEmpty ? nil : details.trimmedGroup
        updated.notes = details.notes
        updated.deprecated = details.deprecated
        updated.categoryID = details.categoryID(in: &model.designLanguage)
        model.designLanguage.typeStyles[index] = updated
        document.setModel(model, undoManager: undoManager, actionName: "Edit Type Style")
        dismiss()
    }
}

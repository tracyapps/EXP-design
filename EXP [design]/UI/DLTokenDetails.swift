import SwiftUI

/// Shared draft for the metadata fields on saved Design Language entries.
struct DLTokenDetails: Equatable {
    enum Category: Hashable { case other, existing(UUID), new }

    var name: String
    var category: Category
    var newCategory = ""
    var group: String
    var notes: String
    var deprecated: String?

    init(name: String, categoryID: UUID?, group: String, notes: String, deprecated: String?) {
        self.name = name
        category = categoryID.map(Category.existing) ?? .other
        self.group = group
        self.notes = notes
        self.deprecated = deprecated
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedGroup: String { group.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNewCategory: String { newCategory.trimmingCharacters(in: .whitespacesAndNewlines) }

    func hasValidCategory(in language: DesignLanguage) -> Bool {
        switch category {
        case .other: true
        case .existing(let id): language.category(id) != nil
        case .new: !trimmedNewCategory.isEmpty
        }
    }

    func categoryID(in language: inout DesignLanguage) -> UUID? {
        switch category {
        case .other: nil
        case .existing(let id): id
        case .new: language.ensureCategory(trimmedNewCategory)
        }
    }
}

struct DLTokenDetailsFields<ExtraRows: View>: View {
    @Binding var details: DLTokenDetails
    let categories: [DLCategory]
    @ViewBuilder let extraRows: () -> ExtraRows
    @FocusState private var nameFocused: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                Text("Name")
                TextField("Name", text: $details.name)
                    .labelsHidden()
                    .focused($nameFocused)
            }
            extraRows()
            GridRow {
                Text("Category")
                Picker("Category", selection: $details.category) {
                    Text("Other").tag(DLTokenDetails.Category.other)
                    ForEach(categories) { category in
                        Text(category.name).tag(DLTokenDetails.Category.existing(category.id))
                    }
                    Divider()
                    Text("New Category…").tag(DLTokenDetails.Category.new)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if details.category == .new {
                GridRow {
                    Text("New category")
                    TextField("New category name", text: $details.newCategory)
                        .labelsHidden()
                }
            }
            GridRow {
                Text("Group")
                TextField("Group", text: $details.group, prompt: Text("Controls / Buttons"))
                    .labelsHidden()
            }
            GridRow(alignment: .top) {
                Text("Notes")
                TextField("Notes", text: $details.notes, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
            }
            GridRow {
                Text("Status")
                Toggle("Deprecated", isOn: Binding(
                    get: { details.deprecated != nil },
                    set: { details.deprecated = $0 ? details.deprecated ?? "" : nil }))
            }
            if details.deprecated != nil {
                GridRow {
                    Text("Reason")
                    TextField("Deprecation reason", text: Binding(
                        get: { details.deprecated ?? "" },
                        set: { details.deprecated = $0 }))
                        .labelsHidden()
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .defaultFocus($nameFocused, true)
    }
}

enum DLTokenEditorTab { case value, details }

struct DLTokenEditorTabs: View {
    let valueLabel: String
    @Binding var selection: DLTokenEditorTab

    var body: some View {
        Picker("Editor section", selection: $selection) {
            Text(valueLabel).tag(DLTokenEditorTab.value)
            Text("Details").tag(DLTokenEditorTab.details)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

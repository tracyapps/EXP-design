//
//  DesignLanguageSettings.swift
//  EXP [design]
//
//  The "Design Language" pane in Settings (Document section). Unlike the app-wide
//  panes, this edits the FRONTMOST document's design language — reached through
//  PanelHub (Settings is one app-wide window and can't hold per-document state).
//  It's the bulk-editing surface: rename / recategorize / delete colors,
//  gradients, and type styles without the canvas-click hazard of the inline
//  panel, add paints by hand with a real picker, and import / export between
//  documents.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Entry point. Resolves the frontmost document (or shows an empty state).
struct DesignLanguageSettingsPane: View {
    var body: some View {
        if let doc = PanelHub.shared.activeDocument {
            DesignLanguageEditor(document: doc, undoManager: PanelHub.shared.activeUndo)
                .id(ObjectIdentifier(doc))
        } else {
            VStack(alignment: .leading, spacing: 24) {
                SettingsGroup("Design Language",
                              footnote: "This edits the design language saved inside a document.") {
                    HStack(spacing: 8) {
                        Image(systemName: "swatchpalette").foregroundStyle(.secondary)
                        Text("Open a design document to edit its colors, gradients, and typography.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Editor

private struct DesignLanguageEditor: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?

    @State private var draftPaint: Paint = .solid(RGBAColor(r: 0.55, g: 0.55, b: 0.6, a: 1))
    @State private var draftName = ""
    @State private var draftCategory: UUID?
    @State private var newCategoryName = ""
    @State private var pasteText = ""
    @State private var showingPaste = false
    @State private var mergeMode: DesignLanguage.MergeMode = .keepBoth
    @State private var draggingCategory: UUID?
    @State private var editingColor: DesignAsset?
    @State private var sortColumn: PaintColumn = .category
    @State private var ascending = true
    @AppStorage("exp.dl.settingsColorFormat") private var colorFormat: ColorFormat = .hex

    private enum PaintColumn: String {
        case name = "Name"
        case value = "Value"
        case category = "Category"
    }

    private var dl: DesignLanguage { document.model.designLanguage }

    private func valueString(_ asset: DesignAsset) -> String {
        if case .solid(let color) = asset.value { return ColorMath.string(color, colorFormat) }
        return DesignLanguageIO.css(for: asset.value)
    }

    private var orderedAssets: [(asset: DesignAsset, value: String)] {
        let rank = Dictionary(uniqueKeysWithValues: dl.categories.enumerated().map { ($1.id, $0) })
        return dl.assets.map { (asset: $0, value: valueString($0)) }.sorted { a, b in
            let order: ComparisonResult
            switch sortColumn {
            case .name:
                order = a.asset.name.localizedStandardCompare(b.asset.name)
            case .value:
                order = a.value.localizedStandardCompare(b.value)
            case .category:
                let ra = a.asset.categoryID.flatMap { rank[$0] } ?? Int.max
                let rb = b.asset.categoryID.flatMap { rank[$0] } ?? Int.max
                order = ra == rb ? .orderedSame : (ra < rb ? .orderedAscending : .orderedDescending)
            }
            if order == .orderedSame {
                return a.asset.name.localizedStandardCompare(b.asset.name) == .orderedAscending
            }
            return order == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    /// Type styles follow the same category/name reading order as paints so the
    /// two halves of the Design Language stay predictable in this bulk editor.
    private var orderedTypeStyles: [TypeStyle] {
        let rank = Dictionary(uniqueKeysWithValues: dl.categories.enumerated().map { ($1.id, $0) })
        return dl.typeStyles.sorted { a, b in
            let ra = a.categoryID.flatMap { rank[$0] } ?? Int.max
            let rb = b.categoryID.flatMap { rank[$0] } ?? Int.max
            if ra != rb { return ra < rb }
            let an = a.name.isEmpty ? a.fallbackLabel : a.name
            let bn = b.name.isEmpty ? b.fallbackLabel : b.name
            return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            entriesGroup
            addGroup
            categoriesGroup
            importExportGroup
            typeStylesGroup
        }
        .sheet(isPresented: $showingPaste) { pasteSheet }
        .sheet(item: $editingColor) { asset in
            DLSavedColorEditor(document: document, asset: asset, undoManager: undoManager)
        }
    }

    // MARK: Import / export

    private var importExportGroup: some View {
        SettingsGroup("Import & Export",
                      footnote: "Share a design language between documents. EXP JSON round-trips names, categories, gradients, and type styles. Paste accepts a HEX list, CSS variables, or a Coolors URL. (Figma / XD import is a future addition.)") {
            HStack(spacing: 8) {
                Button("Import from File\u{2026}") { importFromFile() }.buttonStyle(.exp(.secondary))
                Button("Paste\u{2026}") { pasteText = ""; showingPaste = true }.buttonStyle(.exp(.secondary))
                Spacer()
                Button("Export EXP JSON\u{2026}") { exportToFile() }
                    .buttonStyle(.exp(.secondary)).disabled(dl.assets.isEmpty && dl.typeStyles.isEmpty)
                Button("Copy CSS") { copy(DesignLanguageIO.exportCSS(dl)) }
                    .buttonStyle(.exp(.secondary)).disabled(dl.assets.isEmpty && dl.typeStyles.isEmpty)
            }
        }
    }

    // MARK: Manual add (with a real picker)

    private var addGroup: some View {
        SettingsGroup("Add a color or gradient") {
            PaintWell(label: "Value", paint: $draftPaint)
            HStack(spacing: 8) {
                TextField("Name (optional)", text: $draftName)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                categoryMenu(selection: $draftCategory)
                Spacer()
                Button("Add") { addDraft() }.buttonStyle(.exp(.primary))
            }
        }
    }

    // MARK: Categories

    private var categoriesGroup: some View {
        SettingsGroup("Categories",
                      footnote: "Deleting a category keeps its colors and type styles \u{2014} they just become uncategorized (Other).") {
            if dl.categories.isEmpty {
                Text("No categories yet. Add one to group colors and type styles (e.g. Primary, Accent, Headings).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dl.categories) { cat in
                    DLCategoryRow(
                        category: cat,
                        count: dl.count(in: cat.id),
                        isDragging: draggingCategory == cat.id,
                        beginDrag: {
                            draggingCategory = cat.id
                            return NSItemProvider(object: cat.id.uuidString as NSString)
                        },
                        onRename: { name in commit("Rename Category") { $0.renameCategory(cat.id, to: name) } },
                        onDelete: { commit("Delete Category") { $0.removeCategory(cat.id) } })
                    .onDrop(of: [.text], delegate: CategoryDrop(
                        targetID: cat.id, dragging: $draggingCategory,
                        move: { dragged, before in reorderCategory(dragged, target: cat.id, before: before) }))
                }
            }
            HStack(spacing: 8) {
                TextField("New category", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit(addCategory)
                Button("Add Category") { addCategory() }
                    .buttonStyle(.exp(.secondary))
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Entries table (bulk edit)

    private var entriesGroup: some View {
        SettingsGroup("Colors & Gradients (\(dl.assets.count))") {
            if dl.assets.isEmpty {
                Text("Nothing saved yet.").foregroundStyle(.secondary)
            } else {
                let links = document.model.libraryTokenLinks
                HStack(spacing: 8) {
                    Color.clear.frame(width: 34, height: 1).accessibilityHidden(true)
                    sortButton(.name).frame(minWidth: 76, maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        sortButton(.value)
                        Picker("Color format", selection: $colorFormat) {
                            ForEach(ColorFormat.allCases) { format in
                                Text(format == .rgba ? "RGB/A" : format.rawValue).tag(format)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Color value format")
                    }
                    .frame(minWidth: 145, maxWidth: .infinity, alignment: .leading)
                    sortButton(.category).frame(width: 96, alignment: .leading)
                    Color.clear.frame(width: 24, height: 1).accessibilityHidden(true)
                }
                Divider()
                LazyVStack(spacing: 6) {
                    ForEach(orderedAssets, id: \.asset.id) { entry in
                        let asset = entry.asset
                        DLEntryRow(
                            asset: asset,
                            categories: dl.categories,
                            value: entry.value,
                            isReadOnly: links[asset.id]?.writable == false,
                            onEdit: { editingColor = asset },
                            onCopy: { copy(entry.value) },
                            onRename: { name in commit("Rename Swatch") { $0.rename(asset.id, to: name) } },
                            onSetCategory: { cid in commit("Set Category") { $0.setCategory(asset.id, to: cid) } },
                            onDelete: { commit("Delete Swatch") { $0.remove(asset.id) } })
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private func sortButton(_ column: PaintColumn) -> some View {
        Button {
            if sortColumn == column { ascending.toggle() }
            else { sortColumn = column; ascending = true }
        } label: {
            HStack(spacing: 3) {
                Text(column.rawValue)
                if sortColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Sort by \(column.rawValue)")
        .accessibilityValue(sortColumn == column ? (ascending ? "Ascending" : "Descending") : "")
    }

    private var typeStylesGroup: some View {
        SettingsGroup(
            "Typography · Type Styles (\(dl.typeStyles.count))",
            footnote: "Type Styles store reusable presentation; Paragraph and Heading 1–6 remain content roles on each text layer. Create or update a style from selected text in the Type menu or Design Language panel."
        ) {
            if dl.typeStyles.isEmpty {
                Text("No type styles saved yet.").foregroundStyle(.secondary)
            } else {
                ForEach(orderedTypeStyles) { style in
                    DLTypeStyleRow(
                        style: style,
                        categories: dl.categories,
                        onRename: { name in
                            commit("Rename Type Style") { $0.renameTypeStyle(style.id, to: name) }
                        },
                        onSetCategory: { cid in
                            commit("Set Type Style Category") { $0.setTypeStyleCategory(style.id, to: cid) }
                        },
                        onDelete: {
                            commit("Delete Type Style") { $0.removeTypeStyle(style.id) }
                        })
                    Divider().opacity(0.4)
                }
            }
        }
    }

    // MARK: Category menu (shared by add + rows)

    private func categoryMenu(selection: Binding<UUID?>) -> some View {
        Menu {
            Button("Other") { selection.wrappedValue = nil }
            if !dl.categories.isEmpty { Divider() }
            ForEach(dl.categories) { c in
                Button {
                    selection.wrappedValue = c.id
                } label: {
                    if selection.wrappedValue == c.id { Label(c.name, systemImage: "checkmark") }
                    else { Text(c.name) }
                }
            }
        } label: {
            Text(dl.category(selection.wrappedValue)?.name ?? "Other")
        }
        .fixedSize()
    }

    // MARK: Paste sheet

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste Palette").font(.headline)
            Text("A HEX list, CSS variables, or a Coolors URL. Colors import as uncategorized.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $pasteText)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 360, minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EXPColor.borderSoft))
            HStack(spacing: 8) {
                Picker("On conflict", selection: $mergeMode) {
                    ForEach(DesignLanguage.MergeMode.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 230)
                Spacer(minLength: 0)
                Button("Cancel") { showingPaste = false }.buttonStyle(.exp(.ghost))
                Button("Import") { performPasteImport() }
                    .buttonStyle(.exp(.primary))
                    .disabled(DesignLanguageIO.parsePalette(pasteText).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    // MARK: Actions

    private func addDraft() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let paint = draftPaint
        let cat = draftCategory
        commit("Add Color") { $0.save(paint, name: name, categoryID: cat, provenance: "manual") }
        draftName = ""
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        commit("Add Category") { $0.ensureCategory(name) }
        newCategoryName = ""
    }

    private func reorderCategory(_ draggedID: UUID, target targetID: UUID, before: Bool) {
        let cats = dl.categories
        guard let ti = cats.firstIndex(where: { $0.id == targetID }) else { return }
        let beforeID: UUID? = before ? targetID : (ti + 1 < cats.count ? cats[ti + 1].id : nil)
        commit("Reorder Categories") { $0.moveCategory(draggedID, before: beforeID) }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Import an EXP design-language JSON file."
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let parsed = DesignLanguageIO.parseJSON(data),
              !parsed.assets.isEmpty || !parsed.typeStyles.isEmpty else { return }
        commit("Import Design Language") {
            $0.merge(parsed.assets, categories: parsed.categories, mode: mergeMode)
            $0.mergeTypeStyles(parsed.typeStyles, categories: parsed.categories, mode: mergeMode)
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "design-language.json"
        panel.message = "Export this document's design language as EXP JSON."
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? DesignLanguageIO.exportJSON(dl, patterns: document.model.patterns)
        else { return }
        try? data.write(to: url)
    }

    private func performPasteImport() {
        let assets = DesignLanguageIO.parsePalette(pasteText)
        showingPaste = false
        guard !assets.isEmpty else { return }
        commit("Import Palette") { $0.merge(assets, mode: mergeMode) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// One undo step per edit, registered on the frontmost document.
    private func commit(_ action: String, _ change: (inout DesignLanguage) -> Void) {
        var model = document.model
        change(&model.designLanguage)
        document.setModel(model, undoManager: undoManager, actionName: action)
    }
}

// MARK: - Rows (local draft state so typing doesn't spam undo)

/// One category: inline-rename (commit on Return / blur) + delete.
private struct DLCategoryRow: View {
    let category: DLCategory
    let count: Int
    let isDragging: Bool
    let beginDrag: () -> NSItemProvider
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .contentShape(Rectangle())
                .onDrag(beginDrag)
                .help("Drag to reorder")
            TextField("Category", text: $name)
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, f in if !f { commit() } }
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: 0)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete category (keeps its colors and type styles)")
        }
        .opacity(isDragging ? 0.4 : 1)
        .onAppear { name = category.name }
        .onChange(of: category.name) { _, n in if !focused { name = n } }
    }

    private func commit() {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != category.name { onRename(t) }
    }
}

/// One reusable type treatment: a live face preview, concise values, inline
/// rename, shared category assignment, and delete. Typography values themselves
/// are updated from a selected text layer so this surface never invents content.
private struct DLTypeStyleRow: View {
    let style: TypeStyle
    let categories: [DLCategory]
    let onRename: (String) -> Void
    let onSetCategory: (UUID?) -> Void
    let onDelete: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private var categoryLabel: String {
        categories.first { $0.id == style.categoryID }?.name ?? "Other"
    }

    private var previewFont: Font {
        let size = min(max(style.fontSize, 11), 18)
        return style.fontName.isEmpty
            ? .system(size: size)
            : .custom(style.fontName, fixedSize: size)
    }

    private var details: String {
        var parts = [style.fontName.isEmpty ? "System" : style.fontName,
                     "\(format(style.fontSize)) pt"]
        switch style.lineHeightUnit {
        case .auto: break
        case .multiple: parts.append("line \(format(style.lineHeight))×")
        case .px: parts.append("line \(format(style.lineHeight)) pt")
        case .em: parts.append("line \(format(style.lineHeight)) em")
        }
        if style.tracking != 0 { parts.append("tracking \(format(style.tracking))") }
        if style.align != .left { parts.append(style.align.rawValue.capitalized) }
        if style.textCase != .none { parts.append(style.textCase.rawValue.capitalized) }
        if style.underline { parts.append("Underline") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                TextField(style.fallbackLabel, text: $name)
                    .font(previewFont)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(details)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Other") { onSetCategory(nil) }
                if !categories.isEmpty { Divider() }
                ForEach(categories) { category in
                    Button {
                        onSetCategory(category.id)
                    } label: {
                        if style.categoryID == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
            } label: {
                Text(categoryLabel).frame(minWidth: 84)
            }
            .fixedSize()
            .accessibilityLabel("Category")
            .accessibilityValue(categoryLabel)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete type style")
                .accessibilityLabel("Delete \(name.isEmpty ? style.fallbackLabel : name) type style")
        }
        .onAppear { name = style.name }
        .onChange(of: style.name) { _, newName in if !focused { name = newName } }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != style.name { onRename(trimmed) }
    }

    private func format(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", Double(value))
    }
}

/// Drop target for reordering categories by dragging their grip.
private struct CategoryDrop: DropDelegate {
    let targetID: UUID
    @Binding var dragging: UUID?
    let move: (UUID, Bool) -> Void   // (draggedID, insertBefore)

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = dragging else { return false }
        move(dragged, info.location.y < 15)   // top half of the row = insert before
        dragging = nil
        return true
    }
}

/// One entry: swatch + inline-rename + category menu + delete.
private struct DLEntryRow: View {
    let asset: DesignAsset
    let categories: [DLCategory]
    let value: String
    let isReadOnly: Bool
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onRename: (String) -> Void
    let onSetCategory: (UUID?) -> Void
    let onDelete: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private var categoryLabel: String {
        categories.first { $0.id == asset.categoryID }?.name ?? "Other"
    }

    private var canEdit: Bool {
        !isReadOnly
    }

    private var swatch: some View {
        PaintSwatch(paint: asset.value).frame(width: 30, height: 20)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if canEdit {
                    Button(action: onEdit) { swatch }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(asset.name.isEmpty ? "saved color" : asset.name)")
                        .help(asset.value.savedPaintEditLabel)
                } else {
                    swatch
                        .overlay(alignment: .bottomTrailing) {
                            if isReadOnly { Image(systemName: "lock.fill").font(.caption2) }
                        }
                        .accessibilityLabel(isReadOnly ? "Read-only library color" : "Gradient preview")
                        .help(isReadOnly ? "Edit the source token this alias points to" : "Gradient preview")
                }
            }
            .frame(width: 34)
            .contextMenu {
                if canEdit { Button(asset.value.savedPaintEditLabel, action: onEdit) }
                Button("Copy Value", action: onCopy)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder).frame(minWidth: 76, maxWidth: .infinity)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, f in if !f { commit() } }
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("dl.value.\(asset.id.uuidString)")
                    .help(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy value for \(asset.name.isEmpty ? "unnamed swatch" : asset.name)")
                    .help("Copy Value")
            }
            .frame(minWidth: 145, maxWidth: .infinity, alignment: .leading)
            .clipped()
            Menu {
                Button("Other") { onSetCategory(nil) }
                if !categories.isEmpty { Divider() }
                ForEach(categories) { c in
                    Button {
                        onSetCategory(c.id)
                    } label: {
                        if asset.categoryID == c.id { Label(c.name, systemImage: "checkmark") }
                        else { Text(c.name) }
                    }
                }
            } label: {
                Text(categoryLabel).lineLimit(1)
            }
            .frame(width: 96)
            .accessibilityLabel("Category")
            .accessibilityValue(categoryLabel)
            .accessibilityIdentifier("dl.category.\(asset.id.uuidString)")
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .frame(width: 24)
                .accessibilityLabel("Delete swatch")
        }
        .onAppear { name = asset.name }
        .onChange(of: asset.name) { _, n in if !focused { name = n } }
    }

    private func commit() {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != asset.name { onRename(t) }
    }
}

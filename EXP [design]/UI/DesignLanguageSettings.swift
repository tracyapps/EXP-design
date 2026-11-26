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
            .padding(24)
        }
    }
}

// MARK: - Editor

private struct DesignLanguageEditor: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?

    @AppStorage(AppPreferences.showDesignLanguageCode) private var showsCode = false
    @State private var draftPaint: Paint = .solid(RGBAColor(r: 0.55, g: 0.55, b: 0.6, a: 1))
    @State private var draftName = ""
    @State private var draftCategory: UUID?
    @State private var newCategoryName = ""
    @State private var pasteText = ""
    @State private var showingPaste = false
    @State private var showingMatchingStyles = false
    @State private var mergeMode: DesignLanguage.MergeMode = .keepBoth
    @State private var draggingCategory: UUID?
    @State private var editingColor: PaintEdit?
    @State private var sortOrder = [DLPaletteSort(column: .category)]
    @AppStorage("exp.dl.settingsPaletteColumns") private var paletteColumns: TableColumnCustomization<DLPaletteRow>
    @AppStorage("exp.dl.settingsColorFormat") private var colorFormat: ColorFormat = .hex

    private var dl: DesignLanguage { document.model.designLanguage }
    private var colorModes: [DLMode] { dl.colorModeSet?.modes ?? [] }

    private struct PaintEdit: Identifiable {
        let asset: DesignAsset
        let selection: DLSavedColorEditorMode
        var id: UUID { asset.id }
    }

    private func valueString(_ paint: Paint) -> String {
        if case .solid(let color) = paint { return ColorMath.string(color, colorFormat) }
        return DesignLanguageIO.css(for: paint)
    }

    private func paletteRows(modes: [DLMode]) -> [DLPaletteRow] {
        let rank = Dictionary(uniqueKeysWithValues: dl.categories.enumerated().map { ($1.id, $0) })
        let links = document.model.libraryTokenLinks
        let language = dl
        return language.assets.map { asset in
            let colors = modes.map { mode in
                let paint = language.paint(for: asset, in: mode.id)
                return (mode.id, DLPaletteModeValue(paint: paint, text: valueString(paint)))
            }
            return DLPaletteRow(asset: asset, base: valueString(asset.value),
                                categoryRank: asset.categoryID.flatMap { rank[$0] } ?? Int.max,
                                modes: Dictionary(colors, uniquingKeysWith: { first, _ in first }),
                                isReadOnly: links[asset.id]?.writable == false)
        }.sorted(using: sortOrder + [DLPaletteSort(column: .name)])
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
        VStack(alignment: .leading, spacing: 16) {
            Picker("Design Language view", selection: $showsCode) {
                Text("Table").tag(false)
                Text("Code").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("designLanguage.view")
            .padding(.horizontal, 24)
            .padding(.top, 14)

            if showsCode {
                DesignLanguageCodeEditor(document: document, undoManager: undoManager,
                                         session: document.designLanguageCodeSession)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            } else {
                ScrollView {
                    tableView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tableView: some View {
        VStack(alignment: .leading, spacing: 24) {
            DLColorModeSettingsGroup(document: document, undoManager: undoManager)
            HStack {
                Button("Link Matching Styles…") { showingMatchingStyles = true }
                    .disabled(dl.assets.isEmpty && dl.typeStyles.isEmpty)
                Button("Open Guide", systemImage: "book") {
                    let hub = PanelHub.shared
                    let title = hub.activeDocument === document
                        ? hub.activeFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
                        : "Untitled"
                    DesignLanguageGuideWindow.show(document: document, title: title)
                }
            }
            .sheet(isPresented: $showingMatchingStyles) {
                DLMatchingStylesSheet(document: document, undoManager: undoManager)
            }
            entriesGroup
            addGroup
            categoriesGroup
            importExportGroup
            typeStylesGroup
            ForEach(DLDimensionKind.allCases) { kind in
                DLDimensionSettingsGroup(kind: kind, document: document, undoManager: undoManager)
            }
        }
        .sheet(isPresented: $showingPaste) { pasteSheet }
        .sheet(item: $editingColor) { edit in
            DLSavedColorEditor(document: document, asset: edit.asset, undoManager: undoManager, startingIn: edit.selection)
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
                Button(dl.colorMode().map { "Copy CSS (\($0.name))" } ?? "Copy CSS") {
                    copy(DesignLanguageIO.exportCSS(DesignLanguageIO.paletteSnapshot(dl)))
                }
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
        SettingsGroup("Colors & Gradients (\(dl.assets.count))",
                      footnote: colorModes.isEmpty ? nil : "Base is shared by all modes. Edit a mode cell to override it.") {
            if dl.assets.isEmpty {
                Text("Nothing saved yet.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Picker("Color format", selection: $colorFormat) {
                        ForEach(ColorFormat.allCases) { format in
                            Text(format == .rgba ? "RGB/A" : format.rawValue).tag(format)
                        }
                    }
                    .fixedSize()
                }
                entriesTable
            }
        }
    }

    // A native Table owns both scroll axes. Its headers stay with its viewport
    // and its stable column IDs let macOS restore the user's arrangement.
    private var entriesTable: some View {
        let modes = colorModes
        let rows = paletteRows(modes: modes)
        let rowHeight = EXPInterfaceAccessibility.shared.targetHeight(30)
        return Table(rows, sortOrder: $sortOrder, columnCustomization: $paletteColumns) {
            TableColumn("Name", sortUsing: DLPaletteSort(column: .name)) { row in
                DLPaletteNameCell(asset: row.asset) { name in
                    commit("Rename Swatch") { $0.rename(row.id, to: name) }
                }
            }
            .width(min: 95, ideal: 220)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn(modes.isEmpty ? "Value" : "Base", sortUsing: DLPaletteSort(column: .base)) { row in
                DLPaletteBaseCell(row: row,
                                  onEdit: { editingColor = PaintEdit(asset: row.asset, selection: .base) },
                                  onCopy: { copy(row.base) })
            }
            .width(min: 120, ideal: 230)
            .customizationID("base")
            .disabledCustomizationBehavior(.visibility)

            TableColumnForEach(modes) { mode in
                TableColumn(mode.name, sortUsing: DLPaletteSort(column: .mode(mode.id))) { row in
                    modeCell(row, mode: mode)
                }
                .width(min: 92, ideal: 142)
                .customizationID("mode.\(mode.id.uuidString)")
                .disabledCustomizationBehavior(.visibility)
            }

            TableColumn("Category", sortUsing: DLPaletteSort(column: .category)) { row in
                categoryMenu(selection: Binding(
                    get: { dl.asset(row.id)?.categoryID },
                    set: { id in commit("Set Category") { $0.setCategory(row.id, to: id) } }
                ), fillsColumn: true)
                .accessibilityLabel("Category")
                .accessibilityValue(dl.category(row.asset.categoryID)?.name ?? "Other")
                .accessibilityIdentifier("dl.category.\(row.id.uuidString)")
            }
            .width(min: 96, ideal: 150)
            .customizationID("category")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Actions") { row in
                Button(role: .destructive) {
                    deleteDesignLanguageAsset(row.id, name: row.asset.name.isEmpty ? "Unnamed Swatch" : row.asset.name,
                                              typeStyle: false, document: document, undoManager: undoManager)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete swatch")
            }
            .width(min: 60, ideal: 68, max: 105)
            .customizationID("actions")
            .disabledCustomizationBehavior(.visibility)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { viewportHeight, _ in
            min(CGFloat(rows.count) * (rowHeight + 6) + 44, max(180, viewportHeight * 0.7))
        }
        .accessibilityLabel("Colors and gradients")
    }

    private func modeCell(_ row: DLPaletteRow, mode: DLMode) -> DLModePaintCell {
        let asset = row.asset
        let value = row.modes[mode.id] ?? DLPaletteModeValue(paint: asset.value, text: row.base)
        let inherited = asset.modeValues[mode.id.uuidString] == nil
        let edit: (() -> Void)?
        if case .solid = asset.value, !row.isReadOnly {
            edit = { editingColor = PaintEdit(asset: asset, selection: .override(mode.id)) }
        } else { edit = nil }
        return DLModePaintCell(modeName: mode.name, assetName: asset.name,
                               paint: value.paint, value: value.text, inheritsBase: inherited,
                               edit: edit, copy: { copy(value.text) })
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
                            deleteDesignLanguageAsset(style.id, name: style.name.isEmpty ? style.fallbackLabel : style.name,
                                                      typeStyle: true, document: document, undoManager: undoManager)
                        })
                    Divider().opacity(0.4)
                }
            }
        }
    }

    // MARK: Category menu (shared by add + rows)

    private func categoryMenu(selection: Binding<UUID?>, fillsColumn: Bool = false) -> some View {
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
            Text(dl.category(selection.wrappedValue)?.name ?? "Other").lineLimit(1)
        }
        .fixedSize(horizontal: !fillsColumn, vertical: true)
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
        panel.message = dl.colorMode().map { "Exports the \($0.name) palette. The EXP document keeps all color modes." }
            ?? "Export this document's design language as EXP JSON."
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

private nonisolated struct DLPaletteModeValue: Sendable {
    let paint: Paint
    let text: String
}

private nonisolated struct DLPaletteRow: Identifiable, Sendable {
    let asset: DesignAsset
    let base: String
    let categoryRank: Int
    let modes: [UUID: DLPaletteModeValue]
    let isReadOnly: Bool
    var id: UUID { asset.id }
}

private nonisolated struct DLPaletteSort: SortComparator {
    enum Column: Hashable {
        case name, base, category, mode(UUID)
    }
    let column: Column
    var order: SortOrder = .forward

    func compare(_ lhs: DLPaletteRow, _ rhs: DLPaletteRow) -> ComparisonResult {
        let result: ComparisonResult
        switch column {
        case .name:
            result = lhs.asset.name.localizedStandardCompare(rhs.asset.name)
        case .base:
            result = lhs.base.localizedStandardCompare(rhs.base)
        case .category:
            if lhs.categoryRank == rhs.categoryRank { return .orderedSame }
            result = lhs.categoryRank < rhs.categoryRank ? .orderedAscending : .orderedDescending
        case .mode(let id):
            let first = lhs.modes[id]?.text ?? lhs.base
            let second = rhs.modes[id]?.text ?? rhs.base
            result = first.localizedStandardCompare(second)
        }
        guard order == .reverse, result != .orderedSame else { return result }
        return result == .orderedAscending ? .orderedDescending : .orderedAscending
    }
}

private struct DLPaletteNameCell: View {
    let asset: DesignAsset
    let onRename: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Swatch name", text: $name)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, focused in if !focused { commit() } }
            .onAppear { name = asset.name }
            .onChange(of: asset.name) { _, updated in if !focused { name = updated } }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != asset.name { onRename(trimmed) }
    }
}

private struct DLPaletteBaseCell: View {
    let row: DLPaletteRow
    let onEdit: () -> Void
    let onCopy: () -> Void

    private var name: String { row.asset.name.isEmpty ? "saved color" : row.asset.name }
    private var swatch: some View {
        PaintSwatch(paint: row.asset.value).frame(width: 28, height: 18)
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if row.isReadOnly {
                    swatch
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                        .accessibilityLabel("Read-only library color")
                        .help("Edit the source token this alias points to")
                } else {
                    Button(action: onEdit) { swatch }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(name)")
                        .help(row.asset.value.savedPaintEditLabel)
                }
            }
            .layoutPriority(1)
            Text(row.base)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityIdentifier("dl.value.\(row.id.uuidString)")
                .help(row.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy value for \(name)")
                .help("Copy Value")
                .layoutPriority(1)
        }
        .clipped()
        .contextMenu {
            if !row.isReadOnly { Button(row.asset.value.savedPaintEditLabel, action: onEdit) }
            Button("Copy Value", action: onCopy)
        }
    }
}

private struct DLModePaintCell: View {
    let modeName: String
    let assetName: String
    let paint: Paint
    let value: String
    let inheritsBase: Bool
    let edit: (() -> Void)?
    let copy: () -> Void

    private var label: String { "\(assetName.isEmpty ? "Unnamed swatch" : assetName), \(modeName)" }
    private var detail: String { inheritsBase ? "Uses Base, \(value)" : value }

    var body: some View {
        Group {
            if let edit {
                Button(action: edit) { cell }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(label)")
                    .accessibilityValue(detail)
            } else {
                cell.accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .help(detail)
        .contextMenu {
            if let edit { Button("Edit \(modeName) Value…", action: edit) }
            Button("Copy Value", action: copy)
        }
    }

    private var cell: some View {
        HStack(spacing: 4) {
            PaintSwatch(paint: paint).frame(width: 20, height: 14)
            Text(inheritsBase ? "Uses Base" : value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

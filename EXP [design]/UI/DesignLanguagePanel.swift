//
//  DesignLanguagePanel.swift
//  EXP [design]
//
//  Phase 18d + refinements — the document-local Design Language panel. Colors and
//  gradients are the two visual sections; USER-DEFINED categories (Primary,
//  Secondary, Accent, ...) are cross-cutting filter pills along the top. A category
//  can hold both colors and gradients. Entries with no category show under "Other"
//  once any category exists; with no categories at all, everything is just Colors /
//  Gradients. Every mutation goes through `document.setModel`, so it's all undoable.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// How the Design Language panel lays out its entries. Grows later (typography,
/// other tokens) — the sticky bottom bar has room for more view settings.
enum DLViewMode: String, CaseIterable { case swatches, list }

struct DesignLanguagePanel: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings

    @State private var renaming: DesignAsset?
    @State private var renameDraft = ""
    @State private var renamingStyle: TypeStyle?
    @State private var styleRenameDraft = ""
    @State private var assignStyleAfterCreate: UUID?
    @State private var creatingCategory = false
    @State private var categoryDraft = ""
    @State private var assignAfterCreate: UUID?
    @State private var renamingCategory: DLCategory?
    @State private var categoryRenameDraft = ""
    /// Categories hidden from view. Empty = all shown; new categories appear by
    /// default (they're simply not in this set yet).
    @State private var hiddenCategories: Set<UUID> = []
    @State private var showingPaste = false
    @State private var pasteText = ""
    @State private var showingTransfer = false
    @State private var transferMode: DLTransferMode = .importing
    @State private var mergeMode: DesignLanguage.MergeMode = .keepBoth
    @State private var showingGenerate = false
    @State private var seed: RGBAColor = .black
    @AppStorage("exp.dl.viewMode") private var viewMode: DLViewMode = .swatches

    private var dl: DesignLanguage { document.model.designLanguage }
    private let grid = [GridItem(.adaptive(minimum: 34, maximum: 46), spacing: 8)]
    private let recentGrid = [GridItem(.adaptive(minimum: 18, maximum: 24), spacing: 5)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .bottom) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    Divider()
                    viewOptionsBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Rename swatch", isPresented: renameActive) {
            TextField("Name", text: $renameDraft)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Rename type style", isPresented: styleRenameActive) {
            TextField("Name", text: $styleRenameDraft)
            Button("Save") { commitRenameStyle() }
            Button("Cancel", role: .cancel) { renamingStyle = nil }
        }
        .alert("New category", isPresented: $creatingCategory) {
            TextField("Category name", text: $categoryDraft)
            Button("Create") { commitNewCategory() }
            Button("Cancel", role: .cancel) { assignAfterCreate = nil }
        }
        .alert("Rename category", isPresented: categoryRenameActive) {
            TextField("Name", text: $categoryRenameDraft)
            Button("Save") { commitRenameCategory() }
            Button("Cancel", role: .cancel) { renamingCategory = nil }
        }
        .sheet(isPresented: $showingPaste) { pasteSheet }
        .sheet(isPresented: $showingTransfer) {
            DesignLanguageTransferSheet(document: document, mode: transferMode)
        }
        .sheet(isPresented: $showingGenerate) { generateSheet }
    }

    @ViewBuilder private var content: some View {
        if dl.assets.isEmpty && dl.typeStyles.isEmpty && dl.recents.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    typeSection("Colors", dl.solids)
                    typeSection("Gradients", dl.gradients)
                    typeStylesSection
                    recentsSection
                }
                .padding(10)
                .padding(.bottom, 38)
            }
        }
    }

    /// Sticky bottom bar for view settings (swatches / list, room for more later).
    private var viewOptionsBar: some View {
        HStack(spacing: 8) {
            // Design-system segmented control (accent selection), not the stock
            // grey picker — matches the app's primary controls.
            EXPSegmented(selection: $viewMode, segments: [
                .init(value: DLViewMode.swatches, icon: "square.grid.2x2",
                      accessibilityLabel: "View as swatches"),
                .init(value: DLViewMode.list, icon: "list.bullet",
                      accessibilityLabel: "View as list"),
            ])
            .fixedSize()
            .help("View as swatches or list")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(EXPColor.surfaceToolbar)
    }

    // MARK: Toolbar — wrapping category pills (leading) + stationary actions

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if dl.hasCategories {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(dl.categories) { cat in
                            FilterPill(label: cat.name,
                                       count: dl.count(in: cat.id),
                                       active: !hiddenCategories.contains(cat.id),
                                       action: { toggleCategoryFilter(cat.id) },
                                       onRename: { categoryRenameDraft = cat.name; renamingCategory = cat },
                                       onDelete: {
                                           hiddenCategories.remove(cat.id)
                                           commit("Delete Category") { $0.removeCategory(cat.id) }
                                       })
                        }
                        Button {
                            categoryDraft = ""; assignAfterCreate = nil; creatingCategory = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .background(Capsule().fill(EXPColor.rowHover))
                                .foregroundStyle(EXPColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("New category")
                    }
                } else {
                    Text("\(dl.assets.count + dl.typeStyles.count) saved")
                        .font(.system(size: EXPType.micro))
                        .foregroundStyle(EXPColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    // arrow.up.arrow.down: bidirectional on purpose — the old
                    // square.and.arrow.up is the system SHARE/export glyph and
                    // undersold that importing lives here too.
                    Menu { importExportMenu } label: { Image(systemName: "arrow.up.arrow.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Import or export the design language")
                        .accessibilityLabel("Import or export the design language")
                    Button(action: saveFromSelection) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(EXPColor.accent)
                    .disabled(addableSelectionFills.isEmpty && addableSelectionTypeStyles.isEmpty)
                    .help(addHelp)
                }
                Button {
                    UserDefaults.standard.set("designLanguage", forKey: AppPreferences.requestedSettingsPane)
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.expCompact())
                .help("Open the Design Language editor in Settings")
            }
            .fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    @ViewBuilder private var importExportMenu: some View {
        // v1.3: the transfer sheet replaces the old pile of dropdown items
        // (Paste Palette / Import from File / Export JSON / Copy CSS) — those
        // flows live INSIDE the sheet now, with room for format options and a
        // real preview.
        Button("Import…") { transferMode = .importing; showingTransfer = true }
        Button("Export…") { transferMode = .exporting; showingTransfer = true }
        Divider()
        Button("Generate from Color...") { seed = generatorSeed(); showingGenerate = true }
        Button("New Category...") { categoryDraft = ""; assignAfterCreate = nil; creatingCategory = true }
        Divider()
        Button("Save Type Style from Selection") { saveTypeStyleFromSelection() }
            .disabled(selectedTextContent == nil)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "swatchpalette")
                .font(.system(size: 26)).foregroundStyle(EXPColor.textTertiary)
            Text("No saved colors yet").font(.expLabel).foregroundStyle(EXPColor.textSecondary)
            Text("Select a shape and press Add to save its fill. Colors you apply from here also collect under Recents.")
                .font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: Sections (type first, then category clusters within)

    private struct Cluster { let key: String; let label: String; let items: [DesignAsset] }

    /// Group a type's items by category, honoring the pill filter. Uncategorized
    /// ("Other") is always shown and has no pill.
    private func clusters(for items: [DesignAsset]) -> [Cluster] {
        guard dl.hasCategories else {
            return items.isEmpty ? [] : [Cluster(key: "all", label: "", items: items)]
        }
        var out: [Cluster] = []
        for cat in dl.categories where !hiddenCategories.contains(cat.id) {
            let group = items.filter { $0.categoryID == cat.id }
            if !group.isEmpty { out.append(Cluster(key: cat.id.uuidString, label: cat.name, items: group)) }
        }
        let other = items.filter { $0.categoryID == nil }
        if !other.isEmpty { out.append(Cluster(key: "other", label: DesignLanguage.otherLabel, items: other)) }
        return out
    }

    @ViewBuilder private func typeSection(_ title: String, _ items: [DesignAsset]) -> some View {
        let groups = clusters(for: items)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title, items.count)
                ForEach(groups, id: \.key) { cluster in
                    VStack(alignment: .leading, spacing: 6) {
                        if !cluster.label.isEmpty {
                            Text(cluster.label)
                                .font(.system(size: EXPType.micro, weight: .medium))
                                .foregroundStyle(EXPColor.textTertiary)
                        }
                        switch viewMode {
                        case .swatches:
                            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                                ForEach(cluster.items) { assetCell($0) }
                            }
                        case .list:
                            VStack(spacing: 4) {
                                ForEach(cluster.items) { assetListRow($0) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var recentsSection: some View {
        if !dl.recents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Recents", dl.recents.count)
                switch viewMode {
                case .swatches:
                    LazyVGrid(columns: recentGrid, alignment: .leading, spacing: 5) {
                        ForEach(Array(dl.recents.enumerated()), id: \.offset) { _, paint in
                            PaintSwatch(paint: paint)
                                .frame(width: 22, height: 16)
                                .onTapGesture(count: 2) { apply(paint) }
                                .contextMenu { recentMenu(paint) }
                                .help("Double-click to apply")
                        }
                    }
                case .list:
                    VStack(spacing: 4) {
                        ForEach(Array(dl.recents.enumerated()), id: \.offset) { _, paint in
                            recentListRow(paint)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: EXPType.micro, weight: .semibold))
                .tracking(EXPType.tracking(EXPType.trCaps, EXPType.micro))
                .foregroundStyle(EXPColor.textSecondary)
            Text("\(count)")
                .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Type styles section (v1.3)

    private struct StyleCluster { let key: String; let label: String; let items: [TypeStyle] }

    /// Same category clustering as colors/gradients — categories are cross-cutting.
    private func styleClusters(_ items: [TypeStyle]) -> [StyleCluster] {
        guard dl.hasCategories else {
            return items.isEmpty ? [] : [StyleCluster(key: "all", label: "", items: items)]
        }
        var out: [StyleCluster] = []
        for cat in dl.categories where !hiddenCategories.contains(cat.id) {
            let group = items.filter { $0.categoryID == cat.id }
            if !group.isEmpty { out.append(StyleCluster(key: cat.id.uuidString, label: cat.name, items: group)) }
        }
        let other = items.filter { $0.categoryID == nil }
        if !other.isEmpty { out.append(StyleCluster(key: "other", label: DesignLanguage.otherLabel, items: other)) }
        return out
    }

    @ViewBuilder private var typeStylesSection: some View {
        let groups = styleClusters(dl.typeStyles)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Type Styles", dl.typeStyles.count)
                ForEach(groups, id: \.key) { cluster in
                    VStack(alignment: .leading, spacing: 6) {
                        if !cluster.label.isEmpty {
                            Text(cluster.label)
                                .font(.system(size: EXPType.micro, weight: .medium))
                                .foregroundStyle(EXPColor.textTertiary)
                        }
                        VStack(spacing: 4) {
                            ForEach(cluster.items) { typeStyleRow($0) }
                        }
                    }
                }
            }
        }
    }

    /// One type-style row: the style name PREVIEWED in its own face (display
    /// size capped so big display styles don't blow up the panel; the real size
    /// shows in the detail line). List layout only — type is inherently textual.
    private func typeStyleRow(_ style: TypeStyle) -> some View {
        let title = style.name.isEmpty ? style.fallbackLabel : style.name
        let previewSize = min(max(style.fontSize, 11), 18)
        let previewFont: Font = style.fontName.isEmpty
            ? .system(size: previewSize)
            : .custom(style.fontName, fixedSize: previewSize)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(previewFont)
                    .underline(style.underline)
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(1)
                Text(typeStyleDetail(style))
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "textformat")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(EXPColor.textTertiary)
                .help("Double-click to apply")
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: EXPMetric.radiusRow).fill(EXPColor.rowHover.opacity(0.45)))
        .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
        .onTapGesture(count: 2) { applyTypeStyle(style) }
        .contextMenu { typeStyleMenu(style) }
        .help("\(title) — \(typeStyleDetail(style)) · double-click to apply")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), type style, \(typeStyleDetail(style))")
    }

    private func typeStyleDetail(_ style: TypeStyle) -> String {
        let face = style.fontName.isEmpty ? "System" : style.fontName
        var parts = ["\(face) \(Int(style.fontSize.rounded()))pt"]
        switch style.lineHeightUnit {
        case .auto: break
        case .multiple: parts.append("lh \(style.lineHeight)")
        case .px:       parts.append("lh \(Int(style.lineHeight.rounded()))px")
        case .em:       parts.append("lh \(style.lineHeight)em")
        }
        if style.tracking != 0 { parts.append("tracking \(style.tracking)") }
        if let cat = dl.category(style.categoryID) { parts.insert(cat.name, at: 0) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func typeStyleMenu(_ style: TypeStyle) -> some View {
        Button("Apply to Selection") { applyTypeStyle(style) }
            .disabled(app.selectedNodeIDs.isEmpty)
        Button("Update from Selection") { updateTypeStyleFromSelection(style) }
            .disabled(selectedTextContent == nil)
        Divider()
        Menu("Category") {
            Button("Other") { commit("Set Category") { $0.setTypeStyleCategory(style.id, to: nil) } }
                .disabled(style.categoryID == nil)
            if !dl.categories.isEmpty { Divider() }
            ForEach(dl.categories) { cat in
                Button {
                    commit("Set Category") { $0.setTypeStyleCategory(style.id, to: cat.id) }
                } label: {
                    if style.categoryID == cat.id { Label(cat.name, systemImage: "checkmark") }
                    else { Text(cat.name) }
                }
            }
            Divider()
            Button("New Category...") {
                categoryDraft = ""; assignStyleAfterCreate = style.id; creatingCategory = true
            }
        }
        Button("Rename...") { styleRenameDraft = style.name; renamingStyle = style }
        Button("Copy as CSS") {
            var solo = dl; solo.typeStyles = [style]
            copy(DesignLanguageIO.cssTypeStyles(solo))
        }
        Divider()
        Button("Delete", role: .destructive) { commit("Delete Type Style") { $0.removeTypeStyle(style.id) } }
    }

    // MARK: Type style apply / save

    /// The single selected TEXT layer's content, if any (capture source).
    private var selectedTextContent: (name: String, content: TextContent)? {
        guard let id = app.singleSelectedNodeID else { return nil }
        var found: (String, TextContent)?
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if n.id == id, case .text(let tc) = n.content { found = (n.name, tc); return }
                if case .group(let kids) = n.content { walk(kids) }
            }
        }
        walk(document.model.page(for: app.activeCanvasPageID)?.nodes ?? [])
        return found
    }

    /// Apply to every selected text layer (nested included), re-hugging frames —
    /// the same rule as canvas text styling ops. One undo step.
    private func applyTypeStyle(_ style: TypeStyle) {
        let ids = app.selectedNodeIDs
        guard !ids.isEmpty else { return }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
        func walk(_ nodes: inout [Node]) {
            for i in nodes.indices {
                if ids.contains(nodes[i].id), case .text(var tc) = nodes[i].content {
                    style.apply(to: &tc)
                    nodes[i].content = .text(tc)
                    nodes[i].frame.size = tc.measuredSize(boxWidth: nodes[i].frame.width)
                }
                if case .group(var kids) = nodes[i].content {
                    walk(&kids); nodes[i].content = .group(children: kids)
                }
            }
        }
        walk(&model.pages[pageIndex].nodes)
        model.pages[pageIndex].nodes = model.reflowed(model.pages[pageIndex].nodes)
        document.setModel(model, undoManager: undoManager, actionName: "Apply Type Style")
    }

    private func saveTypeStyleFromSelection() {
        guard let sel = selectedTextContent else { return }
        commit("Save Type Style") {
            $0.saveTypeStyle(TypeStyle.capture(from: sel.content, name: sel.name))
        }
    }

    /// Re-capture an existing style's VALUES from the selected text layer,
    /// keeping its identity, name, and category.
    private func updateTypeStyleFromSelection(_ style: TypeStyle) {
        guard let sel = selectedTextContent else { return }
        commit("Update Type Style") {
            $0.setTypeStyleValues(style.id, from: TypeStyle.capture(from: sel.content))
        }
    }

    private var styleRenameActive: Binding<Bool> {
        Binding(get: { renamingStyle != nil }, set: { if !$0 { renamingStyle = nil } })
    }

    private func commitRenameStyle() {
        guard let s = renamingStyle else { return }
        let name = styleRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        commit("Rename Type Style") { $0.renameTypeStyle(s.id, to: name) }
        renamingStyle = nil
    }

    // MARK: Swatch cell + menus

    private func assetCell(_ asset: DesignAsset) -> some View {
        PaintSwatch(paint: asset.value)
            .frame(height: 30)
            .onTapGesture(count: 2) { apply(asset.value) }
            .contextMenu { assetMenu(asset) }
            .help(assetHelp(asset))
    }

    private func assetListRow(_ asset: DesignAsset) -> some View {
        HStack(spacing: 8) {
            PaintSwatch(paint: asset.value)
                .frame(width: 30, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(asset.name.isEmpty ? "Unnamed" : asset.name)
                    .font(.system(size: EXPType.small, weight: .medium))
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(1)
                Text(assetListDetail(asset))
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(EXPColor.textTertiary)
                .help("Double-click to apply")
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: EXPMetric.radiusRow).fill(EXPColor.rowHover.opacity(0.45)))
        .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
        .onTapGesture(count: 2) { apply(asset.value) }
        .contextMenu { assetMenu(asset) }
        .help(assetHelp(asset))
    }

    private func recentListRow(_ paint: Paint) -> some View {
        HStack(spacing: 6) {
            PaintSwatch(paint: paint)
                .frame(width: 20, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recent")
                    .font(.system(size: EXPType.mini, weight: .medium))
                    .foregroundStyle(EXPColor.textSecondary)
                Text(paintListValue(paint))
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: EXPMetric.radiusRow).fill(EXPColor.rowHover.opacity(0.28)))
        .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
        .onTapGesture(count: 2) { apply(paint) }
        .contextMenu { recentMenu(paint) }
        .help("Double-click to apply")
    }

    private func assetListDetail(_ asset: DesignAsset) -> String {
        let value = paintListValue(asset.value)
        let category = dl.categoryLabel(for: asset)
        return category.isEmpty ? value : "\(category) · \(value)"
    }

    private func paintListValue(_ paint: Paint) -> String {
        paint.isGradient ? "Gradient" : ColorMath.string(paint.representativeColor, .hex)
    }

    private func assetHelp(_ asset: DesignAsset) -> String {
        let name = asset.name.isEmpty ? "Unnamed" : asset.name
        let value = asset.value.isGradient ? "gradient" : ColorMath.string(asset.representativeColor, .hex)
        let cat = dl.categoryLabel(for: asset)
        let catPart = cat.isEmpty ? "" : " · \(cat)"
        return "\(name) — \(value)\(catPart) · double-click to apply"
    }

    @ViewBuilder private func assetMenu(_ asset: DesignAsset) -> some View {
        Button("Apply to Selection") { apply(asset.value) }
            .disabled(app.selectedNodeIDs.isEmpty)
        Divider()
        Menu("Category") {
            Button("Other") { commit("Set Category") { $0.setCategory(asset.id, to: nil) } }
                .disabled(asset.categoryID == nil)
            if !dl.categories.isEmpty { Divider() }
            ForEach(dl.categories) { cat in
                Button {
                    commit("Set Category") { $0.setCategory(asset.id, to: cat.id) }
                } label: {
                    if asset.categoryID == cat.id { Label(cat.name, systemImage: "checkmark") }
                    else { Text(cat.name) }
                }
            }
            Divider()
            Button("New Category...") {
                categoryDraft = ""; assignAfterCreate = asset.id; creatingCategory = true
            }
        }
        Button("Rename...") { renameDraft = asset.name; renaming = asset }
        Button("Duplicate") { duplicate(asset) }
        copyMenu(paint: asset.value, name: asset.name)
        Divider()
        Button("Delete", role: .destructive) { commit("Delete Swatch") { $0.remove(asset.id) } }
    }

    @ViewBuilder private func recentMenu(_ paint: Paint) -> some View {
        Button("Apply to Selection") { apply(paint) }
            .disabled(app.selectedNodeIDs.isEmpty)
        Button("Save Color") { commit("Save Color") { $0.save(paint, provenance: "recent") } }
        copyMenu(paint: paint, name: "")
    }

    @ViewBuilder private func copyMenu(paint: Paint, name: String) -> some View {
        Menu("Copy As") {
            if paint.isGradient, let g = paint.gradientValue {
                Button("CSS gradient") { copy(DesignLanguageIO.cssGradient(g)) }
            } else {
                let c = paint.representativeColor
                Button("HEX") { copy(ColorMath.string(c, .hex)) }
                Button("RGB") { copy(ColorMath.string(c, .rgba)) }
                Button("HSL") { copy(ColorMath.string(c, .hsl)) }
                Button("OKLCH") { copy(ColorMath.string(c, .oklch)) }
                Button("CSS variable") { copy(DesignLanguageIO.cssVariable(name: name, paint: paint)) }
            }
        }
    }

    // MARK: Paste + generate sheets

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste Palette").font(.headline)
            Text("A HEX list, CSS variables, or a Coolors URL. Colors import as uncategorized.")
                .font(.caption).foregroundStyle(EXPColor.textSecondary)
            TextEditor(text: $pasteText)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 320, minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EXPColor.borderSoft))
            HStack(spacing: 8) {
                Picker("On conflict", selection: $mergeMode) {
                    ForEach(DesignLanguage.MergeMode.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 230)
                Spacer(minLength: 0)
                Button("Cancel") { showingPaste = false }
                Button("Import") { performPasteImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(DesignLanguageIO.parsePalette(pasteText).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var generateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate Palette").font(.headline)
            Text("Local, offline suggestions from a seed color. Add any set as new colors.")
                .font(.caption).foregroundStyle(EXPColor.textSecondary)
            ColorWell(label: "Seed", color: $seed)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PaletteProviders.all(seed: seed)) { sug in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(sug.title).font(.system(size: EXPType.small, weight: .semibold))
                                Spacer(minLength: 0)
                                Button("Add") { addSuggestion(sug) }.controlSize(.small)
                            }
                            LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
                                ForEach(Array(sug.paints.enumerated()), id: \.offset) { _, paint in
                                    PaintSwatch(paint: paint).frame(height: 26)
                                }
                            }
                            Text(sug.note)
                                .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 260)
            HStack {
                Spacer(minLength: 0)
                Button("Done") { showingGenerate = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Apply / save

    private func apply(_ paint: Paint) {
        let ids = app.selectedNodeIDs
        guard !ids.isEmpty else { return }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
        func walk(_ nodes: inout [Node]) {
            for i in nodes.indices {
                if ids.contains(nodes[i].id) { setFill(&nodes[i], paint) }
                if case .group(var kids) = nodes[i].content {
                    walk(&kids); nodes[i].content = .group(children: kids)
                }
            }
        }
        walk(&model.pages[pageIndex].nodes)
        model.designLanguage.remember(paint)
        document.setModel(model, undoManager: undoManager, actionName: "Apply Color")
    }

    private func setFill(_ node: inout Node, _ p: Paint) {
        switch node.content {
        case .rectangle(var s): s.fill = p; node.content = .rectangle(s)
        case .ellipse(var s):   s.fill = p; node.content = .ellipse(s)
        case .polygon(var s):   s.fill = p; node.content = .polygon(s)
        case .path(var s):      s.fill = p; node.content = .path(s)
        case .text(var t):      t.applyToAllRuns { $0.color = p.representativeColor }; node.content = .text(t)
        case .group:            if node.autoPadding != nil { node.autoPadding?.fill = p }
        default: break
        }
    }

    private func selectionFill() -> Paint? {
        selectionFills().first
    }

    /// The selection EXPANDED: selected nodes plus every descendant of any
    /// selected group (v1.3 owner request — "select the group, add everything
    /// in it, as if each item were selected directly").
    private func selectionFlattened() -> [Node] {
        let ids = app.selectedNodeIDs
        guard !ids.isEmpty else { return [] }
        var roots: [Node] = []
        func find(_ nodes: [Node]) {
            for n in nodes {
                if ids.contains(n.id) { roots.append(n) }
                // Keep descending even inside a selected group, so a nested
                // selection isn't collected twice below (flatten dedupes by id).
                if case .group(let kids) = n.content { find(kids) }
            }
        }
        find(document.model.page(for: app.activeCanvasPageID)?.nodes ?? [])
        var out: [Node] = []
        var seen: Set<UUID> = []
        func flatten(_ n: Node) {
            if seen.insert(n.id).inserted { out.append(n) }
            if case .group(let kids) = n.content { for k in kids { flatten(k) } }
        }
        for n in roots { flatten(n) }
        return out
    }

    private func selectionFills() -> [Paint] {
        var fills: [Paint] = []
        for n in selectionFlattened() {
            if let f = fillOf(n), !fills.contains(f) { fills.append(f) }
        }
        return fills
    }

    /// Type styles in the selection (nested text included) not yet saved —
    /// the same + button adds these alongside fills (v1.3 owner request).
    private var addableSelectionTypeStyles: [TypeStyle] {
        var out: [TypeStyle] = []
        for n in selectionFlattened() {
            guard case .text(let tc) = n.content else { continue }
            let cand = TypeStyle.capture(from: tc, name: n.name)
            if !dl.typeStyles.contains(where: { $0.sameValues(as: cand) }),
               !out.contains(where: { $0.sameValues(as: cand) }) {
                out.append(cand)
            }
        }
        return out
    }

    private func fillOf(_ n: Node) -> Paint? {
        switch n.content {
        case .rectangle(let s): return s.fill
        case .ellipse(let s):   return s.fill
        case .polygon(let s):   return s.fill
        case .path(let s):      return s.fill
        case .text(let t):      return .solid(t.firstRun.color)
        case .group:            return n.autoPadding?.fill
        default:                return nil
        }
    }

    /// Selected fills that are not already saved. Multi-select saves each unique
    /// color/gradient once, matching the user's expectation that Add acts on the
    /// whole selection rather than whichever element was selected last.
    private var addableSelectionFills: [Paint] {
        selectionFills().filter { dl.firstAsset(matching: $0) == nil }
    }

    private var addHelp: String {
        let fills = addableSelectionFills
        let styles = addableSelectionTypeStyles
        if fills.isEmpty && styles.isEmpty {
            return selectionFlattened().isEmpty
                ? "Select shapes or text (or a group of them) to save fills and type styles"
                : "Everything in this selection is already in your design language"
        }
        var parts: [String] = []
        if !fills.isEmpty { parts.append(fills.count == 1 ? "1 fill" : "\(fills.count) fills") }
        if !styles.isEmpty { parts.append(styles.count == 1 ? "1 type style" : "\(styles.count) type styles") }
        return "Add \(parts.joined(separator: " and ")) from the selection (groups included)"
    }

    private func saveFromSelection() {
        let fills = addableSelectionFills
        let styles = addableSelectionTypeStyles
        guard !fills.isEmpty || !styles.isEmpty else { return }
        commit("Add to Design Language") { dl in
            for fill in fills { dl.save(fill, provenance: "selection") }
            for style in styles { dl.saveTypeStyle(style) }
        }
    }

    private func duplicate(_ asset: DesignAsset) {
        var copy = asset
        copy.id = UUID()
        copy.name = asset.name.isEmpty ? "" : asset.name + " copy"
        commit("Duplicate Swatch") { $0.add(copy) }
    }

    // MARK: Rename + category commit

    private func commitRename() {
        guard let a = renaming else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        commit("Rename Swatch") { $0.rename(a.id, to: name) }
        renaming = nil
    }

    private func commitNewCategory() {
        let name = categoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let assign = assignAfterCreate
        let assignStyle = assignStyleAfterCreate
        assignAfterCreate = nil
        assignStyleAfterCreate = nil
        guard !name.isEmpty else { return }
        commit("New Category") { dl in
            let id = dl.ensureCategory(name)
            if let a = assign { dl.setCategory(a, to: id) }
            if let s = assignStyle { dl.setTypeStyleCategory(s, to: id) }
        }
    }

    private func commitRenameCategory() {
        guard let c = renamingCategory else { return }
        let name = categoryRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingCategory = nil
        guard !name.isEmpty else { return }
        commit("Rename Category") { $0.renameCategory(c.id, to: name) }
    }

    private var categoryRenameActive: Binding<Bool> {
        Binding(get: { renamingCategory != nil }, set: { if !$0 { renamingCategory = nil } })
    }

    private func toggleCategoryFilter(_ id: UUID) {
        if hiddenCategories.contains(id) { hiddenCategories.remove(id) } else { hiddenCategories.insert(id) }
    }

    private func commit(_ action: String, _ change: (inout DesignLanguage) -> Void) {
        var model = document.model
        change(&model.designLanguage)
        document.setModel(model, undoManager: undoManager, actionName: action)
    }

    private var renameActive: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: Copy helper

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: Import / export

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
              let data = try? DesignLanguageIO.exportJSON(dl) else { return }
        try? data.write(to: url)
    }

    private func performPasteImport() {
        let assets = DesignLanguageIO.parsePalette(pasteText)
        showingPaste = false
        guard !assets.isEmpty else { return }
        commit("Import Palette") { $0.merge(assets, mode: mergeMode) }
    }

    private func generatorSeed() -> RGBAColor {
        selectionFill()?.representativeColor
            ?? dl.assets.first?.representativeColor
            ?? .black
    }

    private func addSuggestion(_ s: PaletteSuggestion) {
        commit("Add Generated Palette") { dl in
            for paint in s.paints { dl.save(paint, provenance: "generated: \(s.title.lowercased())") }
        }
    }
}

// MARK: - Filter pill

private struct FilterPill: View {
    let label: String
    let count: Int
    let active: Bool
    let action: () -> Void
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                Text("\(count)")
                    .foregroundStyle(active ? EXPColor.accent.opacity(0.75) : EXPColor.textTertiary)
            }
            .font(.system(size: EXPType.micro, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(active ? EXPColor.accentSubtle : EXPColor.rowHover))
            .foregroundStyle(active ? EXPColor.accent : EXPColor.textSecondary)
            .overlay(Capsule().strokeBorder(active ? EXPColor.accent.opacity(0.3) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(active ? "Hide \(label)" : "Show \(label)")
        .contextMenu {
            Button("Rename...") { onRename() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Flow layout (wraps children to multiple lines)

/// A minimal flow layout: lays children left-to-right, wrapping to a new line when
/// the next child won't fit the proposed width. Used for the category filter pills
/// so they wrap while the export/add buttons stay put.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            widest = max(widest, x - spacing)
        }
        let w = maxW.isFinite ? maxW : widest
        return CGSize(width: w, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            sv.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                     anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

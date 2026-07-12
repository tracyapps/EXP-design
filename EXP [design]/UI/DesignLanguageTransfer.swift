//
//  DesignLanguageTransfer.swift
//  EXP [design]
//
//  v1.3 — the Design Language import/export window ("transfer sheet").
//  One resizable sheet, two modes. Replaces the old cramped dropdown items
//  (Paste Palette / Import from File / Export JSON / Copy CSS) so format
//  options get real estate — and a PREVIEW, so people are confident it worked
//  before anything touches the document.
//
//  Import: a forgiving paste area (CSS/SCSS variables, mixed colors + type,
//  .type-* class blocks, bare hex lists, Coolors URLs) with an automatic
//  preview AND a dedicated Preview button (some people want the explicit
//  press — and it guards against a stale preview mid-typing), category
//  assign/create for the whole batch, merge behavior, then one undoable
//  Import. EXP JSON comes in via a file picker on the same screen.
//
//  Export: pick a format (CSS vars, SCSS vars, EXP JSON, W3C Design Tokens,
//  Sketch palette), see the exact generated text live, copy it or save a file.
//
//  App target ONLY (SwiftUI/AppKit UI — not for EXPThumbnail).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Which side of the sheet is active. The menu opens the sheet pre-set, but
/// the toggle inside lets people flip without reopening.
enum DLTransferMode: String, CaseIterable {
    case importing, exporting
    var label: String { self == .importing ? "Import" : "Export" }
}

struct DesignLanguageTransferSheet: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    @State var mode: DLTransferMode

    // ── Import state ──
    @State private var pasteText = ""
    @State private var parsed = DesignLanguageIO.ParsedVariables()
    @State private var mergeMode: DesignLanguage.MergeMode = .keepBoth
    /// nil = no category ("Other"); non-nil = existing category id.
    @State private var importCategoryID: UUID? = nil
    @State private var creatingNewCategory = false
    @State private var newCategoryName = ""

    // ── Export state ──
    @State private var exportFormat: DLExportFormat = .cssVars
    @State private var copied = false

    private var dl: DesignLanguage { document.model.designLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Design Language")
                    .font(.headline)
                Spacer()
                EXPSegmented(selection: $mode, segments: [
                    .init(value: DLTransferMode.importing, label: "Import"),
                    .init(value: .exporting, label: "Export"),
                ])
            }
            Divider()
            if mode == .importing { importView } else { exportView }
            Divider()
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if mode == .importing {
                    Button("Preview") { refreshPreview() }
                        .help("Re-parse the pasted text — useful after lots of edits, so the preview is never stale")
                    Button("Import") { performImport() }
                        .buttonStyle(.borderedProminent)
                        .tint(EXPColor.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsed.isEmpty)
                        .help(importButtonHelp)
                } else {
                    Button(copied ? "Copied ✓" : "Copy to Clipboard") { copyExport() }
                        .disabled(dl.isEmpty)
                    Button("Save File…") { saveExportFile() }
                        .buttonStyle(.borderedProminent)
                        .tint(EXPColor.accent)
                        .disabled(dl.isEmpty)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity,
               minHeight: 480, idealHeight: 560, maxHeight: .infinity)
        .onChange(of: mode) { copied = false }
    }

    // MARK: Import side

    @ViewBuilder private var importView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste CSS or SCSS variables — colors and type together is fine. Extra characters, wrappers, and messy spacing are all tolerated.")
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $pasteText)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 90, idealHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EXPColor.borderSoft))
                .onChange(of: pasteText) { refreshPreview() }   // automatic preview
                .accessibilityLabel("Paste area for CSS or SCSS variables")

            HStack(spacing: 8) {
                Text("Preview").expSectionLabel()
                Text(previewSummary)
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                Spacer()
                Button("Import EXP JSON File…") { importJSONFile() }
                    .controlSize(.small)
                    .help("Bring in a design language exported from another .design document")
            }
            importPreview
                .frame(maxHeight: .infinity)

            // Batch options: category (existing / new) + merge behavior —
            // mirrors the Design Language settings pattern.
            HStack(spacing: 10) {
                Text("Category").font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textSecondary)
                Picker("Category for imported items", selection: $importCategoryID) {
                    Text(dl.hasCategories ? DesignLanguage.otherLabel : "None").tag(UUID?.none)
                    ForEach(dl.categories) { cat in
                        Text(cat.name).tag(UUID?.some(cat.id))
                    }
                }
                .labelsHidden().fixedSize()
                Button(creatingNewCategory ? "Cancel New" : "New…") {
                    creatingNewCategory.toggle()
                    if !creatingNewCategory { newCategoryName = "" }
                }
                .controlSize(.small)
                if creatingNewCategory {
                    TextField("Category name", text: $newCategoryName)
                        .textFieldStyle(.exp)
                        .frame(width: 140)
                        .accessibilityLabel("New category name")
                }
                Spacer()
                Picker("On conflict", selection: $mergeMode) {
                    ForEach(DesignLanguage.MergeMode.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
            }
            .font(.system(size: EXPType.mini))
        }
    }

    /// Swatches + type rows for everything the paste parsed into.
    @ViewBuilder private var importPreview: some View {
        if parsed.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 20)).foregroundStyle(EXPColor.textTertiary)
                Text(pasteText.isEmpty ? "The preview appears here as you paste."
                                       : "Nothing recognizable yet — colors need a value like #4A90D9, rgb(), hsl(), or oklch(); type needs a font shorthand or family.")
                    .font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(EXPColor.surfaceField.opacity(0.5)))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !parsed.assets.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 220), spacing: 6)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(parsed.assets) { asset in
                                HStack(spacing: 6) {
                                    PaintSwatch(paint: asset.value)
                                        .frame(width: 26, height: 18)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(asset.name.isEmpty ? "Unnamed" : asset.name)
                                            .font(.system(size: EXPType.mini, weight: .medium))
                                            .lineLimit(1)
                                        Text(ColorMath.string(asset.representativeColor, .hex))
                                            .font(.system(size: EXPType.micro))
                                            .foregroundStyle(EXPColor.textTertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(EXPColor.rowHover.opacity(0.4)))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Color \(asset.name.isEmpty ? "unnamed" : asset.name), \(ColorMath.string(asset.representativeColor, .hex))")
                            }
                        }
                    }
                    ForEach(parsed.typeStyles) { style in
                        let title = style.name.isEmpty ? style.fallbackLabel : style.name
                        HStack(spacing: 8) {
                            Text(title)
                                .font(style.fontName.isEmpty
                                      ? .system(size: min(max(style.fontSize, 11), 18))
                                      : .custom(style.fontName, fixedSize: min(max(style.fontSize, 11), 18)))
                                .underline(style.underline)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(style.fontName.isEmpty ? "System" : style.fontName) \(Int(style.fontSize.rounded()))pt")
                                .font(.system(size: EXPType.micro))
                                .foregroundStyle(EXPColor.textTertiary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(EXPColor.rowHover.opacity(0.4)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Type style \(title), \(style.fontName.isEmpty ? "System" : style.fontName), \(Int(style.fontSize.rounded())) points")
                    }
                }
                .padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(EXPColor.surfaceField.opacity(0.5)))
        }
    }

    private var previewSummary: String {
        guard !parsed.isEmpty else { return "" }
        var parts: [String] = []
        if !parsed.assets.isEmpty { parts.append("\(parsed.assets.count) color\(parsed.assets.count == 1 ? "" : "s")") }
        if !parsed.typeStyles.isEmpty { parts.append("\(parsed.typeStyles.count) type style\(parsed.typeStyles.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private var importButtonHelp: String {
        parsed.isEmpty ? "Paste something above first"
                       : "Add \(previewSummary) to this document's design language"
    }

    private func refreshPreview() {
        parsed = DesignLanguageIO.parseVariables(pasteText)
    }

    private func performImport() {
        guard !parsed.isEmpty else { return }
        var model = document.model
        // Resolve the target category (create-on-import when a new name is set).
        var categoryID = importCategoryID
        let newName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if creatingNewCategory, !newName.isEmpty {
            categoryID = model.designLanguage.ensureCategory(newName)
        }
        var assets = parsed.assets
        for i in assets.indices { assets[i].categoryID = categoryID }
        var styles = parsed.typeStyles
        for i in styles.indices { styles[i].categoryID = categoryID }
        model.designLanguage.merge(assets, mode: mergeMode)
        model.designLanguage.mergeTypeStyles(styles, mode: mergeMode)
        document.setModel(model, undoManager: undoManager, actionName: "Import Design Language")
        dismiss()
    }

    private func importJSONFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Import an EXP design-language JSON file."
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let parsed = DesignLanguageIO.parseJSON(data),
              !parsed.assets.isEmpty || !parsed.typeStyles.isEmpty else { return }
        var model = document.model
        model.designLanguage.merge(parsed.assets, categories: parsed.categories, mode: mergeMode)
        model.designLanguage.mergeTypeStyles(parsed.typeStyles, categories: parsed.categories, mode: mergeMode)
        document.setModel(model, undoManager: undoManager, actionName: "Import Design Language")
        dismiss()
    }

    // MARK: Export side

    @ViewBuilder private var exportView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Format", selection: $exportFormat) {
                ForEach(DLExportFormat.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Export format")
            Text(exportFormat.blurb)
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The preview IS the export — exactly what Copy/Save produce.
            ScrollView {
                Text(dl.isEmpty ? "(this document's design language is empty)"
                                : exportFormat.previewText(for: dl))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(EXPColor.surfaceField.opacity(0.5)))
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Export preview, \(exportFormat.label)")
        }
        .onChange(of: exportFormat) { copied = false }
    }

    private func copyExport() {
        let text = exportFormat.previewText(for: dl)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func saveExportFile() {
        guard let data = try? exportFormat.data(for: dl) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "design-language.\(exportFormat.fileExtension)"
        let ext = exportFormat.fileExtension.split(separator: ".").last.map(String.init) ?? "txt"
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
        panel.message = "Save this document's design language as \(exportFormat.label)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}

//
//  ExportPanels.swift
//  EXP [design]
//
//  The save/open panels for export, including the format-picker accessory view.
//  Kept out of the canvas so the editing surface stays focused.
//
//   • Export Selected Artboard… → NSSavePanel with a Format popup (PNG/PDF/SVG).
//     Changing the popup retargets the panel's file type live.
//   • Export All Artboards…      → folder picker with a Format popup
//     (PNG/PDF/SVG/All) plus a "Combine PDF pages into one file" checkbox
//     (enabled only when PDF is involved).
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class ExportPanels: NSObject {

    private let model: Document
    private let renderer: ExportRenderer

    private weak var savePanel: NSSavePanel?      // set only for the single-file flow
    private var formatPopup: NSPopUpButton?
    private var combineCheckbox: NSButton?
    private var notesCheckbox: NSButton?

    /// PNG renders at this scale (a future Settings panel can expose it).
    private let pngScale: CGFloat = 2

    init(model: Document) {
        self.model = model
        self.renderer = ExportRenderer(document: model)
    }

    // MARK: Single artboard → Save panel + format popup

    func exportSelected(_ artboard: Artboard, in window: NSWindow?) {
        let panel = NSSavePanel()
        savePanel = panel
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = artboard.name
        panel.accessoryView = buildAccessory(includeCombine: false)
        applyFormatToSavePanel()
        updateCheckboxesEnabled()

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let format = ExportFormat.allCases[self.formatIndex]
            let notes = self.notesCheckbox?.state == .on
            if let data = self.renderer.data(for: artboard, format: format,
                                             scale: self.pngScale, includeNotes: notes) {
                try? data.write(to: url)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    // MARK: All artboards → folder picker + format popup + combine option

    func exportAll(_ artboards: [Artboard], in window: NSWindow?,
                   message: String = "Choose a folder to export all artboards.") {
        savePanel = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = message
        panel.accessoryView = buildAccessory(includeCombine: true)
        updateCheckboxesEnabled()

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let dir = panel.url else { return }
            let combine = self.combineCheckbox?.state == .on
            let notes = self.notesCheckbox?.state == .on
            // Index 3 = "All"; otherwise a single format.
            let formats: [ExportFormat] = self.formatIndex == 3
                ? ExportFormat.allCases : [ExportFormat.allCases[self.formatIndex]]
            self.writeAll(artboards, to: dir, formats: formats, combinePDF: combine, includeNotes: notes)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    private func writeAll(_ artboards: [Artboard], to dir: URL,
                          formats: [ExportFormat], combinePDF: Bool, includeNotes: Bool) {
        for format in formats {
            if format == .pdf && combinePDF {
                if let data = renderer.multiPagePDFData(for: artboards, includeNotes: includeNotes) {
                    try? data.write(to: dir.appendingPathComponent("Artboards.pdf"))
                }
            } else {
                for artboard in artboards {
                    let base = artboard.name.replacingOccurrences(of: "/", with: "-")
                    if let data = renderer.data(for: artboard, format: format,
                                                scale: pngScale, includeNotes: includeNotes) {
                        try? data.write(to: dir.appendingPathComponent("\(base).\(format.ext)"))
                    }
                }
            }
        }
    }

    // MARK: Accessory view

    private var formatIndex: Int { formatPopup?.indexOfSelectedItem ?? 0 }

    private func buildAccessory(includeCombine: Bool) -> NSView {
        let label = NSTextField(labelWithString: "Format:")

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        var titles = ["PNG (@2×)", "PDF", "SVG"]
        if includeCombine { titles.append("All (PNG + PDF + SVG)") }
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        formatPopup = popup

        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8

        // "Include notes" applies to PDF in both flows.
        let notes = NSButton(checkboxWithTitle: "Include notes (adds a notes page per board)",
                             target: self, action: #selector(formatChanged(_:)))
        notes.state = .off
        notesCheckbox = notes

        var rows: [NSView] = [row]
        if includeCombine {
            let combine = NSButton(checkboxWithTitle: "Combine PDF pages into one file",
                                   target: self, action: #selector(formatChanged(_:)))
            combine.state = .off
            combineCheckbox = combine
            rows.append(combine)
        }
        rows.append(notes)

        let container = NSStackView(views: rows)
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        container.frame = NSRect(x: 0, y: 0, width: 380, height: includeCombine ? 104 : 80)
        return container
    }

    @objc private func formatChanged(_ sender: Any?) {
        applyFormatToSavePanel()
        updateCheckboxesEnabled()
    }

    /// Keep the save panel's enforced type (and filename extension) in sync with
    /// the popup. No-op for the folder flow, where `savePanel` is nil.
    private func applyFormatToSavePanel() {
        guard let panel = savePanel else { return }
        let format = ExportFormat.allCases[formatIndex]
        panel.allowedContentTypes = [format.utType]
        var name = (panel.nameFieldStringValue as NSString).deletingPathExtension
        if name.isEmpty { name = "Artboard" }
        panel.nameFieldStringValue = "\(name).\(format.ext)"
    }

    private func updateCheckboxesEnabled() {
        // PDF (index 1) or All (index 3) make the PDF-only options meaningful.
        let pdfInvolved = (formatIndex == 1 || formatIndex == 3)
        combineCheckbox?.isEnabled = pdfInvolved
        notesCheckbox?.isEnabled = pdfInvolved
    }
}

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
    private var transparentPNGCheckbox: NSButton?

    /// PNG renders at this scale (a future Settings panel can expose it).
    private let pngScale: CGFloat = 2

    /// The single-format popup items, in display order. Decoupled from
    /// `ExportFormat.allCases` so adding a format never shifts the index math.
    /// JPG is offered as an extra option (not part of "All").
    private let singleFormats: [ExportFormat] = [.png, .jpg, .pdf, .svg]
    /// True when the popup's trailing "All" item (folder flow only) is chosen.
    private var isAllSelected: Bool { formatIndex >= singleFormats.count }

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
            let format = self.singleFormats[self.formatIndex]
            let notes = self.notesCheckbox?.state == .on
            let transparentPNG = self.transparentPNGCheckbox?.state == .on
            if let data = self.renderer.data(for: artboard, format: format,
                                             scale: self.pngScale, includeNotes: notes,
                                             transparentPNGBackground: transparentPNG) {
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
            let transparentPNG = self.transparentPNGCheckbox?.state == .on
            // The trailing "All" item = PNG + PDF + SVG; otherwise the chosen format.
            let formats: [ExportFormat] = self.isAllSelected
                ? [.png, .pdf, .svg] : [self.singleFormats[self.formatIndex]]
            self.writeAll(artboards, to: dir, formats: formats, combinePDF: combine,
                          includeNotes: notes, transparentPNG: transparentPNG)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    private func writeAll(_ artboards: [Artboard], to dir: URL,
                          formats: [ExportFormat], combinePDF: Bool, includeNotes: Bool,
                          transparentPNG: Bool) {
        for format in formats {
            if format == .pdf && combinePDF {
                if let data = renderer.multiPagePDFData(for: artboards, includeNotes: includeNotes) {
                    try? data.write(to: dir.appendingPathComponent("Artboards.pdf"))
                }
            } else {
                for artboard in artboards {
                    let base = artboard.name.replacingOccurrences(of: "/", with: "-")
                    if let data = renderer.data(for: artboard, format: format,
                                                scale: pngScale, includeNotes: includeNotes,
                                                transparentPNGBackground: transparentPNG) {
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
        var titles = ["PNG (@2×)", "JPG (@2×)", "PDF", "SVG"]
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

        let transparentPNG = NSButton(checkboxWithTitle: "Transparent background (PNG)",
                                      target: self, action: #selector(formatChanged(_:)))
        transparentPNG.state = .off
        transparentPNGCheckbox = transparentPNG

        var rows: [NSView] = [row]
        rows.append(transparentPNG)
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
        container.frame = NSRect(x: 0, y: 0, width: 380, height: includeCombine ? 128 : 104)
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
        let format = singleFormats[min(formatIndex, singleFormats.count - 1)]
        panel.allowedContentTypes = [format.utType]
        var name = (panel.nameFieldStringValue as NSString).deletingPathExtension
        if name.isEmpty { name = "Artboard" }
        panel.nameFieldStringValue = "\(name).\(format.ext)"
    }

    private func updateCheckboxesEnabled() {
        // PDF (or All) make the PDF-only options meaningful; transparent bg is a
        // PNG-only trait (JPEG can't be transparent).
        let sel: ExportFormat? = formatIndex < singleFormats.count ? singleFormats[formatIndex] : nil
        let pdfInvolved = (sel == .pdf || isAllSelected)
        let pngInvolved = (sel == .png || isAllSelected)
        combineCheckbox?.isEnabled = pdfInvolved
        notesCheckbox?.isEnabled = pdfInvolved
        transparentPNGCheckbox?.isEnabled = pngInvolved
    }
}

//
//  ExportPanels.swift
//  EXP [design]
//
//  The save/open panels for export, including the format-picker accessory view.
//  Kept out of the canvas so the editing surface stays focused.
//
//   • Export Selected Artboard… → NSSavePanel with Format + Size popups.
//     Changing the format retargets the panel's file type live.
//   • Export All Artboards…      → folder picker with Format + Size popups
//     (PNG/JPG/PDF/SVG/All) plus a "Combine PDF pages into one file" checkbox
//     (enabled only when PDF is involved).
//
//  FEAT-063: format and size are remembered between exports, and size is its own
//  control rather than being welded into the format names ("PNG (@2×)").
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class ExportPanels: NSObject {

    private let model: Document
    private let renderer: ExportRenderer

    private weak var savePanel: NSSavePanel?      // set only for the single-file flow
    private var formatPopup: NSPopUpButton?
    private var sizePopup: NSPopUpButton?
    private var combineCheckbox: NSButton?
    private var notesCheckbox: NSButton?
    private var transparentPNGCheckbox: NSButton?

    /// The single-format popup items, in display order. Decoupled from
    /// `ExportFormat.allCases` so adding a format never shifts the index math.
    /// JPG is offered as an extra option (not part of "All").
    private let singleFormats: [ExportFormat] = [.png, .jpg, .pdf, .svg]
    /// True when the popup's trailing "All" item (folder flow only) is chosen.
    private var isAllSelected: Bool { formatIndex >= singleFormats.count }

    /// Raster export scales offered by the Size popup.
    private let scales: [CGFloat] = [0.5, 1, 2, 4]
    /// The scale used before FEAT-063 split size out of the format names. A fresh
    /// install with nothing stored must still open on PNG at 2×, exactly as the
    /// hardcoded `pngScale` did.
    private let defaultScale: CGFloat = 2

    // MARK: Remembered choices
    //
    // Stored as PLAIN UserDefaults values (a format id string, a scale double),
    // never as a Codable payload: Swift's synthesised decoder throws on a missing
    // key instead of using a property default, so adding one field silently wipes
    // the whole saved value. That is exactly how FEAT-022 erased saved tray
    // layouts. Both reads validate and fall back, so a junk or removed value can
    // never leave a popup unselected.

    private enum DefaultsKey {
        static let format = "export.lastFormat"   // an ExportFormat rawValue, or "all"
        static let scale  = "export.lastScale"
    }
    private static let allFormatsToken = "all"

    private var storedFormatIndex: Int {
        guard let raw = UserDefaults.standard.string(forKey: DefaultsKey.format) else { return 0 }
        if raw == Self.allFormatsToken { return singleFormats.count }
        guard let format = ExportFormat(rawValue: raw),
              let index = singleFormats.firstIndex(of: format) else { return 0 }
        return index
    }

    private var storedScaleIndex: Int {
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.scale) as? Double
        let value = CGFloat(stored ?? Double(defaultScale))
        return scales.firstIndex(where: { abs($0 - value) < 0.001 })
            ?? scales.firstIndex(of: defaultScale) ?? 0
    }

    /// Remember the current choices. Called only on a completed export, so
    /// cancelling a panel never changes what the next one opens on.
    private func rememberChoices() {
        let formatToken = isAllSelected
            ? Self.allFormatsToken
            : singleFormats[min(formatIndex, singleFormats.count - 1)].rawValue
        UserDefaults.standard.set(formatToken, forKey: DefaultsKey.format)
        UserDefaults.standard.set(Double(currentScale), forKey: DefaultsKey.scale)
    }

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
        updateAccessoryEnabled()

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let format = self.singleFormats[min(self.formatIndex, self.singleFormats.count - 1)]
            let notes = self.notesCheckbox?.state == .on
            let transparentPNG = self.transparentPNGCheckbox?.state == .on
            if let data = self.renderer.data(for: artboard, format: format,
                                             scale: self.currentScale, includeNotes: notes,
                                             transparentPNGBackground: transparentPNG) {
                try? data.write(to: url)
            }
            // The single-file flow writes exactly the filename the owner typed —
            // no `@Nx` suffix is appended over their choice. Only the folder flow,
            // which names files itself, disambiguates by scale.
            self.rememberChoices()
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
        updateAccessoryEnabled()

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let dir = panel.url else { return }
            let combine = self.combineCheckbox?.state == .on
            let notes = self.notesCheckbox?.state == .on
            let transparentPNG = self.transparentPNGCheckbox?.state == .on
            // The trailing "All" item = PNG + PDF + SVG; otherwise the chosen format.
            let formats: [ExportFormat] = self.isAllSelected
                ? [.png, .pdf, .svg] : [self.singleFormats[self.formatIndex]]
            self.writeAll(artboards, to: dir, formats: formats, combinePDF: combine,
                          includeNotes: notes, transparentPNG: transparentPNG,
                          scale: self.currentScale)
            self.rememberChoices()
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    private func writeAll(_ artboards: [Artboard], to dir: URL,
                          formats: [ExportFormat], combinePDF: Bool, includeNotes: Bool,
                          transparentPNG: Bool, scale: CGFloat) {
        for format in formats {
            if format == .pdf && combinePDF {
                if let data = renderer.multiPagePDFData(for: artboards, includeNotes: includeNotes) {
                    try? data.write(to: dir.appendingPathComponent("Artboards.pdf"))
                }
            } else {
                let suffix = Self.scaleSuffix(for: format, scale: scale)
                for artboard in artboards {
                    let base = artboard.name.replacingOccurrences(of: "/", with: "-")
                    if let data = renderer.data(for: artboard, format: format,
                                                scale: scale, includeNotes: includeNotes,
                                                transparentPNGBackground: transparentPNG) {
                        try? data.write(to: dir.appendingPathComponent("\(base)\(suffix).\(format.ext)"))
                    }
                }
            }
        }
    }

    /// `@2x` / `@0.5x` — appended only when the scale actually differs from 1× and
    /// the format is rasterised. Owner decision 2026-09-03: a plain `board.png` at
    /// 1×, suffixed otherwise, so several sizes can land in one folder without
    /// overwriting each other. PDF and SVG are resolution-independent and are
    /// never suffixed.
    private static func scaleSuffix(for format: ExportFormat, scale: CGFloat) -> String {
        guard format.isRaster, abs(scale - 1) > 0.001 else { return "" }
        let rounded = (scale * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded)) : String(Double(rounded))
        return "@\(text)x"
    }

    // MARK: Accessory view

    private var formatIndex: Int { formatPopup?.indexOfSelectedItem ?? 0 }

    /// The chosen raster scale. Vector formats ignore it; the renderer takes a
    /// scale regardless, so 1× is the harmless value to pass for those.
    private var currentScale: CGFloat {
        guard let index = sizePopup?.indexOfSelectedItem,
              scales.indices.contains(index) else { return defaultScale }
        return scales[index]
    }

    private func buildAccessory(includeCombine: Bool) -> NSView {
        let formatLabel = NSTextField(labelWithString: "Format:")

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        // Size is its own control now, so the format names no longer claim a scale.
        var titles = ["PNG", "JPG", "PDF", "SVG"]
        if includeCombine { titles.append("All (PNG + PDF + SVG)") }
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        popup.setAccessibilityLabel("Format")
        formatPopup = popup
        // Reopen on whatever was exported last. The "All" item only exists in the
        // folder flow, so clamp when the remembered choice can't be shown here.
        popup.selectItem(at: min(storedFormatIndex, titles.count - 1))

        let sizeLabel = NSTextField(labelWithString: "Size:")
        let sizes = NSPopUpButton(frame: .zero, pullsDown: false)
        sizes.addItems(withTitles: ["0.5×", "1×", "2×", "4×"])
        sizes.target = self
        sizes.action = #selector(formatChanged(_:))
        sizes.setAccessibilityLabel("Size")
        sizePopup = sizes
        sizes.selectItem(at: storedScaleIndex)

        let formatRow = NSStackView(views: [formatLabel, popup])
        formatRow.orientation = .horizontal
        formatRow.alignment = .firstBaseline
        formatRow.spacing = 8

        let sizeRow = NSStackView(views: [sizeLabel, sizes])
        sizeRow.orientation = .horizontal
        sizeRow.alignment = .firstBaseline
        sizeRow.spacing = 8

        // "Include notes" applies to PDF in both flows.
        let notes = NSButton(checkboxWithTitle: "Include notes (adds a notes page per board)",
                             target: self, action: #selector(formatChanged(_:)))
        notes.state = .off
        notesCheckbox = notes

        let transparentPNG = NSButton(checkboxWithTitle: "Transparent background (PNG)",
                                      target: self, action: #selector(formatChanged(_:)))
        transparentPNG.state = .off
        transparentPNGCheckbox = transparentPNG

        var rows: [NSView] = [formatRow, sizeRow]
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
        container.frame = NSRect(x: 0, y: 0, width: 380, height: includeCombine ? 158 : 134)

        // Keep the two popups on a common left edge. Activated only now that both
        // rows are inside `container`: a constraint between anchors whose views
        // share no ancestor yet throws NSGenericException, and AppKit swallows
        // that during a menu action, so the export silently did nothing (BUG-067).
        sizeLabel.widthAnchor.constraint(equalTo: formatLabel.widthAnchor).isActive = true

        return container
    }

    @objc private func formatChanged(_ sender: Any?) {
        applyFormatToSavePanel()
        updateAccessoryEnabled()
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

    private func updateAccessoryEnabled() {
        // PDF (or All) make the PDF-only options meaningful; transparent bg is a
        // PNG-only trait (JPEG can't be transparent).
        let sel: ExportFormat? = formatIndex < singleFormats.count ? singleFormats[formatIndex] : nil
        let pdfInvolved = (sel == .pdf || isAllSelected)
        let pngInvolved = (sel == .png || isAllSelected)
        combineCheckbox?.isEnabled = pdfInvolved
        notesCheckbox?.isEnabled = pdfInvolved
        transparentPNGCheckbox?.isEnabled = pngInvolved
        // Size means nothing for a vector format. DISABLED, not hidden, so no
        // control moves under the pointer — the same choice the checkboxes make.
        // "All" includes PNG, so the size still applies to that member.
        let rasterInvolved = (sel?.isRaster ?? false) || isAllSelected
        sizePopup?.isEnabled = rasterInvolved
    }
}

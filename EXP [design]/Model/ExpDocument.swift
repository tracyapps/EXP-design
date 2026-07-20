//
//  ExpDocument.swift
//  EXP [design]
//
//  The bridge between our pure data model (Document) and macOS's document
//  system. We use ReferenceFileDocument (not the value-type FileDocument)
//  deliberately: it's a *class*, so the AppKit canvas can hold one reference and
//  edit it in place — which is exactly the reference-based spirit of the model.
//
//  The file format IS just `Document` encoded to pretty-printed JSON, so it
//  opens instantly and stays human-readable / diff-able. Extension: ".exp".
//
//  Saving relies on the UndoManager: macOS marks a ReferenceFileDocument as
//  "edited" (and therefore needing a save) when you register an undo action.
//  So `setModel` is the single funnel for edits — it swaps the model AND
//  registers the inverse, which both powers ⌘Z and tells the system to save.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

extension UTType {
    /// Our native document type — it *is* JSON underneath, with the ".design"
    /// extension. Declared for real in Info.plist so Finder associates it.
    /// (Changing the extension only takes effect once LaunchServices re-registers
    /// the app — Clean Build Folder + run, or `lsregister -f`.)
    // NOTE: a FRESH identifier (not the old "…document") on purpose — LaunchServices
    // had the old id cached against ".exp" and wouldn't re-point it at ".design".
    // A never-seen id registers clean with ".design".
    static let expDocument = UTType(exportedAs: "tapps.exp-design.designfile",
                                    conformingTo: .json)

    /// The system type bound to the legacy ".exp" extension, if any — added to
    /// `readableContentTypes` so the Open panel still lets you open files saved
    /// with the old extension (they're the same JSON) to migrate them to .design.
    static let legacyExp = UTType(filenameExtension: "exp")
}

final class ExpDocument: ReferenceFileDocument {

    typealias Snapshot = Document

    /// The live design data. @Published so SwiftUI + the canvas redraw on change.
    /// `didSet` bumps `resolveGeneration` on EVERY mutation — whether the model is
    /// replaced (setModel/undo) or edited in place (a live drag mutates `model.nodes`
    /// directly). Mutating a value-type stored property routes through this setter,
    /// so this is one reliable invalidation signal covering every edit site.
    @Published var model: Document {
        didSet { resolveGeneration &+= 1 }
    }

    /// Monotonic counter, bumped whenever `model` changes. The canvas keys an
    /// expensive per-instance resolution cache on it: pan and zoom never touch the
    /// model, so the cache survives those redraws, while any real edit invalidates
    /// it immediately. Not persisted.
    private(set) var resolveGeneration: Int = 0

    // Open our .expd type, plus the legacy .exp ("Symbol Export") type so older
    // files still open from the in-app Open panel (they're the same JSON). We only
    // ever WRITE our own .expd type.
    static var readableContentTypes: [UTType] {
        // .pdf is READ-only here: opening a PDF builds a fresh design (each page →
        // an artboard) that then saves as our own .design type.
        [.expDocument, .pdf] + [UTType.legacyExp].compactMap { $0 }
    }
    static var writableContentTypes: [UTType] { [.expDocument] }

    // MARK: New / Open

    init() {
        model = Document()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Opening a PDF: import each page as an artboard of editable layers instead
        // of decoding our JSON. Untitled, so the first save writes a .design file.
        if configuration.contentType.conforms(to: .pdf) || data.prefix(5).elementsEqual("%PDF-".utf8) {
            guard let pages = PDFImporter.importPages(from: data), !pages.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let laid = PDFImporter.layout(pages)
            var doc = Document()
            doc.artboards = laid.artboards
            doc.nodes = laid.nodes
            model = doc
            return
        }
        var decoded = try JSONDecoder().decode(Document.self, from: data)
        Self.stripBackgroundBlurEffects(&decoded)
        Self.sanitizePDFImages(&decoded)
        model = decoded
    }

    /// SAFETY MIGRATION (2026-07-11): a bad PDF import could (a) store raw PDF
    /// bytes in an image node (NSImage accepts PDF data and passes the size
    /// guard). Such a node makes CoreGraphics try to decode a PDF as a bitmap on
    /// every redraw — it errors ("'PDF' initImage failed") and beach-balls the
    /// canvas, bricking any document that saved it. On open, convert any image
    /// node whose bytes are actually a PDF into a PNG raster of its first page
    /// (content preserved); drop it only if even that fails.
    private static func sanitizePDFImages(_ doc: inout Document) {
        func isPDF(_ d: Data) -> Bool { d.prefix(5).elementsEqual("%PDF-".utf8) }
        func frameSane(_ f: CGRect) -> Bool {
            f.origin.x.isFinite && f.origin.y.isFinite && f.width.isFinite && f.height.isFinite
                && abs(f.minX) < 2_000_000 && abs(f.minY) < 2_000_000
                && f.width < 2_000_000 && f.height < 2_000_000
        }
        func fix(_ nodes: inout [Node]) {
            var result: [Node] = []
            for var n in nodes {
                // Drop nodes with a corrupt frame (NaN/Inf/absurd) — a bad import
                // could produce these and they beach-ball the canvas on redraw.
                if !frameSane(n.frame) { continue }
                if case .image(let img) = n.content, isPDF(img.data) {
                    if let png = PDFImporter.rasterPNGForPage(from: img.data, page: 1) {
                        n.content = .image(ImageContent(data: png, naturalSize: img.naturalSize))
                    } else {
                        continue   // un-rasterizable → drop (it was the thing hanging the app)
                    }
                }
                if case .group(var k) = n.content { fix(&k); n.content = .group(children: k) }
                result.append(n)
            }
            nodes = result
        }
        fix(&doc.nodes)
        for i in doc.sources.indices { fix(&doc.sources[i].children) }
    }

    /// MIGRATION (2026-07-02): background blur was disabled for performance in
    /// Session 125 and abandoned for now (owner decision, Session 162c). A
    /// legacy effect never renders, but it lingers in the inspector, trips
    /// AppKit's picker validation, and muddies performance testing — so strip
    /// it from every layer (including component sources) when a document
    /// opens. The document saves clean on its next edit. If background blur
    /// ever returns, remove this and re-add the picker option.
    private static func stripBackgroundBlurEffects(_ doc: inout Document) {
        func strip(_ nodes: inout [Node]) {
            for i in nodes.indices {
                nodes[i].effects.removeAll { $0.kind == .backgroundBlur }
                if case .group(var children) = nodes[i].content {
                    strip(&children)
					nodes[i].content = .group(children: children)
                }
            }
        }
        strip(&doc.nodes)
        for i in doc.sources.indices { strip(&doc.sources[i].children) }
    }

    // MARK: Save
    //
    // snapshot() is called on the main actor to capture the model; the returned
    // value (a struct, so a safe copy) is then handed to fileWrapper() which may
    // run on a background thread. fileWrapper touches only `snapshot`, never
    // self — that's the whole point of the snapshot step.

    func snapshot(contentType: UTType) throws -> Document {
        model
    }

    nonisolated func fileWrapper(snapshot: Document, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: Undo-aware editing

    /// The single funnel for every edit. Swaps in `newModel`, then registers the
    /// inverse with the UndoManager — which gives us undo/redo for free AND is
    /// what tells macOS the document is dirty and needs saving.
    ///
    /// Snapshot-based undo (restore the whole previous Document) is cheap at v1
    /// sizes and trivial to reason about. For a continuous gesture like dragging,
    /// the caller mutates `model` live and registers a single undo at the end via
    /// `registerUndo(restoring:)`, so one drag = one undo step.
    func setModel(_ newModel: Document, undoManager: UndoManager?, actionName: String) {
        let oldModel = model
        model = newModel
        undoManager?.registerUndo(withTarget: self) { document in
            document.setModel(oldModel, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// Register undo back to `baseline`, assuming `model` already holds the new
    /// state (used by drag, which updates `model` live for smooth feedback).
    func registerUndo(restoring baseline: Document, undoManager: UndoManager?, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { document in
            document.setModel(baseline, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}

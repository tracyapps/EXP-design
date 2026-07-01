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
        [.expDocument] + [UTType.legacyExp].compactMap { $0 }
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
        model = try JSONDecoder().decode(Document.self, from: data)
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

import AppKit

@MainActor
private final class NotesDocumentWindow: NSWindow {
    let documentHistory = UndoManager()
    override var undoManager: UndoManager? { documentHistory }
}

@main
enum NotesUndoLifetimeCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NotesDocumentWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                                         styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let history = window.documentHistory
        history.groupsByEvent = false
        if CommandLine.arguments.contains("--open") {
            let editor = NotesTextView(frame: window.contentView!.bounds)
            editor.isRichText = false
            editor.allowsUndo = true
            editor.enableFormatting()
            window.contentView!.addSubview(editor)
            window.makeFirstResponder(editor)
            print("Native notes manager is document manager: \(editor.undoManager === history)")
            fflush(stdout)
            for round in 0..<20 {
                let baseline = editor.string
                history.beginUndoGrouping()
                editor.insertText("## Title \(round)\n[Guide](https://example.com)\n", replacementRange: editor.selectedRange())
                // The document snapshot inverse refreshes the bound editor, as
                // NotesEditor.updateNSView does after externalText changes.
                history.registerUndo(withTarget: editor) { view in
                    view.string = baseline
                    view.restyleAll()
                }
                history.endUndoGrouping()
                print("Undo open-editor round \(round)")
                fflush(stdout)
                history.undo()
            }
            print("Open-editor interleaving completed")
            exit(0)
        }
        for iteration in 0..<20 {
            let editor = NotesTextView(frame: window.contentView!.bounds)
            editor.isRichText = false
            editor.allowsUndo = true
            editor.string = "# Baseline"
            editor.enableFormatting()
            window.contentView!.addSubview(editor)
            window.makeFirstResponder(editor)
            guard let local = editor.undoManager, local !== history else {
                fputs("FAIL: transient notes typing shares document undo history\n", stderr)
                exit(1)
            }
            local.groupsByEvent = false
            local.beginUndoGrouping()
            history.beginUndoGrouping()
            let addition = "\n## Notes \(iteration)\n[Guide](https://example.com)"
            editor.insertText(addition, replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
            local.endUndoGrouping()
            history.registerUndo(withTarget: editor) { view in view.replaceExternalText("# Baseline") }
            history.endUndoGrouping()
            local.undo()
            guard editor.string == "# Baseline" else {
                fputs("FAIL: local Undo did not restore baseline\n", stderr); exit(1)
            }
            local.redo()
            guard editor.string == "# Baseline" + addition else {
                fputs("FAIL: local Redo did not restore formatted/link text\n", stderr); exit(1)
            }
            history.undo()
            guard editor.string == "# Baseline", !local.canUndo, !local.canRedo else {
                fputs("FAIL: external restore left stale native text operations\n", stderr); exit(1)
            }
            // Resetting unchanged text during ordinary SwiftUI updates must not
            // erase local typing history.
            local.beginUndoGrouping()
            editor.insertText(" next", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
            local.endUndoGrouping()
            editor.replaceExternalText(editor.string)
            guard local.canUndo else { fputs("FAIL: unchanged refresh cleared text history\n", stderr); exit(1) }
            window.makeFirstResponder(nil)
            editor.removeFromSuperview()
            guard !local.canUndo, !local.canRedo else {
                fputs("FAIL: detached notes retained native text operations\n", stderr); exit(1)
            }
            history.removeAllActions()
        }
        print("PASS: 20 real AppKit cycles isolate text/document Undo, restore Redo, clear stale external ranges and detach safely")
        window.close()
    }
}

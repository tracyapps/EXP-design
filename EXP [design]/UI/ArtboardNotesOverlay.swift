//
//  ArtboardNotesOverlay.swift
//  EXP [design]
//
//  Structured handoff notes, attached per artboard. A SwiftUI layer floating over
//  the canvas, positioned with the SAME camera transform the canvas uses
//  (viewPoint = docPoint * zoom + panOffset), so a small notes button sits just
//  left of each artboard's name label and tracks pan/zoom. A GeometryReader pins
//  the content origin to the canvas's top-left.
//
//  The notes text lives on `Artboard.notes` (the model) so it travels with the
//  board. Only open/closed state and the panel's manual size are ephemeral
//  (AppState), so a resize sticks when you close and reopen.
//
//  The editor is an NSTextView (via NotesEditor) so we get real multi-line
//  editing: Return = line break, Tab/Shift-Tab = indent/outdent, and bullet lines
//  ("•", "-", "*") auto-continue on Return. The model stays a plain String
//  (bullets/indents are literal characters) — a clean base for Markdown later.
//

import SwiftUI
import AppKit

struct ArtboardNotesOverlay: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager

    private static let defaultSize = CGSize(width: 240, height: 96)

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                ForEach(document.model.artboards) { artboard in
                    let p = labelAnchor(artboard)

                    NotesButton(hasNotes: !artboard.notes.isEmpty,
                                isOpen: app.openNotesArtboardIDs.contains(artboard.id)) {
                        app.toggleNotes(artboard.id)
                    }
                    .offset(x: p.x - 22, y: p.y)

                    if app.openNotesArtboardIDs.contains(artboard.id) {
                        NotesPanel(title: artboard.name,
                                   text: notesBinding(artboard.id),
                                   size: sizeBinding(artboard.id),
                                   anchorRightEdge: p.x - 26,
                                   top: p.y + 22) {
                            app.toggleNotes(artboard.id)
                        }
                        .id(artboard.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// View-space point at the left edge of the artboard's name label (drawn
    /// ~22pt above the frame's top edge in the canvas).
    private func labelAnchor(_ artboard: Artboard) -> CGPoint {
        CGPoint(x: artboard.frame.minX * app.zoom + app.panOffset.x,
                y: artboard.frame.minY * app.zoom + app.panOffset.y - 22)
    }

    private func notesBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { document.model.artboards.first { $0.id == id }?.notes ?? "" },
            set: { newValue in
                guard let i = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.artboards[i].notes = newValue
                document.setModel(model, undoManager: undoManager, actionName: "Edit Notes")
            }
        )
    }

    private func sizeBinding(_ id: UUID) -> Binding<CGSize> {
        Binding(
            get: { app.notesPanelSize[id] ?? Self.defaultSize },
            set: { app.notesPanelSize[id] = $0 }
        )
    }
}

// MARK: - Toggle button (left of the artboard name)

private struct NotesButton: View {
    let hasNotes: Bool
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: hasNotes ? "note.text" : "note")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOpen ? EXPColor.accentSubtle : EXPColor.surfaceRaised.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(hasNotes ? EXPColor.accent : EXPColor.borderSoft,
                                      lineWidth: hasNotes ? EXPMetric.strokeHairline : 0.5)
                )
                .foregroundStyle(hasNotes ? EXPColor.accent : EXPColor.textSecondary)
                .opacity(hasNotes ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .help(hasNotes ? "Notes (has content) — click to toggle" : "Add notes")
        .accessibilityLabel(hasNotes ? "Artboard notes, has content" : "Add artboard notes")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The editable, resizable, auto-growing panel

private struct NotesPanel: View {
    let title: String
    @Binding var text: String
    @Binding var size: CGSize        // persisted manual size (width, min height)
    let anchorRightEdge: CGFloat
    let top: CGFloat
    let close: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var dragStart: CGSize?

    private let minW: CGFloat = 160, maxW: CGFloat = 520
    private let minH: CGFloat = 56, maxH: CGFloat = 600

    /// Auto-grow to fit text, but never below the manual height nor above the cap
    /// (beyond the cap the editor scrolls).
    private var editorHeight: CGFloat {
        min(maxH, max(size.height, contentHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text").font(.caption2).foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close notes")
                .accessibilityLabel("Close notes")
            }

            NotesEditor(text: $text, contentHeight: $contentHeight, focusOnAppear: true)
                .frame(height: editorHeight)
                .accessibilityLabel("Notes for \(title)")
        }
        .padding(8)
        .frame(width: size.width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: EXPMetric.radiusButton)
                .fill(EXPColor.surfaceRaised)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusButton).strokeBorder(EXPColor.hairline))
        .overlay(alignment: .bottomLeading) { resizeGrip }
        .offset(x: anchorRightEdge - size.width, y: top)   // anchor top-right → grows down + left
    }

    /// Bottom-left grip: drag left to widen, down to add height.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if dragStart == nil { dragStart = size }
                        let base = dragStart ?? size
                        size = CGSize(
                            width: min(maxW, max(minW, base.width - v.translation.width)),
                            height: min(maxH, max(minH, base.height + v.translation.height))
                        )
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .help("Drag to resize")
            .accessibilityHidden(true)
    }
}

// MARK: - NSTextView-backed editor (line breaks, Tab indent, bullet continuation)

private struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var focusOnAppear: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NotesTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        tv.string = text

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        if focusOnAppear {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        reportHeight(tv)
    }

    private func reportHeight(_ tv: NSTextView) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2 + 4
        DispatchQueue.main.async {
            if abs(contentHeight - h) > 0.5 { contentHeight = h }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: NotesEditor
        init(_ parent: NotesEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.reportHeight(tv)
        }
    }
}

/// NSTextView that turns Tab into indentation and continues bullet lists, so
/// notes feel like a real outline editor (and stays Markdown-friendly text).
private final class NotesTextView: NSTextView {
    private let indent = "    "                 // 4 spaces
    private let bulletMarkers = ["• ", "- ", "* "]

    override func insertTab(_ sender: Any?) {
        insertText(indent, replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        // Outdent: drop a leading indent (or up to 4 leading spaces / one tab) on
        // the current line.
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lineRange)
        var drop = 0
        if line.hasPrefix(indent) { drop = indent.count }
        else if line.hasPrefix("\t") { drop = 1 }
        else { drop = line.prefix { $0 == " " }.count }   // up to a few stray spaces
        guard drop > 0 else { return }
        let removal = NSRange(location: lineRange.location, length: drop)
        if shouldChangeText(in: removal, replacementString: "") {
            textStorage?.replaceCharacters(in: removal, with: "")
            didChangeText()
        }
    }

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange)

        // Leading whitespace (preserve indentation on the new line).
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        let afterLeading = line.dropFirst(leading.count)

        if let marker = bulletMarkers.first(where: { afterLeading.hasPrefix($0) }) {
            let content = afterLeading.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                // Empty bullet → end the list: clear this line's marker.
                let clear = NSRange(location: lineRange.location, length: line.count)
                if shouldChangeText(in: clear, replacementString: "\n") {
                    textStorage?.replaceCharacters(in: clear, with: "\n")
                    didChangeText()
                }
                return
            }
            // Continue the list with same indent + marker.
            super.insertNewline(sender)
            insertText(leading + marker, replacementRange: selectedRange())
            return
        }

        // Plain line: keep its indentation on the next line.
        super.insertNewline(sender)
        if !leading.isEmpty { insertText(leading, replacementRange: selectedRange()) }
    }
}

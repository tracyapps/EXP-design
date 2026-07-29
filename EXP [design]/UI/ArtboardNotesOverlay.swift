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
//  THREE THINGS HERE ARE LOAD-BEARING FOR PERFORMANCE — read before editing:
//
//  1. Typing does NOT touch the model. The editor writes to a local draft; the
//     draft is committed on a ~400ms idle debounce and on end-editing. Writing
//     per keystroke meant a full `Document` value copy, a `resolveGeneration`
//     bump (which invalidates the canvas's per-instance resolution cache), and a
//     separate undo registration for every character typed. On a 600-artboard
//     import that was the most expensive path in the app running per keypress.
//
//  2. A whole typing burst collapses into ONE undo entry. The first commit of a
//     session registers the undo; later commits in that session write straight to
//     the model. The session ends when the editor resigns first responder or the
//     panel closes.
//
//  3. Buttons are culled to the visible viewport. Documents can hold hundreds of
//     artboards; without culling every one of them rebuilt a button on every
//     pan/zoom frame. Boards that already HAVE notes always keep their button;
//     the empty "add notes" affordance appears only once a board is big enough
//     on screen to be worth annotating.
//
//  The editor is an NSTextView (via NotesEditor) so we get real multi-line
//  editing: Return = line break, Tab/Shift-Tab = indent/outdent, and bullet and
//  checkbox lines auto-continue on Return. Light formatting (bold, italic,
//  heading, bullets, checkboxes) is drawn by styling the plain string IN PLACE —
//  there is no rich-text storage and no Markdown renderer, so `Artboard.notes`
//  stays a plain String and the model, codec, and agent contract are unchanged.
//

import SwiftUI
import AppKit

struct ArtboardNotesOverlay: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager

    /// Roomier than a sticky note: ~8 lines of body text at the default width,
    /// which is about where a real handoff note lands before you resize it.
    private static let defaultSize = CGSize(width: 320, height: 180)

    /// Below this on-screen width, an empty board's "add notes" button is hidden.
    /// Boards that already have notes always show theirs.
    private static let minOnScreenWidthForEmptyButton: CGFloat = 120

    /// How far the panel's right edge reaches PAST the artboard's left edge. Just
    /// enough overlap to read as attached to the board; the body of the note still
    /// sits in empty canvas so you can write about a board without covering it.
    private static let boardOverlap: CGFloat = 34

    /// True while an editing session is in flight. The FIRST commit of a session
    /// registers the undo entry; every later commit in the same session writes
    /// straight to the model, so a typing burst is one undo step, not many.
    @State private var sessionActive = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(visibleArtboards) { artboard in
                    let anchor = labelAnchor(artboard)

                    NotesButton(hasNotes: !artboard.notes.isEmpty,
                                isOpen: app.openNotesArtboardIDs.contains(artboard.id)) {
                        app.toggleNotes(artboard.id)   // the panel flushes on disappear
                    }
                    .offset(x: anchor.x - 22, y: anchor.y)

                    if app.openNotesArtboardIDs.contains(artboard.id) {
                        let origin = panelOrigin(artboard, anchor: anchor, viewport: geo.size)

                        NotesPanel(title: artboard.name,
                                   externalText: artboard.notes,
                                   size: sizeBinding(artboard.id),
                                   origin: origin,
                                   commit: { self.commit($0, to: artboard.id) },
                                   endSession: { self.endSession() },
                                   close: {
                                       self.endSession()
                                       app.toggleNotes(artboard.id)
                                   })
                        .id(artboard.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Culling

    /// Artboards worth building an overlay for. Evaluated ONCE per body pass (not
    /// per row) — filtering a few hundred rects is trivial; building a few hundred
    /// SwiftUI buttons on every pan frame is not.
    private var visibleArtboards: [Artboard] {
        let all = document.model.page(for: app.activeCanvasPageID)?.artboards ?? []
        guard let visible = app.visibleDocumentRect else { return all }

        // The button and label sit ~40pt above the frame in VIEW space, so pad the
        // test in document space by that much: a board scrolled just off the top
        // can still own a visible button.
        let pad = 48 / max(app.zoom, 0.01)
        let probe = visible.insetBy(dx: -pad, dy: -pad)

        return all.filter { artboard in
            guard artboard.frame.intersects(probe) else { return false }
            if !artboard.notes.isEmpty { return true }
            if app.openNotesArtboardIDs.contains(artboard.id) { return true }
            return artboard.frame.width * app.zoom >= Self.minOnScreenWidthForEmptyButton
        }
    }

    // MARK: - Geometry

    /// View-space point at the left edge of the artboard's name label (drawn
    /// ~22pt above the frame's top edge in the canvas).
    private func labelAnchor(_ artboard: Artboard) -> CGPoint {
        CGPoint(x: artboard.frame.minX * app.zoom + app.panOffset.x,
                y: artboard.frame.minY * app.zoom + app.panOffset.y - 22)
    }

    /// The panel drops straight down from the notes button with its TOP-RIGHT
    /// corner pinned just inside the board's left edge, so it grows LEFT into empty
    /// canvas and never buries the artboard it describes. That pin is also what the
    /// resize grips work against — see `NotesPanel`.
    private func panelOrigin(_ artboard: Artboard, anchor: CGPoint, viewport: CGSize) -> CGPoint {
        let width = (app.notesPanelSize[artboard.id] ?? Self.defaultSize).width
        let margin: CGFloat = 8

        var right = anchor.x + Self.boardOverlap    // right edge, slightly over the board
        var y = anchor.y + 20                       // just below the button

        if viewport.width > 0 { right = min(right, viewport.width - margin) }
        // Height auto-grows, so clamp on the header instead of the full box: the
        // title bar and close button always stay reachable.
        if viewport.height > 0 { y = min(y, viewport.height - 72) }
        y = max(margin, y)

        return CGPoint(x: max(margin, right - width), y: y)
    }

    private func sizeBinding(_ id: UUID) -> Binding<CGSize> {
        Binding(
            get: { app.notesPanelSize[id] ?? Self.defaultSize },
            set: { app.notesPanelSize[id] = $0 }
        )
    }

    // MARK: - Debounced commit + coalesced undo

    /// Write the draft into the model. The first commit of a session registers the
    /// undo entry (so the pre-typing state is always recoverable even if the window
    /// goes away mid-session); later commits in the same session skip registration,
    /// which is what collapses a typing burst into one "Edit Notes" step.
    private func commit(_ text: String, to id: UUID) {
        var model = document.model
        guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID),
              let i = model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }),
              model.pages[pageIndex].artboards[i].notes != text else { return }

        model.pages[pageIndex].artboards[i].notes = text

        if sessionActive {
            document.model = model
        } else {
            sessionActive = true
            document.setModel(model, undoManager: undoManager, actionName: "Edit Notes")
        }
    }

    /// End the editing session, so the next burst of typing starts a fresh undo step.
    private func endSession() { sessionActive = false }
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
    /// The model's current value. Typing does NOT flow back through this — it only
    /// re-seeds the draft when the model changes underneath us (undo/redo).
    let externalText: String
    @Binding var size: CGSize        // persisted manual size (width, min height)
    let origin: CGPoint
    let commit: (String) -> Void
    let endSession: () -> Void
    let close: () -> Void

    /// What the editor actually edits. Kept local so keystrokes never touch the
    /// document; see the perf note at the top of this file.
    @State private var draft: String = ""
    @State private var contentHeight: CGFloat = 0
    @State private var dragStart: CGSize?
    @State private var commitTask: Task<Void, Never>?

    private let minW: CGFloat = 200, maxW: CGFloat = 520
    private let minH: CGFloat = 72, maxH: CGFloat = 600

    /// How long the editor sits idle before the draft is written to the model.
    /// Short enough that an autosave or a crash costs at most this much typing,
    /// long enough that ordinary typing never reaches the model.
    private static let commitDelay: Duration = .milliseconds(400)

    /// Auto-grow to fit text, but never below the manual height nor above the cap
    /// (beyond the cap the editor scrolls).
    private var editorHeight: CGFloat {
        min(maxH, max(size.height, contentHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "note.text").font(.caption2).foregroundStyle(.secondary)
                Text("Notes for").font(.caption).foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(action: closeNow) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close notes")
                .accessibilityLabel("Close notes")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Notes for \(title)")

            Divider().opacity(0.6)

            NotesEditor(text: $draft,
                        contentHeight: $contentHeight,
                        focusOnAppear: true,
                        onEndEditing: flushAndEndSession)
                .frame(height: editorHeight)
                .accessibilityLabel("Notes for \(title)")
                .accessibilityHint("Command B for bold, Command I for italic. Right click for heading, bullet, and checklist formatting.")
        }
        .padding(8)
        .frame(width: size.width, alignment: .topLeading)
        // Two shadows, not one: a tight contact shadow anchors the panel to the
        // canvas, a broad ambient shadow lifts it clearly above the artboard
        // underneath. Opaque fill, no material — Reduce Transparency stays honest.
        .background(
            RoundedRectangle(cornerRadius: EXPMetric.radiusButton)
                .fill(EXPColor.surfaceRaised)
                .shadow(color: .black.opacity(0.34), radius: 20, y: 10)
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EXPMetric.radiusButton)
                .strokeBorder(EXPColor.borderSoft, lineWidth: EXPMetric.strokeHairline)
        )
        .overlay(alignment: .leading)       { edgeGrip(.left) }
        .overlay(alignment: .bottom)        { edgeGrip(.bottom) }
        .overlay(alignment: .bottomLeading) { cornerGrip }
        .offset(x: origin.x, y: origin.y)
        .onAppear { draft = externalText }
        .onDisappear { flushAndEndSession() }
        .onChange(of: draft) { _, newValue in
            commitTask?.cancel()
            commitTask = Task {
                try? await Task.sleep(for: Self.commitDelay)
                guard !Task.isCancelled else { return }
                commit(newValue)
                commitTask = nil
            }
        }
        .onChange(of: externalText) { _, newValue in
            // The model changed underneath us (undo/redo, or an agent write) and we
            // have nothing pending — take the new value.
            if commitTask == nil && newValue != draft { draft = newValue }
        }
    }

    /// Write anything outstanding immediately, then close the undo session.
    private func flushAndEndSession() {
        commitTask?.cancel()
        commitTask = nil
        commit(draft)
        endSession()
    }

    private func closeNow() {
        flushAndEndSession()
        close()
    }

    // MARK: Resize — the top-right corner is the pin

    // The panel's right edge is fixed to the artboard, so growing WIDER means
    // growing leftward: the left edge and the bottom-left corner both subtract the
    // drag's x translation. Top and right are the pin and deliberately have no grip.
    private enum GripEdge { case left, bottom }

    @ViewBuilder
    private func edgeGrip(_ edge: GripEdge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: edge == .left ? 7 : nil, height: edge == .bottom ? 7 : nil)
            .frame(maxWidth: edge == .bottom ? .infinity : nil,
                   maxHeight: edge == .left ? .infinity : nil)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .left ? .leading : .bottom))
            .gesture(resizeGesture(horizontal: edge == .left, vertical: edge == .bottom))
            .help(edge == .left ? "Drag to widen" : "Drag to change height")
            .accessibilityHidden(true)
    }

    private var cornerGrip: some View {
        Image(systemName: "chevron.left.chevron.right")
            .font(.system(size: 7, weight: .bold))
            .rotationEffect(.degrees(45))
            .foregroundStyle(.tertiary)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .bottomLeading))
            .gesture(resizeGesture(horizontal: true, vertical: true))
            .help("Drag to resize")
            .accessibilityHidden(true)
    }

    private func resizeGesture(horizontal: Bool, vertical: Bool) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if dragStart == nil { dragStart = size }
                let base = dragStart ?? size
                size = CGSize(
                    width: horizontal ? min(maxW, max(minW, base.width - v.translation.width))
                                      : base.width,
                    height: vertical ? min(maxH, max(minH, base.height + v.translation.height))
                                     : base.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }
}

// MARK: - NSTextView-backed editor (line breaks, Tab indent, list continuation)

private struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var focusOnAppear: Bool = false
    var onEndEditing: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NotesTextView()
        tv.delegate = context.coordinator
        // Plain text storage: formatting is drawn as attributes over the string,
        // never stored in it, so `tv.string` is always exactly what we persist.
        tv.isRichText = false
        tv.font = NotesTextView.bodyFont
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        tv.string = text
        tv.enableFormatting()

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
        guard let tv = scroll.documentView as? NotesTextView else { return }
        context.coordinator.parent = self
        if tv.string != text {
            tv.string = text
            tv.restyleAll()
        }
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
        var parent: NotesEditor
        init(_ parent: NotesEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.reportHeight(tv)
        }

        /// First responder lost — this is the natural end of an editing session, so
        /// the pending draft is flushed and the undo entry is closed here.
        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }
    }
}

/// NSTextView that turns Tab into indentation, continues bullet and checkbox
/// lists, and draws light formatting over the plain string.
///
/// Formatting is deliberately small: bold, italic, one heading level, bullets and
/// checkboxes. No links, tables, images, or code blocks — those belong in the
/// handoff artifact, not in a canvas sticky note. Markers are dimmed rather than
/// hidden, because hiding them makes the caret jump in ways that feel broken.
private final class NotesTextView: NSTextView, NSTextStorageDelegate {

    // MARK: Fonts + limits

    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let boldFont = NSFont.boldSystemFont(ofSize: 13)
    static let headingFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static var italicFont: NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    }
    static var boldItalicFont: NSFont {
        NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
    }

    /// Past this length the editor stops styling and behaves as plain text. A note
    /// this long is a document, not a note, and styling it on every keystroke would
    /// be exactly the kind of weight this feature is not allowed to add.
    private static let maxStyledLength = 20_000

    private let indent = "    "                 // 4 spaces
    private let bulletMarkers = ["• ", "- ", "* "]
    private let checkboxMarkers = ["[ ] ", "[x] ", "[X] "]

    private var isRestyling = false

    // MARK: Inline patterns (compiled once)

    private static let boldPattern = try! NSRegularExpression(
        pattern: "\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*")
    private static let italicPattern = try! NSRegularExpression(
        pattern: "(?<![\\w_])_(?=\\S)(.+?)(?<=\\S)_(?![\\w_])")

    /// Dimmed marker colour, but never dimmed away entirely when the user has asked
    /// the system for increased contrast.
    private var markerColor: NSColor {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .secondaryLabelColor
            : .tertiaryLabelColor
    }

    // MARK: Setup

    func enableFormatting() {
        textStorage?.delegate = self
        restyleAll()
    }

    func restyleAll() {
        guard let ts = textStorage else { return }
        restyle(NSRange(location: 0, length: ts.length))
    }

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isRestyling else { return }
        restyle(editedRange)
    }

    /// Restyle only the paragraphs the edit touched. A keystroke costs one line's
    /// worth of regex, not the whole note.
    private func restyle(_ range: NSRange) {
        guard let ts = textStorage else { return }
        isRestyling = true
        defer { isRestyling = false }

        let ns = ts.string as NSString
        let safe = NSRange(location: min(range.location, ns.length),
                           length: min(range.length, max(0, ns.length - min(range.location, ns.length))))
        let scope = ns.paragraphRange(for: safe)
        guard scope.length > 0 else { return }

        ts.setAttributes([.font: Self.bodyFont, .foregroundColor: NSColor.labelColor], range: scope)
        guard ts.length <= Self.maxStyledLength else { return }

        let text = ts.string
        ns.enumerateSubstrings(in: scope, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            self.styleLine(lineRange, in: ts, ns: ns, text: text)
        }
    }

    private func styleLine(_ lineRange: NSRange, in ts: NSTextStorage, ns: NSString, text: String) {
        guard lineRange.length > 0 else { return }
        let line = ns.substring(with: lineRange)
        // Every marker below is ASCII (or a single BMP bullet), so Character counts
        // and UTF-16 offsets agree and can be mixed with `lineRange` safely.
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let afterLeading = String(line.dropFirst(leading))
        var bodyStart = lineRange.location + leading

        // Heading: "# " makes the whole line a heading; the marker stays visible but dimmed.
        if afterLeading.hasPrefix("# ") {
            ts.addAttribute(.font, value: Self.headingFont, range: lineRange)
            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: bodyStart, length: 2))
            bodyStart += 2
        }
        // Checkbox: "[ ] " / "[x] ". A checked line is struck through and dimmed.
        else if let marker = checkboxMarkers.first(where: { afterLeading.hasPrefix($0) }) {
            let markerRange = NSRange(location: bodyStart, length: marker.count)
            ts.addAttribute(.foregroundColor,
                            value: marker == "[ ] " ? markerColor : NSColor.secondaryLabelColor,
                            range: markerRange)
            if marker != "[ ] " {
                let rest = NSRange(location: bodyStart + marker.count,
                                   length: max(0, lineRange.length - leading - marker.count))
                if rest.length > 0 {
                    ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: rest)
                    ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: rest)
                }
            }
            bodyStart += marker.count
        }
        // Bullet: dim the marker so the text itself reads as the content.
        else if let marker = bulletMarkers.first(where: { afterLeading.hasPrefix($0) }) {
            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: bodyStart, length: marker.count))
            bodyStart += marker.count
        }

        // Inline emphasis over the remainder of the line.
        let bodyRange = NSRange(location: bodyStart,
                                length: max(0, lineRange.location + lineRange.length - bodyStart))
        guard bodyRange.length > 0 else { return }

        applyInline(Self.boldPattern, markerLength: 2, in: bodyRange, ts: ts, text: text) { current in
            NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
        }
        applyInline(Self.italicPattern, markerLength: 1, in: bodyRange, ts: ts, text: text) { current in
            NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
        }
    }

    /// Apply a font trait to the content between markers and dim the markers.
    /// Traits compose, so `**_both_**` renders bold-italic.
    private func applyInline(_ pattern: NSRegularExpression,
                             markerLength: Int,
                             in range: NSRange,
                             ts: NSTextStorage,
                             text: String,
                             transform: (NSFont) -> NSFont) {
        pattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges > 1 else { return }
            let full = m.range
            let content = m.range(at: 1)
            guard content.length > 0 else { return }

            let current = (ts.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont)
                ?? Self.bodyFont
            ts.addAttribute(.font, value: transform(current), range: content)

            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: full.location, length: markerLength))
            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: full.location + full.length - markerLength,
                                           length: markerLength))
        }
    }

    // MARK: ⌘B / ⌘I — so nobody has to type asterisks

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch chars {
        case "b": wrapSelection(with: "**"); return true
        case "i": wrapSelection(with: "_");  return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }

    /// Wrap the selection in `marker`, or unwrap it if it's already wrapped. With
    /// an empty selection, inserts the pair and parks the caret between them.
    private func wrapSelection(with marker: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let n = marker.count

        // Already wrapped? Unwrap.
        if sel.length >= n * 2 {
            let inner = ns.substring(with: sel)
            if inner.hasPrefix(marker) && inner.hasSuffix(marker) {
                let stripped = String(inner.dropFirst(n).dropLast(n))
                if shouldChangeText(in: sel, replacementString: stripped) {
                    textStorage?.replaceCharacters(in: sel, with: stripped)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location, length: stripped.utf16.count))
                }
                return
            }
        }

        let selected = sel.length > 0 ? ns.substring(with: sel) : ""
        let replacement = marker + selected + marker
        guard shouldChangeText(in: sel, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: sel, with: replacement)
        didChangeText()
        if sel.length > 0 {
            setSelectedRange(NSRange(location: sel.location + n, length: selected.utf16.count))
        } else {
            setSelectedRange(NSRange(location: sel.location + n, length: 0))
        }
    }

    // MARK: Right-click Format menu

    // The keyboard shortcuts above are not the only way in. ⌘B / ⌘I are also
    // Type ▸ Bold / Italic in the menu bar (disabled unless canvas text is being
    // edited, so they don't fight each other), and everything here is reachable by
    // right-click — which is how someone who doesn't know the syntax discovers it.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())

        let format = NSMenu(title: "Format")
        let entries: [(String, Selector, String)] = [
            ("Bold",      #selector(notesToggleBold(_:)),      "b"),
            ("Italic",    #selector(notesToggleItalic(_:)),    "i"),
            ("Heading",   #selector(notesToggleHeading(_:)),   ""),
            ("Bullet",    #selector(notesToggleBullet(_:)),    ""),
            ("Checklist", #selector(notesToggleChecklist(_:)), "")
        ]
        for (title, action, key) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            format.addItem(item)
        }

        let host = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        host.submenu = format
        menu.addItem(host)
        return menu
    }

    @objc private func notesToggleBold(_ sender: Any?) { wrapSelection(with: "**") }
    @objc private func notesToggleItalic(_ sender: Any?) { wrapSelection(with: "_") }

    @objc private func notesToggleHeading(_ sender: Any?) {
        toggleLinePrefix("# ", replacing: ["- ", "* ", "• ", "[ ] ", "[x] ", "[X] "])
    }

    @objc private func notesToggleBullet(_ sender: Any?) {
        toggleLinePrefix("- ", replacing: ["* ", "• ", "# ", "[ ] ", "[x] ", "[X] "])
    }

    @objc private func notesToggleChecklist(_ sender: Any?) {
        toggleLinePrefix("[ ] ", replacing: ["[x] ", "[X] ", "- ", "* ", "• ", "# "])
    }

    /// Add `prefix` to every line touched by the selection, or strip it if they all
    /// already have it. `replacing` are the other line markers, so switching a
    /// bullet to a checkbox swaps rather than stacks.
    private func toggleLinePrefix(_ prefix: String, replacing siblings: [String]) {
        let ns = string as NSString
        var block = ns.lineRange(for: selectedRange())
        guard block.length > 0 else { return }

        // Keep the paragraph terminator out of the rewrite.
        if ns.substring(with: NSRange(location: block.location + block.length - 1, length: 1)) == "\n" {
            block.length -= 1
        }
        guard block.length > 0 else { return }

        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let allPrefixed = lines.allSatisfy { line in
            String(line.drop { $0 == " " || $0 == "\t" }).hasPrefix(prefix)
        }

        let rebuilt = lines.map { line -> String in
            let leading = String(line.prefix { $0 == " " || $0 == "\t" })
            var body = String(line.dropFirst(leading.count))
            for marker in [prefix] + siblings where body.hasPrefix(marker) {
                body = String(body.dropFirst(marker.count))
                break
            }
            return allPrefixed ? leading + body : leading + prefix + body
        }.joined(separator: "\n")

        let target = NSRange(location: block.location, length: block.length)
        guard shouldChangeText(in: target, replacementString: rebuilt) else { return }
        textStorage?.replaceCharacters(in: target, with: rebuilt)
        didChangeText()
        setSelectedRange(NSRange(location: block.location, length: (rebuilt as NSString).length))
    }

    // MARK: Indentation + list continuation

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

        // A checkbox line continues as an UNCHECKED checkbox, never a checked one.
        if let marker = checkboxMarkers.first(where: { afterLeading.hasPrefix($0) }) {
            let content = afterLeading.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { clearLine(lineRange, length: line.count); return }
            super.insertNewline(sender)
            insertText(leading + "[ ] ", replacementRange: selectedRange())
            return
        }

        if let marker = bulletMarkers.first(where: { afterLeading.hasPrefix($0) }) {
            let content = afterLeading.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { clearLine(lineRange, length: line.count); return }
            // Continue the list with same indent + marker.
            super.insertNewline(sender)
            insertText(leading + marker, replacementRange: selectedRange())
            return
        }

        // Plain line: keep its indentation on the next line.
        super.insertNewline(sender)
        if !leading.isEmpty { insertText(leading, replacementRange: selectedRange()) }
    }

    /// Empty list item + Return → end the list.
    private func clearLine(_ lineRange: NSRange, length: Int) {
        let clear = NSRange(location: lineRange.location, length: length)
        if shouldChangeText(in: clear, replacementString: "\n") {
            textStorage?.replaceCharacters(in: clear, with: "\n")
            didChangeText()
        }
    }
}

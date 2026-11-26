import AppKit
import SwiftUI

enum DLSourceCommand { case toggleBlock, foldAll, expandAll }

@Observable
final class DLSourceControls {
    var hasFolds = false
    @ObservationIgnored var perform: ((DLSourceCommand) -> Void)?
}

struct DLSourceTextView: NSViewRepresentable {
    let source: String
    let format: DLCodeFormat
    let onEdit: ((String) -> Void)?
    let controls: DLSourceControls

    func makeCoordinator() -> Coordinator { Coordinator(format: format) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.backgroundColor = .textBackgroundColor

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let text = SourceEditor(frame: CGRect(origin: .zero, size: scroll.contentSize), textContainer: container)
        context.coordinator.storage = storage
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.usesFindBar = true
        text.allowsUndo = true
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.maxSize = NSSize(width: .greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = text.maxSize
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.setAccessibilityLabel(format == .json ? "Design Language JSON source" : "\(format.rawValue) source")
        text.setAccessibilityIdentifier("designLanguage.code.\(format.rawValue.lowercased())")
        scroll.documentView = text

        let coordinator = context.coordinator
        coordinator.text = text
        coordinator.controls = controls
        controls.perform = { [weak coordinator] command in coordinator?.perform(command) }
        text.delegate = coordinator
        text.onCopy = { [weak coordinator] in coordinator?.copySelection() ?? false }
        let ruler = SourceRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.clipsToBounds = true
        ruler.editor = coordinator
        ruler.clientView = text
        ruler.ruleThickness = 55
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        coordinator.ruler = ruler
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEdit = onEdit
        if let text = coordinator.text {
            let font = NSFont.monospacedSystemFont(ofSize: 12 * EXPInterfaceAccessibility.shared.textScale,
                                                   weight: .regular)
            if text.font != font { text.font = font }
            text.isEditable = onEdit != nil && coordinator.folded.isEmpty
        }
        if source != coordinator.source { coordinator.load(source) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let format: DLCodeFormat
        weak var text: SourceEditor?
        weak var ruler: SourceRuler?
        weak var controls: DLSourceControls?
        var storage: NSTextStorage?
        var onEdit: ((String) -> Void)?
        private let undo = UndoManager()
        private(set) var source = ""
        private(set) var folded: Set<DLCodeSyntax.Fold> = []
        private var syntax: DLCodeSyntax
        private var foldStarts: [Int: DLCodeSyntax.Fold] = [:]
        private var projection = DLCodeSyntax.Projection(text: "", replacements: [])
        private(set) var displayLines = [0]
        private var isRefreshing = false

        init(format: DLCodeFormat) {
            self.format = format
            syntax = DLCodeSyntax("", format: format)
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func load(_ next: String) {
            source = next
            folded.removeAll()
            updateAnalysis()
            render(preservePosition: false)
            undo.removeAllActions()
        }

        func textDidChange(_ notification: Notification) {
            guard let text, folded.isEmpty, !isRefreshing else { return }
            source = text.string
            updateAnalysis()
            projection = syntax.project(source, folded: [])
            displayLines = syntax.lines
            colorize()
            onEdit?(source)
        }

        private func updateAnalysis() {
            syntax = DLCodeSyntax(source, format: format)
            foldStarts = Dictionary(syntax.folds.map {
                (DLCodeSyntax.lineIndex(containing: $0.opening, in: syntax.lines), $0)
            }, uniquingKeysWith: { first, _ in first })
        }

        private func render(preservePosition: Bool) {
            guard let text else { return }
            isRefreshing = true
            defer { isRefreshing = false }
            let previous = text.selectedRange()
            let position = projection.sourceOffset(for: previous.location)
            let end = projection.sourceOffset(for: NSMaxRange(previous), trailing: true)
            projection = syntax.project(source, folded: folded)
            displayLines = folded.isEmpty ? syntax.lines : DLCodeSyntax.lineStarts(projection.text as NSString)
            text.breakUndoCoalescing()
            undo.disableUndoRegistration()
            let font = text.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
            text.textStorage?.setAttributedString(NSAttributedString(string: projection.text, attributes: attributes))
            text.typingAttributes = attributes
            undo.enableUndoRegistration()
            text.isEditable = onEdit != nil && folded.isEmpty
            let newStart = projection.displayOffset(for: position)
            let newEnd = projection.displayOffset(for: end)
            if preservePosition {
                let range = NSRange(location: newStart, length: max(0, newEnd - newStart))
                text.setSelectedRange(range)
                text.scrollRangeToVisible(range)
            } else {
                text.setSelectedRange(NSRange(location: 0, length: 0))
                text.scroll(.zero)
            }
            colorize()
            let hasFolds = !folded.isEmpty
            // Loading an export may come from a SwiftUI representable update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.folded.isEmpty != hasFolds else { return }
                self.controls?.hasFolds = hasFolds
            }
        }

        private func colorize() {
            guard let text, let layout = text.layoutManager else { return }
            let length = (projection.text as NSString).length
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for item in syntax.highlights {
                let start = projection.displayOffset(for: item.range.location)
                let end = projection.displayOffset(for: NSMaxRange(item.range))
                guard end > start, projection.sourceOffset(for: start) == item.range.location else { continue }
                let range = NSRange(location: start, length: end - start)
                layout.addTemporaryAttribute(.foregroundColor, value: ink(item.style), forCharacterRange: range)
            }
            for replacement in projection.replacements {
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                             forCharacterRange: replacement.display)
            }
            ruler?.needsDisplay = true
        }

        private func ink(_ style: DLCodeSyntax.Style) -> NSColor {
            if style == .comment { return .secondaryLabelColor }
            let colors: (light: UInt32, dark: UInt32)
            switch style {
            case .key, .directive: colors = (0x7041A0, 0xDBB0FC)
            case .string: colors = (0x22623D, 0xA9DB94)
            case .number: colors = (0x884516, 0xF0B380)
            case .literal: colors = (0x8C3656, 0xF7A6C4)
            case .variable: colors = (0x155E86, 0x92CEFC)
            case .comment: colors = (0x5C5C5C, 0xACACAC)
            }
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let rgb = dark ? colors.dark : colors.light
                return NSColor(srgbRed: CGFloat(rgb >> 16) / 255,
                               green: CGFloat(rgb >> 8 & 255) / 255,
                               blue: CGFloat(rgb & 255) / 255, alpha: 1)
            }
        }

        func originalLine(_ displayLine: Int) -> Int {
            let offset = projection.sourceOffset(for: displayLines[displayLine])
            return DLCodeSyntax.lineIndex(containing: offset, in: syntax.lines)
        }

        func fold(onDisplayLine line: Int) -> DLCodeSyntax.Fold? { foldStarts[originalLine(line)] }

        func toggleFold(onDisplayLine line: Int) {
            if let block = fold(onDisplayLine: line) { toggle(block) }
        }

        private func toggle(_ block: DLCodeSyntax.Fold) {
            if folded.remove(block) == nil { folded.insert(block) }
            render(preservePosition: true)
        }

        func perform(_ command: DLSourceCommand) {
            switch command {
            case .toggleBlock:
                if let selection = text?.selectedRange(),
                   let block = syntax.fold(at: projection.sourceOffset(for: selection.location)) {
                    toggle(block)
                }
            case .foldAll:
                var blocks = syntax.folds
                if format == .json, blocks.count > 1 { blocks.removeFirst() }
                guard !blocks.isEmpty else { return }
                folded = Set(blocks)
                render(preservePosition: true)
            case .expandAll:
                guard !folded.isEmpty else { return }
                folded.removeAll()
                render(preservePosition: true)
            }
        }

        func copySelection() -> Bool {
            guard !folded.isEmpty, let range = text?.selectedRange(), range.length > 0 else { return false }
            let start = projection.sourceOffset(for: range.location)
            let end = projection.sourceOffset(for: NSMaxRange(range), trailing: true)
            let value = (source as NSString).substring(with: NSRange(location: start, length: end - start))
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(value, forType: .string)
        }
    }

    final class SourceEditor: NSTextView {
        var onCopy: (() -> Bool)?

        override func copy(_ sender: Any?) {
            if onCopy?() != true { super.copy(sender) }
        }
    }

    final class SourceRuler: NSRulerView {
        weak var editor: Coordinator?

        override var isFlipped: Bool { true }
        override func isAccessibilityElement() -> Bool { false }

        override func drawHashMarksAndLabels(in rect: NSRect) {
            // An AppKit dirty rectangle can include the rest of the pane.
            // Keep the gutter background and labels inside the ruler.
            let dirty = rect.intersection(bounds)
            guard !dirty.isEmpty else { return }
            guard let editor, let text = editor.text, let layout = text.layoutManager,
                  let container = text.textContainer else { return }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSBezierPath(rect: dirty).addClip()
            let origin = text.textContainerOrigin
            let visible = text.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
            let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let first = DLCodeSyntax.lineIndex(containing: chars.location, in: editor.displayLines)
            let last = DLCodeSyntax.lineIndex(containing: NSMaxRange(chars), in: editor.displayLines)
            let font = NSFont.monospacedDigitSystemFont(ofSize: text.font?.pointSize ?? 12, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            let length = (text.string as NSString).length
            NSColor.controlBackgroundColor.setFill()
            dirty.fill()
            NSColor.separatorColor.setFill()
            CGRect(x: bounds.maxX - 1, y: dirty.minY, width: 1, height: dirty.height).fill()
            for line in first...last {
                let char = editor.displayLines[line]
                let fragment: NSRect
                if char == length {
                    fragment = layout.extraLineFragmentRect
                } else {
                    let glyph = layout.glyphIndexForCharacter(at: char)
                    fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                }
                let position = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: text)
                let label = String(editor.originalLine(line) + 1) as NSString
                let size = label.size(withAttributes: attributes)
                let y = position.y + (fragment.height - size.height) / 2
                label.draw(at: NSPoint(x: bounds.maxX - 17 - size.width, y: y), withAttributes: attributes)
                if let block = editor.fold(onDisplayLine: line) {
                    let arrow = (editor.folded.contains(block) ? "▸" : "▾") as NSString
                    arrow.draw(at: NSPoint(x: bounds.maxX - 13, y: y), withAttributes: attributes)
                }
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let editor, let text = editor.text, let layout = text.layoutManager,
                  let container = text.textContainer else { return }
            var point = text.convert(event.locationInWindow, from: nil)
            point.x = 0
            point.y -= text.textContainerOrigin.y
            let char = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            editor.toggleFold(onDisplayLine: DLCodeSyntax.lineIndex(containing: char, in: editor.displayLines))
        }
    }
}

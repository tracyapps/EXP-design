import AppKit

/// NSTextView that turns Tab into indentation, continues bullet and checkbox
/// lists, and draws light formatting over the plain string.
///
/// Formatting is deliberately small: emphasis, six ATX heading levels, basic
/// inline web/mail links, bullets and checkboxes. Images are never loaded. This
/// is an editable Markdown subset, not a full Markdown renderer. Markers are dimmed rather than
/// hidden, because hiding them makes the caret jump in ways that feel broken.
final class NotesTextView: NSTextView, NSTextStorageDelegate {
    static let formattingHelp = "Markdown: # through ###### for headings; [label](https://example.com) for links. Right click for formatting."

    // Native text operations contain ranges into this transient editor. Never
    // mix them with the document's whole-model snapshots: restoring a snapshot
    // can replace the string before AppKit invokes the older native operation.
    // The panel continues to commit one coalesced Edit Notes document snapshot.
    private let textHistory = UndoManager()
    override var undoManager: UndoManager? { textHistory }

    func replaceExternalText(_ value: String) {
        guard value != string else { return }
        textHistory.removeAllActions()
        string = value
        restyleAll()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { textHistory.removeAllActions() }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: Fonts + limits

    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let boldFont = NSFont.boldSystemFont(ofSize: 13)
    static let headingFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let headingSizes: [CGFloat] = [18, 16, 15, 14, 13, 13]
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
    private var hadCodeFence = false
    private var wasOversized = false

    // MARK: Inline patterns (compiled once)

    private static let boldPattern = try! NSRegularExpression(
        pattern: "\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*")
    private static let italicPattern = try! NSRegularExpression(
        pattern: "(?<![\\w_])_(?=\\S)(.+?)(?<=\\S)_(?![\\w_])")
    private static let headingPattern = try! NSRegularExpression(
        pattern: "^ {0,3}(#{1,6})(?:[ \\t]+|$)")
    // A deliberately bounded inline subset: visible label + destination, with
    // one balanced parenthesis pair in URLs. References/titles stay plain text.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"(?<!!)(?<!\\)\[([^\[\]\r\n]+)\]\(([^()\s]+(?:\([^()\s]*\)[^()\s]*)*)\)"#)
    private static let codePattern = try! NSRegularExpression(pattern: #"(`+).*?\1"#)

    /// Same allowlist at discovery and activation. Never dispatch file/custom
    /// schemes from a note or load images while styling it.
    static func linkDestination(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let url = components.url else { return nil }
        switch scheme {
        case "https", "http": return components.host?.isEmpty == false ? url : nil
        case "mailto": return components.path.isEmpty ? nil : url
        default: return nil
        }
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        let value = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
        guard let url = Self.linkDestination(value) else { return }
        super.clicked(onLink: url, at: charIndex)
    }

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
        // Ordinary edits still style only their paragraphs. Fence edits can
        // change following lines, so fence-containing notes get a bounded full
        // pass, including once after the last fence is removed.
        let oversized = ts.length > Self.maxStyledLength
        let hasFence = !oversized && (ts.string.contains("```") || ts.string.contains("~~~"))
        let fullPass = hasFence || hadCodeFence || oversized != wasOversized
        let scope = fullPass ? NSRange(location: 0, length: ns.length) : ns.paragraphRange(for: safe)
        hadCodeFence = hasFence
        wasOversized = oversized
        guard scope.length > 0 else { return }

        ts.setAttributes([.font: Self.bodyFont, .foregroundColor: NSColor.labelColor], range: scope)
        guard !oversized else { return }

        let text = ts.string
        var fence: (Character, Int)?
        ns.enumerateSubstrings(in: scope, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let trimmed = line.drop { $0 == " " }
            let indentation = line.count - trimmed.count
            if indentation < 4, let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix { $0 == first }.count
                if let current = fence {
                    if first == current.0, count >= current.1,
                       trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    return
                } else if count >= 3 {
                    fence = (first, count)
                    return
                }
            }
            guard fence == nil else { return }
            let prefix = line.prefix { $0 == " " || $0 == "\t" }
            let columns = prefix.reduce(0) { width, character in
                character == "\t" ? width + (4 - width % 4) : width + 1
            }
            // Existing indented checklist/bullet formatting remains intact.
            // Other indented text must not gain active links as a side effect.
            let body = String(line.dropFirst(prefix.count))
            let list = (self.checkboxMarkers + self.bulletMarkers).contains { body.hasPrefix($0) }
            self.styleLine(lineRange, in: ts, ns: ns, text: text, allowLinks: columns < 4 || list)
        }
    }

    private func styleLine(_ lineRange: NSRange, in ts: NSTextStorage, ns: NSString,
                           text: String, allowLinks: Bool) {
        guard lineRange.length > 0 else { return }
        let line = ns.substring(with: lineRange)
        // Every marker below is ASCII (or a single BMP bullet), so Character counts
        // and UTF-16 offsets agree and can be mixed with `lineRange` safely.
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let afterLeading = String(line.dropFirst(leading))
        var bodyStart = lineRange.location + leading

        // ATX headings, with visible syntax and distinct sizes. Four-space
        // indentation and seven hashes are plain text, not headings.
        if let heading = Self.headingPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let level = heading.range(at: 1).length
            let font = NSFont.systemFont(ofSize: Self.headingSizes[level - 1], weight: .semibold)
            ts.addAttribute(.font, value: font, range: lineRange)
            let markerLength = heading.range.length - leading
            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: bodyStart, length: markerLength))
            bodyStart += markerLength
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
        guard allowLinks else { return }
        let code = Self.codePattern.matches(in: text, range: bodyRange).map(\.range)
        for link in Self.linkPattern.matches(in: text, range: bodyRange) {
            guard !code.contains(where: { NSIntersectionRange($0, link.range).length > 0 }),
                  let destination = Self.linkDestination(ns.substring(with: link.range(at: 2))) else { continue }
            ts.addAttributes([.link: destination, .foregroundColor: NSColor.linkColor,
                              .underlineStyle: NSUnderlineStyle.single.rawValue], range: link.range(at: 1))
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
        toggleLinePrefix("# ", replacing: ["## ", "### ", "#### ", "##### ", "###### ", "- ", "* ", "• ", "[ ] ", "[x] ", "[X] "])
    }

    @objc private func notesToggleBullet(_ sender: Any?) {
        toggleLinePrefix("- ", replacing: ["* ", "• ", "# ", "## ", "### ", "#### ", "##### ", "###### ", "[ ] ", "[x] ", "[X] "])
    }

    @objc private func notesToggleChecklist(_ sender: Any?) {
        toggleLinePrefix("[ ] ", replacing: ["[x] ", "[X] ", "- ", "* ", "• ", "# ", "## ", "### ", "#### ", "##### ", "###### "])
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

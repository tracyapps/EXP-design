import AppKit

@MainActor
private final class LinkRecorder: NSObject, NSTextViewDelegate {
    var destinations: [URL] = []
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { destinations.append(url) }
        return true // Exercise native activation without opening a browser/mail app.
    }
}

@main
enum NotesFormattingCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        func require(_ value: Bool, _ message: String) {
            guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func editor(_ text: String) -> NotesTextView {
            let view = NotesTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
            view.isRichText = false
            view.allowsUndo = true
            view.string = text
            view.enableFormatting()
            return view
        }
        func attribute(_ view: NotesTextView, _ key: NSAttributedString.Key, _ text: String) -> Any? {
            let range = (view.string as NSString).range(of: text)
            return view.textStorage?.attribute(key, at: range.location, effectiveRange: nil)
        }
        for level in 1...6 {
            let text = String(repeating: "#", count: level) + " Heading 🧑🏽‍🎨"
            let view = editor(text)
            let font = attribute(view, .font, "Heading") as! NSFont
            require(font.fontDescriptor.symbolicTraits.contains(.bold), "heading level \(level) must be emphasized")
            require(view.string == text, "styling must preserve source at level \(level)")
        }
        print("ok: six heading levels and Unicode source preservation")
        let links = "🧑🏽‍🎨 [Design guide](https://example.com/guide_(design)) and [Email](mailto:hello@example.com)"
        let view = editor(links)
        require((attribute(view, .link, "Design guide") as? URL)?.absoluteString == "https://example.com/guide_(design)", "web link destination/Unicode range")
        require((attribute(view, .link, "Email") as? URL)?.scheme == "mailto", "mail link")
        require(view.string == links, "link styling must preserve saved Markdown")
        require(attribute(view, .underlineStyle, "Design guide") as? Int == NSUnderlineStyle.single.rawValue, "link distinction must not rely on color alone")
        print("ok: native link attributes, balanced URL parentheses and non-color distinction")
        for text in ["[Bad](javascript:alert)", "[Bad](file:///tmp/private)", "[Bad](exp://apply)",
                     "[Bad](data:text/plain,secret)", "[Bad](https:missing-host)",
                     "![Bad](https://example.com/image)", #"\[Bad](https://example.com)"#,
                     "`[Bad](https://example.com)`", "```\n[Bad](https://example.com)\n```"] {
            let plain = editor(text)
            require(attribute(plain, .link, "Bad") == nil, "unsafe, image, escaped or code syntax must stay inert: \(text)")
        }
        print("ok: unsafe schemes, malformed hosts, images, escapes and code remain inert")
        let recorder = LinkRecorder()
        view.delegate = recorder
        let linkIndex = (links as NSString).range(of: "Design guide").location
        view.clicked(onLink: URL(string: "https://example.com/guide_(design)")!, at: linkIndex)
        require(recorder.destinations.count == 1, "native link activation reaches delegate")
        view.clicked(onLink: URL(fileURLWithPath: "/tmp/private"), at: linkIndex)
        view.clicked(onLink: "exp://apply", at: linkIndex)
        require(recorder.destinations.count == 1, "activation must revalidate unsupported schemes")
        print("ok: real NSTextView link activation and activation-time scheme guard")
        view.string = "Design guide"
        view.restyleAll()
        require(attribute(view, .link, "Design guide") == nil, "removing Markdown must clear link attributes")
        let ordinary = editor("####### Too many\n#NoSpace\n    ## Indented code")
        for word in ["Too many", "NoSpace", "Indented code"] {
            let font = attribute(ordinary, .font, word) as! NSFont
            require(!font.fontDescriptor.symbolicTraits.contains(.bold), "invalid heading must remain body text")
        }
        let emphasis = editor("**Bold** and _italic_\n[x] Done")
        require((attribute(emphasis, .font, "Bold") as! NSFont).fontDescriptor.symbolicTraits.contains(.bold), "existing bold")
        require((attribute(emphasis, .font, "italic") as! NSFont).fontDescriptor.symbolicTraits.contains(.italic), "existing italic")
        require(attribute(emphasis, .strikethroughStyle, "Done") as? Int == NSUnderlineStyle.single.rawValue, "existing checked task")
        let nested = editor("    [x] Nested task")
        require(attribute(nested, .strikethroughStyle, "Nested task") as? Int == NSUnderlineStyle.single.rawValue, "existing indented checklist styling")
        print("ok: stale links cleared; heading boundaries and existing emphasis/tasks preserved")

        let formatted = editor("### Details")
        formatted.setSelectedRange(NSRange(location: 4, length: 7))
        formatted.perform(NSSelectorFromString("notesToggleBullet:"), with: nil)
        require(formatted.string == "- Details", "switching a level-three heading to a bullet replaces the marker")
        formatted.perform(NSSelectorFromString("notesToggleHeading:"), with: nil)
        require(formatted.string == "# Details", "existing Heading action stays available")
        formatted.perform(NSSelectorFromString("notesToggleChecklist:"), with: nil)
        require(formatted.string == "[ ] Details", "switching headings to checklists replaces the marker")
        formatted.setSelectedRange(NSRange(location: (formatted.string as NSString).length, length: 0))
        formatted.insertNewline(nil)
        require(formatted.string == "[ ] Details\n[ ] ", "existing task continuation")
        formatted.insertNewline(nil)
        require(formatted.string == "[ ] Details\n\n", "Return on empty task ends list")
        print("ok: existing format actions replace heading levels; task continuation/end retained")

        let growing = editor("[Guide](https://example.com)\n")
        growing.insertText(String(repeating: "x", count: 20_001), replacementRange: NSRange(location: (growing.string as NSString).length, length: 0))
        require(attribute(growing, .link, "Guide") == nil, "crossing the styling limit clears earlier link attributes")
        growing.string = "[Guide](https://example.com)"
        growing.restyleAll()
        require(attribute(growing, .link, "Guide") is URL, "shrinking restores link styling")
        let fence = editor("```\n[Guide](https://example.com)\n```")
        fence.insertText("", replacementRange: NSRange(location: 0, length: 4))
        require(attribute(fence, .link, "Guide") is URL, "removing an opening fence restyles following lines")
        print("ok: long-note fallback and downstream fence edits do not leave stale links")

        if CommandLine.arguments.count == 2 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = NSAppearance(named: name)!
                appearance.performAsCurrentDrawingAppearance {
                    let sample = editor("# Project notes\n## Research\n### Details\n#### Decisions\n##### Follow up\n###### References\n\n**Bold**, _italic_ and [Design guide](https://example.com)\n[ ] Review with keyboard\n[x] Keep saved notes unchanged")
                    sample.frame.size = NSSize(width: 500, height: 320)
                    sample.appearance = appearance
                    sample.textContainerInset = NSSize(width: 12, height: 12)
                    sample.backgroundColor = .windowBackgroundColor
                    sample.layoutManager!.ensureLayout(for: sample.textContainer!)
                    let bitmap = sample.bitmapImageRepForCachingDisplay(in: sample.bounds)!
                    sample.cacheDisplay(in: sample.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("notes-\(name.rawValue).png"))
                }
            }
            print("ok: real AppKit notes renders saved for light/dark inspection")
        }
    }
}

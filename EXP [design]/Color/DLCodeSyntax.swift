import Foundation

enum DLCodeFormat: String, CaseIterable {
    case json = "JSON", css = "CSS", scss = "SCSS"

    var filename: String? {
        switch self {
        case .json: nil
        case .css: "tokens.css"
        case .scss: "_tokens.scss"
        }
    }
}

/// Lexing matches UTF-16 offsets because TextKit's ranges use UTF-16.
struct DLCodeSyntax {
    enum Style: String, CaseIterable {
        case key, string, number, literal, comment, variable, directive
    }

    struct Highlight {
        let style: Style
        let range: NSRange
    }

    struct Fold: Hashable {
        let opening: Int
        let closing: Int
    }

    struct Projection {
        let text: String
        let replacements: [Replacement]

        struct Replacement {
            let display: NSRange
            let source: NSRange
        }

        func sourceOffset(for offset: Int, trailing: Bool = false) -> Int {
            var removed = 0
            for mark in replacements {
                if offset <= mark.display.location { break }
                if offset < NSMaxRange(mark.display) {
                    return trailing ? NSMaxRange(mark.source) : mark.source.location
                }
                removed += mark.source.length - mark.display.length
            }
            return offset + removed
        }

        func displayOffset(for offset: Int) -> Int {
            var removed = 0
            for mark in replacements {
                if offset <= mark.source.location { break }
                if offset < NSMaxRange(mark.source) { return mark.display.location }
                removed += mark.source.length - mark.display.length
            }
            return offset - removed
        }
    }

    let highlights: [Highlight]
    let folds: [Fold]
    let lines: [Int]

    init(_ text: String, format: DLCodeFormat) {
        let string = text as NSString
        lines = Self.lineStarts(string)
        var spans: [Highlight] = []
        var blocks: [Fold] = []
        var stack: [(symbol: unichar, offset: Int)] = []
        let regex = format == .json ? Self.json : format == .css ? Self.css : Self.scss
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: string.length)) { match, _, _ in
            guard let match else { return }
            if let style = Style.allCases.first(where: { match.range(withName: $0.rawValue).location != NSNotFound }) {
                spans.append(Highlight(style: style, range: match.range))
            } else if match.range(withName: "open").location != NSNotFound {
                stack.append((string.character(at: match.range.location), match.range.location))
            } else if let open = stack.last, let close = Self.delimiters[open.symbol],
                      close == string.character(at: match.range.location) {
                stack.removeLast()
                let end = match.range.location
                if string.lineRange(for: NSRange(location: open.offset, length: 0)).location !=
                    string.lineRange(for: NSRange(location: end, length: 0)).location {
                    blocks.append(Fold(opening: open.offset, closing: end))
                }
            }
        }
        highlights = spans
        folds = blocks.sorted { $0.opening < $1.opening }
    }

    static func lineStarts(_ string: NSString) -> [Int] {
        var offsets = [0]
        var offset = 0
        while offset < string.length {
            var end = 0
            var contentsEnd = 0
            string.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            if end < string.length || contentsEnd < end { offsets.append(end) }
            offset = end
        }
        return offsets
    }

    static func lineIndex(containing offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid } else { high = mid }
        }
        return low
    }

    func fold(at offset: Int) -> Fold? {
        let line = Self.lineIndex(containing: offset, in: lines)
        if let start = folds.first(where: { Self.lineIndex(containing: $0.opening, in: lines) == line }) {
            return start
        }
        return folds.last { $0.opening <= offset && $0.closing >= offset }
    }

    func project(_ source: String, folded: Set<Fold>) -> Projection {
        guard !folded.isEmpty else { return Projection(text: source, replacements: []) }
        let string = source as NSString
        let marker = " … "
        let markerLength = (marker as NSString).length
        var output = ""
        var offset = 0
        var displayLength = 0
        var replacements: [Projection.Replacement] = []
        for fold in folds where folded.contains(fold) && fold.opening >= offset {
            let prefixLength = fold.opening + 1 - offset
            output += string.substring(with: NSRange(location: offset, length: prefixLength)) + marker
            displayLength += prefixLength
            replacements.append(.init(display: NSRange(location: displayLength, length: markerLength),
                                      source: NSRange(location: fold.opening + 1, length: fold.closing - fold.opening - 1)))
            displayLength += markerLength
            offset = fold.closing
        }
        output += string.substring(from: offset)
        return Projection(text: output, replacements: replacements)
    }

    private static let delimiters: [unichar: unichar] = [123: 125, 91: 93, 40: 41]
    private static let json = try! NSRegularExpression(pattern:
        #"(?<key>"(?:\\.|[^"\\\r\n])*"(?=[ \t\r\n]*:))|(?<string>"(?:\\.|[^"\\\r\n])*(?:"|(?=\r|\n|\z)))|(?<number>-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?<literal>\b(?:true|false|null)\b)|(?<open>[{\[])|(?<close>[}\]])"#)
    private static let styleTokens =
        #"(?<string>"(?:\\.|[^"\\\r\n])*"|\x27(?:\\.|[^\x27\\\r\n])*\x27)|(?<variable>\$[\w-]+|--[\w-]+)|(?<directive>@[\w-]+)|(?<literal>#[\da-fA-F]{3,8}\b|\b(?:true|false|null)\b)|(?<number>[+-]?(?<![\w-])(?:\d*\.\d+|\d+)(?:%|[A-Za-z]+)?)|(?<key>[A-Za-z-][\w-]*(?=\s*:))|(?<open>[{(])|(?<close>[})])"#
    private static let css = try! NSRegularExpression(pattern:
        #"(?<comment>/\*[\s\S]*?(?:\*/|\z))|"# + styleTokens)
    private static let scss = try! NSRegularExpression(pattern:
        #"(?<comment>/\*[\s\S]*?(?:\*/|\z)|(?<![:\w])//[^\r\n]*)|"# + styleTokens)
}

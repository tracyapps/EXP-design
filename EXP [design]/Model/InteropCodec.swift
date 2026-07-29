//
//  InteropCodec.swift
//  EXP [design]
//
//  Shared import/export contract. External formats are never allowed to fail
//  silently: every codec returns a structured fidelity report alongside the
//  native EXP payload it produced.
//

import Foundation
import CoreGraphics

nonisolated enum InteropFormat: String, Sendable {
    case adobeXD = "Adobe XD"
    case figma = "Figma"
}

nonisolated enum InteropCapability: Hashable, Sendable {
    case read
    case write
}

nonisolated enum InteropProgressPhase: String, Sendable {
    case opening = "Opening package"
    case decoding = "Decoding artwork"
    case mapping = "Mapping layers"
    case finishing = "Finishing import"
}

nonisolated struct InteropProgress: Sendable {
    var phase: InteropProgressPhase
    var completed: Int
    var total: Int
    var detail: String = ""

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

/// Thread-safe cancellation shared by every codec. The first XD UI is modal and
/// quick, but the same contract is ready for large packages and Figma network
/// reads without changing importer APIs later.
nonisolated final class InteropCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

nonisolated struct InteropContext: @unchecked Sendable {
    var cancellation: InteropCancellationToken
    var progress: ((InteropProgress) -> Void)?

    init(cancellation: InteropCancellationToken = InteropCancellationToken(),
         progress: ((InteropProgress) -> Void)? = nil) {
        self.cancellation = cancellation
        self.progress = progress
    }

    func report(_ phase: InteropProgressPhase, completed: Int, total: Int,
                detail: String = "") throws {
        if cancellation.isCancelled { throw InteropCodecError.cancelled }
        progress?(InteropProgress(phase: phase, completed: completed,
                                  total: total, detail: detail))
    }
}

nonisolated enum InteropIssueSeverity: String, Sendable {
    case information = "Info"
    case warning = "Warning"
    case error = "Error"
}

nonisolated enum InteropFidelity: String, Sendable {
    case exact = "Mapped"
    case approximate = "Approximated"
    case unsupported = "Unsupported"
}

nonisolated struct InteropImportIssue: Sendable {
    var severity: InteropIssueSeverity
    var fidelity: InteropFidelity
    var category: String
    var message: String
    /// Human-readable source location such as an XD layer path or package entry.
    var location: String?
    var occurrences: Int = 1
}

nonisolated struct InteropImportReport: Sendable {
    var format: InteropFormat
    var sourceName: String
    var mappedCounts: [String: Int] = [:]
    var issues: [InteropImportIssue] = []
    var notesWritten: Int = 0

    private static let issueLimit = 1_000

    mutating func mapped(_ kind: String, count: Int = 1) {
        mappedCounts[kind, default: 0] += count
    }

    mutating func add(_ severity: InteropIssueSeverity, _ fidelity: InteropFidelity,
                      category: String, message: String, location: String? = nil) {
        // One issue TYPE with an occurrence count is much more useful than a
        // thousand repeated rows for a component-heavy document. Keep the first
        // concrete location as an example the designer can inspect.
        if let index = issues.firstIndex(where: {
            $0.severity == severity && $0.fidelity == fidelity
                && $0.category == category && $0.message == message
        }) {
            issues[index].occurrences += 1
            return
        }
        guard issues.count < Self.issueLimit else {
            if issues.count == Self.issueLimit {
                issues.append(InteropImportIssue(
                    severity: .warning, fidelity: .unsupported,
                    category: "Report",
                    message: "Additional fidelity issues were omitted after the first \(Self.issueLimit).",
                    location: nil))
            }
            return
        }
        issues.append(InteropImportIssue(severity: severity, fidelity: fidelity,
                                         category: category, message: message,
                                         location: location))
    }

    var warningCount: Int { issues.filter { $0.severity == .warning }.reduce(0) { $0 + $1.occurrences } }
    var errorCount: Int { issues.filter { $0.severity == .error }.reduce(0) { $0 + $1.occurrences } }
    var unsupportedCount: Int { issues.filter { $0.fidelity == .unsupported }.reduce(0) { $0 + $1.occurrences } }
    var approximateCount: Int { issues.filter { $0.fidelity == .approximate }.reduce(0) { $0 + $1.occurrences } }

    var summary: String {
        let total = mappedCounts.values.reduce(0, +)
        var parts = ["Mapped \(total) item\(total == 1 ? "" : "s")"]
        if approximateCount > 0 { parts.append("\(approximateCount) approximated") }
        if unsupportedCount > 0 { parts.append("\(unsupportedCount) unsupported") }
        if notesWritten > 0 { parts.append("\(notesWritten) note\(notesWritten == 1 ? "" : "s") added") }
        return parts.joined(separator: " · ")
    }

    var detailedText: String {
        var lines = ["\(format.rawValue) Import Report", sourceName, "", summary, ""]
        if !mappedCounts.isEmpty {
            lines.append("Mapped")
            for item in mappedCounts.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
                lines.append("  \(item.key): \(item.value)")
            }
            lines.append("")
        }
        if issues.isEmpty {
            lines.append("No fidelity warnings.")
        } else {
            lines.append("Fidelity details")
            for issue in issues {
                let whereText = issue.location.map { " — \($0)" } ?? ""
                let countText = issue.occurrences > 1 ? " ×\(issue.occurrences)" : ""
                lines.append("  [\(issue.severity.rawValue)] [\(issue.fidelity.rawValue)] \(issue.category)\(countText): \(issue.message)\(whereText)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Native material produced by an importer, before it is merged into the open
/// document. Top-level node frames use document coordinates; group children use
/// their normal group-local coordinates.
nonisolated struct InteropImportPayload: Sendable {
    /// Remote document formats can carry true pages. Offline/flat importers may
    /// continue filling `artboards` + `nodes` to merge into the active page.
    var pages: [CanvasPage] = []
    var artboards: [Artboard] = []
    var nodes: [Node] = []
    var sources: [ComponentSource] = []
    var designLanguage = DesignLanguage()

    var isEmpty: Bool {
        pages.isEmpty && artboards.isEmpty && nodes.isEmpty
            && sources.isEmpty && designLanguage.isEmpty
    }

    mutating func translate(by delta: CGPoint) {
        for pageIndex in pages.indices {
            for i in pages[pageIndex].artboards.indices {
                pages[pageIndex].artboards[i].frame.origin.x += delta.x
                pages[pageIndex].artboards[i].frame.origin.y += delta.y
            }
            for i in pages[pageIndex].nodes.indices {
                pages[pageIndex].nodes[i].frame.origin.x += delta.x
                pages[pageIndex].nodes[i].frame.origin.y += delta.y
            }
        }
        for i in artboards.indices {
            artboards[i].frame.origin.x += delta.x
            artboards[i].frame.origin.y += delta.y
        }
        for i in nodes.indices {
            nodes[i].frame.origin.x += delta.x
            nodes[i].frame.origin.y += delta.y
        }
    }
}

nonisolated struct InteropImportResult: Sendable {
    var payload: InteropImportPayload
    var report: InteropImportReport
}

nonisolated struct InteropExportResult: Sendable {
    var writtenURLs: [URL]
    var report: InteropImportReport
}

nonisolated enum InteropCodecError: LocalizedError, Sendable {
    case cancelled
    case unreadablePackage(String)
    case unsupportedOperation(String)
    case noUsableArtwork

    var errorDescription: String? {
        switch self {
        case .cancelled: return "The import was cancelled."
        case .unreadablePackage(let reason): return "The package could not be read: \(reason)"
        case .unsupportedOperation(let operation): return "This codec does not support \(operation)."
        case .noUsableArtwork: return "No supported artwork was found in the package."
        }
    }
}

nonisolated protocol InteropCodec {
    var format: InteropFormat { get }
    var capabilities: Set<InteropCapability> { get }

    func read(from url: URL, context: InteropContext) throws -> InteropImportResult
    func write(_ document: Document, to url: URL,
               context: InteropContext) throws -> InteropExportResult
}

nonisolated extension InteropCodec {
    func write(_ document: Document, to url: URL,
               context: InteropContext) throws -> InteropExportResult {
        throw InteropCodecError.unsupportedOperation("export")
    }
}

import AppKit

/// File-backed diagnostic logging for tester reports (v1.3).
///
/// Public path:
///
/// **REPORT** — Help ▸ Save Diagnostic Report… snapshots the header, front
/// document stats, and a geometry audit into one file at a location the tester
/// picks (NSSavePanel = sandbox-safe), ready to attach to a bug report or Send
/// Feedback message.
///
/// Hidden developer perf instrumentation can still append lines to the rotating
/// per-day file in `~/Library/Logs/EXP [design]/`, but those controls are not in
/// the public View menu and they do not write to the Xcode console.
///
/// Design rules:
/// - Logging must never block the canvas: `log()` is fire-and-forget onto a
///   serial utility queue; file I/O never happens on the main thread.
/// - Rotation is per calendar day; only the newest `keepFiles` logs are kept.
/// - App-chrome infrastructure on purpose — references NO model types, so it
///   must NOT be added to the EXPThumbnail extension target.
/// - Concurrency: the app target defaults to MainActor isolation, but this type
///   is `nonisolated` on purpose — perf lines arrive from wherever the canvas
///   measures, and all mutable state is confined to the serial `queue`
///   (hence `@unchecked Sendable`; the queue IS the isolation).
nonisolated final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    private let queue = DispatchQueue(label: "exp.diagnostic-log", qos: .utility)
    private var handle: FileHandle?
    private var openedURL: URL?
    private var wroteSessionHeader = false
    private let keepFiles = 5

    // MARK: Locations

    /// `~/Library/Logs/EXP [design]/` (inside the sandbox container).
    static var logDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("EXP [design]", isDirectory: true)
    }

    /// Today's log file (rotation unit = one calendar day).
    static var currentLogURL: URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return logDirectory.appendingPathComponent(
            "EXP-diagnostics-\(df.string(from: Date())).log")
    }

    // MARK: Public API

    /// Append one timestamped line. Cheap to call from anywhere (including the
    /// perf meter's flush) — actual I/O is queued off the main thread.
    func log(_ line: String) {
        queue.async { self.append(line) }
    }

    /// Append several lines as one queued unit (keeps multi-line blocks like
    /// the geometry audit contiguous even if other logs race them).
    func log(lines: [String]) {
        queue.async { for l in lines { self.append(l) } }
    }

    /// Reveal today's log in Finder, creating the directory (and an empty file
    /// with a session header) if nothing has been written yet — so the menu
    /// item always lands somewhere real instead of failing silently.
    static func revealInFinder() {
        shared.queue.sync { shared.ensureOpen() }
        NSWorkspace.shared.activateFileViewerSelecting([currentLogURL])
    }

    /// The machine/app header block. Also used by Save Diagnostic Report.
    static func sessionHeader() -> [String] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var model = "unknown"
        var size = 64
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 {
            model = String(cString: buf)
        }
        return [
            "════════════════════════════════════════",
            "EXP [design] \(version) (build \(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) — \(model)",
            "Session start: \(ISO8601DateFormatter().string(from: Date()))",
            "════════════════════════════════════════",
        ]
    }

    /// The last `maxLines` lines of today's stream log (for the report).
    static func tailOfCurrentLog(maxLines: Int = 400) -> [String] {
        guard let text = try? String(contentsOf: currentLogURL, encoding: .utf8) else { return [] }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return Array(all.suffix(maxLines))
    }

    // MARK: File plumbing (always on `queue`)

    private func append(_ line: String) {
        ensureOpen()
        guard let handle else { return }
        let ts = timeFormatter.string(from: Date())
        if let data = ("[\(ts)] \(line)\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private func ensureOpen() {
        // Day rolled over? Close and reopen against the new file.
        if let openedURL, openedURL != Self.currentLogURL {
            try? handle?.close()
            handle = nil
            wroteSessionHeader = false
        }
        guard handle == nil else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
        let url = Self.currentLogURL
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        openedURL = url
        if !wroteSessionHeader, let handle {
            wroteSessionHeader = true
            let block = Self.sessionHeader().joined(separator: "\n") + "\n"
            if let data = block.data(using: .utf8) { try? handle.write(contentsOf: data) }
        }
        pruneOldLogs()
    }

    /// Keep the newest `keepFiles` daily logs; delete the rest.
    private func pruneOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.logDirectory, includingPropertiesForKeys: nil) else { return }
        let logs = files
            .filter { $0.lastPathComponent.hasPrefix("EXP-diagnostics-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // name = date, desc
        for stale in logs.dropFirst(keepFiles) {
            try? fm.removeItem(at: stale)
        }
    }

    /// Only ever touched on `queue` (DateFormatter is not Sendable).
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

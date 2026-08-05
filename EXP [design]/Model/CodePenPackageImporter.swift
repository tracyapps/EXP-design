//
//  CodePenPackageImporter.swift
//  EXP [design]
//
//  Imports a CodePen 2.0 exported ZIP through the proven rendered-HTML seam.
//  Only dist/index.html is rendered. Source/configuration are preserved as
//  opaque, hashed provenance; no package manager, compiler, or build script is
//  ever invoked by EXP.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers
import zlib

@MainActor
final class CodePenPackageImporter {
    nonisolated struct Limits: Sendable {
        var maximumArchiveBytes = 128 * 1_024 * 1_024
        var maximumEntries = 5_000
        var maximumEntryBytes = 32 * 1_024 * 1_024
        var maximumExpandedBytes = 256 * 1_024 * 1_024
        var maximumPreservedSourceBytes = 8 * 1_024 * 1_024
    }

    private let limits: Limits
    private let capture: RenderedHTMLWebKitCapture

    init(limits: Limits = Limits()) {
        self.limits = limits
        capture = RenderedHTMLWebKitCapture()
    }

    func read(from archiveURL: URL,
              viewports: [RenderedHTMLViewport],
              context: InteropContext = InteropContext()) async throws
        -> InteropImportResult {
        guard archiveURL.isFileURL else {
            throw InteropCodecError.unreadablePackage(
                "CodePen import requires a local ZIP file")
        }
        try context.report(.opening, completed: 0, total: 1,
                           detail: archiveURL.lastPathComponent)
        if context.cancellation.isCancelled { throw InteropCodecError.cancelled }

        let accessStarted = archiveURL.startAccessingSecurityScopedResource()
        let archiveData: Data
        do {
            defer {
                if accessStarted { archiveURL.stopAccessingSecurityScopedResource() }
            }
            let values = try archiveURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw InteropCodecError.unreadablePackage(
                    "the selected CodePen export is not a regular file")
            }
            guard (values.fileSize ?? 0) <= limits.maximumArchiveBytes else {
                throw InteropCodecError.unreadablePackage(
                    "the ZIP exceeds the \(limits.maximumArchiveBytes / 1_024 / 1_024) MB compressed-package limit")
            }
            archiveData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        } catch let error as InteropCodecError {
            throw error
        } catch {
            throw InteropCodecError.unreadablePackage(error.localizedDescription)
        }

        let archive = try CodePenZipArchive(
            data: archiveData,
            maximumEntries: limits.maximumEntries,
            maximumEntryBytes: limits.maximumEntryBytes,
            maximumExpandedBytes: limits.maximumExpandedBytes)
        let package = try CodePenExportPackage(archive: archive,
                                               archiveName: archiveURL.lastPathComponent)

        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("EXP-CodePen-Import-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionRoot) }

        let materialized = try package.materialize(
            at: extractionRoot,
            maximumPreservedSourceBytes: limits.maximumPreservedSourceBytes,
            context: context)
        let entryURL = extractionRoot.appendingPathComponent(package.entryPath)
        var result = try await capture.readLocalFile(
            from: entryURL,
            scopedDirectory: extractionRoot,
            viewports: viewports,
            context: context)

        result.report.format = .codePen
        result.report.sourceName = archiveURL.lastPathComponent
        result.report.add(
            .information, .exact, category: "CodePen package",
            message: "Rendered dist/index.html from CodePen’s last successful build. EXP did not run a package manager, compiler, Block, or build script.",
            location: package.entryPath)
        result.report.add(
            .information, .exact, category: "Browser behavior",
            message: "Browser-ready JavaScript referenced by dist/index.html was allowed only inside EXP’s short-lived, non-persistent, network-blocked WebKit render. Authored src scripts were preserved but not executed or mapped to editable behavior.",
            location: package.entryPath)
        result.report.add(
            .information, .exact, category: "CodePen source provenance",
            message: "Recorded \(materialized.resources.count) package files with SHA-256 receipts and retained \(materialized.retainedTextCount) bounded text source file\(materialized.retainedTextCount == 1 ? "" : "s") for future handoff.")
        if package.configurationPaths.isEmpty {
            result.report.add(
                .warning, .approximate, category: "CodePen configuration",
                message: "No .codepen/pen.config.json was present. The browser-ready build was imported, but CodePen 2.0 Block identity could not be retained.")
        } else {
            result.report.add(
                .information, .exact, category: "CodePen configuration",
                message: "Preserved CodePen configuration and Block/processor files byte-for-byte within the source-retention limit.",
                location: package.configurationPaths.joined(separator: ", "))
        }

        if !result.payload.pages.isEmpty {
            result.payload.pages[0].name = package.displayName
        }
        if !result.codeBridges.isEmpty {
            let archiveDigest = Self.sha256(archiveData)
            result.codeBridges[0].connector = "codepen-2-zip"
            result.codeBridges[0].source.displayName = package.displayName
            result.codeBridges[0].source.stableID = "codepen-export:\(archiveDigest)"
            result.codeBridges[0].source.entryPath = package.entryPath
            result.codeBridges[0].source.packagePath = archiveURL.lastPathComponent
            result.codeBridges[0].source.buildTool = "CodePen Compiler"
            result.codeBridges[0].source.metadata["packageRoot"] = package.packageRoot
            result.codeBridges[0].source.metadata["configurationPaths"] =
                package.configurationPaths.joined(separator: ";")
            result.codeBridges[0].resources = materialized.resources
            result.codeBridges[0].baseline?.sourceDigest = archiveDigest
            result.codeBridges[0].baseline?.metadata["archiveSHA256"] = archiveDigest
            result.codeBridges[0].baseline?.metadata["resourceCount"] =
                String(materialized.resources.count)
            result.codeBridges[0].baseline?.metadata["preservedSourceBytes"] =
                String(materialized.retainedTextBytes)
            result.codeBridges[0].metadata["packageFormat"] = "codepen-2-export"
            result.codeBridges[0].metadata["renderArtifact"] = "last-successful-dist"
            result.codeBridges[0].metadata["buildExecution"] = "never"
            result.codeBridges[0].metadata["renderedJavaScriptPolicy"] =
                "isolated-browser-only"
            result.codeBridges[0].metadata["sourceScriptPolicy"] =
                "preserve-opaque-no-execute"
            result.codeBridges[0].metadata["sourceWritePolicy"] = "receipt-only"
            for index in result.codeBridges[0].bindings.indices {
                result.codeBridges[0].bindings[index].sourcePath = package.entryPath
                result.codeBridges[0].bindings[index].writableProperties = []
                result.codeBridges[0].bindings[index].metadata["connector"] =
                    "codepen-2-zip"
            }
        }
        try context.report(.finishing, completed: 1, total: 1,
                           detail: result.report.summary)
        return result
    }

    func cancel() {
        capture.cancel()
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CodePen package shape

nonisolated struct CodePenExportPackage {
    struct Materialized: Sendable {
        var resources: [CodeBridgeResource]
        var retainedTextCount: Int
        var retainedTextBytes: Int
    }

    let archive: CodePenZipArchive
    let archiveName: String
    let packageRoot: String
    let entryPath: String
    let displayName: String
    let configurationPaths: [String]
    private let files: [(entry: CodePenZipArchive.Entry, path: String)]

    init(archive: CodePenZipArchive, archiveName: String) throws {
        self.archive = archive
        self.archiveName = archiveName
        let safeFiles = try archive.entries.compactMap { entry
            -> (entry: CodePenZipArchive.Entry, path: String)? in
            guard !entry.isDirectory else { return nil }
            return (entry, try CodePenZipArchive.normalizedArchivePath(entry.name))
        }
        let candidates = safeFiles.filter {
            $0.path.lowercased() == "dist/index.html"
                || $0.path.lowercased().hasSuffix("/dist/index.html")
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            if candidates.isEmpty {
                throw InteropCodecError.unreadablePackage(
                    "CodePen’s browser-ready dist/index.html is missing")
            }
            throw InteropCodecError.unreadablePackage(
                "the ZIP contains more than one dist/index.html and its CodePen package root is ambiguous")
        }

        let suffix = "dist/index.html"
        let root = String(candidate.path.dropLast(suffix.count))
        let packageFiles = safeFiles.compactMap { item
            -> (entry: CodePenZipArchive.Entry, path: String)? in
            guard item.path.hasPrefix(root) else { return nil }
            let relative = String(item.path.dropFirst(root.count))
            return relative.isEmpty ? nil : (item.entry, relative)
        }
        guard packageFiles.contains(where: {
            $0.path.lowercased().hasPrefix("src/")
        }) else {
            throw InteropCodecError.unreadablePackage(
                "the ZIP has dist/index.html but no sibling src folder, so it is not a complete CodePen export")
        }

        packageRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        entryPath = suffix
        let name = URL(fileURLWithPath: archiveName)
            .deletingPathExtension().lastPathComponent
        displayName = name.isEmpty ? "CodePen Export" : name
        files = packageFiles.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        configurationPaths = files.map(\.path).filter { path in
            let lower = path.lowercased()
            return lower == ".codepen/pen.config.json"
                || lower == "src/.codepen/pen.config.json"
                || lower.contains("/.codepen/")
                || lower.hasSuffix(".config.json")
        }
    }

    func materialize(at root: URL,
                     maximumPreservedSourceBytes: Int,
                     context: InteropContext) throws -> Materialized {
        var decoded: [(path: String, data: Data, mimeType: String,
                       role: String, isText: Bool)] = []
        decoded.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            if context.cancellation.isCancelled { throw InteropCodecError.cancelled }
            try context.report(.decoding, completed: index, total: files.count,
                               detail: file.path)
            let data = try archive.data(for: file.entry)
            let destination = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let type = UTType(filenameExtension: destination.pathExtension)
            let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
            decoded.append((file.path, data, mimeType,
                            Self.resourceRole(path: file.path, mimeType: mimeType),
                            Self.isText(path: file.path, type: type)))
        }

        var remaining = max(0, maximumPreservedSourceBytes)
        var retainedCount = 0
        var retainedBytes = 0
        let preservationOrder = decoded.indices.sorted {
            Self.preservationPriority(decoded[$0].path)
                < Self.preservationPriority(decoded[$1].path)
        }
        var preservedByIndex: [Int: Data] = [:]
        for index in preservationOrder where decoded[index].isText {
            let data = decoded[index].data
            guard data.count <= remaining else { continue }
            preservedByIndex[index] = data
            remaining -= data.count
            retainedCount += 1
            retainedBytes += data.count
        }

        let resources = decoded.enumerated().map { index, file in
            let preserved = preservedByIndex[index]
            return CodeBridgeResource(
                path: file.path,
                role: file.role,
                mimeType: file.mimeType,
                byteCount: file.data.count,
                sha256: SHA256.hash(data: file.data)
                    .map { String(format: "%02x", $0) }.joined(),
                preservedData: preserved,
                metadata: [
                    "packageSection": Self.packageSection(file.path),
                    "preservation": preserved != nil
                        ? "inline" : (file.isText
                            ? "digest-only-cap-reached" : "digest-only"),
                    "executedAsBuildInput": "false"
                ])
        }
        return Materialized(resources: resources,
                            retainedTextCount: retainedCount,
                            retainedTextBytes: retainedBytes)
    }

    private static func preservationPriority(_ path: String) -> Int {
        let lower = path.lowercased()
        if lower.contains(".codepen/") || lower.hasSuffix(".config.json") { return 0 }
        if lower.hasPrefix("src/") { return 1 }
        if lower.hasPrefix("dist/") { return 2 }
        return 3
    }

    private static func packageSection(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.contains(".codepen/") { return "codepen-configuration" }
        if lower.hasPrefix("dist/") { return "dist" }
        if lower.hasPrefix("src/") { return "src" }
        return "package-metadata"
    }

    private static func isText(path: String, type: UTType?) -> Bool {
        if type?.conforms(to: .text) == true { return true }
        return ["html", "htm", "css", "scss", "sass", "less", "styl",
                "js", "mjs", "cjs", "jsx", "ts", "tsx", "json", "svg",
                "xml", "md", "markdown", "txt", "map", "yml", "yaml"]
            .contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func resourceRole(path: String, mimeType: String) -> String {
        let lower = path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if lower.contains(".codepen/") || ext == "json" || ext == "map" {
            return "configuration"
        }
        switch ext {
        case "html", "htm": return "document"
        case "css", "scss", "sass", "less", "styl": return "stylesheet"
        case "js", "mjs", "cjs", "jsx", "ts", "tsx": return "script"
        case "woff", "woff2", "ttf", "otf": return "font"
        case "svg", "png", "jpg", "jpeg", "gif", "webp", "avif": return "image"
        default:
            if mimeType.hasPrefix("image/") { return "image" }
            if mimeType.hasPrefix("font/") { return "font" }
            return "resource"
        }
    }
}

// MARK: - Bounded ZIP reader

/// Purpose-built reader for CodePen exports. It never trusts archive paths and
/// never restores permissions or symlinks; materialized files are fresh data
/// files inside one private temporary folder.
nonisolated struct CodePenZipArchive {
    struct Entry: Sendable {
        var name: String
        var flags: UInt16
        var compression: UInt16
        var crc: UInt32
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
        var unixMode: UInt16
        var isDirectory: Bool { name.hasSuffix("/") }
        var isSymlink: Bool { unixMode & 0xf000 == 0xa000 }
    }

    let bytes: Data
    let entries: [Entry]

    init(data: Data, maximumEntries: Int, maximumEntryBytes: Int,
         maximumExpandedBytes: Int) throws {
        bytes = data
        guard data.count >= 22 else {
            throw InteropCodecError.unreadablePackage("not a ZIP archive")
        }
        let searchStart = max(0, data.count - 65_557)
        var endOffset: Int?
        var cursor = data.count - 22
        while cursor >= searchStart {
            if data.cpU32(cursor) == 0x0605_4b50 { endOffset = cursor; break }
            cursor -= 1
        }
        guard let endOffset else {
            throw InteropCodecError.unreadablePackage("ZIP directory is missing")
        }
        let count = Int(data.cpU16(endOffset + 10))
        guard count <= maximumEntries else {
            throw InteropCodecError.unreadablePackage("ZIP contains too many entries")
        }
        let directoryOffset = Int(data.cpU32(endOffset + 16))
        var parsed: [Entry] = []
        var expandedBytes = 0
        var offset = directoryOffset
        for _ in 0..<count {
            guard offset + 46 <= data.count,
                  data.cpU32(offset) == 0x0201_4b50 else {
                throw InteropCodecError.unreadablePackage("ZIP directory is corrupt")
            }
            let flags = data.cpU16(offset + 8)
            let compression = data.cpU16(offset + 10)
            let crc = data.cpU32(offset + 16)
            let compressedSize = Int(data.cpU32(offset + 20))
            let uncompressedSize = Int(data.cpU32(offset + 24))
            let nameLength = Int(data.cpU16(offset + 28))
            let extraLength = Int(data.cpU16(offset + 30))
            let commentLength = Int(data.cpU16(offset + 32))
            let externalAttributes = data.cpU32(offset + 38)
            let localOffset = Int(data.cpU32(offset + 42))
            guard compressedSize != Int(UInt32.max),
                  uncompressedSize != Int(UInt32.max) else {
                throw InteropCodecError.unreadablePackage(
                    "ZIP64 CodePen packages are not supported yet")
            }
            guard uncompressedSize <= maximumEntryBytes else {
                throw InteropCodecError.unreadablePackage(
                    "a ZIP entry exceeds the per-file safety limit")
            }
            expandedBytes += uncompressedSize
            guard expandedBytes <= maximumExpandedBytes else {
                throw InteropCodecError.unreadablePackage(
                    "the expanded ZIP exceeds the safety limit")
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd],
                                    encoding: .utf8) else {
                throw InteropCodecError.unreadablePackage(
                    "a ZIP entry name is not valid UTF-8")
            }
            _ = try Self.normalizedArchivePath(name)
            let entry = Entry(
                name: name, flags: flags, compression: compression, crc: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset,
                unixMode: UInt16((externalAttributes >> 16) & 0xffff))
            guard !entry.isSymlink else {
                throw InteropCodecError.unreadablePackage(
                    "symbolic links are not allowed in a CodePen import")
            }
            parsed.append(entry)
            offset = nameEnd + extraLength + commentLength
        }
        entries = parsed
    }

    static func normalizedArchivePath(_ raw: String) throws -> String {
        guard !raw.isEmpty, !raw.hasPrefix("/"), !raw.contains("\\"),
              !raw.contains("\0") else {
            throw InteropCodecError.unreadablePackage(
                "the ZIP contains an unsafe absolute or platform-specific path")
        }
        let isDirectory = raw.hasSuffix("/")
        let pieces = raw.split(separator: "/", omittingEmptySubsequences: false)
        var clean: [String] = []
        for (index, piece) in pieces.enumerated() {
            if piece.isEmpty && isDirectory && index == pieces.count - 1 { continue }
            guard !piece.isEmpty, piece != ".", piece != ".." else {
                throw InteropCodecError.unreadablePackage(
                    "the ZIP contains an unsafe traversal path")
            }
            clean.append(String(piece))
        }
        guard !clean.isEmpty else {
            throw InteropCodecError.unreadablePackage("the ZIP contains an empty path")
        }
        return clean.joined(separator: "/") + (isDirectory ? "/" : "")
    }

    func data(for entry: Entry) throws -> Data {
        guard entry.flags & 0x1 == 0 else {
            throw InteropCodecError.unreadablePackage(
                "encrypted ZIP entries are unsupported")
        }
        let offset = entry.localHeaderOffset
        guard offset + 30 <= bytes.count,
              bytes.cpU32(offset) == 0x0403_4b50 else {
            throw InteropCodecError.unreadablePackage(
                "a ZIP entry header is corrupt")
        }
        let nameLength = Int(bytes.cpU16(offset + 26))
        let extraLength = Int(bytes.cpU16(offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else {
            throw InteropCodecError.unreadablePackage(
                "a ZIP entry is truncated")
        }
        let compressed = Data(bytes[start..<end])
        let result: Data
        switch entry.compression {
        case 0:
            result = compressed
        case 8:
            result = try inflateRaw(compressed,
                                    expectedSize: entry.uncompressedSize)
        default:
            throw InteropCodecError.unreadablePackage(
                "ZIP compression method \(entry.compression) is unsupported")
        }
        guard result.count == entry.uncompressedSize else {
            throw InteropCodecError.unreadablePackage(
                "a ZIP entry size does not match its directory record")
        }
        let actualCRC: UInt32 = result.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(crc32(0, base, uInt(result.count)))
        }
        guard actualCRC == entry.crc else {
            throw InteropCodecError.unreadablePackage(
                "a ZIP entry checksum failed")
        }
        return result
    }

    private func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let outputCount = output.count
        var stream = z_stream()
        let initialized = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                                        Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else {
            throw InteropCodecError.unreadablePackage(
                "the ZIP deflate decoder could not start")
        }
        defer { inflateEnd(&stream) }
        let status: Int32 = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer(mutating:
                    inputBytes.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END,
              Int(stream.total_out) == expectedSize else {
            throw InteropCodecError.unreadablePackage(
                "a deflated ZIP entry is corrupt")
        }
        return output
    }
}

nonisolated private extension Data {
    func cpU16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)])
            | UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func cpU32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[index(startIndex, offsetBy: offset)])
            | UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8
            | UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16
            | UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
    }
}

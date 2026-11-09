import Foundation
import CryptoKit

// This storage-only executable never measures or renders text.
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { CGSize(width: maxWidth ?? 20, height: 20) }
    func measuredSize(boxWidth: CGFloat) -> CGSize { CGSize(width: boxWidth, height: 20) }
}

private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}
private func rejected(_ message: String, _ body: () throws -> Void) {
    do { try body(); fputs("FAIL: accepted \(message)\n", stderr); exit(1) }
    catch { print("PASS: rejected \(message)") }
}
private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

@main private enum NativeDocumentStorageCheck {
    static func main() throws {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOTkAAAAASUVORK5CYII=")!
        let image = Node(name: "Image", frame: CGRect(x: 0, y: 0, width: 64, height: 64),
                         content: .image(ImageContent(data: bytes, naturalSize: CGSize(width: 1, height: 1))))
        let baseline = Data(repeating: 37, count: 2 * 1_024 * 1_024)
        let bridge = CodeBridgeManifest(connector: "storage-check", source: CodeBridgeSource(displayName: "Fixture"),
                                        resources: [CodeBridgeResource(path: "source.bin", role: "source", preservedData: baseline),
                                                    CodeBridgeResource(path: "empty", role: "source", preservedData: Data())],
                                        metadata: ["$expAsset": "opaque connector metadata", "byteCount": "not a binary reference"])
        var document = Document(artboards: [], nodes: [image, Node(name: "Folder", frame: .zero, content: .group(children: [image]))],
                                codeBridges: [bridge])
        document.pages.append(CanvasPage(name: "Second", nodes: [image]))
        let original = try NativeDocumentStorage.legacyData(document)
        if CommandLine.arguments.count > 1 {
            try original.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let legacy = try NativeDocumentStorage.read(FileWrapper(regularFileWithContents: original))
        try require(NativeDocumentStorage.legacyData(legacy) == original, "legacy JSON reads and re-encodes without migration")
        let package = try NativeDocumentStorage.package(document)
        let assets = package.fileWrappers!["assets"]!.fileWrappers!
        require(assets.count == 3, "identical image bytes across pages/nested groups are stored once; empty data survives")
        let model = package.fileWrappers!["document.json"]!.regularFileContents!
        require(model.count < original.count / 10, "large preserved source bytes are externalized, not base64-encoded into the model")
        let restored = try NativeDocumentStorage.read(package)
        try require(NativeDocumentStorage.legacyData(restored) == original, "package round trip preserves the complete legacy document representation")
        for folder in [package, package.fileWrappers!["assets"]!] {
            let finder = FileWrapper(regularFileWithContents: Data([0, 1, 2]))
            finder.preferredFilename = ".DS_Store"; folder.addFileWrapper(finder)
        }
        try require(NativeDocumentStorage.legacyData(NativeDocumentStorage.read(package)) == original,
                    "ordinary Finder metadata at package/asset level does not brick the document")
        let firstModel = model
        document.pages[0].name = "A small edit"
        let edited = try NativeDocumentStorage.package(document, existing: package)
        let editedAssets = edited.fileWrappers!["assets"]!.fileWrappers!
        require(assets.allSatisfy { editedAssets[$0.key] === $0.value }, "small edit reuses every unchanged binary FileWrapper")
        require(package.fileWrappers!["document.json"]!.regularFileContents == firstModel,
                "a new save leaves the previous model/version wrapper untouched")

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("exp-storage-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("Fixture.designpkg")
        try package.write(to: file, options: .atomic, originalContentsURL: nil)
        let disk = try FileWrapper(url: file)
        let reopened = try NativeDocumentStorage.read(disk)
        try require(NativeDocumentStorage.legacyData(reopened) == original, "written package reopens from disk with identical model and asset bytes")
        let legacyFile = scratch.appendingPathComponent("Original.design")
        try original.write(to: legacyFile)
        try edited.write(to: scratch.appendingPathComponent("Edited.designpkg"), options: .atomic, originalContentsURL: nil)
        try require(Data(contentsOf: legacyFile) == original, "separate package copy does not alter the original JSON file")
        let moved = scratch.appendingPathComponent("Moved.designpkg")
        try FileManager.default.moveItem(at: file, to: moved)
        try require(NativeDocumentStorage.legacyData(NativeDocumentStorage.read(FileWrapper(url: moved))) == original,
                    "package is self-contained after move")
        let blockingFile = scratch.appendingPathComponent("Not a directory")
        try Data([1]).write(to: blockingFile)
        rejected("failed copy write through a non-directory") {
            try edited.write(to: blockingFile.appendingPathComponent("CannotSave.designpkg"), options: .atomic, originalContentsURL: nil)
        }
        try require(Data(contentsOf: legacyFile) == original, "failed separate-copy write leaves the original unchanged")

        func altered(_ modify: (FileWrapper) throws -> Void) throws -> FileWrapper {
            let p = try NativeDocumentStorage.package(document)
            try modify(p); return p
        }
        rejected("missing asset") {
            let p = try altered { $0.fileWrappers!["assets"]!.removeFileWrapper($0.fileWrappers!["assets"]!.fileWrappers![hash(bytes)]!) }
            _ = try NativeDocumentStorage.read(p)
        }
        rejected("damaged asset") {
            let p = try altered {
                let a = $0.fileWrappers!["assets"]!; a.removeFileWrapper(a.fileWrappers![hash(bytes)]!)
                let f = FileWrapper(regularFileWithContents: Data([1, 2])); f.preferredFilename = hash(bytes); a.addFileWrapper(f)
            }
            _ = try NativeDocumentStorage.read(p)
        }
        rejected("missing optional bridge resource (must not silently drop the bridge)") {
            let p = try altered { $0.fileWrappers!["assets"]!.removeFileWrapper($0.fileWrappers!["assets"]!.fileWrappers![hash(baseline)]!) }
            _ = try NativeDocumentStorage.read(p)
        }
        rejected("asset symlink") {
            let p = try altered {
                let a = $0.fileWrappers!["assets"]!; a.removeFileWrapper(a.fileWrappers![hash(bytes)]!)
                let f = FileWrapper(symbolicLinkWithDestinationURL: legacyFile); f.preferredFilename = hash(bytes); a.addFileWrapper(f)
            }
            _ = try NativeDocumentStorage.read(p)
        }
        rejected("model checksum mismatch") {
            let p = try altered {
                $0.removeFileWrapper($0.fileWrappers!["document.json"]!)
                let f = FileWrapper(regularFileWithContents: Data("{}".utf8)); f.preferredFilename = "document.json"; $0.addFileWrapper(f)
            }
            _ = try NativeDocumentStorage.read(p)
        }
        for (version, features) in [(2, [String]()), (1, ["unknown-required-feature"])] {
            rejected("unknown format/required feature \(version)/\(features)") {
                let p = try altered {
                    $0.removeFileWrapper($0.fileWrappers!["package.json"]!)
                    let data = try JSONEncoder().encode(NativeDocumentStorage.Envelope(formatVersion: version, modelSHA256: hash(model), requiredFeatures: features))
                    let f = FileWrapper(regularFileWithContents: data); f.preferredFilename = "package.json"; $0.addFileWrapper(f)
                }
                _ = try NativeDocumentStorage.read(p)
            }
        }
        // Valid envelope checksum must not make a malicious model reference safe.
        for target in ["../outside", "/tmp/outside", String(repeating: "a", count: 64)] {
            rejected("unsafe or missing asset reference \(target.prefix(16))") {
                let p = try altered {
                    let body = $0.fileWrappers!["document.json"]!.regularFileContents!
                    let text = String(decoding: body, as: UTF8.self).replacingOccurrences(of: hash(bytes), with: target)
                    let data = Data(text.utf8)
                    $0.removeFileWrapper($0.fileWrappers!["document.json"]!)
                    let f = FileWrapper(regularFileWithContents: data); f.preferredFilename = "document.json"; $0.addFileWrapper(f)
                    $0.removeFileWrapper($0.fileWrappers!["package.json"]!)
                    let e = FileWrapper(regularFileWithContents: try JSONEncoder().encode(NativeDocumentStorage.Envelope(formatVersion: 1, modelSHA256: hash(data), requiredFeatures: [])))
                    e.preferredFilename = "package.json"; $0.addFileWrapper(e)
                }
                _ = try NativeDocumentStorage.read(p)
            }
        }
        print("PASS: native package storage, legacy compatibility and corruption boundaries")
    }
}

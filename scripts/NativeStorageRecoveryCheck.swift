import AppKit
import Foundation

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { CGSize(width: maxWidth ?? 20, height: 20) }
    func measuredSize(boxWidth: CGFloat) -> CGSize { CGSize(width: boxWidth, height: 20) }
}

// Exercises AppKit's safe writer with the production package codec. This is
// deliberately separate from the owner's real SwiftUI save/Undo/Versions pass.
final class RecoveryDocument: NSDocument {
    var value = Document(artboards: [], nodes: [])
    var interruptAt: String?
    var readyFile: URL?
    override func write(to url: URL, ofType typeName: String, for operation: NSDocument.SaveOperationType, originalContentsURL: URL?) throws {
        if interruptAt == "partial" {
            // The safe writer supplies a staging location. Stop with an
            // incomplete staged package to simulate process death mid-write.
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("partial staged model".utf8).write(to: url.appendingPathComponent("document.json"))
        } else {
            try super.write(to: url, ofType: typeName, for: operation, originalContentsURL: originalContentsURL)
        }
        if interruptAt != nil, let readyFile {
            try Data([1]).write(to: readyFile)
            // The parent terminates this disposable writer, never the app.
            while true { Thread.sleep(forTimeInterval: 0.05) }
        }
    }
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        try NativeDocumentStorage.package(value)
    }
}

@main enum RecoveryProbe {
    @MainActor static func main() throws {
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--interrupt" {
            let child = RecoveryDocument()
            child.value.pages[0].name = "Interrupted edit"
            child.interruptAt = CommandLine.arguments[3]
            child.readyFile = URL(fileURLWithPath: CommandLine.arguments[4])
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            child.fileURL = url
            try child.writeSafely(to: url, ofType: "tapps.exp-design.package", for: .saveOperation)
            fatalError("FAIL: interrupted writer returned")
        }
        guard CommandLine.arguments.count == 2 else { fatalError("Use the bounded disk-image runner") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let target = root.appendingPathComponent("Recovery.designpkg")
        let doc = RecoveryDocument()
        doc.value.codeBridges = [CodeBridgeManifest(connector: "recovery-check", source: CodeBridgeSource(displayName: "Recovery"), resources: [CodeBridgeResource(path: "asset.bin", role: "source", preservedData: Data(repeating: 17, count: 1_024 * 1_024))])]
        let baseline = try NativeDocumentStorage.legacyData(doc.value)
        try doc.writeSafely(to: target, ofType: "tapps.exp-design.package", for: .saveAsOperation)
        doc.fileURL = target
        func unchanged(_ label: String) throws {
            let restored = try NativeDocumentStorage.read(FileWrapper(url: target))
            guard try NativeDocumentStorage.legacyData(restored) == baseline else { fatalError("FAIL: \(label)") }
            print("PASS: \(label)")
        }
        try unchanged("AppKit safe writer saves a complete initial package")
        for stage in ["partial", "complete"] {
            let marker = root.appendingPathComponent("ready-\(stage)")
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--interrupt", target.path, stage, marker.path]
            try child.run()
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: marker.path), child.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard FileManager.default.fileExists(atPath: marker.path) else {
                child.terminate(); child.waitUntilExit()
                fatalError("FAIL: writer did not reach interrupted stage")
            }
            kill(child.processIdentifier, SIGKILL)
            child.waitUntilExit()
            guard child.terminationReason == .uncaughtSignal else { fatalError("FAIL: writer not interrupted") }
            try unchanged("process death after \(stage) staging leaves the original complete")
        }
        doc.value.pages[0].name = "Unsaved recovery edit"
        doc.value.codeBridges[0].resources[0].preservedData = Data(repeating: 29, count: 16 * 1_024 * 1_024)
        let filler = root.appendingPathComponent("disposable-filler")
        guard FileManager.default.createFile(atPath: filler.path, contents: nil) else { fatalError("FAIL: filler creation") }
        let handle = try FileHandle(forWritingTo: filler)
        var filled = false
        for _ in 0..<96 {
            do { try handle.write(contentsOf: Data(repeating: 71, count: 1_024 * 1_024)) }
            catch { filled = true; break }
        }
        try? handle.close()
        guard filled else { fatalError("FAIL: isolated volume did not fill") }
        for operation in [NSDocument.SaveOperationType.saveOperation, .autosaveInPlaceOperation] {
            do {
                try doc.writeSafely(to: target, ofType: "tapps.exp-design.package", for: operation)
                fatalError("FAIL: full-volume save unexpectedly succeeded")
            } catch { print("PASS: full-volume \(operation.rawValue) reports a write failure") }
            try unchanged("full-volume \(operation.rawValue) retains the last complete package")
        }
        try FileManager.default.removeItem(at: filler)
        try doc.writeSafely(to: target, ofType: "tapps.exp-design.package", for: .saveOperation)
        let recovered = try NativeDocumentStorage.read(FileWrapper(url: target))
        guard try NativeDocumentStorage.legacyData(recovered) == NativeDocumentStorage.legacyData(doc.value) else { fatalError("FAIL: retry lost unsaved edits") }
        print("PASS: retry after freeing space saves the complete in-memory edit")
        let deniedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("exp-denied-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: deniedRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedRoot.path)
            try? FileManager.default.removeItem(at: deniedRoot)
        }
        let deniedURL = deniedRoot.appendingPathComponent("Denied.designpkg")
        try doc.writeSafely(to: deniedURL, ofType: "tapps.exp-design.package", for: .saveAsOperation)
        let deniedBaseline = try NativeDocumentStorage.legacyData(doc.value)
        doc.fileURL = deniedURL
        doc.value.pages[0].name = "Permission-denied edit"
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: deniedRoot.path)
        do {
            try doc.writeSafely(to: deniedURL, ofType: "tapps.exp-design.package", for: .saveOperation)
            fatalError("FAIL: permission-denied save unexpectedly succeeded")
        } catch { print("PASS: denied-write Save reports an error") }
        let denied = try NativeDocumentStorage.read(FileWrapper(url: deniedURL))
        guard try NativeDocumentStorage.legacyData(denied) == deniedBaseline else { fatalError("FAIL: denied write lost saved data") }
        print("PASS: denied-write Save retains the complete original")
    }
}

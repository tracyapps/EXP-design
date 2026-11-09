import CryptoKit
import Foundation

/// Native storage only. Document's ordinary Codable representation remains
/// self-contained JSON for legacy saves, clipboard, Handoff and agents.
nonisolated enum NativeDocumentStorage {
    static let formatVersion = 1
    static let maximumModelBytes = 128 * 1_024 * 1_024
    static let maximumAssetBytes = 512 * 1_024 * 1_024
    static let maximumTotalAssetBytes = 1_024 * 1_024 * 1_024
    static let maximumAssets = 4_096

    struct Envelope: Codable {
        var formatVersion: Int
        var modelSHA256: String
        var requiredFeatures: [String]
    }
    struct AssetReference: Codable {
        var asset: String
        var byteCount: Int
        enum CodingKeys: String, CodingKey { case asset = "$expAsset", byteCount }
    }
    enum StorageError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let reason) = self { return "This EXP package couldn't be read or saved. \(reason)" }
            return nil
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func checkFinderMetadata(in files: [String: FileWrapper]) throws {
        if let metadata = files[".DS_Store"] {
            guard metadata.isRegularFile, let data = metadata.regularFileContents,
                  data.count <= 1_024 * 1_024 else {
                throw StorageError.invalid("Finder metadata is unsafe or too large.")
            }
        }
    }

    /// JSONEncoder's custom strategy is Sendable. The lock owns all collector
    /// state; each save has its own collector and never touches live UI/model.
    private final class Assets: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        private var totalBytes = 0
        func insert(_ data: Data) throws -> AssetReference {
            guard data.count <= maximumAssetBytes else { throw StorageError.invalid("An asset exceeds the 512 MB limit.") }
            let key = digest(data)
            lock.lock(); defer { lock.unlock() }
            if values[key] == nil {
                guard values.count < maximumAssets,
                      totalBytes <= maximumTotalAssetBytes - data.count else {
                    throw StorageError.invalid("The document exceeds the package asset limit.")
                }
                values[key] = data
                totalBytes += data.count
            }
            return AssetReference(asset: key, byteCount: data.count)
        }
        func snapshot() -> [String: Data] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
    }

    private final class DecodeStatus: @unchecked Sendable {
        private let lock = NSLock()
        private var failed = false
        func recordFailure() { lock.lock(); failed = true; lock.unlock() }
        var hasFailure: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    }

    static func legacyData(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func package(_ document: Document, existing: FileWrapper? = nil) throws -> FileWrapper {
        let assets = Assets()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dataEncodingStrategy = .custom { data, encoder in
            try assets.insert(data).encode(to: encoder)
        }
        let model = try encoder.encode(document)
        guard model.count <= maximumModelBytes else { throw StorageError.invalid("The model exceeds the 128 MB limit.") }
        let envelope = try JSONEncoder().encode(Envelope(formatVersion: formatVersion,
                                                         modelSHA256: digest(model), requiredFeatures: []))
        let priorFolder = existing?.isDirectory == true ? existing?.fileWrappers?["assets"] : nil
        let priorAssets = priorFolder?.isDirectory == true ? priorFolder?.fileWrappers : nil
        var wrappers: [String: FileWrapper] = [:]
        for (key, data) in assets.snapshot() {
            // Keep unchanged wrappers: FileWrapper can avoid rewriting their
            // contents. Never mutate the previous version's directory/model.
            if let prior = priorAssets?[key], prior.isRegularFile,
               prior.regularFileContents == data {
                wrappers[key] = prior
            } else { wrappers[key] = FileWrapper(regularFileWithContents: data) }
        }
        return FileWrapper(directoryWithFileWrappers: [
            "package.json": FileWrapper(regularFileWithContents: envelope),
            "document.json": FileWrapper(regularFileWithContents: model),
            "assets": FileWrapper(directoryWithFileWrappers: wrappers)
        ])
    }

    static func read(_ file: FileWrapper) throws -> Document {
        if file.isRegularFile, let data = file.regularFileContents {
            return try JSONDecoder().decode(Document.self, from: data)
        }
        guard file.isDirectory, let children = file.fileWrappers,
              Set(children.keys).subtracting([".DS_Store"]) == Set(["package.json", "document.json", "assets"]),
              let header = children["package.json"], header.isRegularFile,
              let envelopeData = header.regularFileContents, envelopeData.count <= 16_384,
              let body = children["document.json"], body.isRegularFile,
              let model = body.regularFileContents, model.count <= maximumModelBytes,
              let assetFolder = children["assets"], assetFolder.isDirectory,
              let assetFiles = assetFolder.fileWrappers,
              assetFiles.keys.filter({ $0 != ".DS_Store" }).count <= maximumAssets else {
            throw StorageError.invalid("Its directory structure is missing, unsafe or too large.")
        }
        // Browsing a document in Finder can create .DS_Store. It isn't artwork.
        try checkFinderMetadata(in: children)
        try checkFinderMetadata(in: assetFiles)
        let envelope = try JSONDecoder().decode(Envelope.self, from: envelopeData)
        guard envelope.formatVersion == formatVersion, envelope.requiredFeatures.isEmpty else {
            throw StorageError.invalid("It requires a newer version of EXP (package format \(envelope.formatVersion)). The original has not been changed.")
        }
        guard isDigest(envelope.modelSHA256), digest(model) == envelope.modelSHA256 else {
            throw StorageError.invalid("The model checksum doesn't match. Restore a complete copy of this document.")
        }
        var assets: [String: Data] = [:]
        var totalBytes = 0
        for (key, wrapper) in assetFiles where key != ".DS_Store" {
            guard isDigest(key), wrapper.isRegularFile,
                  let data = wrapper.regularFileContents, data.count <= maximumAssetBytes,
                  totalBytes <= maximumTotalAssetBytes - data.count,
                  digest(data) == key else {
                throw StorageError.invalid("An asset is unsafe, damaged or exceeds the size limit.")
            }
            assets[key] = data
            totalBytes += data.count
        }
        let frozenAssets = assets
        // Some legacy optional model fields decode with try? to rescue artwork.
        // Validate EVERY storage reference first, including those fields, so a
        // missing bridge asset cannot silently discard the entire bridge.
        func validateReferences(_ value: Any) throws {
            if let object = value as? [String: Any] {
                // User/connector metadata is [String:String] and can use these
                // names too. Only a typed binary reference has a numeric length.
                if object["$expAsset"] is String, object["byteCount"] is NSNumber {
                    guard Set(object.keys) == Set(["$expAsset", "byteCount"]) else {
                        throw StorageError.invalid("An asset reference contains unknown fields.")
                    }
                    let reference = try JSONDecoder().decode(AssetReference.self, from: JSONSerialization.data(withJSONObject: object))
                    guard isDigest(reference.asset), reference.byteCount >= 0,
                          frozenAssets[reference.asset]?.count == reference.byteCount else {
                        throw StorageError.invalid("A referenced asset is missing or has an incorrect length.")
                    }
                } else {
                    for child in object.values { try validateReferences(child) }
                }
            } else if let array = value as? [Any] {
                for child in array { try validateReferences(child) }
            }
        }
        try validateReferences(JSONSerialization.jsonObject(with: model))
        let status = DecodeStatus()
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { decoder in
            do {
                let reference = try AssetReference(from: decoder)
                guard isDigest(reference.asset), reference.byteCount >= 0,
                      let data = frozenAssets[reference.asset], data.count == reference.byteCount else {
                    throw StorageError.invalid("A referenced asset is missing or has an incorrect length.")
                }
                return data
            } catch {
                status.recordFailure()
                throw error
            }
        }
        let document = try decoder.decode(Document.self, from: model)
        guard !status.hasFailure else { throw StorageError.invalid("A binary field contains an invalid asset reference.") }
        return document
    }
}

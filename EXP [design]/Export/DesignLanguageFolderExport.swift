import Foundation

/// A self-contained guide and sibling token files from the same snapshot.
struct DesignLanguageFolderExport {
    struct File {
        let name: String
        let contents: String
    }

    let files: [File]

    init(guide: DesignLanguageGuide, template: String) throws {
        let names = ["tokens.css", "_tokens.scss", "tokens.json", "tokens.resolver.json"]
        files = [File(name: "index.html", contents: try guide.html(template: template))]
            + names.compactMap { name in guide.files[name].map { File(name: name, contents: $0) } }
    }

    /// Stage the complete export on the same volume, then rename it into
    /// place. A failed export or a name collision leaves existing files alone.
    @discardableResult
    func write(to parent: URL, folderName: String, fileManager: FileManager = .default) throws -> URL {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw ExportError.invalidName
        }
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else { throw ExportError.alreadyExists(name) }
        let staging = parent.appendingPathComponent(".exp-guide-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }
        for file in files {
            try file.contents.write(to: staging.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }

    private enum ExportError: LocalizedError {
        case invalidName
        case alreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "Enter a folder name without slashes or colons."
            case .alreadyExists(let name):
                "“\(name)” already exists here. Choose another location or folder name."
            }
        }
    }
}

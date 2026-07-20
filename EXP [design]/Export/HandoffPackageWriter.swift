//
//  HandoffPackageWriter.swift
//  EXP [design]
//
//  v1.5 Chunk A: write the first EXP handoff package spine. The package is a
//  folder with a stable extension so it is inspectable, diffable, and easy for
//  agents/dev teams to consume before the later semantic HTML exporter lands.
//

import Foundation
import CryptoKit

struct HandoffPackageWriter {
    static let packageExtension = "exph"
    static let packageFormatVersion = 1

    let document: Document
    let sourceURL: URL?
    let toolVersion: String
    let buildVersion: String

    init(document: Document, sourceURL: URL? = nil,
         bundle: Bundle = .main) {
        self.document = document
        self.sourceURL = sourceURL
        toolVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    func write(to packageURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: packageURL.path) {
            try fm.removeItem(at: packageURL)
        }
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let designData = try encodedDesign()
        let tokensData = try DesignLanguageIO.exportDesignTokensJSON(document.designLanguage)
        let readmeData = Data(readme().utf8)

        try designData.write(to: packageURL.appendingPathComponent("design.json"), options: .atomic)
        try tokensData.write(to: packageURL.appendingPathComponent("tokens.json"), options: .atomic)
        try manifestData(designData: designData, tokensData: tokensData, readmeData: readmeData)
            .write(to: packageURL.appendingPathComponent("manifest.json"), options: .atomic)
        try readmeData.write(to: packageURL.appendingPathComponent("README.llm.md"), options: .atomic)
    }

    private func encodedDesign() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(document)
    }

    private func manifestData(designData: Data, tokensData: Data, readmeData: Data) throws -> Data {
        let manifest = HandoffManifest(
            expHandoffPackage: Self.packageFormatVersion,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            tool: .init(name: "EXP [design]", version: toolVersion, build: buildVersion),
            sourceDocument: sourceURL?.lastPathComponent,
            entries: [
                .init(path: "design.json",
                      role: "document",
                      mediaType: "application/json",
                      // What the encoder actually writes (an opened v1 file
                      // still reports its decoded version in memory).
                      schemaVersion: Document.currentSchemaVersion,
                      bytes: designData.count,
                      sha256: sha256(designData)),
                .init(path: "tokens.json",
                      role: "design-tokens",
                      mediaType: "application/json",
                      schemaVersion: 1,
                      bytes: tokensData.count,
                      sha256: sha256(tokensData)),
                .init(path: "README.llm.md",
                      role: "orientation",
                      mediaType: "text/markdown",
                      schemaVersion: nil,
                      bytes: readmeData.count,
                      sha256: sha256(readmeData)),
            ],
            summary: .init(artboards: document.artboards.count,
                           nodes: count(document.nodes),
                           components: document.sources.count,
                           notes: document.artboards.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                           designTokens: document.designLanguage.assets.count + document.designLanguage.typeStyles.count),
            fidelity: .init(geometry: "native",
                            styles: "native",
                            text: "native",
                            components: "source-instance references",
                            semantics: "component ARIA roles where assigned",
                            notes: "artboard notes included"))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(manifest)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func count(_ nodes: [Node]) -> Int {
        nodes.reduce(0) { total, node in
            if case .group(let children) = node.content {
                return total + 1 + count(children)
            }
            return total + 1
        }
    }

    private func readme() -> String {
        let sourceName = sourceURL?.lastPathComponent ?? "Untitled document"
        let notes = document.artboards
            .filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "- \($0.name) (`\($0.id.uuidString)`) has artboard notes." }
            .joined(separator: "\n")
        let roles = document.sources
            .compactMap { source -> String? in
                guard let role = source.a11y.role else { return nil }
                return "- \(source.name) (`\(source.id.uuidString)`) is categorized as ARIA `\(role.rawValue)`."
            }
            .joined(separator: "\n")

        return """
        # EXP Handoff Package

        Source: \(sourceName)
        Generated by EXP [design] \(toolVersion) (\(buildVersion)).

        ## Files

        - `manifest.json` lists package entries, versions, counts, and fidelity notes.
        - `design.json` is the public EXP document payload. Node, artboard, component, and design-language ids are stable references.
        - `tokens.json` is the document Design Language as W3C Design Tokens JSON.
        - `README.llm.md` is this orientation file for people and local agents.

        ## How to Read This

        Use `manifest.json` first, then open `design.json` for geometry, layers, components, ARIA role categories, and artboard notes. Use ids as the only reference currency: do not infer identity from names or layer order. `tokens.json` carries reusable colors, gradients, and type styles when the document has them.

        ## Artboard Notes

        \(notes.isEmpty ? "No artboard notes are present." : notes)

        ## Component Semantics

        \(roles.isEmpty ? "No component ARIA roles are assigned." : roles)

        ## Fidelity

        This v1.5 package preserves EXP's native document data. Semantic HTML/CSS export is planned for a later interop chunk, so this package intentionally does not pretend to be production markup yet.
        """
    }
}

private struct HandoffManifest: Codable {
    struct Tool: Codable {
        var name: String
        var version: String
        var build: String
    }

    struct Entry: Codable {
        var path: String
        var role: String
        var mediaType: String
        var schemaVersion: Int?
        var bytes: Int
        var sha256: String
    }

    struct Summary: Codable {
        var artboards: Int
        var nodes: Int
        var components: Int
        var notes: Int
        var designTokens: Int
    }

    struct Fidelity: Codable {
        var geometry: String
        var styles: String
        var text: String
        var components: String
        var semantics: String
        var notes: String
    }

    var expHandoffPackage: Int
    var generatedAt: String
    var tool: Tool
    var sourceDocument: String?
    var entries: [Entry]
    var summary: Summary
    var fidelity: Fidelity
}

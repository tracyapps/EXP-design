//
//  HandoffPackageWriter.swift
//  EXP [design]
//
//  v1.5 Chunk A: write the first EXP handoff package spine. The package is a
//  folder with a stable extension so it is inspectable, diffable, and easy for
//  agents/dev teams to consume. v2.0 B1 adds the first semantic HTML/CSS slice.
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
        let htmlBundle = SemanticHTMLExporter(document: document).makeBundle()
        let readmeData = Data(readme(htmlBundle: htmlBundle).utf8)

        try designData.write(to: packageURL.appendingPathComponent("design.json"), options: .atomic)
        try tokensData.write(to: packageURL.appendingPathComponent("tokens.json"), options: .atomic)
        for artifact in htmlBundle.artifacts {
            let target = packageURL.appendingPathComponent(artifact.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try artifact.data.write(to: target, options: .atomic)
        }
        try manifestData(designData: designData, tokensData: tokensData,
                         htmlBundle: htmlBundle, readmeData: readmeData)
            .write(to: packageURL.appendingPathComponent("manifest.json"), options: .atomic)
        try readmeData.write(to: packageURL.appendingPathComponent("README.llm.md"), options: .atomic)
    }

    private func encodedDesign() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(document)
    }

    private func manifestData(designData: Data, tokensData: Data,
                              htmlBundle: SemanticHTMLBundle,
                              readmeData: Data) throws -> Data {
        let htmlEntries = htmlBundle.artifacts.map { artifact in
            HandoffManifest.Entry(path: artifact.path,
                                  role: artifact.role,
                                  mediaType: artifact.mediaType,
                                  schemaVersion: SemanticHTMLExporter.formatVersion,
                                  bytes: artifact.data.count,
                                  sha256: sha256(artifact.data))
        }
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
            ] + htmlEntries + [
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
                           designTokens: document.designLanguage.assets.count + document.designLanguage.typeStyles.count,
                           semanticHTMLPages: htmlBundle.pagePaths.count,
                           semanticHTMLNodes: htmlBundle.emittedNodeCount,
                           semanticHTMLOmittedWallNodes: htmlBundle.omittedWallNodeCount),
            fidelity: .init(geometry: "native",
                            styles: "native",
                            text: "native",
                            components: "source-instance references",
                            semantics: "HTML B2 native/ARIA component contract with explicit requirements for missing model facts",
                            notes: "full artboard notes included in README and as safe HTML comments; wall-only nodes omitted and counted",
                            semanticHTMLRequirements: htmlBundle.fidelityIssues.map {
                                .init(artboardID: $0.artboardID,
                                      nodeID: $0.nodeID,
                                      sourceID: $0.sourceID,
                                      role: $0.role?.rawValue,
                                      requirement: $0.requirement,
                                      detail: $0.detail)
                            }))
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

    private func readme(htmlBundle: SemanticHTMLBundle) -> String {
        let sourceName = sourceURL?.lastPathComponent ?? "Untitled document"
        let notes = document.artboards
            .filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { artboard in
                "### \(markdownInline(artboard.name))\n\n" +
                "Artboard id: `\(artboard.id.uuidString)`\n\n" +
                markdownBlockquote(artboard.notes)
            }
            .joined(separator: "\n\n")
        let roles = document.sources
            .compactMap { source -> String? in
                guard let role = source.a11y.role else { return nil }
                return "- \(source.name) (`\(source.id.uuidString)`) is categorized as ARIA `\(role.rawValue)`."
            }
            .joined(separator: "\n")
        let htmlPages = htmlBundle.pagePaths
            .map { "- `\($0)`" }
            .joined(separator: "\n")
        let semanticRequirements = htmlBundle.fidelityIssues.map { issue in
            let role = issue.role.map { " ARIA `\($0.rawValue)`" } ?? ""
            return "- Artboard `\(issue.artboardID.uuidString)`, node `\(issue.nodeID.uuidString)`\(role): **\(markdownInline(issue.requirement))** — \(issue.detail)"
        }.joined(separator: "\n")

        return """
        # EXP Handoff Package

        Source: \(sourceName)
        Generated by EXP [design] \(toolVersion) (\(buildVersion)).

        ## Files

        - `manifest.json` lists package entries, versions, counts, and fidelity notes.
        - `design.json` is the public EXP document payload. Node, artboard, component, and design-language ids are stable references.
        - `tokens.json` is the document Design Language as W3C Design Tokens JSON.
        - `html/styles.css` is the shared generated stylesheet.
        - `html/*.html` contains one standalone page per artboard.
        - `README.llm.md` is this orientation file for people and local agents.

        ## How to Read This

        Use `manifest.json` first, then open `design.json` for geometry, layers, components, ARIA role categories, and artboard notes. Use ids as the only reference currency: do not infer identity from names or layer order. `tokens.json` carries reusable colors, gradients, and type styles when the document has them. Open an HTML page directly in a browser; its relative link resolves the shared stylesheet without a build step or remote dependency.

        ## HTML Entry Points

        \(htmlPages.isEmpty ? "No artboards were available for HTML export." : htmlPages)

        The B2 HTML slice preserves artboard ownership, stable `data-exp-id` references, component source references, repeated-instance identity, visibility, and absolute geometry. Categorized components use native HTML where EXP can do so honestly and explicit ARIA otherwise. Accessible-name layers and typed relationships stay id-based. Component states export as conventional pseudo-classes, disabled attributes, or custom `data-state` selectors. EXP generates no JavaScript and does not fabricate missing behavior or values. Flex auto-layout and token-linked declarations arrive in B3.

        \(htmlBundle.omittedWallNodeCount == 0 ? "No wall-only nodes were omitted." : "\(htmlBundle.omittedWallNodeCount) wall-only node(s) were omitted because they do not belong to an artboard.")

        ## Artboard Notes

        \(notes.isEmpty ? "No artboard notes are present." : notes)

        ## Component Semantics

        \(roles.isEmpty ? "No component ARIA roles are assigned." : roles)

        ## Semantic HTML Requirements

        \(semanticRequirements.isEmpty ? "No unresolved semantic HTML requirements were found." : semanticRequirements)

        ## Fidelity

        This package preserves EXP's native document data and includes the v2.0 B2 semantic HTML/CSS contract. The generated pages are deterministic, inspectable handoff artifacts—not a claim that listed downstream interaction requirements have been implemented.
        """
    }

    private func markdownInline(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        for character in ["`", "*", "_", "{", "}", "[", "]", "<", ">", "#", "|"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\\(character)")
        }
        return escaped
    }

    private func markdownBlockquote(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
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
        var semanticHTMLPages: Int
        var semanticHTMLNodes: Int
        var semanticHTMLOmittedWallNodes: Int
    }

    struct Fidelity: Codable {
        struct SemanticIssue: Codable {
            var artboardID: UUID
            var nodeID: UUID
            var sourceID: UUID?
            var role: String?
            var requirement: String
            var detail: String
        }

        var geometry: String
        var styles: String
        var text: String
        var components: String
        var semantics: String
        var notes: String
        var semanticHTMLRequirements: [SemanticIssue]
    }

    var expHandoffPackage: Int
    var generatedAt: String
    var tool: Tool
    var sourceDocument: String?
    var entries: [Entry]
    var summary: Summary
    var fidelity: Fidelity
}

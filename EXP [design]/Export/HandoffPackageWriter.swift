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
    let generatedAt: Date

    init(document: Document, sourceURL: URL? = nil,
         bundle: Bundle = .main, generatedAt: Date = Date()) {
        self.document = document
        self.sourceURL = sourceURL
        self.generatedAt = generatedAt
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
        let readmeData = Data(orientationMarkdown(htmlBundle: htmlBundle).utf8)

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
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
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
            summary: .init(artboards: document.allArtboards.count,
                           nodes: document.pages.reduce(0) { $0 + count($1.nodes) },
                           components: document.sources.count,
                           notes: document.allArtboards.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                           designTokens: document.designLanguage.assets.count + document.designLanguage.typeStyles.count,
                           semanticHTMLPages: htmlBundle.pagePaths.count,
                           semanticHTMLNodes: htmlBundle.emittedNodeCount,
                           semanticHTMLOmittedWallNodes: htmlBundle.omittedWallNodeCount),
            fidelity: .init(geometry: "native geometry where representable; structured visual fallbacks identify approximations",
                            styles: "CSS/SVG with structured visual fallbacks for unsupported effects and paint details",
                            text: "native",
                            components: "source-instance references",
                            semantics: "HTML B2 native/ARIA component contract with explicit requirements for missing model facts",
                            notes: "full artboard notes included in README and as safe HTML comments; wall-only nodes omitted and counted",
                            semanticHTMLRequirements: htmlBundle.fidelityIssues.map {
                                .init(artboardID: $0.artboardID,
                                      nodeID: $0.nodeID,
                                      instanceID: $0.instanceID,
                                      sourceID: $0.sourceID,
                                      role: $0.role?.rawValue,
                                      category: $0.category.rawValue,
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

    /// The same orientation shipped as README.llm.md and exposed through MCP.
    /// Keeping one generator prevents the package and live bridge from drifting.
    func orientationMarkdown() -> String {
        orientationMarkdown(htmlBundle: SemanticHTMLExporter(document: document).makeBundle())
    }

    private func orientationMarkdown(htmlBundle: SemanticHTMLBundle) -> String {
        let sourceName = sourceURL?.lastPathComponent ?? "Untitled document"
        let notes = document.allArtboards
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
        let componentProps = document.sources
            .compactMap { source -> String? in
                let props = Self.publicProps(of: source, in: document)
                guard !props.isEmpty else { return nil }
                return "### \(markdownInline(source.name))\n\n" + props.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        let htmlPages = htmlBundle.pagePaths
            .map { "- `\($0)`" }
            .joined(separator: "\n")
        let semanticRequirements = htmlBundle.fidelityIssues.map { issue in
            let role = issue.role.map { " ARIA `\($0.rawValue)`" } ?? ""
            let instance = issue.instanceID.map { ", instance `\($0.uuidString)`" } ?? ""
            // Three distinct things, named distinctly. A reader has to be able to
            // tell "a rule was broken" from "we approximated something visual"
            // from "this is legal but probably not what you meant" — flattening
            // them makes the report either alarmist or ignorable. FEAT-016.
            let category: String
            switch issue.category {
            case .visualFallback:      category = "Visual fallback"
            case .advisory:            category = "Advisory"
            case .semanticRequirement: category = "Semantic requirement"
            }
            return "- \(category) — artboard `\(issue.artboardID.uuidString)`, node `\(issue.nodeID.uuidString)`\(instance)\(role): **\(markdownInline(issue.requirement))** — \(issue.detail)"
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

        The v2.0 HTML slice preserves artboard ownership, stable `data-exp-id` references, component source references, repeated-instance identity, visibility, and absolute geometry. Categorized components use native HTML where EXP can do so honestly and explicit ARIA otherwise. Accessible-name layers and typed relationships stay id-based. Component states export as conventional pseudo-classes, disabled attributes, or custom `data-state` selectors. EXP generates no JavaScript and does not fabricate missing behavior or values. Flex auto-layout and token-linked declarations are included; semantic requirements and visual approximations are listed below instead of being silently dropped.

        \(htmlBundle.omittedWallNodeCount == 0 ? "No wall-only nodes were omitted." : "\(htmlBundle.omittedWallNodeCount) wall-only node(s) were omitted because they do not belong to an artboard.")

        ## Artboard Notes

        \(notes.isEmpty ? "No artboard notes are present." : notes)

        ## Component Semantics

        \(roles.isEmpty ? "No component ARIA roles are assigned." : roles.joined(separator: "\n"))

        ## Component Props

        Fields the component author marked PUBLIC — the ones intended to be real props in code, as opposed to tweaks made locally in EXP. A path with more than one step reaches a layer inside a nested component; each step is that nested component's layer name.

        \(componentProps.isEmpty ? "No fields are marked as public props. Everything overridable is currently EXP-local." : componentProps)

        ## Semantic HTML Requirements & Visual Fallbacks

        \(semanticRequirements.isEmpty ? "No unresolved semantic HTML requirements were found." : semanticRequirements)

        ## Fidelity

        This package preserves EXP's native document data and includes the verified v2.0 semantic HTML/CSS contract. The generated pages are deterministic, inspectable handoff artifacts—not a claim that listed downstream interaction requirements have been implemented or that a reported visual fallback is pixel-identical.
        """
    }

    /// Public props of a component, INCLUDING ones on layers inside nested
    /// components, addressed by the same path `NestedInstanceOverride` uses.
    ///
    /// `publicProps` has existed on `Node` for a while and was never advertised
    /// anywhere in the package — so a reader had to infer a component's API from
    /// the raw model tree, which is exactly the guessing a handoff exists to
    /// prevent. Its stored meaning is deliberately preserved: false keeps an
    /// override EXP-local, true declares it part of the component's public
    /// contract. This reports that declaration; it does not gate anything.
    static func publicProps(of source: ComponentSource, in document: Document,
                            nodes: [Node]? = nil, path: [String] = [],
                            depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var out: [String] = []
        for node in nodes ?? source.children {
            let name = node.name.isEmpty ? "(unnamed)" : node.name
            let here = path + [name]
            if node.publicProps.text {
                out.append("- `\(here.joined(separator: " / "))` — text")
            }
            if node.publicProps.fill {
                out.append("- `\(here.joined(separator: " / "))` — fill")
            }
            switch node.content {
            case .group(let children):
                // Groups are structure, not identity — they do not add a path step,
                // for the same reason a relationship endpoint never names one.
                out += publicProps(of: source, in: document, nodes: children,
                                   path: path, depth: depth + 1)
            case .instance(let nested):
                guard let nestedSource = document.source(for: nested.sourceID) else { break }
                out += publicProps(of: nestedSource, in: document,
                                   nodes: nestedSource.children,
                                   path: here, depth: depth + 1)
            default:
                break
            }
        }
        return out
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
            var instanceID: UUID?
            var sourceID: UUID?
            var role: String?
            var category: String
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

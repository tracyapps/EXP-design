//
//  StorybookPackageImporter.swift
//  EXP [design]
//
//  First E2 slice: import a user-selected static Storybook build through its
//  published index.json + isolated iframe.html contract. EXP never installs
//  dependencies or runs a framework/build command; browser-ready local output
//  runs only in the existing network-blocked, non-persistent WebKit boundary.
//

import CryptoKit
import CoreGraphics
import Foundation

nonisolated struct StorybookStorySummary: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var name: String
    var importPath: String?
    var tags: [String]

    var displayName: String { "\(title) / \(name)" }

    var searchableText: String {
        ([id, title, name, importPath ?? ""] + tags)
            .joined(separator: " ").localizedLowercase
    }
}

nonisolated struct StorybookCatalogSummary: Sendable {
    var version: String?
    var stories: [StorybookStorySummary]
}

@MainActor
final class StorybookPackageImporter {
    nonisolated struct Limits: Sendable {
        var maximumIndexBytes = 16 * 1_024 * 1_024
        var maximumProjectMetadataBytes = 1 * 1_024 * 1_024
        var maximumStories = 100
        var maximumEntryReceiptBytes = 64 * 1_024
    }

    private let limits: Limits
    private let capture: RenderedHTMLWebKitCapture

    init(limits: Limits = Limits()) {
        self.limits = limits
        self.capture = RenderedHTMLWebKitCapture()
    }

    /// Read only the bounded public catalog so the UI can offer story selection
    /// before WebKit renders anything. No story or package script executes here.
    func discover(from directoryURL: URL) throws -> StorybookCatalogSummary {
        let package = try readPackage(at: directoryURL)
        return StorybookCatalogSummary(
            version: package.catalog.version,
            stories: package.catalog.stories.map {
                StorybookStorySummary(id: $0.id, title: $0.title, name: $0.name,
                                      importPath: $0.importPath, tags: $0.tags)
            })
    }

    func read(from directoryURL: URL,
              storyIDs: Set<String>? = nil,
              viewports: [RenderedHTMLViewport],
              context: InteropContext = InteropContext()) async throws
        -> InteropImportResult {
        let package = try readPackage(at: directoryURL)
        let root = package.root
        let iframeURL = package.iframeURL
        let indexData = package.indexData
        let catalog = package.catalog
        let accessStarted = root.startAccessingSecurityScopedResource()
        defer { if accessStarted { root.stopAccessingSecurityScopedResource() } }
        guard !catalog.stories.isEmpty else {
            throw InteropCodecError.noUsableArtwork
        }
        let requestedStories: [StorybookCatalog.Story]
        if let storyIDs {
            guard !storyIDs.isEmpty else { throw InteropCodecError.noUsableArtwork }
            requestedStories = catalog.stories.filter { storyIDs.contains($0.id) }
            guard requestedStories.count == storyIDs.count else {
                throw InteropCodecError.unreadablePackage(
                    "one or more selected stories no longer exist in index.json")
            }
        } else {
            requestedStories = catalog.stories
        }
        guard requestedStories.count <= limits.maximumStories else {
            throw InteropCodecError.unreadablePackage(
                "choose at most \(limits.maximumStories) stories per import")
        }

        var page = CanvasPage(name: root.lastPathComponent)
        var report = InteropImportReport(format: .storybook,
                                         sourceName: root.lastPathComponent)
        var resourcesByPath: [String: CodeBridgeResource] = [:]
        var bindings: [CodeBridgeBinding] = []
        var contracts: [CodeBridgeBehaviorContract] = []
        var nextX: CGFloat = 0

        for (index, story) in requestedStories.enumerated() {
            try context.report(.opening, completed: index,
                               total: requestedStories.count,
                               detail: "\(story.title) / \(story.name)")
            if context.cancellation.isCancelled || Task.isCancelled {
                throw InteropCodecError.cancelled
            }
            var rendered = try await capture.readLocalFile(
                from: iframeURL, scopedDirectory: root,
                queryItems: [URLQueryItem(name: "id", value: story.id),
                             URLQueryItem(name: "viewMode", value: "story")],
                transport: .loopbackHTTP,
                readiness: .storybookStory,
                viewports: viewports, context: context)
            // A Storybook story is rendered *at* a selected viewport, even when
            // its preview body shrink-wraps a 32px button or 72px accordion.
            // Keep that viewport as the minimum canvas rather than producing a
            // misleading sliver; genuinely taller story content still expands
            // the measured artboard. Ordinary local HTML retains its separate
            // content-height contract in RenderedHTMLImporter.
            if !rendered.payload.pages.isEmpty {
                for artboardIndex in rendered.payload.pages[0].artboards.indices
                    where artboardIndex < viewports.count {
                    rendered.payload.pages[0].artboards[artboardIndex].frame.size.height = max(
                        rendered.payload.pages[0].artboards[artboardIndex].frame.height,
                        viewports[artboardIndex].renderHeight)
                    // Storybook previews commonly leave html/body transparent;
                    // the browser canvas underneath is nevertheless white. A
                    // transparent EXP board exposes the dark canvas and turns
                    // the unused viewport into the large black regions seen in
                    // real imports, so retain the browser's default backdrop.
                    if rendered.payload.pages[0].artboards[artboardIndex]
                        .background.representativeColor.a <= 0.001 {
                        rendered.payload.pages[0].artboards[artboardIndex]
                            .background = .white
                    }
                }
            }
            rendered.payload.translate(by: CGPoint(x: nextX, y: 0))
            guard let renderedPage = rendered.payload.pages.first else { continue }

            for var artboard in renderedPage.artboards {
                let viewport = artboard.name.split(separator: "—").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Viewport"
                artboard.name = "\(story.title) / \(story.name) — \(viewport)"
                var metadata = "Storybook story: \(story.id)"
                if let importPath = story.importPath { metadata += "\nSource: \(importPath)" }
                if !story.tags.isEmpty { metadata += "\nTags: \(story.tags.joined(separator: ", "))" }
                artboard.notes = metadata + "\n\n" + artboard.notes
                page.artboards.append(artboard)
            }
            page.nodes.append(contentsOf: renderedPage.nodes)
            nextX = (page.artboards.map(\.frame.maxX).max() ?? nextX)
                + RenderedHTMLImporter.artboardGap

            merge(rendered.report, into: &report)
            var runtimeMetadata: [String: String] = [:]
            if let bridge = rendered.codeBridges.first {
                runtimeMetadata = bridge.source.metadata
                for resource in bridge.resources { resourcesByPath[resource.path] = resource }
                for var binding in bridge.bindings {
                    binding.externalID = "\(story.id):\(binding.externalID)"
                    binding.externalKind = binding.expArtboardID == nil
                        ? "storybook-dom" : "storybook-story-viewport"
                    binding.metadata["storyID"] = story.id
                    binding.metadata["storyTitle"] = story.title
                    binding.metadata["storyName"] = story.name
                    binding.metadata["connector"] = "storybook-static"
                    bindings.append(binding)
                }
            }
            var payload = [
                "title": story.title,
                "name": story.name,
                "tags": story.tags.joined(separator: ",")
            ]
            if let importPath = story.importPath { payload["importPath"] = importPath }
            if let initialArgs = runtimeMetadata["initialArgsJSON"] {
                payload["initialArgsJSON"] = initialArgs
            }
            if let receipt = story.entryReceipt(maximumBytes: limits.maximumEntryReceiptBytes) {
                payload["indexEntryJSON"] = receipt
            }
            contracts.append(CodeBridgeBehaviorContract(
                externalID: story.id, kind: "storybook-story",
                name: "\(story.title) / \(story.name)", payload: payload))
        }

        guard !page.artboards.isEmpty else { throw InteropCodecError.noUsableArtwork }
        let digest = Self.sha256(indexData)
        resourcesByPath["index.json"] = CodeBridgeResource(
            path: "index.json", role: "configuration", mimeType: "application/json",
            byteCount: indexData.count, sha256: digest,
            preservedData: indexData.count <= limits.maximumIndexBytes ? indexData : nil,
            metadata: ["preservation": "inline"])
        if let projectData = package.projectData {
            resourcesByPath["project.json"] = CodeBridgeResource(
                path: "project.json", role: "configuration",
                mimeType: "application/json", byteCount: projectData.count,
                sha256: Self.sha256(projectData), preservedData: projectData,
                metadata: ["preservation": "inline"])
        }
        let project = package.projectMetadata
        let manifest = CodeBridgeManifest(
            connector: "storybook-static",
            source: CodeBridgeSource(
                displayName: root.lastPathComponent,
                stableID: "storybook-index:\(digest)", entryPath: "index.json",
                framework: project?.framework,
                frameworkVersion: project?.frameworkVersion,
                buildTool: project?.builder ?? "Storybook",
                buildToolVersion: project?.builderVersion
                    ?? project?.storybookVersion ?? catalog.version,
                metadata: ["iframeEntry": "iframe.html"]
                    .merging(project?.sourceMetadata ?? [:]) { current, _ in current }),
            resources: resourcesByPath.values.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            },
            bindings: bindings, behaviorContracts: contracts,
            baseline: CodeBridgeBaseline(
                sourceDigest: digest,
                metadata: ["storyCount": String(requestedStories.count),
                           "catalogStoryCount": String(catalog.stories.count),
                           "viewportCount": String(viewports.count)]),
            metadata: [
                "packageFormat": "storybook-static",
                "renderContract": "index.json+iframe.html",
                "buildExecution": "never",
                "sourceWritePolicy": "receipt-only"
            ])
        report.format = .storybook
        report.sourceName = root.lastPathComponent
        report.mapped("Story", count: requestedStories.count)
        report.add(.information, .exact, category: "Storybook package",
                   message: "Discovered \(catalog.stories.count) stories through index.json and rendered the \(requestedStories.count) selected isolated iframe stor\(requestedStories.count == 1 ? "y" : "ies"). EXP did not install dependencies or run a Storybook/framework build.")
        report.add(.information, .exact, category: "Storybook provenance",
                   message: "Story ids, titles, names, tags, import paths, published initial args, index entries, build/framework metadata when available, consumed-resource hashes, and receipt-only DOM bindings were retained in the hidden code bridge.")
        return InteropImportResult(payload: InteropImportPayload(pages: [page]),
                                   report: report, codeBridges: [manifest])
    }

    func cancel() { capture.cancel() }

    private struct Package {
        var root: URL
        var iframeURL: URL
        var indexData: Data
        var catalog: StorybookCatalog
        var projectData: Data?
        var projectMetadata: StorybookProjectMetadata?
    }

    private func readPackage(at directoryURL: URL) throws -> Package {
        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw InteropCodecError.unreadablePackage(
                "Storybook import requires a static-build folder")
        }
        let indexURL = root.appendingPathComponent("index.json")
        let iframeURL = root.appendingPathComponent("iframe.html")
        guard (try? indexURL.resourceValues(forKeys: [.isRegularFileKey])
            .isRegularFile) == true else {
            throw InteropCodecError.unreadablePackage(
                "index.json is missing; choose the root of a built Storybook")
        }
        guard (try? iframeURL.resourceValues(forKeys: [.isRegularFileKey])
            .isRegularFile) == true else {
            throw InteropCodecError.unreadablePackage(
                "iframe.html is missing; choose a complete static Storybook build")
        }
        let accessStarted = root.startAccessingSecurityScopedResource()
        defer { if accessStarted { root.stopAccessingSecurityScopedResource() } }
        let indexData = try Data(contentsOf: indexURL, options: .mappedIfSafe)
        guard indexData.count <= limits.maximumIndexBytes else {
            throw InteropCodecError.unreadablePackage(
                "index.json exceeds the \(limits.maximumIndexBytes / 1_024 / 1_024) MB limit")
        }
        let projectURL = root.appendingPathComponent("project.json")
        let projectData: Data?
        if (try? projectURL.resourceValues(forKeys: [.isRegularFileKey])
            .isRegularFile) == true,
           let data = try? Data(contentsOf: projectURL, options: .mappedIfSafe),
           data.count <= limits.maximumProjectMetadataBytes {
            projectData = data
        } else {
            projectData = nil
        }
        return Package(root: root, iframeURL: iframeURL, indexData: indexData,
                       catalog: try StorybookCatalog(data: indexData),
                       projectData: projectData,
                       projectMetadata: projectData.flatMap(StorybookProjectMetadata.init))
    }

    private func merge(_ source: InteropImportReport,
                       into destination: inout InteropImportReport) {
        for (kind, count) in source.mappedCounts { destination.mapped(kind, count: count) }
        for issue in source.issues {
            for _ in 0..<issue.occurrences {
                destination.add(issue.severity, issue.fidelity,
                                category: issue.category, message: issue.message,
                                location: issue.location)
            }
        }
        destination.notesWritten += source.notesWritten
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated private struct StorybookProjectMetadata {
    var framework: String?
    var frameworkVersion: String?
    var builder: String?
    var builderVersion: String?
    var storybookVersion: String?
    var sourceMetadata: [String: String]

    init?(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let frameworkObject = root["framework"] as? [String: Any]
        framework = frameworkObject?["name"] as? String
            ?? root["framework"] as? String
        builder = root["builder"] as? String
        let packages = root["storybookPackages"] as? [String: Any] ?? [:]
        func packageVersion(_ name: String?) -> String? {
            guard let name,
                  let entry = packages[name] as? [String: Any] else { return nil }
            return entry["version"] as? String
        }
        frameworkVersion = packageVersion(framework)
        builderVersion = packageVersion(builder)

        var metadata: [String: String] = [:]
        if let version = root["storybookVersion"] as? String {
            storybookVersion = version
            metadata["storybookVersion"] = version
        } else {
            storybookVersion = nil
        }
        if let renderer = root["renderer"] as? String {
            metadata["renderer"] = renderer
        }
        if let language = root["language"] as? String {
            metadata["language"] = language
        }
        if let packageManager = root["packageManager"] as? [String: Any] {
            if let type = packageManager["type"] as? String {
                metadata["packageManager"] = type
            }
            if let version = packageManager["version"] as? String {
                metadata["packageManagerVersion"] = version
            }
        }
        sourceMetadata = metadata
    }
}

nonisolated private struct StorybookCatalog {
    struct Story {
        var id: String
        var title: String
        var name: String
        var importPath: String?
        var tags: [String]
        var raw: [String: Any]

        func entryReceipt(maximumBytes: Int) -> String? {
            guard JSONSerialization.isValidJSONObject(raw),
                  let data = try? JSONSerialization.data(
                    withJSONObject: raw, options: [.sortedKeys]),
                  data.count <= maximumBytes else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    var version: String?
    var stories: [Story]

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw InteropCodecError.unreadablePackage("index.json is not a JSON object")
        }
        version = (root["v"] as? NSNumber)?.stringValue
            ?? root["v"] as? String
        let rawEntries = (root["entries"] as? [String: Any])
            ?? (root["stories"] as? [String: Any])
        guard let rawEntries else {
            throw InteropCodecError.unreadablePackage(
                "index.json has no Storybook entries/stories catalog")
        }
        stories = rawEntries.compactMap { key, value in
            guard let entry = value as? [String: Any] else { return nil }
            let type = (entry["type"] as? String)?.lowercased()
            guard type == nil || type == "story" else { return nil }
            let id = (entry["id"] as? String) ?? key
            guard !id.isEmpty else { return nil }
            let title = (entry["title"] as? String) ?? "Untitled"
            let name = (entry["name"] as? String) ?? id
            let tags = entry["tags"] as? [String] ?? []
            return Story(id: id, title: title, name: name,
                         importPath: entry["importPath"] as? String,
                         tags: tags, raw: entry)
        }.sorted {
            let left = "\($0.title)\u{0}\($0.name)\u{0}\($0.id)"
            let right = "\($1.title)\u{0}\($1.name)\u{0}\($1.id)"
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

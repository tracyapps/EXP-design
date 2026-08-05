//
//  RenderedHTMLWebKitCapture.swift
//  EXP [design]
//
//  E1b's local-file browser boundary. This owns the short-lived WKWebView,
//  applies the privacy/limit contract, and hands browser snapshots to the pure
//  RenderedHTMLImporter mapper. Remote URL trust/session work is intentionally
//  a later layer; this first production path permits only the selected folder.
//

import AppKit
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers
import WebKit

nonisolated enum RenderedHTMLLocalTransport: Sendable {
    case customScheme
    /// Storybook's production runtime uses ES modules and webpack chunks, which
    /// WebKit does not execute reliably from a custom URL scheme. Serve only the
    /// selected folder on an ephemeral 127.0.0.1 port instead.
    case loopbackHTTP
}

nonisolated enum RenderedHTMLReadiness: Sendable {
    case documentSettled
    case storybookStory
}

@MainActor
final class RenderedHTMLWebKitCapture: NSObject, WKNavigationDelegate {
    nonisolated struct Limits: Sendable {
        var maximumNodes = 15_000
        var maximumPayloadBytes = 64 * 1_024 * 1_024
        var renderDeadline: TimeInterval = 10
        var settleMilliseconds = 1_200
        var maximumViewports = 5
        /// Source text is useful for lossless handoff, but a design file should
        /// not silently become an unbounded website archive.
        var maximumPreservedSourceBytes = 8 * 1_024 * 1_024
    }

    private let limits: Limits
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var loadMonitor: Task<Void, Never>?
    private weak var activeWebView: WKWebView?
    private var expectedMainDocument: URL?
    private var navigationNotes: [String] = []

    private struct RenderedCapture {
        var snapshotData: Data
        var resources: [CodeBridgeResource]
    }

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func readLocalFile(from fileURL: URL,
                       scopedDirectory: URL? = nil,
                       queryItems: [URLQueryItem] = [],
                       transport: RenderedHTMLLocalTransport = .customScheme,
                       readiness: RenderedHTMLReadiness = .documentSettled,
                       viewports: [RenderedHTMLViewport],
                       context: InteropContext = InteropContext()) async throws
        -> InteropImportResult {
        guard fileURL.isFileURL else {
            throw InteropCodecError.unreadablePackage("local HTML import requires a file URL")
        }
        guard !viewports.isEmpty, viewports.count <= limits.maximumViewports else {
            throw InteropCodecError.unreadablePackage(
                "choose between 1 and \(limits.maximumViewports) browser viewports")
        }
        let directoryURL = (scopedDirectory ?? fileURL.deletingLastPathComponent())
            .resolvingSymlinksInPath().standardizedFileURL
        let resolvedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let directoryPrefix = directoryURL.path.hasSuffix("/")
            ? directoryURL.path : directoryURL.path + "/"
        let directoryValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard directoryValues.isDirectory == true else {
            throw InteropCodecError.unreadablePackage(
                "the allowed HTML resource location is not a folder")
        }
        guard resolvedFileURL.path.hasPrefix(directoryPrefix) else {
            throw InteropCodecError.unreadablePackage(
                "the selected HTML file is outside the allowed folder")
        }
        let values = try resolvedFileURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true,
              values.contentType?.conforms(to: .html) == true else {
            throw InteropCodecError.unreadablePackage("the selected HTML item is not a regular file")
        }
        guard (values.fileSize ?? 0) <= limits.maximumPayloadBytes else {
            throw InteropCodecError.unreadablePackage(
                "the selected HTML file exceeds the \(limits.maximumPayloadBytes / 1_024 / 1_024) MB safety limit")
        }

        let accessStarted = (scopedDirectory ?? fileURL).startAccessingSecurityScopedResource()
        defer {
            if accessStarted { (scopedDirectory ?? fileURL).stopAccessingSecurityScopedResource() }
            tearDownActiveRender()
        }

        let loopbackServer: LocalHTMLHTTPServer?
        switch transport {
        case .customScheme:
            loopbackServer = nil
        case .loopbackHTTP:
            loopbackServer = try LocalHTMLHTTPServer(
                directory: directoryURL,
                maximumResourceBytes: limits.maximumPayloadBytes)
        }
        defer { loopbackServer?.stop() }
        let ruleList = try await localOnlyRuleList(
            allowedLoopbackOrigin: loopbackServer?.allowedResourceOrigin)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        var snapshots: [Data] = []
        snapshots.reserveCapacity(viewports.count)
        var totalPayloadBytes = 0
        var remainingNodes = limits.maximumNodes
        var limitMessages: [String] = []
        var resourcesByPath: [String: CodeBridgeResource] = [:]
        let sourceName = resolvedFileURL.deletingPathExtension().lastPathComponent
        let entryPath = String(resolvedFileURL.path.dropFirst(directoryPrefix.count))

        for (index, viewport) in viewports.enumerated() {
            guard remainingNodes > 0 else {
                limitMessages.append("The (limits.maximumNodes)-node import limit was reached; remaining viewports were omitted.")
                break
            }
            try context.report(.opening, completed: index, total: viewports.count,
                               detail: "Rendering \(viewport.name)")
            if context.cancellation.isCancelled || Task.isCancelled {
                throw InteropCodecError.cancelled
            }
            let capture = try await render(fileURL: resolvedFileURL,
                                           scopedDirectory: directoryURL,
                                           sourceName: sourceName,
                                           sourceLocation: entryPath,
                                           queryItems: queryItems,
                                           transport: transport,
                                           readiness: readiness,
                                           loopbackServer: loopbackServer,
                                           viewport: viewport, dataStore: dataStore,
                                           ruleList: ruleList,
                                           maximumNodes: remainingNodes,
                                           context: context)
            let data = capture.snapshotData
            for resource in capture.resources { resourcesByPath[resource.path] = resource }
            guard data.count <= limits.maximumPayloadBytes else {
                throw InteropCodecError.unreadablePackage(
                    "the \(viewport.name) browser snapshot exceeded the \(limits.maximumPayloadBytes / 1_024 / 1_024) MB safety limit")
            }
            guard totalPayloadBytes + data.count <= limits.maximumPayloadBytes else {
                limitMessages.append("The (limits.maximumPayloadBytes / 1_024 / 1_024) MB serialized-payload limit was reached; (viewport.name) and remaining viewports were omitted.")
                break
            }
            let snapshot: RenderedHTMLSnapshot
            do {
                snapshot = try JSONDecoder().decode(RenderedHTMLSnapshot.self, from: data)
            } catch {
                throw InteropCodecError.unreadablePackage(
                    "the (viewport.name) browser snapshot was invalid: (String(reflecting: error))")
            }
            let captured = snapshot.capturedNodeCount ?? elementCount(snapshot.root)
            remainingNodes = max(0, remainingNodes - captured)
            if snapshot.notes.contains(where: { $0.hasPrefix("Node limit reached") }) {
                limitMessages.append("The (limits.maximumNodes)-node import limit was reached while rendering (viewport.name); later DOM elements were omitted.")
            }
            totalPayloadBytes += data.count
            snapshots.append(data)
        }

        var result = try RenderedHTMLImporter().read(snapshotData: snapshots,
                                                     context: context)
        for message in Array(Set(limitMessages)).sorted() {
            result.report.add(.warning, .unsupported, category: "Limits",
                              message: message)
        }
        result.report.add(.information, .exact, category: "Sources",
                          message: "The selected HTML file and resources inside its folder were allowed. Remote subresources were blocked for this local-file import.",
                          location: directoryURL.path)
        let resources = boundedPreservedResources(
            Array(resourcesByPath.values),
            maximumBytes: limits.maximumPreservedSourceBytes)
        if !result.codeBridges.isEmpty {
            result.codeBridges[0].source.stableID =
                "local-folder:\(directoryURL.lastPathComponent)/\(entryPath)"
            result.codeBridges[0].source.entryPath = entryPath
            result.codeBridges[0].source.metadata["folderName"] = directoryURL.lastPathComponent
            result.codeBridges[0].resources = resources
            result.codeBridges[0].baseline?.sourceDigest = resources.first {
                $0.path == entryPath
            }?.sha256
            result.codeBridges[0].baseline?.metadata["resourceCount"] =
                String(resources.count)
            result.codeBridges[0].baseline?.metadata["preservedSourceBytes"] =
                String(resources.compactMap(\.preservedData).reduce(0) { $0 + $1.count })
        }
        let retainedCount = resources.filter { $0.preservedData != nil }.count
        result.report.add(.information, .exact, category: "Source provenance",
                          message: "Recorded \(resources.count) used local resources and retained \(retainedCount) bounded text source file\(retainedCount == 1 ? "" : "s") for future handoff.")
        return result
    }

    func cancel() {
        finishLoad(.failure(InteropCodecError.cancelled))
        activeWebView?.stopLoading()
    }

    private func render(fileURL: URL,
                        scopedDirectory: URL,
                        sourceName: String,
                        sourceLocation: String,
                        queryItems: [URLQueryItem],
                        transport: RenderedHTMLLocalTransport,
                        readiness: RenderedHTMLReadiness,
                        loopbackServer: LocalHTMLHTTPServer?,
                        viewport: RenderedHTMLViewport,
                        dataStore: WKWebsiteDataStore,
                        ruleList: WKContentRuleList,
                        maximumNodes: Int,
                        context: InteropContext) async throws -> RenderedCapture {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.suppressesIncrementalRendering = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(ruleList)

        let resourceProvider: LocalHTMLResourceProviding
        let documentURL: URL
        switch transport {
        case .customScheme:
            let handler = LocalHTMLSchemeHandler(
                directory: scopedDirectory,
                maximumResourceBytes: limits.maximumPayloadBytes)
            configuration.setURLSchemeHandler(handler,
                                              forURLScheme: LocalHTMLSchemeHandler.scheme)
            resourceProvider = handler
            documentURL = handler.url(for: sourceLocation, queryItems: queryItems)
        case .loopbackHTTP:
            guard let loopbackServer else {
                throw InteropCodecError.unreadablePackage(
                    "the isolated Storybook server was unavailable")
            }
            resourceProvider = loopbackServer
            documentURL = loopbackServer.url(for: sourceLocation, queryItems: queryItems)
        }

        let frame = CGRect(x: 0, y: 0,
                           width: max(1, viewport.width),
                           height: max(1, viewport.renderHeight))
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        activeWebView = webView
        expectedMainDocument = documentURL
        navigationNotes = []

        // WebKit does not complete layout reliably without a window. Keep this
        // one offscreen and never key/front; it exists only for the render pass.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)

        defer {
            loadMonitor?.cancel()
            loadMonitor = nil
            webView.stopLoading()
            webView.navigationDelegate = nil
            window.contentView = nil
            if activeWebView === webView { activeWebView = nil }
            expectedMainDocument = nil
        }

        try await load(webView, documentURL: documentURL, context: context)
        switch readiness {
        case .documentSettled:
            try await settle(context: context)
        case .storybookStory:
            try await waitForStorybookStory(in: webView, context: context)
        }
        if let animationNote = try await stabilizeAnimations(in: webView) {
            navigationNotes.append(animationNote)
        }
        try context.report(.decoding, completed: 0, total: 1,
                           detail: "Measuring \(viewport.name) DOM")

        let script = RenderedHTMLExtractionScript.source(
            sourceName: sourceName,
            // A relative package location is enough to bind the result and
            // avoids persisting a private absolute path in artboard Notes.
            sourceURL: sourceLocation,
            viewport: viewport,
            maximumNodes: maximumNodes)
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as Any) }
            }
        }
        if context.cancellation.isCancelled || Task.isCancelled {
            throw InteropCodecError.cancelled
        }
        guard let json = value as? String, var data = json.data(using: .utf8) else {
            throw InteropCodecError.unreadablePackage(
                "WebKit returned no rendered DOM for \(viewport.name)")
        }

        do {
            var snapshot = try JSONDecoder().decode(RenderedHTMLSnapshot.self, from: data)
            snapshot.notes.append(contentsOf: navigationNotes)
            if case .storybookStory = readiness {
                snapshot.runtimeMetadata = try await storybookRuntimeMetadata(in: webView)
            }
            snapshot.root = preservingOriginalAssets(in: snapshot.root,
                                                      provider: resourceProvider)
            guard snapshot.documentHeight > 1 else {
                throw InteropCodecError.unreadablePackage(
                    "the rendered page was empty or had not finished laying out")
            }
            data = try JSONEncoder().encode(snapshot)
        } catch {
            throw InteropCodecError.unreadablePackage(
                "WebKit returned an invalid rendered snapshot for \(viewport.name): \(String(reflecting: error))")
        }
        return RenderedCapture(snapshotData: data,
                               resources: resourceProvider.resourceReceipts())
    }

    private func boundedPreservedResources(_ resources: [CodeBridgeResource],
                                           maximumBytes: Int) -> [CodeBridgeResource] {
        var remaining = max(0, maximumBytes)
        return resources.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { resource in
                var copy = resource
                if let data = copy.preservedData {
                    if data.count <= remaining {
                        remaining -= data.count
                        copy.metadata["preservation"] = "inline"
                    } else {
                        copy.preservedData = nil
                        copy.metadata["preservation"] = "digest-only-cap-reached"
                    }
                }
                return copy
            }
    }

    /// Canvas pixels remain the correct fallback for raster sources, cropping,
    /// and unsupported vector content. A trusted local SVG is different: keep
    /// its original markup so the native SVG importer can reconstruct paths,
    /// gradients, and effects instead of receiving the canvas PNG.
    private func preservingOriginalAssets(in element: RenderedHTMLElement,
                                          provider: LocalHTMLResourceProviding)
        -> RenderedHTMLElement {
        var copy = element
        if var asset = copy.renderedAsset {
            var baseURL: URL?
            if let source = asset.sourceURL,
               let url = URL(string: source),
               let resource = provider.resource(for: url),
               resource.mimeType == "image/svg+xml" || url.pathExtension.lowercased() == "svg" {
                asset.mimeType = "image/svg+xml"
                asset.data = resource.data
                baseURL = url
            }
            if asset.mimeType.lowercased() == "image/svg+xml" {
                asset.data = inliningLocalSVGUses(
                    in: asset.data, relativeTo: baseURL, provider: provider)
            }
            copy.renderedAsset = asset
        }
        if copy.renderedAsset == nil,
           copy.attributes["data-exp-mask-image"] == "unsupported",
           let source = copy.attributes["data-exp-mask-source"],
           let url = URL(string: source),
           let resource = provider.resource(for: url),
           resource.mimeType == "image/svg+xml"
                || url.pathExtension.lowercased() == "svg",
           let data = editableMaskSVG(
                resource.data, paint: maskPaintColor(copy.style),
                size: copy.rect.size) {
            copy.renderedAsset = RenderedHTMLAsset(
                mimeType: "image/svg+xml", data: data,
                naturalWidth: max(1, copy.rect.width),
                naturalHeight: max(1, copy.rect.height), sourceURL: source)
            copy.attributes["data-exp-mask-image"] = "editable-local-svg"
        }
        if let source = singleBackgroundURL(copy.style.backgroundImage),
           let url = URL(string: source),
           let resource = provider.resource(for: url),
           resource.mimeType.hasPrefix("image/") || NSImage(data: resource.data) != nil {
            let size = NSImage(data: resource.data)?.size ?? .zero
            copy.backgroundAsset = RenderedHTMLAsset(
                mimeType: resource.mimeType, data: resource.data,
                naturalWidth: max(1, size.width), naturalHeight: max(1, size.height),
                sourceURL: source)
        }
        copy.children = copy.children.map {
            preservingOriginalAssets(in: $0, provider: provider)
        }
        return copy
    }

    /// A same-folder SVG used as a CSS mask is already inside the user's
    /// selected static package. Preserve its silhouette as editable vector
    /// geometry and recolor painted paths to the mask element's resolved fill.
    /// Scripts, foreignObject, event handlers, and external references are
    /// removed before the existing SVG importer sees the markup.
    private func editableMaskSVG(_ data: Data, paint: String,
                                 size: CGSize) -> Data? {
        guard data.count <= 256 * 1_024,
              let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
              let root = document.rootElement(),
              root.localName == "svg" else { return nil }

        let disallowed = (try? root.nodes(
            forXPath: ".//*[local-name()='script' or local-name()='foreignObject']")) ?? []
        for node in disallowed { node.detach() }

        let elements = [root] + ((try? root.nodes(forXPath: ".//*"))?
            .compactMap { $0 as? XMLElement } ?? [])
        for element in elements {
            for attribute in element.attributes ?? [] {
                let name = attribute.name?.lowercased() ?? ""
                if name.hasPrefix("on") {
                    element.removeAttribute(forName: attribute.name ?? "")
                } else if name == "href" || name == "xlink:href" {
                    let value = attribute.stringValue ?? ""
                    if !value.hasPrefix("#") && !value.lowercased().hasPrefix("data:") {
                        element.removeAttribute(forName: attribute.name ?? "")
                    }
                }
            }
            if let fill = element.attribute(forName: "fill"),
               fill.stringValue?.lowercased() != "none" {
                fill.stringValue = paint
            }
            if let stroke = element.attribute(forName: "stroke"),
               stroke.stringValue?.lowercased() != "none" {
                stroke.stringValue = paint
            }
        }
        func setRootAttribute(_ name: String, _ value: String) {
            if let attribute = root.attribute(forName: name) {
                attribute.stringValue = value
            } else {
                root.addAttribute(XMLNode.attribute(withName: name,
                                                    stringValue: value) as! XMLNode)
            }
        }
        setRootAttribute("width", "\(max(1, size.width))")
        setRootAttribute("height", "\(max(1, size.height))")
        setRootAttribute("fill", paint)
        return document.xmlData(options: [.nodeCompactEmptyElement])
    }

    private func maskPaintColor(_ style: RenderedHTMLComputedStyle) -> String {
        let background = style.backgroundColor
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if background == "transparent" || background == "rgba(0, 0, 0, 0)"
            || background == "rgba(0,0,0,0)" {
            return style.color
        }
        return style.backgroundColor
    }

    /// Inline same-folder SVG sprite symbols referenced by `<use>`. Browser
    /// layout resolves these correctly, but the native SVG importer intentionally
    /// performs no file/network reads. Namespacing copied IDs keeps gradients and
    /// filters editable without colliding with definitions already in the SVG.
    private func inliningLocalSVGUses(in data: Data, relativeTo baseURL: URL?,
                                     provider: LocalHTMLResourceProviding) -> Data {
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
              let root = document.rootElement(),
              let useNodes = try? root.nodes(forXPath: ".//*[local-name()='use']")
                .compactMap({ $0 as? XMLElement }) else { return data }

        let existingDefs = (try? root.nodes(forXPath: "./*[local-name()='defs']"))?
            .compactMap { $0 as? XMLElement }.first
        var definitions = existingDefs
        var importedTargets: [String: String] = [:]

        for use in useNodes {
            let hrefAttribute = use.attribute(forName: "href")
                ?? use.attribute(forName: "xlink:href")
            guard let hrefAttribute,
                  let raw = hrefAttribute.stringValue,
                  !raw.hasPrefix("#"), !raw.lowercased().hasPrefix("data:"),
                  let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                  let fragment = resolved.fragment, !fragment.isEmpty else { continue }

            let cacheKey = resolved.absoluteString
            if let importedID = importedTargets[cacheKey] {
                hrefAttribute.stringValue = "#\(importedID)"
                continue
            }
            guard let resource = provider.resource(for: resolved),
                  resource.mimeType == "image/svg+xml"
                    || resolved.pathExtension.lowercased() == "svg",
                  let external = try? XMLDocument(
                    data: resource.data, options: [.nodePreserveAll]),
                  let externalRoot = external.rootElement(),
                  let candidates = try? externalRoot.nodes(forXPath: "//*[@id]")
                    .compactMap({ $0 as? XMLElement }),
                  let source = candidates.first(where: {
                    $0.attribute(forName: "id")?.stringValue == fragment
                  }),
                  let imported = source.copy() as? XMLElement else { continue }

            let digest = SHA256.hash(data: Data(resolved.absoluteString.utf8))
                .prefix(5).map { String(format: "%02x", $0) }.joined()
            let prefix = "exp_\(digest)_"
            let importedElements = [imported]
                + ((try? imported.nodes(forXPath: ".//*"))?
                    .compactMap { $0 as? XMLElement } ?? [])
            var rewrittenIDs: [String: String] = [:]
            for element in importedElements {
                if let oldID = element.attribute(forName: "id")?.stringValue,
                   !oldID.isEmpty {
                    rewrittenIDs[oldID] = prefix + oldID
                }
            }
            for element in importedElements {
                if let id = element.attribute(forName: "id"),
                   let oldID = id.stringValue,
                   let newID = rewrittenIDs[oldID] {
                    id.stringValue = newID
                }
                for attribute in element.attributes ?? [] {
                    guard var value = attribute.stringValue else { continue }
                    for (oldID, newID) in rewrittenIDs {
                        value = value.replacingOccurrences(
                            of: "url(#\(oldID))", with: "url(#\(newID))")
                        if value == "#\(oldID)" { value = "#\(newID)" }
                    }
                    attribute.stringValue = value
                }
            }
            guard let importedID = rewrittenIDs[fragment] else { continue }
            if root.attribute(forName: "viewBox") == nil,
               let viewBox = imported.attribute(forName: "viewBox")?.stringValue {
                root.addAttribute(XMLNode.attribute(withName: "viewBox",
                                                    stringValue: viewBox) as! XMLNode)
            }
            if definitions == nil {
                let created = XMLElement(name: "defs")
                root.insertChild(created, at: 0)
                definitions = created
            }
            definitions?.addChild(imported)
            hrefAttribute.stringValue = "#\(importedID)"
            importedTargets[cacheKey] = importedID
        }
        return document.xmlData(options: [.nodeCompactEmptyElement])
    }

    private func singleBackgroundURL(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("url("), value.hasSuffix(")") else { return nil }
        let body = String(value.dropFirst(4).dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        // A comma outside a data URI means multiple CSS layers, which the
        // bounded mapper reports instead of partially embedding.
        guard body.lowercased().hasPrefix("data:") || !body.contains(",") else { return nil }
        return body
    }

    private func elementCount(_ element: RenderedHTMLElement) -> Int {
        1 + element.children.reduce(0) { $0 + elementCount($1) }
    }

    private func load(_ webView: WKWebView, documentURL: URL,
                      context: InteropContext) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            let deadline = Date().addingTimeInterval(limits.renderDeadline)
            loadMonitor = Task { @MainActor [weak self] in
                while let self, self.loadContinuation != nil {
                    if context.cancellation.isCancelled || Task.isCancelled {
                        self.activeWebView?.stopLoading()
                        self.finishLoad(.failure(InteropCodecError.cancelled))
                        return
                    }
                    if Date() >= deadline {
                        self.activeWebView?.stopLoading()
                        self.finishLoad(.failure(InteropCodecError.unreadablePackage(
                            "the browser did not finish rendering within \(Int(self.limits.renderDeadline)) seconds")))
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            webView.load(URLRequest(url: documentURL))
        }
    }

    private func settle(context: InteropContext) async throws {
        var remaining = limits.settleMilliseconds
        while remaining > 0 {
            if context.cancellation.isCancelled || Task.isCancelled {
                throw InteropCodecError.cancelled
            }
            let interval = min(remaining, 50)
            try await Task.sleep(for: .milliseconds(interval))
            remaining -= interval
        }
    }

    /// `didFinish` only means iframe.html loaded. Storybook then imports its
    /// preview runtime and selected story asynchronously. Do not snapshot its
    /// intentionally hidden preparing shell as an empty one-pixel document.
    private func waitForStorybookStory(in webView: WKWebView,
                                       context: InteropContext) async throws {
        let deadline = Date().addingTimeInterval(limits.renderDeadline)
        var lastDetail = "Storybook did not expose a render state"
        var stableSignature: String?
        var stableSince: Date?
        while Date() < deadline {
            if context.cancellation.isCancelled || Task.isCancelled {
                throw InteropCodecError.cancelled
            }
            let script = #"""
            (() => {
              const body = document.body;
              const root = document.getElementById("storybook-root");
              const shown = !!body && body.classList.contains("sb-show-main");
              const failed = !!body && body.classList.contains("sb-show-errordisplay");
              const noPreview = !!body && body.classList.contains("sb-show-nopreview");
              const error = [document.getElementById("error-message")?.textContent,
                document.getElementById("error-stack")?.textContent]
                .filter(Boolean).join(" ").trim();
              const rootRect = root ? root.getBoundingClientRect() : null;
              let contentRect = rootRect;
              if (root && root.childElementCount > 0
                  && (!rootRect || rootRect.width <= 0 || rootRect.height <= 0)) {
                let left = [], top = [], right = [], bottom = [];
                const descendants = root.querySelectorAll("*");
                for (let index = 0; index < descendants.length && index < 5000; index++) {
                  const element = descendants[index];
                  const style = getComputedStyle(element);
                  if (style.display === "none" || style.visibility === "hidden"
                      || style.visibility === "collapse") continue;
                  const rect = element.getBoundingClientRect();
                  if (rect.width <= 0 || rect.height <= 0) continue;
                  left.push(rect.left); top.push(rect.top);
                  right.push(rect.right); bottom.push(rect.bottom);
                }
                if (left.length > 0) {
                  const minLeft = Math.min(...left), minTop = Math.min(...top);
                  contentRect = {left: minLeft, top: minTop,
                    width: Math.max(...right) - minLeft,
                    height: Math.max(...bottom) - minTop};
                }
              }
              const populated = !!root && root.childElementCount > 0
                && !!contentRect && contentRect.width > 0 && contentRect.height > 0;
              const preview = window.__STORYBOOK_PREVIEW__;
              const selectedID = new URLSearchParams(location.search).get("id");
              const currentRender = preview?.currentRender
                || preview?.storyRenders?.find(render => render.id === selectedID)
                || preview?.storyRenders?.[preview.storyRenders.length - 1];
              const phase = currentRender?.phase || "";
              const runtimeReady = !preview || ["completed", "finished"].includes(phase);
              const runtimeFailed = ["aborted", "errored", "error"].includes(phase);
              const bodyTextLength = (body?.innerText || "").length;
              const dialogCount = document.querySelectorAll('[role="dialog"], dialog').length;
              return {state: failed ? "error" : (noPreview ? "no-preview"
                : (runtimeFailed ? "runtime-error"
                : (shown && populated && runtimeReady ? "ready" : "waiting"))),
                error, bodyClass: body?.className || "",
                phase,
                bodyChildCount: body?.childElementCount || 0,
                bodyTextLength,
                dialogCount,
                childCount: root?.childElementCount || 0,
                rootWidth: contentRect?.width || 0,
                rootHeight: contentRect?.height || 0};
            })();
            """#
            let value: Any = try await withCheckedThrowingContinuation { continuation in
                webView.evaluateJavaScript(script) { value, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: value as Any) }
                }
            }
            if let status = value as? [String: Any] {
                let state = status["state"] as? String ?? "waiting"
                let error = status["error"] as? String ?? ""
                let bodyClass = status["bodyClass"] as? String ?? ""
                let phase = status["phase"] as? String ?? ""
                let bodyChildCount = (status["bodyChildCount"] as? NSNumber)?.intValue ?? 0
                let bodyTextLength = (status["bodyTextLength"] as? NSNumber)?.intValue ?? 0
                let dialogCount = (status["dialogCount"] as? NSNumber)?.intValue ?? 0
                let childCount = (status["childCount"] as? NSNumber)?.intValue ?? 0
                let width = (status["rootWidth"] as? NSNumber)?.doubleValue ?? 0
                let height = (status["rootHeight"] as? NSNumber)?.doubleValue ?? 0
                lastDetail = "body class \(bodyClass.isEmpty ? "(none)" : bodyClass); "
                    + "story root \(childCount) child\(childCount == 1 ? "" : "ren"), "
                    + "\(Int(width)) × \(Int(height)) px"
                    + (phase.isEmpty ? "" : "; runtime phase \(phase)")
                    + "; \(dialogCount) dialog\(dialogCount == 1 ? "" : "s")"
                if state == "ready" {
                    // Storybook 7 can briefly report `completed` after mounting
                    // and then enter `playing`; Storybook 10 settles at `finished`.
                    // Recheck the runtime and the whole body (portals live
                    // outside #storybook-root) until both remain stable.
                    let signature = [bodyClass, phase, String(bodyChildCount),
                                     String(bodyTextLength), String(dialogCount),
                                     String(childCount), String(Int(width)),
                                     String(Int(height))].joined(separator: "|")
                    if signature != stableSignature {
                        stableSignature = signature
                        stableSince = Date()
                    } else if let stableSince,
                              Date().timeIntervalSince(stableSince)
                                >= Double(limits.settleMilliseconds) / 1_000 {
                        return
                    }
                } else {
                    stableSignature = nil
                    stableSince = nil
                }
                if state == "error" || state == "runtime-error" || state == "no-preview" {
                    throw InteropCodecError.unreadablePackage(error.isEmpty
                        ? "Storybook reported \(state == "no-preview" ? "no preview" : "a render error") for the selected story"
                        : "Storybook could not render the selected story: \(error)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw InteropCodecError.unreadablePackage(
            "Storybook did not finish rendering the selected story within \(Int(limits.renderDeadline)) seconds (\(lastDetail))")
    }

    /// Offscreen WebKit may throttle CSS animations at their first keyframe.
    /// That is disastrous for common entrance effects whose `from` state is
    /// opacity:0. A design import needs the stable rendered destination, so
    /// advance finite animations to their final filled state before measuring.
    /// Infinite animations have no final state; pause those at the browser's
    /// current sample and disclose the approximation in the Import Report.
    private func stabilizeAnimations(in webView: WKWebView) async throws -> String? {
        let script = #"""
        (() => {
          let finite = 0, infinite = 0, failed = 0;
          for (const animation of document.getAnimations()) {
            try {
              const timing = animation.effect && animation.effect.getComputedTiming
                ? animation.effect.getComputedTiming() : null;
              const end = timing ? Number(timing.endTime) : NaN;
              if (Number.isFinite(end)) {
                animation.currentTime = Math.max(0, end);
                animation.pause();
                finite += 1;
              } else {
                animation.pause();
                infinite += 1;
              }
            } catch (_) { failed += 1; }
          }
          return {finite, infinite, failed};
        })();
        """#
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as Any) }
            }
        }
        guard let counts = value as? [String: Any] else { return nil }
        let finite = (counts["finite"] as? NSNumber)?.intValue ?? 0
        let infinite = (counts["infinite"] as? NSNumber)?.intValue ?? 0
        let failed = (counts["failed"] as? NSNumber)?.intValue ?? 0
        guard finite + infinite + failed > 0 else { return nil }
        var note = "Animation sampling: advanced \(finite) finite animation\(finite == 1 ? "" : "s") to the final state"
        if infinite > 0 {
            note += "; paused \(infinite) infinite animation\(infinite == 1 ? "" : "s") at the current browser sample"
        }
        if failed > 0 {
            note += "; \(failed) animation\(failed == 1 ? "" : "s") could not be stabilized"
        }
        return note + "."
    }

    /// Storybook's normalized story is the authoritative runtime source for
    /// initial args. Retain only a bounded JSON-safe value: functions, DOM
    /// objects, cycles, and deep/unbounded structures are deliberately omitted.
    private func storybookRuntimeMetadata(in webView: WKWebView) async throws
        -> [String: String]? {
        let script = #"""
        (() => {
          const render = window.__STORYBOOK_PREVIEW__?.currentRender;
          const story = render?.story;
          if (!story) return null;
          const seen = new WeakSet();
          let entries = 0;
          const safe = (value, depth = 0) => {
            if (value === null || typeof value === "boolean"
                || typeof value === "string") return value;
            if (typeof value === "number") return Number.isFinite(value) ? value : null;
            if (typeof value !== "object" || depth >= 6 || entries >= 500) return undefined;
            if (seen.has(value)) return undefined;
            seen.add(value);
            if (Array.isArray(value)) return value.slice(0, 100)
              .map(item => safe(item, depth + 1)).filter(item => item !== undefined);
            const result = {};
            for (const [key, item] of Object.entries(value).slice(0, 100)) {
              entries += 1;
              const normalized = safe(item, depth + 1);
              if (normalized !== undefined) result[key] = normalized;
            }
            return result;
          };
          const args = JSON.stringify(safe(story.initialArgs || {}));
          if (!args || args.length > 65536) return {storyID: story.id || render.id || ""};
          return {storyID: story.id || render.id || "", initialArgsJSON: args};
        })();
        """#
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as Any) }
            }
        }
        guard let raw = value as? [String: Any] else { return nil }
        let metadata = raw.compactMapValues { $0 as? String }
        return metadata.isEmpty ? nil : metadata
    }

    private func localOnlyRuleList(allowedLoopbackOrigin: String? = nil) async throws
        -> WKContentRuleList {
        let types = ["document", "image", "style-sheet", "script", "font",
                     "svg-document", "media", "popup", "ping", "fetch",
                     "websocket", "other"]
        var rules: [[String: Any]] = ["^https?://", "^file://"].map { filter in
            ["trigger": ["url-filter": filter, "resource-type": types],
             "action": ["type": "block"]]
        }
        if let allowedLoopbackOrigin {
            let escaped = NSRegularExpression.escapedPattern(for: allowedLoopbackOrigin)
            rules.append([
                "trigger": ["url-filter": "^\(escaped)/"],
                "action": ["type": "ignore-previous-rules"]
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        let source = String(decoding: data, as: UTF8.self)
        guard let store = WKContentRuleListStore.default() else {
            throw InteropCodecError.unreadablePackage(
                "the browser safety-rule store is unavailable")
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: "exp-rendered-html-local-v1",
                encodedContentRuleList: source
            ) { list, error in
                if let list { continuation.resume(returning: list) }
                else {
                    continuation.resume(throwing: error
                        ?? InteropCodecError.unreadablePackage(
                            "the local-only browser safety rules could not be created"))
                }
            }
        }
    }

    private func finishLoad(_ result: Result<Void, Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        loadMonitor?.cancel()
        loadMonitor = nil
        continuation.resume(with: result)
    }

    private func tearDownActiveRender() {
        loadMonitor?.cancel()
        loadMonitor = nil
        activeWebView?.stopLoading()
        activeWebView?.navigationDelegate = nil
        activeWebView = nil
        expectedMainDocument = nil
        if loadContinuation != nil {
            finishLoad(.failure(InteropCodecError.cancelled))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        finishLoad(.failure(InteropCodecError.unreadablePackage(
            "WebKit could not render the HTML file: \(error.localizedDescription)")))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finishLoad(.failure(InteropCodecError.unreadablePackage(
            "WebKit could not open the HTML file: \(error.localizedDescription)")))
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let target = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let expectedMainDocument,
           target != expectedMainDocument {
            navigationNotes.append("Blocked navigation away to \(target.absoluteString)")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

private struct LocalHTMLResource {
    var data: Data
    var mimeType: String
    var isText: Bool
}

private protocol LocalHTMLResourceProviding: AnyObject {
    func resource(for requestURL: URL) -> LocalHTMLResource?
    func resourceReceipts() -> [CodeBridgeResource]
}

/// One bounded, traversal-safe view of the folder selected by the designer.
/// Both transports use this catalog so Storybook's HTTP compatibility does not
/// widen EXP's resource or provenance boundary.
private final class LocalHTMLResourceCatalog: @unchecked Sendable {
    private let directory: URL
    private let directoryPrefix: String
    private let maximumResourceBytes: Int
    private let receiptLock = NSLock()
    private var receiptsByPath: [String: CodeBridgeResource] = [:]

    init(directory: URL, maximumResourceBytes: Int) {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        self.directoryPrefix = self.directory.path.hasSuffix("/")
            ? self.directory.path : self.directory.path + "/"
        self.maximumResourceBytes = maximumResourceBytes
    }

    func resource(atPercentEncodedPath encodedPath: String) -> LocalHTMLResource? {
        let relative = encodedPath.removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let target = directory.appendingPathComponent(relative)
            .resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(directoryPrefix),
              (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let values = try? target.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= maximumResourceBytes,
              let data = try? Data(contentsOf: target, options: .mappedIfSafe),
              data.count <= maximumResourceBytes else { return nil }
        let type = UTType(filenameExtension: target.pathExtension)
        let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
        let isText = type?.conforms(to: .text) == true
            || ["html", "htm", "css", "js", "mjs", "cjs", "json", "svg", "xml",
                "md", "txt", "map"].contains(target.pathExtension.lowercased())
        let normalizedPath = String(target.path.dropFirst(directoryPrefix.count))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let receipt = CodeBridgeResource(
            path: normalizedPath,
            role: resourceRole(for: target.pathExtension, mimeType: mimeType),
            mimeType: mimeType, byteCount: data.count, sha256: digest,
            preservedData: isText ? data : nil,
            metadata: ["preservation": isText ? "inline-candidate" : "digest-only"])
        receiptLock.lock()
        receiptsByPath[normalizedPath] = receipt
        receiptLock.unlock()
        return LocalHTMLResource(data: data, mimeType: mimeType, isText: isText)
    }

    func resourceReceipts() -> [CodeBridgeResource] {
        receiptLock.lock()
        defer { receiptLock.unlock() }
        return Array(receiptsByPath.values)
    }

    private func resourceRole(for pathExtension: String, mimeType: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "document"
        case "css", "scss", "sass", "less": return "stylesheet"
        case "js", "mjs", "cjs", "ts", "tsx", "jsx": return "script"
        case "json", "map": return "configuration"
        case "woff", "woff2", "ttf", "otf": return "font"
        case "svg", "png", "jpg", "jpeg", "gif", "webp", "avif": return "image"
        default:
            if mimeType.hasPrefix("image/") { return "image" }
            if mimeType.hasPrefix("font/") { return "font" }
            return "resource"
        }
    }
}

/// Serves exactly one selected directory through one same-origin custom scheme.
/// Relative HTML/CSS/image/font URLs stay inspectable by CSSOM; path traversal,
/// absolute file URLs, and network URLs never reach this handler.
private final class LocalHTMLSchemeHandler: NSObject, WKURLSchemeHandler,
    LocalHTMLResourceProviding, @unchecked Sendable {
    static let scheme = "exp-local"
    private let catalog: LocalHTMLResourceCatalog

    init(directory: URL, maximumResourceBytes: Int) {
        self.catalog = LocalHTMLResourceCatalog(
            directory: directory, maximumResourceBytes: maximumResourceBytes)
    }

    func url(for relativePath: String,
             queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "import"
        components.path = "/" + relativePath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let resource = resource(for: requestURL) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "RenderedHTMLLocalScheme", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The local resource URL was invalid."]))
            return
        }
        let response = URLResponse(url: requestURL, mimeType: resource.mimeType,
                                   expectedContentLength: resource.data.count,
                                   textEncodingName: resource.isText ? "utf-8" : nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(resource.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    func resourceReceipts() -> [CodeBridgeResource] { catalog.resourceReceipts() }

    func resource(for requestURL: URL) -> LocalHTMLResource? {
        guard requestURL.scheme == Self.scheme, requestURL.host == "import" else { return nil }
        return catalog.resource(atPercentEncodedPath: requestURL.path)
    }
}

/// Ephemeral HTTP compatibility seam for production Storybook builds. It binds
/// only to IPv4 loopback, chooses an OS-assigned port, accepts GET/HEAD, serves
/// only catalog-approved files, and is stopped as soon as the import completes.
private final class LocalHTMLHTTPServer: LocalHTMLResourceProviding,
    @unchecked Sendable {
    private let catalog: LocalHTMLResourceCatalog
    private let queue = DispatchQueue(
        label: "org.thisroad.exp.storybook-loopback", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(
        label: "org.thisroad.exp.storybook-loopback.connections",
        qos: .userInitiated, attributes: .concurrent)
    private let stateLock = NSLock()
    private var source: DispatchSourceRead?
    private var socketDescriptor: Int32 = -1
    private let routePrefix = "/_exp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let port: UInt16

    var origin: String { "http://127.0.0.1:\(port)" }
    // WebKit's local-only rule list admits this ephemeral origin; the server
    // still enforces the random route token plus the narrow root-file alias.
    var allowedResourceOrigin: String { origin }

    init(directory: URL, maximumResourceBytes: Int) throws {
        catalog = LocalHTMLResourceCatalog(
            directory: directory, maximumResourceBytes: maximumResourceBytes)
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else {
            throw Self.serverError("could not create the isolated loopback socket")
        }
        var shouldClose = true
        defer { if shouldClose { Darwin.close(descriptor) } }

        var reuse: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse,
                         socklen_t(MemoryLayout.size(ofValue: reuse))) == 0 else {
            throw Self.serverError("could not configure the isolated loopback socket")
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(descriptor, 32) == 0 else {
            throw Self.serverError("could not bind the isolated Storybook server to loopback")
        }
        var bound = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw Self.serverError("could not resolve the isolated Storybook port")
        }
        port = UInt16(bigEndian: bound.sin_port)

        let currentFlags = fcntl(descriptor, F_GETFL, 0)
        guard currentFlags >= 0,
              fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            throw Self.serverError("could not start the isolated Storybook server")
        }
        socketDescriptor = descriptor
        let readSource = DispatchSource.makeReadSource(
            fileDescriptor: descriptor, queue: queue)
        source = readSource
        readSource.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
        readSource.setCancelHandler { Darwin.close(descriptor) }
        shouldClose = false
        readSource.resume()
    }

    deinit { stop() }

    func stop() {
        stateLock.lock()
        let current = source
        source = nil
        socketDescriptor = -1
        stateLock.unlock()
        current?.cancel()
    }

    func url(for relativePath: String,
             queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: origin)!
        components.path = routePrefix + "/" + relativePath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    func resource(for requestURL: URL) -> LocalHTMLResource? {
        guard requestURL.scheme == "http", requestURL.host == "127.0.0.1",
              requestURL.port == Int(port) else { return nil }
        let resourcePath: String
        if requestURL.path.hasPrefix(routePrefix + "/") {
            resourcePath = String(requestURL.path.dropFirst(routePrefix.count))
        } else {
            // Published static builds can retain a deploy-root reference such as
            // `/dds-icons.svg` or `/icons/close.svg`. Permit only an existing
            // path inside the user-selected catalog. The catalog resolves and
            // standardizes the target before enforcing the selected-directory
            // prefix, so traversal and files outside that package remain blocked.
            let relative = requestURL.path.drop(while: { $0 == "/" })
            guard !relative.isEmpty, !relative.hasPrefix("_exp_") else { return nil }
            resourcePath = "/" + relative
        }
        return catalog.resource(atPercentEncodedPath: resourcePath)
    }

    func resourceReceipts() -> [CodeBridgeResource] { catalog.resourceReceipts() }

    private func acceptAvailableConnections() {
        while true {
            stateLock.lock()
            let descriptor = socketDescriptor
            stateLock.unlock()
            guard descriptor >= 0 else { return }
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            connectionQueue.async { [weak self] in self?.serve(client: client) }
        }
    }

    private func serve(client: Int32) {
        defer { Darwin.close(client) }
        let currentFlags = fcntl(client, F_GETFL, 0)
        if currentFlags >= 0 {
            _ = fcntl(client, F_SETFL, currentFlags & ~O_NONBLOCK)
        }
        var noSignal: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                       socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                       socklen_t(MemoryLayout.size(ofValue: timeout)))

        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while request.count < 32_768 {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count <= 0 { break }
            request.append(contentsOf: buffer.prefix(Int(count)))
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        guard let header = String(data: request, encoding: .utf8),
              let requestLine = header.components(separatedBy: "\r\n").first else {
            sendStatus(400, reason: "Bad Request", client: client)
            return
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD",
              let requestURL = URL(string: origin + parts[1]),
              let resource = resource(for: requestURL) else {
            sendStatus(404, reason: "Not Found", client: client)
            return
        }
        let headers = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: \(resource.mimeType)\r\n"
            + "Content-Length: \(resource.data.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Connection: close\r\n\r\n"
        send(Data(headers.utf8), client: client)
        if parts[0] == "GET" { send(resource.data, client: client) }
    }

    private func sendStatus(_ status: Int, reason: String, client: Int32) {
        let body = Data("\(status) \(reason)".utf8)
        let headers = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        send(Data(headers.utf8), client: client)
        send(body, client: client)
    }

    private func send(_ data: Data, client: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard var address = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.send(client, address, remaining, 0)
                guard written > 0 else { return }
                remaining -= written
                address = address.advanced(by: written)
            }
        }
    }

    private static func serverError(_ message: String) -> InteropCodecError {
        .unreadablePackage("\(message): \(String(cString: strerror(errno)))")
    }
}

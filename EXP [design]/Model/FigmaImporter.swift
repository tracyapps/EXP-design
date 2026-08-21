//
//  FigmaImporter.swift
//  EXP [design]
//
//  Sanctioned Figma REST importer. Authentication and networking stay separate
//  from the defensive JSON mapper so real API responses and checked-in fixtures
//  exercise exactly the same conversion path.
//

import Foundation
import CoreGraphics

nonisolated struct FigmaRESTImporter {
    let format: InteropFormat = .figma
    let capabilities: Set<InteropCapability> = [.read]

    struct Request: Sendable {
        var fileKey: String
        var token: String
    }

    /// Accept either the opaque key itself or normal design/proto/FigJam URLs.
    static func fileKey(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("/") {
            return trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
                ? trimmed : nil
        }
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host == "figma.com" || host.hasSuffix(".figma.com") else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let marker = parts.firstIndex(where: {
            ["design", "file", "proto", "board"].contains($0.lowercased())
        }), parts.indices.contains(marker + 1) else { return nil }
        let key = parts[marker + 1]
        return key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
            ? key : nil
    }

    func read(_ request: Request,
              context: InteropContext = InteropContext()) async throws -> InteropImportResult {
        let key = request.fileKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = request.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw InteropCodecError.unreadablePackage("the Figma file key is empty")
        }
        guard !token.isEmpty else {
            throw InteropCodecError.unreadablePackage("a Figma personal access token is required")
        }

        try context.report(.opening, completed: 0, total: 1, detail: "Connecting to Figma")
        let fileURL = try endpoint("files/\(key)", query: [URLQueryItem(name: "geometry", value: "paths")])
        let fileData = try await fetch(fileURL, token: token, context: context,
                                       maximumBytes: 512 * 1_024 * 1_024)
        try context.report(.decoding, completed: 1, total: 1, detail: "Reading file JSON")
        guard let root = try JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
            throw InteropCodecError.unreadablePackage("Figma returned invalid file JSON")
        }

        let refs = Self.imageReferences(in: root)
        var imageData: [String: Data] = [:]
        if !refs.isEmpty {
            try context.report(.opening, completed: 0, total: refs.count,
                               detail: "Requesting \(refs.count) image fill\(refs.count == 1 ? "" : "s")")
            if let catalogURL = try? endpoint("files/\(key)/images"),
               let catalogData = try? await fetch(catalogURL, token: token, context: context,
                                                  maximumBytes: 32 * 1_024 * 1_024),
               let catalog = try? JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
               let urls = catalog["images"] as? [String: Any] {
                let ordered = refs.sorted()
                for (index, ref) in ordered.enumerated() {
                    try context.report(.opening, completed: index, total: ordered.count,
                                       detail: "Downloading image \(index + 1) of \(ordered.count)")
                    guard let raw = urls[ref] as? String, let url = URL(string: raw) else { continue }
                    if let data = try? await fetch(url, token: token, context: context,
                                                  maximumBytes: 128 * 1_024 * 1_024) {
                        imageData[ref] = data
                    }
                }
            }
        }

        try context.report(.mapping, completed: 0, total: 1, detail: "Mapping editable pages")
        let result = try FigmaFileMapper(root: root, imageData: imageData,
                                         requestedImageRefs: refs).map(context: context)
        try context.report(.finishing, completed: 1, total: 1, detail: result.report.summary)
        return result
    }

    /// Fixture entry point: no credentials/network, same production mapper.
    static func readFileData(_ data: Data, sourceName: String = "Figma fixture",
                             imageData: [String: Data] = [:],
                             context: InteropContext = InteropContext()) throws -> InteropImportResult {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InteropCodecError.unreadablePackage("the Figma fixture is not valid JSON")
        }
        if root["name"] == nil { root["name"] = sourceName }
        return try FigmaFileMapper(root: root, imageData: imageData,
                                   requestedImageRefs: imageReferences(in: root)).map(context: context)
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.figma.com"
        components.path = "/v1/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw InteropCodecError.unreadablePackage("the Figma API URL could not be created")
        }
        return url
    }

    private func fetch(_ url: URL, token: String, context: InteropContext,
                       maximumBytes: Int) async throws -> Data {
        if context.cancellation.isCancelled { throw InteropCodecError.cancelled }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        // Signed image-fill URLs point at Figma's CDN/storage provider. Never
        // forward the personal token beyond the official API origin.
        if url.host?.lowercased() == "api.figma.com" {
            request.setValue(token, forHTTPHeaderField: "X-Figma-Token")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if context.cancellation.isCancelled || Task.isCancelled {
                throw InteropCodecError.cancelled
            }
            throw InteropCodecError.unreadablePackage("Figma request failed: \(error.localizedDescription)")
        }
        if context.cancellation.isCancelled { throw InteropCodecError.cancelled }
        guard data.count <= maximumBytes else {
            throw InteropCodecError.unreadablePackage("a Figma response exceeded the import safety limit")
        }
        guard let http = response as? HTTPURLResponse else {
            throw InteropCodecError.unreadablePackage("Figma returned an invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.apiMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            switch http.statusCode {
            case 401, 403:
                throw InteropCodecError.unreadablePackage("Figma denied access. Check that the token has file_content:read scope and that you can view the file. \(message)")
            case 404:
                throw InteropCodecError.unreadablePackage("Figma could not find that file. Check the URL/key and your file access.")
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").map { " Retry after \($0) seconds." } ?? ""
                throw InteropCodecError.unreadablePackage("Figma's rate limit was reached.\(retry)")
            default:
                throw InteropCodecError.unreadablePackage("Figma returned HTTP \(http.statusCode): \(message)")
            }
        }
        return data
    }

    private static func apiMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["message"] as? String) ?? (json["err"] as? String)
    }

    private static func imageReferences(in value: Any) -> Set<String> {
        var refs = Set<String>()
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if (object["type"] as? String) == "IMAGE", let ref = object["imageRef"] as? String {
                    refs.insert(ref)
                }
                for child in object.values { walk(child) }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(value)
        return refs
    }
}

// MARK: - Defensive Figma JSON → EXP mapping

nonisolated private final class FigmaFileMapper {
    typealias JSON = [String: Any]

    let root: JSON
    let imageData: [String: Data]
    let requestedImageRefs: Set<String>
    var report: InteropImportReport
    var designLanguage = DesignLanguage()
    var componentObjects: [String: JSON] = [:]
    var componentSourceIDs: [String: UUID] = [:]
    var nodeIDs: [String: UUID] = [:]
    var sources: [ComponentSource] = []
    var namedPaints = Set<String>()
    var namedTypeStyles = Set<String>()
    let styleMetadata: [String: JSON]

    init(root: JSON, imageData: [String: Data], requestedImageRefs: Set<String>) {
        self.root = root
        self.imageData = imageData
        self.requestedImageRefs = requestedImageRefs
        let name = Self.string(root["name"]) ?? "Figma file"
        self.report = InteropImportReport(format: .figma, sourceName: name)
        self.styleMetadata = root["styles"] as? [String: JSON] ?? [:]
    }

    func map(context: InteropContext) throws -> InteropImportResult {
        guard let document = root["document"] as? JSON,
              Self.string(document["type"]) == "DOCUMENT" else {
            throw InteropCodecError.unreadablePackage("Figma file JSON has no DOCUMENT root")
        }
        let pageObjects = (document["children"] as? [Any])?.compactMap { $0 as? JSON } ?? []
        guard !pageObjects.isEmpty else { throw InteropCodecError.noUsableArtwork }

        collectComponents(in: document)
        for id in componentObjects.keys { componentSourceIDs[id] = UUID() }
        for id in componentObjects.keys.sorted() {
            guard let object = componentObjects[id], let frame = Self.bounds(object) else { continue }
            let children = mapContainerChildren(object, parentAbsoluteOrigin: frame.origin,
                                                namespace: "source:\(id)", path: Self.name(object),
                                                includeSurface: true)
            let source = ComponentSource(id: componentSourceIDs[id]!, name: Self.name(object),
                                         size: frame.size, children: children)
            sources.append(source)
            report.mapped("Component source")
        }

        var pages: [CanvasPage] = []
        for (pageIndex, pageObject) in pageObjects.enumerated() {
            try context.report(.mapping, completed: pageIndex, total: pageObjects.count,
                               detail: Self.name(pageObject))
            guard Self.string(pageObject["type"]) == "CANVAS" else {
                report.add(.warning, .unsupported, category: "Page",
                           message: "A non-canvas document child was skipped.",
                           location: Self.name(pageObject))
                continue
            }
            pages.append(mapPage(pageObject))
        }

        if !requestedImageRefs.isEmpty && imageData.count < requestedImageRefs.count {
            report.add(.warning, .unsupported, category: "Image fills",
                       message: "One or more Figma image resources could not be downloaded; their editable containers were preserved.",
                       location: report.sourceName)
        }
        if containsBoundVariables(root) {
            report.add(.information, .approximate, category: "Variables",
                       message: "Bound values render through the imported properties, but reusable Figma variables were not added to Design Language because Figma restricts its variables endpoint to Enterprise accounts.",
                       location: report.sourceName)
        }
        guard !pages.isEmpty else { throw InteropCodecError.noUsableArtwork }
        let payload = InteropImportPayload(pages: pages, sources: sources,
                                           designLanguage: designLanguage)
        return InteropImportResult(payload: payload, report: report)
    }

    private func mapPage(_ object: JSON) -> CanvasPage {
        let pageName = Self.name(object)
        var page = CanvasPage(name: pageName)
        let children = (object["children"] as? [Any])?.compactMap { $0 as? JSON } ?? []
        for child in children {
            let type = Self.string(child["type"]) ?? "UNKNOWN"
            if type == "FRAME", let frame = Self.bounds(child), Self.sane(frame) {
                let background = paint(from: firstVisiblePaint(child["fills"]))
                    ?? color(child["backgroundColor"]).map(Paint.solid) ?? .white
                let nodes = mapContainerChildren(child, parentAbsoluteOrigin: .zero,
                                                 namespace: "page:\(page.id.uuidString)",
                                                 path: "\(pageName) / \(Self.name(child))",
                                                 includeSurface: false,
                                                 localizeChildren: false)
                var notes = ""
                if let transitions = child["transitionNodeID"] as? String {
                    notes = "Figma prototype destination: \(transitions)"
                    report.notesWritten += 1
                }
                page.artboards.append(Artboard(name: Self.name(child), frame: frame,
                                               notes: notes, background: background))
                page.nodes.append(contentsOf: nodes)
                report.mapped("Artboard")
            } else if let node = mapNode(child, parentAbsoluteOrigin: .zero,
                                         namespace: "page:\(page.id.uuidString)",
                                         path: "\(pageName) / \(Self.name(child))") {
                page.nodes.append(node)
            }
        }
        report.mapped("Page")
        return page
    }

    private func collectComponents(in object: JSON) {
        if Self.string(object["type"]) == "COMPONENT", let id = Self.string(object["id"]) {
            componentObjects[id] = object
        }
        for child in (object["children"] as? [Any])?.compactMap({ $0 as? JSON }) ?? [] {
            collectComponents(in: child)
        }
    }

    private func mapContainerChildren(_ object: JSON, parentAbsoluteOrigin: CGPoint,
                                      namespace: String, path: String,
                                      includeSurface: Bool = true,
                                      localizeChildren: Bool = true) -> [Node] {
        guard let containerFrame = Self.bounds(object) else { return [] }
        var children: [Node] = []
        let fill = paint(from: firstVisiblePaint(object["fills"]))
        let stroke = strokeStyle(object)
        let radii = cornerRadii(object)
        // A nested Figma frame's own surface is real editable content. Top-level
        // artboards keep that surface in Artboard.background instead.
        if includeSurface && (fill != nil || stroke.width > 0) {
            children.append(Node(name: "Background",
                                 frame: CGRect(origin: .zero, size: containerFrame.size),
                                 isAbsoluteInAutoLayout: true,
                                 content: .rectangle(RectangleShape(
                                    fill: fill ?? .clear,
                                    cornerRadius: radii.uniform,
                                    stroke: stroke.color,
                                    strokeWidth: stroke.width,
                                    strokeAlignment: stroke.alignment,
                                    strokePattern: stroke.pattern,
                                    cornerRadii: radii.perCorner))))
        }
        let childParentOrigin = localizeChildren ? containerFrame.origin : CGPoint.zero
        for child in (object["children"] as? [Any])?.compactMap({ $0 as? JSON }) ?? [] {
            if let mapped = mapNode(child, parentAbsoluteOrigin: childParentOrigin,
                                    namespace: namespace,
                                    path: "\(path) / \(Self.name(child))") {
                children.append(mapped)
            }
        }
        return children
    }

    private func mapNode(_ object: JSON, parentAbsoluteOrigin: CGPoint,
                         namespace: String, path: String) -> Node? {
        let type = Self.string(object["type"]) ?? "UNKNOWN"
        guard let absolute = Self.bounds(object), Self.sane(absolute) else {
            report.add(.warning, .unsupported, category: "Geometry",
                       message: "The Figma layer has missing or invalid bounds and was skipped.",
                       location: path)
            return nil
        }
        let frame = absolute.offsetBy(dx: -parentAbsoluteOrigin.x, dy: -parentAbsoluteOrigin.y)
        let name = Self.name(object)
        let externalID = Self.string(object["id"]) ?? UUID().uuidString
        let id = uuid(for: "\(namespace):\(externalID)")
        var mappedRotation = Self.rotation(object)
        var node: Node?

        switch type {
        case "GROUP", "FRAME", "SECTION", "COMPONENT_SET":
            let children = mapContainerChildren(object, parentAbsoluteOrigin: parentAbsoluteOrigin,
                                                namespace: namespace, path: path)
            // mapContainerChildren localized children against this container's
            // absolute origin; its own frame is local to the caller.
            if type == "COMPONENT_SET" {
                report.add(.warning, .approximate, category: "Component variants",
                           message: "The Figma component set was imported as an editable group of component instances; variant properties are not states yet.",
                           location: path)
            }
            guard !children.isEmpty else { return nil }
            var group = Node(id: id, name: name, frame: frame,
                             content: .group(children: children))
            applyAutoLayout(object, to: &group, path: path)
            if Self.bool(object["clipsContent"]) == true {
                report.add(.warning, .approximate, category: "Clipping",
                           message: "Frame clipping was reduced to editable frame bounds and may need review.",
                           location: path)
            }
            node = group
        case "COMPONENT":
            if let sourceID = componentSourceIDs[externalID] {
                node = Node(id: id, name: name, frame: frame,
                            content: .instance(ComponentInstance(sourceID: sourceID)))
                report.mapped("Component placement")
            }
        case "INSTANCE":
            if let componentID = Self.string(object["componentId"]),
               let sourceID = componentSourceIDs[componentID] {
                node = Node(id: id, name: name, frame: frame,
                            content: .instance(ComponentInstance(sourceID: sourceID)))
                report.mapped("Component instance")
                let hasOverrides = !((object["overrides"] as? [Any])?.isEmpty ?? true)
                    || !((object["componentProperties"] as? JSON)?.isEmpty ?? true)
                if hasOverrides {
                    report.add(.warning, .approximate, category: "Component overrides",
                               message: "The local component reference was preserved, but Figma instance property overrides are not mapped in this first slice.",
                               location: path)
                }
            } else {
                let children = mapContainerChildren(object, parentAbsoluteOrigin: parentAbsoluteOrigin,
                                                    namespace: namespace, path: path)
                guard !children.isEmpty else { return nil }
                node = Node(id: id, name: name, frame: frame, content: .group(children: children))
                report.mapped("Group")
                report.add(.warning, .approximate, category: "Remote component",
                           message: "The instance's component source was not present in the file response, so its resolved layers were preserved as an editable group.",
                           location: path)
            }
        case "RECTANGLE", "ROUNDED_RECTANGLE":
            node = mapRectangle(object, id: id, name: name, frame: frame, path: path)
        case "ELLIPSE":
            let fill = paint(from: firstVisiblePaint(object["fills"])) ?? .clear
            let stroke = strokeStyle(object)
            node = Node(id: id, name: name, frame: frame,
                        content: .ellipse(EllipseShape(fill: fill, stroke: stroke.color,
                                                       strokeWidth: stroke.width,
                                                       strokeAlignment: stroke.alignment,
                                                       strokePattern: stroke.pattern)))
            report.mapped("Ellipse")
        case "REGULAR_POLYGON":
            let fill = paint(from: firstVisiblePaint(object["fills"])) ?? .clear
            let stroke = strokeStyle(object)
            node = Node(id: id, name: name, frame: frame,
                        content: .polygon(PolygonShape(
                            sides: Int(Self.number(object["pointCount"]) ?? 3), fill: fill,
                            stroke: stroke.color, strokeWidth: stroke.width,
                            strokeAlignment: stroke.alignment,
                            strokePattern: stroke.pattern)))
            report.mapped("Polygon")
        case "LINE":
            let mapped = mapLine(object, id: id, name: name,
                                 parentAbsoluteOrigin: parentAbsoluteOrigin,
                                 sourceRotation: mappedRotation)
            node = mapped.node
            mappedRotation = mapped.rotation
            report.mapped("Line")
        case "VECTOR", "BOOLEAN_OPERATION", "STAR":
            node = mapVector(object, id: id, name: name, frame: frame, path: path)
        case "TEXT":
            node = mapText(object, id: id, name: name, frame: frame, path: path)
        case "SLICE":
            report.add(.information, .unsupported, category: "Slice",
                       message: "Export slices are metadata and were not imported as artwork.",
                       location: path)
            return nil
        default:
            let children = mapContainerChildren(object, parentAbsoluteOrigin: parentAbsoluteOrigin,
                                                namespace: namespace, path: path)
            if !children.isEmpty {
                node = Node(id: id, name: name, frame: frame, content: .group(children: children))
                report.mapped("Group")
                report.add(.warning, .approximate, category: "Layer",
                           message: "Figma \(type) was reduced to an editable group.", location: path)
            } else {
                report.add(.warning, .unsupported, category: "Layer",
                           message: "Unsupported Figma node type “\(type)”.", location: path)
                return nil
            }
        }

        guard var result = node else { return nil }
        result.isVisible = Self.bool(object["visible"]) ?? true
        result.isLocked = Self.bool(object["locked"]) ?? false
        result.opacity = Self.clamped(Self.number(object["opacity"]) ?? 1)
        result.rotation = mappedRotation
        result.blendMode = blendMode(Self.string(object["blendMode"]))
        result.isAbsoluteInAutoLayout = Self.string(object["layoutPositioning"]) == "ABSOLUTE"
        result.effects = effects(object["effects"], path: path)
        if case .group(let children) = result.content,
           children.contains(where: \.isMaskShape) {
            // Figma expresses a mask as a marked sibling inside an ordinary
            // group/frame. EXP expresses the same relationship on the parent
            // group, so promote it here; otherwise the downloaded image exists
            // but the mask never participates in rendering.
            result.isMask = true
            report.mapped("Mask group")
        }
        if Self.bool(object["isMask"]) == true {
            result.isMaskShape = true
            report.add(.warning, .approximate, category: "Mask",
                       message: "The mask layer was marked, but Figma's sibling mask range may need regrouping in EXP.",
                       location: path)
        }
        return result
    }

    /// Figma LINE nodes are semantically one straight segment. Normalize them to
    /// EXP's horizontal local segment + rotation representation instead of drawing
    /// diagonally across `absoluteBoundingBox`. That box is post-transform and can
    /// include a few pixels on the minor axis; treating those pixels as endpoint
    /// geometry is what turned axis-aligned rules into visibly 1–3° slants.
    private func mapLine(_ object: JSON, id: UUID, name: String,
                         parentAbsoluteOrigin: CGPoint,
                         sourceRotation: Double) -> (node: Node, rotation: Double) {
        let absolute = Self.rawBounds(object) ?? .zero
        var localDirection: Double = 0
        var length: CGFloat = 0
        if let size = object["size"] as? JSON,
           let dx = Self.number(size["x"]), let dy = Self.number(size["y"]),
           dx.isFinite, dy.isFinite, hypot(dx, dy) > 0.000_001 {
            length = hypot(CGFloat(dx), CGFloat(dy))
            localDirection = atan2(dy, dx) * 180 / .pi
        } else {
            // Defensive REST fallback: `size` is geometry=paths-only and older or
            // unusual responses may omit it. A clearly vertical returned box is a
            // vertical segment, not a diagonal from its top-left to bottom-right.
            length = max(absolute.width, absolute.height)
            if abs(sourceRotation) < 0.000_001, absolute.height > absolute.width {
                localDirection = 90
            }
        }
        length = max(0.001, length)
        let center = CGPoint(x: absolute.midX - parentAbsoluteOrigin.x,
                             y: absolute.midY - parentAbsoluteOrigin.y)
        let frame = CGRect(x: center.x - length / 2, y: center.y,
                           width: length, height: 0)
        let stroke = strokeStyle(object)
        let node = Node(id: id, name: name, frame: frame,
                        content: .line(LineShape(start: .zero,
                                                end: CGPoint(x: length, y: 0),
                                                stroke: stroke.color,
                                                strokeWidth: max(1, stroke.width),
                                                strokePattern: stroke.pattern,
                                                strokeCap: stroke.cap,
                                                startMarker: stroke.marker,
                                                endMarker: stroke.marker)))
        return (node, Self.normalizedRotation(sourceRotation + localDirection))
    }

    private func mapRectangle(_ object: JSON, id: UUID, name: String,
                              frame: CGRect, path: String) -> Node {
        if let image = imagePaint(object["fills"]), let ref = Self.string(image["imageRef"]) {
            if let data = imageData[ref] {
                report.mapped("Image")
                if Self.string(image["scaleMode"]) != "FILL" {
                    report.add(.warning, .approximate, category: "Image crop",
                               message: "The embedded image is editable, but its Figma scale/crop mode was reduced to the layer bounds.",
                               location: path)
                }
                return Node(id: id, name: name, frame: frame,
                            content: .image(ImageContent(data: data, naturalSize: frame.size)))
            }
            report.add(.warning, .unsupported, category: "Image fill",
                       message: "The image resource could not be downloaded; its editable container was preserved.",
                       location: path)
        }
        let fill = paint(from: firstVisiblePaint(object["fills"])) ?? .clear
        let stroke = strokeStyle(object)
        let radii = cornerRadii(object)
        report.mapped("Rectangle")
        registerPaintStyle(object, paint: fill)
        return Node(id: id, name: name, frame: frame,
                    content: .rectangle(RectangleShape(fill: fill,
                        cornerRadius: radii.uniform, stroke: stroke.color,
                        strokeWidth: stroke.width, strokeAlignment: stroke.alignment,
                        strokePattern: stroke.pattern,
                        cornerRadii: radii.perCorner)))
    }

    private func mapVector(_ object: JSON, id: UUID, name: String,
                           frame: CGRect, path: String) -> Node? {
        let fillGeometries = (object["fillGeometry"] as? [Any])?.compactMap { $0 as? JSON } ?? []
        let strokeGeometries = (object["strokeGeometry"] as? [Any])?.compactMap { $0 as? JSON } ?? []
        let geometries = fillGeometries.isEmpty ? strokeGeometries : fillGeometries
        var subpaths: [SVGPath.Subpath] = []
        for geometry in geometries {
            guard let data = Self.string(geometry["path"]) else { continue }
            subpaths.append(contentsOf: SVGPath.parse(data))
        }
        let contours = subpaths.map(\.points)
        guard !contours.isEmpty else {
            report.add(.warning, .unsupported, category: "Vector path",
                       message: "Figma supplied no reusable vector path geometry.", location: path)
            return nil
        }
        let rawBounds = Self.pathBounds(contours.flatMap { $0 })
        let sx = rawBounds.width > 0 ? frame.width / rawBounds.width : 1
        let sy = rawBounds.height > 0 ? frame.height / rawBounds.height : 1
        func local(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - rawBounds.minX) * sx,
                    y: (point.y - rawBounds.minY) * sy)
        }
        let mapped = contours.map { contour in
            contour.map { point in
                PathPoint(point: local(point.point), controlIn: point.controlIn.map(local),
                          controlOut: point.controlOut.map(local))
            }
        }
        let fill = paint(from: firstVisiblePaint(object["fills"])) ?? .clear
        let stroke = strokeStyle(object)
        let closed = !fillGeometries.isEmpty || subpaths.allSatisfy(\.closed)
        report.mapped("Vector path")
        return Node(id: id, name: name, frame: frame,
                    content: .path(PathShape(points: mapped[0], closed: closed, fill: fill,
                                             stroke: stroke.color, strokeWidth: stroke.width,
                                             strokeAlignment: stroke.alignment,
                                             strokePattern: stroke.pattern,
                                             strokeCap: stroke.cap,
                                             startMarker: closed ? .none : stroke.marker,
                                             endMarker: closed ? .none : stroke.marker,
                                             contours: mapped.count > 1 ? mapped : nil)))
    }

    private func mapText(_ object: JSON, id: UUID, name: String,
                         frame: CGRect, path: String) -> Node {
        let raw = Self.string(object["characters"]) ?? ""
        var base = object["style"] as? JSON ?? [:]
        // Figma keeps the default text paint on the TEXT node, not necessarily
        // inside TypeStyle. Looking only at style.fills made perfectly valid
        // white/yellow text fall through to EXP's black default.
        if base["fills"] == nil, let fills = object["fills"] { base["fills"] = fills }
        var runs: [TextRun] = []
        if let overrides = object["characterStyleOverrides"] as? [Any],
           overrides.count == Array(raw).count,
           let table = object["styleOverrideTable"] as? JSON, !overrides.isEmpty {
            let characters = Array(raw)
            var start = 0
            while start < characters.count {
                let key = String(Int(Self.number(overrides[start]) ?? 0))
                var end = start + 1
                while end < characters.count,
                      Int(Self.number(overrides[end]) ?? 0) == Int(Self.number(overrides[start]) ?? 0) {
                    end += 1
                }
                var style = base
                if let override = table[key] as? JSON { style.merge(override) { _, new in new } }
                runs.append(textRun(String(characters[start..<end]), style: style))
                start = end
            }
        } else {
            runs = [textRun(raw, style: base)]
            if let overrides = object["characterStyleOverrides"] as? [Any],
               Set(overrides.compactMap { Self.number($0) }).count > 1 {
                report.add(.warning, .approximate, category: "Rich text",
                           message: "Mixed character styling could not be aligned to the returned text and was reduced to the base text style.",
                           location: path)
            }
        }
        let align: TextAlign
        switch Self.string(base["textAlignHorizontal"]) {
        case "CENTER": align = .center
        case "RIGHT": align = .right
        default: align = .left
        }
        let lineHeight = Self.number(base["lineHeightPx"]) ?? 1.3
        let lineUnit: LineHeightUnit = Self.number(base["lineHeightPx"]) == nil ? .auto : .px
        let tracking = Self.number(base["letterSpacing"]) ?? 0
        let autoResize = Self.string(base["textAutoResize"])
        let box: TextBox = autoResize == "WIDTH_AND_HEIGHT" ? .auto : .fixed
        let textCase: TextCase
        switch Self.string(base["textCase"]) {
        case "UPPER": textCase = .upper
        case "LOWER": textCase = .lower
        case "TITLE": textCase = .title
        case "SMALL_CAPS", "SMALL_CAPS_FORCED":
            textCase = .upper
            report.add(.warning, .approximate, category: "Text case",
                       message: "Figma small caps were reduced to uppercase text transformation.",
                       location: path)
        default: textCase = .none
        }
        let text = TextContent(runs: runs, align: align, lineHeight: lineHeight,
                               lineHeightUnit: lineUnit, tracking: tracking,
                               box: box, textCase: textCase)
        registerTypeStyle(object, text: text)
        report.mapped("Text")
        return Node(id: id, name: name, frame: frame, content: .text(text))
    }

    private func textRun(_ string: String, style: JSON) -> TextRun {
        let fill = paint(from: firstVisiblePaint(style["fills"]))?.representativeColor ?? .black
        let font = Self.string(style["fontPostScriptName"])
            ?? Self.string(style["fontFamily"]) ?? ""
        return TextRun(string: string, fontName: font,
                       fontSize: Self.number(style["fontSize"]) ?? 16,
                       color: fill,
                       underline: Self.string(style["textDecoration"]) == "UNDERLINE")
    }

    private func applyAutoLayout(_ object: JSON, to node: inout Node, path: String) {
        guard let mode = Self.string(object["layoutMode"]), mode != "NONE" else { return }
        var layout = AutoLayout()
        layout.direction = mode == "VERTICAL" ? .vertical : .horizontal
        layout.gap = Self.number(object["itemSpacing"]) ?? 0
        layout.distribution = Self.string(object["primaryAxisAlignItems"]) == "SPACE_BETWEEN"
            ? .spaceBetween : .packed
        switch Self.string(object["primaryAxisAlignItems"]) {
        case "CENTER": layout.primary = .center
        case "MAX": layout.primary = .end
        default: layout.primary = .start
        }
        switch Self.string(object["counterAxisAlignItems"]) {
        case "MIN": layout.cross = .start
        case "MAX": layout.cross = .end
        default: layout.cross = .center
        }
        node.autoLayout = layout
        var padding = AutoPadding()
        padding.paddingTop = Self.number(object["paddingTop"]) ?? 0
        padding.paddingRight = Self.number(object["paddingRight"]) ?? 0
        padding.paddingBottom = Self.number(object["paddingBottom"]) ?? 0
        padding.paddingLeft = Self.number(object["paddingLeft"]) ?? 0
        node.autoPadding = padding
        report.add(.information, .approximate, category: "Auto layout",
                   message: "Figma auto layout was mapped to EXP's editable stack and padding model; advanced sizing constraints may need review.",
                   location: path)
    }

    private func firstVisiblePaint(_ value: Any?) -> JSON? {
        (value as? [Any])?.compactMap { $0 as? JSON }
            .first { Self.bool($0["visible"]) != false && Self.string($0["type"]) != "IMAGE" }
    }

    private func imagePaint(_ value: Any?) -> JSON? {
        (value as? [Any])?.compactMap { $0 as? JSON }
            .first { Self.bool($0["visible"]) != false && Self.string($0["type"]) == "IMAGE" }
    }

    private func paint(from object: JSON?) -> Paint? {
        guard let object else { return nil }
        switch Self.string(object["type"]) {
        case "SOLID":
            return color(object["color"], opacity: Self.number(object["opacity"]) ?? 1).map(Paint.solid)
        case "GRADIENT_LINEAR", "GRADIENT_RADIAL":
            let stops = (object["gradientStops"] as? [Any])?.compactMap { value -> GradientStop? in
                guard let stop = value as? JSON,
                      let color = color(stop["color"]) else { return nil }
                return GradientStop(color: color, position: Self.clamped(Self.number(stop["position"]) ?? 0))
            } ?? []
            guard !stops.isEmpty else { return nil }
            let handles = (object["gradientHandlePositions"] as? [Any])?.compactMap { $0 as? JSON } ?? []
            let angle: Double
            if handles.count >= 2 {
                let a = CGPoint(x: Self.number(handles[0]["x"]) ?? 0,
                                y: Self.number(handles[0]["y"]) ?? 0)
                let b = CGPoint(x: Self.number(handles[1]["x"]) ?? 1,
                                y: Self.number(handles[1]["y"]) ?? 0)
                angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
            } else { angle = 0 }
            let kind: GradientFill.Kind = Self.string(object["type"]) == "GRADIENT_RADIAL" ? .radial : .linear
            return .gradient(GradientFill(kind: kind, stops: stops, angle: angle))
        case "GRADIENT_ANGULAR", "GRADIENT_DIAMOND":
            report.add(.warning, .approximate, category: "Gradient",
                       message: "Angular/diamond gradients were reduced to their first color.")
            let first = (object["gradientStops"] as? [Any])?.first as? JSON
            return color(first?["color"]).map(Paint.solid)
        default: return nil
        }
    }

    private func strokeStyle(_ object: JSON) -> (color: RGBAColor, width: CGFloat,
                                                  alignment: StrokeAlignment,
                                                  pattern: StrokePattern,
                                                  cap: StrokeLineCap,
                                                  marker: StrokeMarker) {
        let paint = firstVisiblePaint(object["strokes"])
        let color = self.paint(from: paint)?.representativeColor ?? .clear
        let width = Self.number(object["strokeWeight"]) ?? 0
        let alignment: StrokeAlignment
        switch Self.string(object["strokeAlign"]) {
        case "INSIDE": alignment = .inside
        case "OUTSIDE": alignment = .outside
        default: alignment = .center
        }
        let dashes = (object["strokeDashes"] as? [Any])?.compactMap(Self.number) ?? []
        let pattern: StrokePattern
        if dashes.isEmpty {
            pattern = .solid
        } else if (dashes.first ?? 1) <= max(0.01, width * 0.25)
                    || Self.string(object["strokeCap"]) == "ROUND" && (dashes.first ?? width) <= width {
            pattern = .dotted
        } else {
            pattern = .dashed
        }
        let rawCap = Self.string(object["strokeCap"]) ?? "NONE"
        let cap: StrokeLineCap
        let marker: StrokeMarker
        switch rawCap {
        case "ROUND":
            cap = .round; marker = .none
        case "SQUARE":
            cap = .square; marker = .none
        case "LINE_ARROW", "TRIANGLE_ARROW", "ARROW_LINES", "ARROW_EQUILATERAL", "TRIANGLE_FILLED":
            cap = .butt; marker = .arrow
        default:
            cap = .butt; marker = .none
        }
        return (color, width, alignment, pattern, cap, marker)
    }

    private func cornerRadii(_ object: JSON) -> (uniform: CGFloat, perCorner: CornerRadii?) {
        if let values = object["rectangleCornerRadii"] as? [Any], values.count >= 4 {
            let radii = values.prefix(4).map { Self.number($0) ?? 0 }
            let corners = CornerRadii(topLeft: radii[0], topRight: radii[1],
                                      bottomRight: radii[2], bottomLeft: radii[3])
            return (radii[0], corners.isUniform ? nil : corners)
        }
        return (Self.number(object["cornerRadius"]) ?? 0, nil)
    }

    private func effects(_ value: Any?, path: String) -> [Effect] {
        var result: [Effect] = []
        for raw in value as? [Any] ?? [] {
            guard let object = raw as? JSON, Self.bool(object["visible"]) != false,
                  let type = Self.string(object["type"]) else { continue }
            switch type {
            case "DROP_SHADOW", "INNER_SHADOW":
                let offset = object["offset"] as? JSON
                result.append(Effect(kind: type == "INNER_SHADOW" ? .innerShadow : .dropShadow,
                                     color: color(object["color"]) ?? .black,
                                     dx: Self.number(offset?["x"]) ?? 0,
                                     dy: Self.number(offset?["y"]) ?? 0,
                                     blur: Self.number(object["radius"]) ?? 0,
                                     spread: Self.number(object["spread"]) ?? 0))
            case "BACKGROUND_BLUR":
                result.append(Effect(kind: .backgroundBlur,
                                     blur: Self.number(object["radius"]) ?? 0))
            case "LAYER_BLUR":
                report.add(.warning, .unsupported, category: "Effects",
                           message: "Figma layer blur is not editable in EXP yet.", location: path)
            default: break
            }
        }
        return result
    }

    private func registerPaintStyle(_ object: JSON, paint: Paint) {
        guard let styles = object["styles"] as? JSON,
              let styleID = Self.string(styles["fill"]),
              let meta = styleMetadata[styleID],
              let name = Self.string(meta["name"]), namedPaints.insert(styleID).inserted else { return }
        designLanguage.assets.append(DesignAsset(name: name, value: paint,
                                                  provenance: "Figma paint style"))
        report.mapped("Design Language asset")
    }

    private func registerTypeStyle(_ object: JSON, text: TextContent) {
        guard let styles = object["styles"] as? JSON,
              let styleID = Self.string(styles["text"]),
              let meta = styleMetadata[styleID],
              let name = Self.string(meta["name"]), namedTypeStyles.insert(styleID).inserted else { return }
        let run = text.firstRun
        designLanguage.typeStyles.append(TypeStyle(name: name, provenance: "Figma text style",
                                                    fontName: run.fontName, fontSize: run.fontSize,
                                                    underline: run.underline, align: text.align,
                                                    lineHeight: text.lineHeight,
                                                    lineHeightUnit: text.lineHeightUnit,
                                                    tracking: text.tracking, textCase: text.textCase))
        report.mapped("Type style")
    }

    private func uuid(for key: String) -> UUID {
        if let existing = nodeIDs[key] { return existing }
        let value = UUID()
        nodeIDs[key] = value
        return value
    }

    private func color(_ value: Any?, opacity: Double = 1) -> RGBAColor? {
        guard let object = value as? JSON else { return nil }
        return RGBAColor(r: Self.clamped(Self.number(object["r"]) ?? 0),
                         g: Self.clamped(Self.number(object["g"]) ?? 0),
                         b: Self.clamped(Self.number(object["b"]) ?? 0),
                         a: Self.clamped((Self.number(object["a"]) ?? 1) * opacity))
    }

    private func blendMode(_ value: String?) -> BlendMode {
        switch value {
        case "MULTIPLY": return .multiply
        case "SCREEN": return .screen
        case "OVERLAY": return .overlay
        case "DARKEN": return .darken
        case "LIGHTEN": return .lighten
        case "COLOR_DODGE": return .colorDodge
        case "COLOR_BURN": return .colorBurn
        case "SOFT_LIGHT": return .softLight
        case "HARD_LIGHT": return .hardLight
        case "DIFFERENCE": return .difference
        case "EXCLUSION": return .exclusion
        case "HUE": return .hue
        case "SATURATION": return .saturation
        case "COLOR": return .color
        case "LUMINOSITY": return .luminosity
        default: return .normal
        }
    }

    private func containsBoundVariables(_ value: Any) -> Bool {
        if let object = value as? JSON {
            if object["boundVariables"] != nil { return true }
            return object.values.contains(where: containsBoundVariables)
        }
        if let array = value as? [Any] { return array.contains(where: containsBoundVariables) }
        return false
    }

    private static func name(_ object: JSON) -> String {
        let value = string(object["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? (string(object["type"]) ?? "Layer") : value
    }

    private static func rawBounds(_ object: JSON) -> CGRect? {
        guard let value = (object["absoluteBoundingBox"] as? JSON)
                ?? (object["absoluteRenderBounds"] as? JSON),
              let x = number(value["x"]), let y = number(value["y"]),
              let width = number(value["width"]), let height = number(value["height"]) else { return nil }
        let minimum: CGFloat = typeAllowsZeroSize(string(object["type"])) ? 0 : 0.01
        return CGRect(x: x, y: y, width: max(minimum, width),
                      height: max(minimum, height))
    }

    private static func bounds(_ object: JSON) -> CGRect? {
        guard let bounding = rawBounds(object) else { return nil }
        let minimum: CGFloat = typeAllowsZeroSize(string(object["type"])) ? 0 : 0.01
        guard let size = object["size"] as? JSON,
              let rawWidth = number(size["x"]), let rawHeight = number(size["y"]),
              rawWidth.isFinite, rawHeight.isFinite else { return bounding }
        let unrotated = CGSize(width: max(minimum, rawWidth), height: max(minimum, rawHeight))
        // `absoluteBoundingBox` is already the axis-aligned box *after* Figma's
        // rotation. EXP stores the unrotated frame and rotates it at draw time.
        // Centering Figma's `size` on the returned bounding-box center converts
        // between those two representations without applying the angle twice.
        return CGRect(x: bounding.midX - unrotated.width / 2,
                      y: bounding.midY - unrotated.height / 2,
                      width: unrotated.width, height: unrotated.height)
    }

    private static func typeAllowsZeroSize(_ type: String?) -> Bool { type == "LINE" }

    /// Figma documents `rotation` as the angle encoded by `relativeTransform`.
    /// Prefer the matrix returned by geometry=paths because it is the actual
    /// transform applied to the accompanying geometry; fall back to the scalar
    /// for older/minimal responses.
    private static func rotation(_ object: JSON) -> Double {
        if let rows = object["relativeTransform"] as? [Any], rows.count >= 2,
           let first = rows[0] as? [Any], let second = rows[1] as? [Any],
           first.count >= 2, second.count >= 2,
           let m00 = number(first[0]), let m01 = number(first[1]),
           let m10 = number(second[0]), let m11 = number(second[1]),
           [m00, m01, m10, m11].allSatisfy(\.isFinite),
           hypot(m00, m10) > 0.000_001,
           m00 * m11 - m01 * m10 > 0 {
            return normalizedRotation(atan2(-m10, m00) * 180 / .pi)
        }
        return normalizedRotation(number(object["rotation"]) ?? 0)
    }

    private static func normalizedRotation(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result <= -180 { result += 360 }
        return abs(result) < 0.000_001 ? 0 : result
    }

    private static func sane(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
            && rect.width >= 0 && rect.height >= 0
            && abs(rect.minX) < 100_000_000 && abs(rect.minY) < 100_000_000
            && rect.width < 100_000_000 && rect.height < 100_000_000
    }

    private static func pathBounds(_ points: [PathPoint]) -> CGRect {
        let values = points.flatMap { [$0.point, $0.controlIn, $0.controlOut].compactMap { $0 } }
        guard let first = values.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in values.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
    private static func clamped(_ value: Double) -> Double { min(1, max(0, value)) }
}

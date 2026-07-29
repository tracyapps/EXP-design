//
//  XDImporter.swift
//  EXP [design]
//
//  Offline Adobe XD rescue importer. An `.xd` document is a ZIP package whose
//  artwork is stored in AGC JSON trees. The format was never published as a
//  stable interchange specification, so this decoder is intentionally
//  defensive and reports every approximation/unsupported construct.
//

import Foundation
import CoreGraphics
import zlib

nonisolated struct XDImporter: InteropCodec {
    let format: InteropFormat = .adobeXD
    let capabilities: Set<InteropCapability> = [.read]

    func read(from url: URL, context: InteropContext = InteropContext()) throws -> InteropImportResult {
        try context.report(.opening, completed: 0, total: 1, detail: url.lastPathComponent)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw InteropCodecError.unreadablePackage(error.localizedDescription)
        }
        let archive = try XDZipArchive(data: data)
        let resourceStore = XDResourceStore(archive: archive)
        let allArtworkEntries = archive.entries
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix("graphiccontent.agc") }
        guard !allArtworkEntries.isEmpty else {
            throw InteropCodecError.unreadablePackage("graphicContent.agc is missing")
        }

        var report = InteropImportReport(format: .adobeXD, sourceName: url.lastPathComponent)
        if archive.entries.contains(where: { $0.name == "mimetype" }),
           let mimetypeEntry = archive.entries.first(where: { $0.name == "mimetype" }),
           let mimetype = String(data: try archive.data(for: mimetypeEntry), encoding: .utf8),
           !mimetype.contains("adobe.sparkler.project") {
            report.add(.warning, .approximate, category: "Package",
                       message: "The package MIME marker is not the expected Adobe XD project type.",
                       location: "mimetype")
        }

        let resourceEntry = allArtworkEntries.first {
            $0.name.lowercased() == "resources/graphics/graphiccontent.agc"
        }
        let catalog = try resourceEntry.map { entry in
            try Self.readResourceCatalog(archive.data(for: entry), report: &report)
        } ?? ResourceCatalog()
        let globalInteractions: [String: [Interaction]]
        if let entry = archive.entries.first(where: { $0.name.lowercased() == "interactions/interactions.json" }) {
            globalInteractions = (try? Self.readInteractions(archive.data(for: entry))) ?? [:]
        } else {
            globalInteractions = [:]
        }

        // Current XD packages split one AGC per artboard under `artwork/` and
        // keep names/positions in the resource AGC. Older packages may be one
        // monolithic resource AGC, so retain that as a fallback.
        var artworkEntries = allArtworkEntries.filter {
            $0.name.lowercased().hasPrefix("artwork/")
        }
        if artworkEntries.isEmpty, let resourceEntry { artworkEntries = [resourceEntry] }
        artworkEntries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var payload = InteropImportPayload(designLanguage: catalog.designLanguage)
        if !catalog.designLanguage.assets.isEmpty {
            report.mapped("Design Language asset", count: catalog.designLanguage.assets.count)
        }
        var seenArtboardIDs = Set<String>()
        for (index, entry) in artworkEntries.enumerated() {
            try context.report(.decoding, completed: index, total: artworkEntries.count,
                               detail: entry.name)
            let artworkData = try archive.data(for: entry)
            let partial = try Self.decodeArtwork(artworkData, sourcePath: entry.name,
                                                  externalArtboards: catalog.artboards,
                                                  externalArtboardNames: catalog.artboardNames,
                                                  globalInteractions: globalInteractions,
                                                  resourceStore: resourceStore,
                                                  report: &report, context: context)
            for artboard in partial.artboards {
                let sourceID = partial.sourceArtboardIDs[artboard.id] ?? artboard.id.uuidString
                guard seenArtboardIDs.insert(sourceID).inserted else {
                    report.add(.information, .exact, category: "Package",
                               message: "A duplicate artboard definition was ignored.",
                               location: sourceID)
                    continue
                }
                payload.artboards.append(artboard)
                payload.nodes.append(contentsOf: partial.nodesByArtboard[artboard.id] ?? [])
            }
            payload.nodes.append(contentsOf: partial.wallNodes)
        }

        guard !payload.artboards.isEmpty || !payload.nodes.isEmpty else {
            throw InteropCodecError.noUsableArtwork
        }
        try context.report(.finishing, completed: 1, total: 1, detail: report.summary)
        return InteropImportResult(payload: payload, report: report)
    }

    /// AGC-only entry point for the headless golden check. Production imports
    /// always use `read(from:)`, which additionally validates the ZIP package.
    static func readArtworkData(_ data: Data, sourceName: String = "graphicContent.agc",
                                context: InteropContext = InteropContext()) throws -> InteropImportResult {
        var report = InteropImportReport(format: .adobeXD, sourceName: sourceName)
        let decoded = try decodeArtwork(data, sourcePath: sourceName,
                                        externalArtboards: [:], externalArtboardNames: [:],
                                        globalInteractions: [:],
                                        resourceStore: nil,
                                        report: &report, context: context)
        var payload = InteropImportPayload()
        payload.artboards = decoded.artboards
        for board in decoded.artboards {
            payload.nodes.append(contentsOf: decoded.nodesByArtboard[board.id] ?? [])
        }
        payload.nodes.append(contentsOf: decoded.wallNodes)
        guard !payload.artboards.isEmpty || !payload.nodes.isEmpty else {
            throw InteropCodecError.noUsableArtwork
        }
        return InteropImportResult(payload: payload, report: report)
    }

    private static func preferredArtworkRank(_ path: String) -> Int {
        path.lowercased() == "resources/graphics/graphiccontent.agc" ? 0 : 1
    }
}

// MARK: - AGC scenegraph mapping

nonisolated private extension XDImporter {
    typealias JSON = [String: Any]

    struct DecodedArtwork {
        var artboards: [Artboard] = []
        var nodesByArtboard: [UUID: [Node]] = [:]
        var sourceArtboardIDs: [UUID: String] = [:]
        var wallNodes: [Node] = []
    }

    struct Interaction {
        var sourceLayer: String
        var trigger: String
        var action: String
        var destinationID: String?
        var transition: String?
    }

    struct ResourceCatalog {
        var artboards: JSON = [:]
        var artboardNames: [String: String] = [:]
        var designLanguage = DesignLanguage()
    }

    static func readResourceCatalog(_ data: Data,
                                    report: inout InteropImportReport) throws -> ResourceCatalog {
        guard let root = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw InteropCodecError.unreadablePackage("the XD resource catalog is not valid JSON")
        }
        let records = root["artboards"] as? JSON ?? [:]
        var names: [String: String] = [:]
        for (id, value) in records {
            if let record = value as? JSON, let name = string(record["name"]) { names[id] = name }
        }
        var language = DesignLanguage()
        if let resources = root["resources"] as? JSON,
           let meta = resources["meta"] as? JSON,
           let ux = meta["ux"] as? JSON {
            var seenPaints: [Paint] = []
            if let library = ux["documentLibrary"] as? JSON,
               let elements = library["elements"] as? [Any] {
                for (index, rawElement) in elements.enumerated() {
                    guard let element = rawElement as? JSON,
                          let value = libraryPaint(element, report: &report),
                          !seenPaints.contains(value) else { continue }
                    let authoredName = string(element["name"]) ?? string(element["displayName"])
                    let fallbackName: String
                    switch value {
                    case .solid(let color): fallbackName = hexName(color)
                    case .gradient: fallbackName = "Gradient \(index + 1)"
                    }
                    let trimmedName = authoredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    language.assets.append(DesignAsset(
                        name: trimmedName.isEmpty ? fallbackName : trimmedName,
                        value: value,
                        provenance: "Adobe XD document asset"))
                    seenPaints.append(value)
                }
            }
            if let swatches = ux["colorSwatches"] as? [Any] {
                for value in swatches {
                    guard let color = color(value), color.a > 0 else { continue }
                    let paint = Paint.solid(color)
                    guard !seenPaints.contains(paint) else { continue }
                    language.assets.append(DesignAsset(
                        name: hexName(color), value: paint,
                        provenance: "Adobe XD document color"))
                    seenPaints.append(paint)
                }
            }
            if let symbols = ux["symbols"] as? [Any], !symbols.isEmpty {
                report.add(.warning, .unsupported, category: "Components",
                           message: "\(symbols.count) XD component definition\(symbols.count == 1 ? "" : "s") found; source/state reconstruction is not in this first importer slice.",
                           location: "resources/graphics/graphicContent.agc")
            }
        }
        return ResourceCatalog(artboards: records, artboardNames: names,
                               designLanguage: language)
    }

    static func libraryPaint(_ element: JSON,
                             report: inout InteropImportReport) -> Paint? {
        guard let representations = element["representations"] as? [Any] else { return nil }
        for rawRepresentation in representations {
            guard let representation = rawRepresentation as? JSON,
                  let type = string(representation["type"])?.lowercased() else { continue }
            if type.contains("xdcolor"), let color = color(representation["content"]) {
                return .solid(color)
            }
            if type.contains("gradient"),
               let rawStops = representation["content"] as? [Any] {
                let stops = rawStops.compactMap { rawStop -> GradientStop? in
                    guard let stop = rawStop as? JSON,
                          let color = color(stop["color"]) else { return nil }
                    return GradientStop(color: color, position: number(stop["stop"]) ?? 0)
                }
                guard stops.count >= 2 else { continue }
                let kind: GradientFill.Kind = type.contains("radial") ? .radial : .linear
                report.add(.information, .approximate, category: "Design Language",
                           message: "An XD library gradient was imported without authored direction metadata; EXP uses a left-to-right direction.",
                           location: string(element["name"]) ?? string(element["id"]) ?? "Document asset")
                return .gradient(GradientFill(kind: kind, stops: stops, angle: 0))
            }
        }
        return nil
    }

    static func readInteractions(_ data: Data) throws -> [String: [Interaction]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? JSON,
              let values = root["interactions"] as? JSON else { return [:] }
        var result: [String: [Interaction]] = [:]
        for (sourceID, rawActions) in values {
            guard let actions = rawActions as? [Any] else { continue }
            for raw in actions {
                guard let action = raw as? JSON else { continue }
                let props = action["properties"] as? JSON
                result[sourceID, default: []].append(Interaction(
                    sourceLayer: sourceID,
                    trigger: string(action["triggerEvent"]) ?? "trigger",
                    action: string(action["action"]) ?? "action",
                    destinationID: string(props?["destination"]),
                    transition: string(props?["transition"])))
            }
        }
        return result
    }

    static func decodeArtwork(_ data: Data, sourcePath: String,
                              externalArtboards: JSON,
                              externalArtboardNames: [String: String],
                              globalInteractions: [String: [Interaction]],
                              resourceStore: XDResourceStore?,
                              report: inout InteropImportReport,
                              context: InteropContext) throws -> DecodedArtwork {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw InteropCodecError.unreadablePackage("\(sourcePath) is not valid JSON")
        }
        guard let root = object as? JSON else {
            throw InteropCodecError.unreadablePackage("\(sourcePath) has no artwork root")
        }
        let top = root["children"] as? [Any] ?? []
        var records = externalArtboards
        if let localRecords = root["artboards"] as? JSON {
            for (key, value) in localRecords where value is JSON { records[key] = value }
        }

        // Resolve interaction destinations to authored artboard names before any
        // node is mapped. The note remains useful even when an action itself has
        // no EXP behavior equivalent yet.
        var artboardNames = externalArtboardNames
        for value in top {
            guard let item = value as? JSON, string(item["type"]) == "artboard" else { continue }
            let sourceID = string(item["id"]) ?? string(item["ref"]) ?? UUID().uuidString
            let record = records[sourceID] as? JSON
            artboardNames[sourceID] = string(record?["name"]) ?? string(item["name"]) ?? "Artboard"
        }

        var decoded = DecodedArtwork()
        let artboardTotal = max(1, top.count)
        for (index, value) in top.enumerated() {
            try context.report(.mapping, completed: index, total: artboardTotal,
                               detail: sourcePath)
            guard let item = value as? JSON else { continue }
            let type = string(item["type"]) ?? "unknown"
            if type != "artboard" {
                var ignoredInteractions: [Interaction] = []
                if let node = mapNode(item, parentOrigin: .zero, rootLevel: true,
                                      path: "Pasteboard", interactions: &ignoredInteractions,
                                      globalInteractions: globalInteractions,
                                      resourceStore: resourceStore,
                                      report: &report) {
                    decoded.wallNodes.append(node)
                } else {
                    report.add(.warning, .unsupported, category: "Layer",
                               message: "Unsupported top-level XD node type “\(type)”.",
                               location: sourcePath)
                }
                continue
            }

            let sourceID = string(item["id"]) ?? string(item["ref"]) ?? UUID().uuidString
            let record = records[sourceID] as? JSON
            let name = string(record?["name"]) ?? string(item["name"]) ?? "Artboard"
            guard let frame = artboardBounds(item, record: record), sane(frame) else {
                report.add(.error, .unsupported, category: "Artboard",
                           message: "The artboard has missing or invalid bounds and was skipped.",
                           location: name)
                continue
            }
            let background = paint((item["style"] as? JSON)?["fill"]) ?? .white
            var interactions: [Interaction] = []
            let childValues = ((item["artboard"] as? JSON)?["children"] as? [Any])
                ?? (item["children"] as? [Any]) ?? []
            var nodes: [Node] = []
            for child in childValues {
                guard let child = child as? JSON else { continue }
                let childName = string(child["name"]) ?? string(child["type"]) ?? "Layer"
                if let node = mapNode(child, parentOrigin: frame.origin, rootLevel: true,
                                      path: "\(name) / \(childName)",
                                      interactions: &interactions,
                                      globalInteractions: globalInteractions,
                                      resourceStore: resourceStore,
                                      report: &report) {
                    nodes.append(node)
                }
            }
            var notes = ""
            if !interactions.isEmpty {
                let lines = interactions.map { interaction -> String in
                    let destination = interaction.destinationID.flatMap { artboardNames[$0] }
                        ?? interaction.destinationID ?? "unspecified destination"
                    let transition = interaction.transition.map { ", \($0)" } ?? ""
                    return "XD prototype: \(interaction.sourceLayer) — \(interaction.trigger) / \(interaction.action) → \(destination)\(transition)"
                }
                notes = lines.joined(separator: "\n")
                report.notesWritten += lines.count
                report.add(.information, .approximate, category: "Prototype",
                           message: "XD prototype behavior was recorded in the artboard notes; EXP does not model the interaction implementation.",
                           location: name)
            }
            let board = Artboard(name: name, frame: frame, notes: notes,
                                 background: background)
            decoded.artboards.append(board)
            decoded.nodesByArtboard[board.id] = nodes
            decoded.sourceArtboardIDs[board.id] = sourceID
            report.mapped("Artboard")
        }

        if externalArtboards.isEmpty,
           let resources = root["resources"] as? JSON,
           let meta = resources["meta"] as? JSON,
           let ux = meta["ux"] as? JSON,
           let symbols = ux["symbols"] as? [Any], !symbols.isEmpty {
            report.add(.warning, .unsupported, category: "Components",
                       message: "\(symbols.count) XD component definition\(symbols.count == 1 ? "" : "s") found; component-source reconstruction is not in this first importer slice.",
                       location: sourcePath)
        }
        return decoded
    }

    static func mapNode(_ object: JSON, parentOrigin: CGPoint, rootLevel: Bool,
                        path: String,
                        interactions: inout [Interaction],
                        globalInteractions: [String: [Interaction]],
                        resourceStore: XDResourceStore?,
                        report: inout InteropImportReport) -> Node? {
        let type = string(object["type"]) ?? "unknown"
        let name = string(object["name"]) ?? defaultName(for: type, object: object)
        let layerPath = path.hasSuffix(name) ? path : "\(path) / \(name)"
        collectInteractions(object, layerName: name, global: globalInteractions,
                            into: &interactions)

        let style = object["style"] as? JSON
        var node: Node?
        switch type {
        case "group", "scrollableGroup", "repeatGrid", "booleanGroup":
            let container = (object[type] as? JSON) ?? (object["group"] as? JSON) ?? object
            let childValues = container["children"] as? [Any] ?? object["children"] as? [Any] ?? []
            let origin = nodeOrigin(object, parentOrigin: parentOrigin, rootLevel: rootLevel)
            var children: [Node] = []
            for childValue in childValues {
                guard let child = childValue as? JSON else { continue }
                let childName = string(child["name"]) ?? string(child["type"]) ?? "Layer"
                if let mapped = mapNode(child, parentOrigin: origin, rootLevel: false,
                                        path: "\(layerPath) / \(childName)",
                                        interactions: &interactions,
                                        globalInteractions: globalInteractions,
                                        resourceStore: resourceStore,
                                        report: &report) {
                    children.append(mapped)
                }
            }
            guard !children.isEmpty else {
                report.add(.warning, .unsupported, category: "Group",
                           message: "The container had no supported child layers and was skipped.",
                           location: layerPath)
                return nil
            }
            let frame: CGRect
            if let explicit = explicitContainerBounds(object, origin: origin), sane(explicit) {
                frame = explicit
            } else {
                frame = children.dropFirst().reduce(children[0].frame) { $0.union($1.frame) }
            }
            // EXP group children are local. AGC children were mapped into the
            // current document coordinate space, so localize exactly once.
            for i in children.indices {
                children[i].frame.origin.x -= frame.minX
                children[i].frame.origin.y -= frame.minY
            }
            var group = Node(name: name, frame: frame, content: .group(children: children))
            if type == "repeatGrid" || type == "booleanGroup" {
                report.add(.warning, .approximate, category: "Group",
                           message: "XD \(type) was imported as an ordinary editable group.",
                           location: layerPath)
            }
            if let ux = ((object["meta"] as? JSON)?["ux"] as? JSON), ux["mask"] != nil {
                group.isMask = true
                report.add(.warning, .approximate, category: "Mask",
                           message: "The masked container was preserved, but its mask-child designation may need review.",
                           location: layerPath)
            }
            if let ux = ((object["meta"] as? JSON)?["ux"] as? JSON), ux["symbolId"] != nil {
                report.add(.warning, .approximate, category: "Components",
                           message: "An XD component instance was flattened to an editable group; source identity and states are not preserved yet.",
                           location: layerPath)
            }
            node = group
            report.mapped("Group")

        case "shape":
            guard let frame = nodeBounds(object, parentOrigin: parentOrigin, rootLevel: rootLevel), sane(frame) else {
                report.add(.warning, .unsupported, category: "Geometry",
                           message: "The shape has missing or invalid bounds and was skipped.",
                           location: layerPath)
                return nil
            }
            node = mapShape(object, frame: frame, name: name, path: layerPath,
                            resourceStore: resourceStore,
                            report: &report)

        case "text":
            let textFrame = (object["text"] as? JSON)?["frame"] as? JSON
            let hasExactBounds = ((((object["meta"] as? JSON)?["ux"] as? JSON)?["bounds"] as? JSON) != nil)
                || (string(textFrame?["type"]) == "area"
                    && number(textFrame?["width"]) != nil
                    && number(textFrame?["height"]) != nil)
            guard let frame = textBounds(object, parentOrigin: parentOrigin, rootLevel: rootLevel), sane(frame) else {
                report.add(.warning, .unsupported, category: "Geometry",
                           message: "The text layer has missing or invalid bounds and was skipped.",
                           location: layerPath)
                return nil
            }
            if !hasExactBounds {
                report.add(.warning, .approximate, category: "Text geometry",
                           message: "XD does not store reusable text bounds in this artwork tree; EXP estimated the editable text box from its runs and line layout.",
                           location: layerPath)
            }
            node = mapText(object, frame: frame, name: name)
            report.mapped("Text")

        case "syncRef", "symbolInstance":
            report.add(.warning, .unsupported, category: "Components",
                       message: "The XD component instance was skipped until component-source reconstruction is available.",
                       location: layerPath)
            return nil

        case "image", "linkedGraphic", "video", "lottie":
            report.add(.warning, .unsupported, category: "Media",
                       message: "The embedded \(type) layer was not imported in this first slice.",
                       location: layerPath)
            return nil

        default:
            report.add(.warning, .unsupported, category: "Layer",
                       message: "Unsupported XD node type “\(type)”.",
                       location: layerPath)
            return nil
        }

        guard var node else { return nil }
        node.isVisible = bool(object["visible"]) ?? true
        node.opacity = clamped(number(object["opacity"]) ?? number(style?["opacity"]) ?? 1)
        node.blendMode = blendMode(string(object["blendMode"]) ?? string(style?["blendMode"]))
        if let transform = effectiveTransform(object) {
            let a = number(transform["a"]) ?? 1
            let b = number(transform["b"]) ?? 0
            let c = number(transform["c"]) ?? 0
            let d = number(transform["d"]) ?? 1
            if abs(b) > 0.000_001 || abs(c) > 0.000_001 {
                node.rotation = atan2(b, a) * 180 / .pi
                if abs(a * d - b * c - 1) > 0.001 {
                    report.add(.warning, .approximate, category: "Transform",
                               message: "Rotation was preserved, but skew/non-uniform transform geometry was reduced to EXP bounds.",
                               location: layerPath)
                }
            }
        }
        if let style, style["blur"] != nil || style["shadow"] != nil {
            report.add(.warning, .unsupported, category: "Effects",
                       message: "One or more XD effects are not mapped yet.",
                       location: layerPath)
        }
        return node
    }

    static func mapShape(_ object: JSON, frame: CGRect, name: String, path: String,
                         resourceStore: XDResourceStore?,
                         report: inout InteropImportReport) -> Node? {
        guard let shape = object["shape"] as? JSON else {
            report.add(.warning, .unsupported, category: "Shape",
                       message: "Shape geometry is missing.", location: path)
            return nil
        }
        let kind = string(shape["type"]) ?? "unknown"
        let style = object["style"] as? JSON
        if let sourceFill = style?["fill"] as? JSON {
            switch string(sourceFill["type"]) {
            case "pattern":
                if let pattern = sourceFill["pattern"] as? JSON,
                   let ux = (pattern["meta"] as? JSON)?["ux"] as? JSON,
                   let uid = string(ux["uid"]),
                   let data = resourceStore?.data(for: uid), !data.isEmpty {
                    let naturalWidth = max(1, number(pattern["width"]) ?? frame.width)
                    let naturalHeight = max(1, number(pattern["height"]) ?? frame.height)
                    let image = Node(name: name, frame: frame,
                                     content: .image(ImageContent(
                                        data: data,
                                        naturalSize: CGSize(width: naturalWidth,
                                                            height: naturalHeight))))
                    report.mapped("Image")

                    let sourceAspect = naturalWidth / naturalHeight
                    let frameAspect = Double(frame.width / frame.height)
                    if abs(sourceAspect - frameAspect) / max(0.001, sourceAspect) > 0.02 {
                        report.add(.warning, .approximate, category: "Image crop",
                                   message: "The embedded XD image was preserved, but EXP reduced its fill/crop behavior to the layer bounds.",
                                   location: path)
                    }
                    let hasCorners = number(shape["radius"]) ??
                        (shape["r"] as? [Any])?.compactMap { number($0) }.max() ?? 0
                    let strokeObject = style?["stroke"] as? JSON
                    let strokeWidth = string(strokeObject?["type"]) == "none"
                        ? 0 : number(strokeObject?["width"]) ?? 0
                    if hasCorners > 0 || strokeWidth > 0 {
                        report.add(.warning, .approximate, category: "Image container",
                                   message: "The embedded image is editable, but its original container corners or stroke need review.",
                                   location: path)
                    }
                    return image
                }
                report.add(.warning, .unsupported, category: "Image fill",
                           message: "The XD image resource is missing or unreadable; its editable container was imported without the bitmap.",
                           location: path)
            case "gradient" where paint(sourceFill) == nil:
                report.add(.warning, .unsupported, category: "Gradient",
                           message: "The XD gradient definition could not be decoded; the shape was imported without that fill.",
                           location: path)
            case let type? where type != "solid" && type != "none" && type != "gradient":
                report.add(.warning, .unsupported, category: "Fill",
                           message: "Unsupported XD fill type “\(type)”.",
                           location: path)
            default: break
            }
        }
        let fill = paint(style?["fill"]) ?? .clear
        let (stroke, width, alignment) = strokeStyle(style?["stroke"])
        let result: Node
        switch kind {
        case "rect", "rectangle":
            let radii = (shape["r"] as? [Any])?.compactMap { number($0) }
            let uniform = radii?.first ?? number(shape["radius"]) ?? 0
            let corners: CornerRadii?
            if let radii, radii.count >= 4 {
                corners = CornerRadii(topLeft: radii[0], topRight: radii[1],
                                      bottomRight: radii[2], bottomLeft: radii[3])
            } else { corners = nil }
            result = Node(name: name, frame: frame,
                          content: .rectangle(RectangleShape(fill: fill,
                            cornerRadius: uniform, stroke: stroke, strokeWidth: width,
                            strokeAlignment: alignment, cornerRadii: corners)))
            report.mapped("Rectangle")
        case "ellipse", "circle":
            result = Node(name: name, frame: frame,
                          content: .ellipse(EllipseShape(fill: fill, stroke: stroke,
                                                        strokeWidth: width,
                                                        strokeAlignment: alignment)))
            report.mapped("Ellipse")
        case "polygon":
            let sides = Int(number(shape["sides"]) ?? 3)
            result = Node(name: name, frame: frame,
                          content: .polygon(PolygonShape(sides: sides, fill: fill,
                                                        stroke: stroke, strokeWidth: width,
                                                        strokeAlignment: alignment)))
            report.mapped("Polygon")
        case "line":
            let x1 = number(shape["x1"]) ?? 0, y1 = number(shape["y1"]) ?? 0
            let x2 = number(shape["x2"]) ?? frame.width, y2 = number(shape["y2"]) ?? frame.height
            let minX = min(x1, x2), minY = min(y1, y2)
            let rawWidth = abs(x2 - x1), rawHeight = abs(y2 - y1)
            let scaleX = rawWidth > 0 ? Double(frame.width) / rawWidth : 1
            let scaleY = rawHeight > 0 ? Double(frame.height) / rawHeight : 1
            result = Node(name: name, frame: frame,
                          content: .line(LineShape(start: CGPoint(x: (x1 - minX) * scaleX,
                                                                  y: (y1 - minY) * scaleY),
                                                  end: CGPoint(x: (x2 - minX) * scaleX,
                                                                y: (y2 - minY) * scaleY),
                                                  stroke: stroke, strokeWidth: max(1, width))))
            report.mapped("Line")
        case "path", "compound":
            guard let data = string(shape["path"]), !data.isEmpty else {
                report.add(.warning, .unsupported, category: "Vector path",
                           message: "The XD path has no path data.", location: path)
                return nil
            }
            let subpaths = SVGPath.parse(data)
            guard !subpaths.isEmpty else {
                report.add(.warning, .unsupported, category: "Vector path",
                           message: "The XD SVG-style path data could not be decoded.", location: path)
                return nil
            }
            let rawBounds = pathBounds(subpaths.flatMap(\.points))
            let sx = rawBounds.width > 0 ? frame.width / rawBounds.width : 1
            let sy = rawBounds.height > 0 ? frame.height / rawBounds.height : 1
            let contours = subpaths.map { subpath in
                subpath.points.map { point -> PathPoint in
                    func local(_ p: CGPoint) -> CGPoint {
                        CGPoint(x: (p.x - rawBounds.minX) * sx,
                                y: (p.y - rawBounds.minY) * sy)
                    }
                    return PathPoint(point: local(point.point),
                                     controlIn: point.controlIn.map(local),
                                     controlOut: point.controlOut.map(local))
                }
            }
            let closed = subpaths.contains { $0.closed } || fill.representativeColor.a > 0
            let pathShape = PathShape(points: contours[0], closed: closed,
                                      fill: fill, stroke: stroke, strokeWidth: width,
                                      strokeAlignment: alignment,
                                      contours: contours.count > 1 ? contours : nil)
            result = Node(name: name, frame: frame, content: .path(pathShape))
            report.mapped("Vector path")
        default:
            report.add(.warning, .unsupported, category: "Vector path",
                       message: "XD \(kind) path data is not decoded yet.",
                       location: path)
            return nil
        }
        return result
    }

    static func mapText(_ object: JSON, frame: CGRect, name: String) -> Node {
        let text = object["text"] as? JSON
        let raw = string(text?["rawText"]) ?? name
        let style = object["style"] as? JSON
        let ux = ((object["meta"] as? JSON)?["ux"] as? JSON)
        let explicitRanges = ux?["specRangedstyles"] as? [Any] ?? []
        let sequentialRanges = ux?["rangedStyles"] as? [Any] ?? []
        var runs: [TextRun] = []
        let ns = raw as NSString
        for value in explicitRanges {
            guard let range = value as? JSON,
                  let from = number(range["from"]), let to = number(range["to"]),
                  Int(from) >= 0, Int(to) >= Int(from), Int(to) <= ns.length,
                  let rangeStyle = range["style"] as? JSON else { continue }
            let string = ns.substring(with: NSRange(location: Int(from), length: Int(to - from)))
            let font = rangeStyle["font"] as? JSON
            let color = paint(rangeStyle["fill"])?.representativeColor
                ?? paint(style?["fill"])?.representativeColor ?? .black
            runs.append(TextRun(string: string,
                                fontName: XDImporter.string(font?["postscriptName"]) ?? "",
                                fontSize: number(font?["size"]) ?? 16,
                                color: color,
                                underline: bool(rangeStyle["underline"]) ?? false))
        }
        if runs.isEmpty, !sequentialRanges.isEmpty {
            var location = 0
            for value in sequentialRanges {
                guard let rangeStyle = value as? JSON else { continue }
                let length = min(ns.length - location,
                                 max(0, Int(number(rangeStyle["length"]) ?? 0)))
                guard length > 0 else { continue }
                let substring = ns.substring(with: NSRange(location: location, length: length))
                let color = paint(rangeStyle["fill"])?.representativeColor
                    ?? paint(style?["fill"])?.representativeColor ?? .black
                runs.append(TextRun(string: substring,
                                    fontName: string(rangeStyle["postscriptName"]) ?? "",
                                    fontSize: number(rangeStyle["fontSize"]) ?? 16,
                                    color: color,
                                    underline: bool(rangeStyle["underline"]) ?? false))
                location += length
            }
        }
        if runs.isEmpty || runs.map(\.string).joined() != raw {
            let font = style?["font"] as? JSON
            runs = [TextRun(string: raw,
                            fontName: string(font?["postscriptName"]) ?? "",
                            fontSize: number(font?["size"]) ?? 16,
                            color: paint(style?["fill"])?.representativeColor ?? .black)]
        }
        let attributes = style?["textAttributes"] as? JSON
        let align: TextAlign
        switch string(attributes?["paragraphAlign"]) {
        case "center": align = .center
        case "right": align = .right
        default: align = .left
        }
        let lineHeight = number(attributes?["lineHeight"]) ?? 1.3
        let hasAbsoluteLineHeight = number(attributes?["lineHeight"]) != nil
        let frameType = string((text?["frame"] as? JSON)?["type"])
        // XD stores character spacing in 1/1000ths of the font size. EXP stores
        // absolute point spacing (the same number CSS exports as px), so carrying
        // `-20` across verbatim exaggerated a subtle -2% setting into -20pt.
        let rawCharacterSpacing = number(attributes?["letterSpacing"])
            ?? sequentialRanges.compactMap { value in
                number((value as? JSON)?["charSpacing"])
            }.first
            ?? 0
        let referenceFontSize = runs.first?.fontSize ?? number((style?["font"] as? JSON)?["size"]) ?? 16
        let tracking = rawCharacterSpacing * referenceFontSize / 1_000
        let content = TextContent(runs: runs, align: align, lineHeight: lineHeight,
                                  lineHeightUnit: hasAbsoluteLineHeight ? .px : .auto,
                                  tracking: tracking,
                                  box: frameType == "positioned" ? .auto : .fixed)
        return Node(name: name, frame: frame, content: .text(content))
    }

    static func collectInteractions(_ object: JSON, layerName: String,
                                    global: [String: [Interaction]],
                                    into output: inout [Interaction]) {
        if let id = string(object["id"]), let actions = global[id] {
            output.append(contentsOf: actions.map {
                var interaction = $0
                interaction.sourceLayer = layerName
                return interaction
            })
        }
        guard let ux = ((object["meta"] as? JSON)?["ux"] as? JSON),
              let values = ux["interactions"] as? [Any] else { return }
        for value in values {
            guard let wrapper = value as? JSON,
                  bool(wrapper["enabled"]) != false,
                  let data = wrapper["data"] as? JSON,
                  let interaction = data["interaction"] as? JSON else { continue }
            let props = interaction["properties"] as? JSON
            output.append(Interaction(
                sourceLayer: layerName,
                trigger: string(interaction["triggerEvent"]) ?? "trigger",
                action: string(interaction["action"]) ?? "action",
                destinationID: string(props?["destination"]),
                transition: string(props?["transition"])))
        }
    }

    static func artboardBounds(_ object: JSON, record: JSON?) -> CGRect? {
        if let bounds = (((object["meta"] as? JSON)?["ux"] as? JSON)?["bounds"] as? JSON),
           let rect = rect(bounds) { return rect }
        guard let record, let width = number(record["width"]), let height = number(record["height"]) else {
            return nil
        }
        return CGRect(x: number(record["x"]) ?? 0, y: number(record["y"]) ?? 0,
                      width: width, height: height)
    }

    static func nodeBounds(_ object: JSON, parentOrigin: CGPoint,
                           rootLevel: Bool) -> CGRect? {
        if let bounds = (((object["meta"] as? JSON)?["ux"] as? JSON)?["bounds"] as? JSON),
           let rect = rect(bounds) { return rect }
        let shape = object["shape"] as? JSON
        let local = (((object["meta"] as? JSON)?["ux"] as? JSON)?["localBounds"] as? JSON)
            ?? shape
        if string(shape?["type"]) == "path" || string(shape?["type"]) == "compound",
           let data = string(shape?["path"]) {
            let parsed = SVGPath.parse(data)
            let bounds = pathBounds(parsed.flatMap(\.points))
            guard !bounds.isNull, !bounds.isEmpty else { return nil }
            return transformedLocalBounds(bounds, object: object, parentOrigin: parentOrigin,
                                          rootLevel: rootLevel)
        }
        if string(shape?["type"]) == "line",
           let x1 = number(shape?["x1"]), let y1 = number(shape?["y1"]),
           let x2 = number(shape?["x2"]), let y2 = number(shape?["y2"]) {
            let bounds = CGRect(x: min(x1, x2), y: min(y1, y2),
                                width: max(0.001, abs(x2 - x1)),
                                height: max(0.001, abs(y2 - y1)))
            return transformedLocalBounds(bounds, object: object, parentOrigin: parentOrigin,
                                          rootLevel: rootLevel)
        }
        guard let local, let r = rect(local) else { return nil }
        return transformedLocalBounds(r, object: object, parentOrigin: parentOrigin,
                                      rootLevel: rootLevel)
    }

    static func transformedLocalBounds(_ local: CGRect, object: JSON,
                                       parentOrigin: CGPoint, rootLevel: Bool) -> CGRect {
        let transform = effectiveTransform(object)
        let usesLocal = localTransform(object) != nil
        let base = usesLocal || !rootLevel ? parentOrigin : .zero
        let sx = number(transform?["a"]) ?? 1, sy = number(transform?["d"]) ?? 1
        return CGRect(x: base.x + (number(transform?["tx"]) ?? 0) + local.minX * sx,
                      y: base.y + (number(transform?["ty"]) ?? 0) + local.minY * sy,
                      width: max(0.001, abs(local.width * sx)),
                      height: max(0.001, abs(local.height * sy))).standardized
    }

    static func nodeOrigin(_ object: JSON, parentOrigin: CGPoint,
                           rootLevel: Bool) -> CGPoint {
        let transform = effectiveTransform(object)
        let usesLocal = localTransform(object) != nil
        let base = usesLocal || !rootLevel ? parentOrigin : .zero
        return CGPoint(x: base.x + (number(transform?["tx"]) ?? 0),
                       y: base.y + (number(transform?["ty"]) ?? 0))
    }

    static func explicitContainerBounds(_ object: JSON, origin: CGPoint) -> CGRect? {
        if let bounds = (((object["meta"] as? JSON)?["ux"] as? JSON)?["bounds"] as? JSON),
           let rect = rect(bounds) { return rect }
        guard let ux = ((object["meta"] as? JSON)?["ux"] as? JSON),
              let width = number(ux["width"]), let height = number(ux["height"]) else { return nil }
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    static func textBounds(_ object: JSON, parentOrigin: CGPoint,
                           rootLevel: Bool) -> CGRect? {
        if let bounds = (((object["meta"] as? JSON)?["ux"] as? JSON)?["bounds"] as? JSON),
           let rect = rect(bounds) { return rect }
        let text = object["text"] as? JSON
        let raw = string(text?["rawText"]) ?? string(object["name"]) ?? ""
        let frame = text?["frame"] as? JSON
        let frameType = string(frame?["type"])
        let style = object["style"] as? JSON
        let font = style?["font"] as? JSON
        let fontSize = max(1, number(font?["size"]) ?? 16)
        let attrs = style?["textAttributes"] as? JSON
        let lineHeight = max(fontSize, number(attrs?["lineHeight"]) ?? fontSize * 1.2)
        let origin = nodeOrigin(object, parentOrigin: parentOrigin, rootLevel: rootLevel)

        if frameType == "area", let width = number(frame?["width"]),
           let height = number(frame?["height"]) {
            return CGRect(origin: origin, size: CGSize(width: max(1, width),
                                                       height: max(1, height)))
        }

        let sourceLines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let naturalWidth = max(1, sourceLines.map { Double($0.count) * fontSize * 0.58 }.max() ?? fontSize)
        let width = frameType == "autoHeight" ? max(1, number(frame?["width"]) ?? naturalWidth)
            : naturalWidth
        let lineCount: Double
        if frameType == "autoHeight" {
            lineCount = sourceLines.reduce(0) { count, line in
                count + max(1, ceil(Double(line.count) * fontSize * 0.58 / width))
            }
        } else {
            lineCount = Double(max(1, sourceLines.count))
        }
        let height = max(lineHeight, lineCount * lineHeight)
        let align = string(attrs?["paragraphAlign"])
        let x = frameType == "autoHeight" ? origin.x
            : origin.x - (align == "center" ? width / 2 : align == "right" ? width : 0)
        let y = frameType == "autoHeight" ? origin.y : origin.y - fontSize * 0.82
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func effectiveTransform(_ object: JSON) -> JSON? {
        localTransform(object) ?? (object["transform"] as? JSON)
    }

    static func localTransform(_ object: JSON) -> JSON? {
        (((object["meta"] as? JSON)?["ux"] as? JSON)?["localTransform"] as? JSON)
    }

    static func pathBounds(_ points: [PathPoint]) -> CGRect {
        let values = points.flatMap { [$0.point, $0.controlIn, $0.controlOut].compactMap { $0 } }
        guard let first = values.first else { return .null }
        return values.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    static func rect(_ object: JSON) -> CGRect? {
        guard let width = number(object["width"]), let height = number(object["height"]) else { return nil }
        return CGRect(x: number(object["x"]) ?? 0, y: number(object["y"]) ?? 0,
                      width: width, height: height)
    }

    static func paint(_ value: Any?) -> Paint? {
        guard let object = value as? JSON else { return nil }
        if string(object["type"]) == "none" { return nil }
        if let color = object["color"] as? JSON,
           let rgb = color["value"] as? JSON,
           let r = number(rgb["r"]), let g = number(rgb["g"]), let b = number(rgb["b"]) {
            let alpha = number(color["alpha"]) ?? number(object["opacity"]) ?? 1
            return .solid(RGBAColor(r: channel(r), g: channel(g), b: channel(b), a: clamped(alpha)))
        }
        if let packed = number(object["value"]) {
            let value = UInt32(clamping: Int64(packed))
            return .solid(RGBAColor(r: Double((value >> 16) & 0xff) / 255,
                                    g: Double((value >> 8) & 0xff) / 255,
                                    b: Double(value & 0xff) / 255,
                                    a: Double((value >> 24) & 0xff) / 255))
        }
        if string(object["type"]) == "gradient",
           let gradient = object["gradient"] as? JSON,
           let meta = gradient["meta"] as? JSON,
           let ux = meta["ux"] as? JSON,
           let resources = ux["gradientResources"] as? JSON,
           let rawStops = resources["stops"] as? [Any] {
            let stops = rawStops.compactMap { value -> GradientStop? in
                guard let stop = value as? JSON, let color = color(stop["color"]) else { return nil }
                return GradientStop(color: color, position: number(stop["offset"]) ?? 0)
            }
            if stops.count >= 2 {
                let kind: GradientFill.Kind = string(resources["type"]) == "radial" ? .radial : .linear
                let x1 = number(gradient["x1"]) ?? 0, y1 = number(gradient["y1"]) ?? 0.5
                let x2 = number(gradient["x2"]) ?? 1, y2 = number(gradient["y2"]) ?? 0.5
                let angle = atan2(y2 - y1, x2 - x1) * 180 / .pi
                return .gradient(GradientFill(kind: kind, stops: stops, angle: angle))
            }
        }
        return nil
    }

    static func color(_ value: Any?) -> RGBAColor? {
        guard let object = value as? JSON else { return nil }
        if let rgb = object["value"] as? JSON,
           let r = number(rgb["r"]), let g = number(rgb["g"]), let b = number(rgb["b"]) {
            return RGBAColor(r: channel(r), g: channel(g), b: channel(b),
                             a: clamped(number(object["alpha"]) ?? 1))
        }
        return paint(object)?.representativeColor
    }

    static func hexName(_ color: RGBAColor) -> String {
        let r = Int((clamped(color.r) * 255).rounded())
        let g = Int((clamped(color.g) * 255).rounded())
        let b = Int((clamped(color.b) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func strokeStyle(_ value: Any?) -> (RGBAColor, CGFloat, StrokeAlignment) {
        guard let object = value as? JSON, string(object["type"]) != "none" else {
            return (.black, 0, .center)
        }
        let color = paint(object)?.representativeColor
            ?? paint(["type": "solid", "color": object["color"] as Any])?.representativeColor
            ?? .black
        let alignment: StrokeAlignment
        switch string(object["align"]) {
        case "inside": alignment = .inside
        case "outside": alignment = .outside
        default: alignment = .center
        }
        return (color, number(object["width"]) ?? 1, alignment)
    }

    static func blendMode(_ value: String?) -> BlendMode {
        switch value?.lowercased().replacingOccurrences(of: "_", with: "") {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "colordodge": return .colorDodge
        case "colorburn": return .colorBurn
        case "softlight": return .softLight
        case "hardlight": return .hardLight
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        default: return .normal
        }
    }

    static func defaultName(for type: String, object: JSON) -> String {
        if type == "shape", let shape = object["shape"] as? JSON,
           let kind = string(shape["type"]) { return kind.capitalized }
        return type.capitalized.isEmpty ? "Layer" : type.capitalized
    }

    static func sane(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
            && rect.width < 2_000_000 && rect.height < 2_000_000
            && abs(rect.minX) < 2_000_000 && abs(rect.minY) < 2_000_000
    }

    static func string(_ value: Any?) -> String? { value as? String }
    static func bool(_ value: Any?) -> Bool? { value as? Bool }
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
    static func channel(_ value: Double) -> Double { clamped(value > 1 ? value / 255 : value) }
    static func clamped(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - Bounded in-memory ZIP reader

nonisolated private struct XDZipArchive {
    struct Entry {
        var name: String
        var flags: UInt16
        var compression: UInt16
        var crc: UInt32
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    let bytes: Data
    let entries: [Entry]

    private static let maxEntries = 10_000
    private static let maxEntryBytes = 128 * 1_024 * 1_024

    init(data: Data) throws {
        bytes = data
        guard data.count >= 22 else { throw InteropCodecError.unreadablePackage("not a ZIP archive") }
        let searchStart = max(0, data.count - 65_557)
        var endOffset: Int?
        var cursor = data.count - 22
        while cursor >= searchStart {
            if data.u32(cursor) == 0x0605_4b50 { endOffset = cursor; break }
            cursor -= 1
        }
        guard let endOffset else { throw InteropCodecError.unreadablePackage("ZIP directory is missing") }
        let count = Int(data.u16(endOffset + 10))
        guard count <= Self.maxEntries else {
            throw InteropCodecError.unreadablePackage("ZIP contains too many entries")
        }
        let directoryOffset = Int(data.u32(endOffset + 16))
        var parsed: [Entry] = []
        var offset = directoryOffset
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(offset) == 0x0201_4b50 else {
                throw InteropCodecError.unreadablePackage("ZIP directory is corrupt")
            }
            let flags = data.u16(offset + 8)
            let compression = data.u16(offset + 10)
            let crc = data.u32(offset + 16)
            let compressedSize = Int(data.u32(offset + 20))
            let uncompressedSize = Int(data.u32(offset + 24))
            let nameLength = Int(data.u16(offset + 28))
            let extraLength = Int(data.u16(offset + 30))
            let commentLength = Int(data.u16(offset + 32))
            let localOffset = Int(data.u32(offset + 42))
            guard compressedSize != Int(UInt32.max), uncompressedSize != Int(UInt32.max) else {
                throw InteropCodecError.unreadablePackage("ZIP64 packages are not supported yet")
            }
            guard uncompressedSize <= Self.maxEntryBytes else {
                throw InteropCodecError.unreadablePackage("a ZIP entry exceeds the safety limit")
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                throw InteropCodecError.unreadablePackage("ZIP entry name is invalid")
            }
            parsed.append(Entry(name: name, flags: flags, compression: compression,
                                crc: crc, compressedSize: compressedSize,
                                uncompressedSize: uncompressedSize,
                                localHeaderOffset: localOffset))
            offset = nameEnd + extraLength + commentLength
        }
        entries = parsed
    }

    func data(for entry: Entry) throws -> Data {
        guard entry.flags & 0x1 == 0 else {
            throw InteropCodecError.unreadablePackage("encrypted ZIP entries are unsupported")
        }
        let offset = entry.localHeaderOffset
        guard offset + 30 <= bytes.count, bytes.u32(offset) == 0x0403_4b50 else {
            throw InteropCodecError.unreadablePackage("ZIP entry header is corrupt")
        }
        let nameLength = Int(bytes.u16(offset + 26))
        let extraLength = Int(bytes.u16(offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else {
            throw InteropCodecError.unreadablePackage("ZIP entry data is truncated")
        }
        let compressed = Data(bytes[start..<end])
        let result: Data
        switch entry.compression {
        case 0:
            result = compressed
        case 8:
            result = try inflateRaw(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw InteropCodecError.unreadablePackage("ZIP compression method \(entry.compression) is unsupported")
        }
        guard result.count == entry.uncompressedSize else {
            throw InteropCodecError.unreadablePackage("ZIP entry size does not match its directory record")
        }
        let actualCRC: UInt32 = result.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(crc32(0, base, uInt(result.count)))
        }
        guard actualCRC == entry.crc else {
            throw InteropCodecError.unreadablePackage("ZIP entry checksum failed")
        }
        return result
    }

    private func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let outputCount = output.count
        var stream = z_stream()
        let initialized = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                                        Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else {
            throw InteropCodecError.unreadablePackage("the deflate decoder could not start")
        }
        defer { inflateEnd(&stream) }
        let status: Int32 = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer(mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expectedSize else {
            throw InteropCodecError.unreadablePackage("a deflated ZIP entry is corrupt")
        }
        return output
    }
}

/// Lazily decodes only image resources actually referenced by mapped artwork.
/// Repeated XD placements share the same cached `Data` storage, which avoids
/// inflating the same bitmap hundreds of times in component-heavy documents.
nonisolated private final class XDResourceStore: @unchecked Sendable {
    private let archive: XDZipArchive
    private let entries: [String: XDZipArchive.Entry]
    private let lock = NSLock()
    private var cache: [String: Data] = [:]

    init(archive: XDZipArchive) {
        self.archive = archive
        var indexed: [String: XDZipArchive.Entry] = [:]
        for entry in archive.entries where !entry.isDirectory {
            let lower = entry.name.lowercased()
            guard lower.hasPrefix("resources/") else { continue }
            let identifier = String(lower.dropFirst("resources/".count))
            // Image blobs live directly under resources/<uid>. Catalog AGCs and
            // any future nested metadata are never exposed through this lookup.
            guard !identifier.isEmpty, !identifier.contains("/") else { continue }
            indexed[identifier] = entry
        }
        entries = indexed
    }

    func data(for identifier: String) -> Data? {
        let key = identifier.lowercased()
        lock.lock()
        if let data = cache[key] {
            lock.unlock()
            return data
        }
        lock.unlock()

        guard let entry = entries[key], let decoded = try? archive.data(for: entry) else {
            return nil
        }
        lock.lock()
        if let existing = cache[key] {
            lock.unlock()
            return existing
        }
        cache[key] = decoded
        lock.unlock()
        return decoded
    }
}

nonisolated private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)])
            | UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[index(startIndex, offsetBy: offset)])
            | UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8
            | UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16
            | UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
    }
}

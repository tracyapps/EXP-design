//
//  Document.swift
//  EXP [design]
//
//  THE FOUNDATION. Everything hangs off this model, so it's built right from
//  the first lines: it is reference-based (a component instance points at a
//  source, it never copies it) and it is the *data*, with no UI/AppKit imports.
//
//  Why value types (structs) + Codable, not classes?
//   • Codable gives us save/open almost for free — the file format is just this
//     tree encoded to JSON (the instant-open format the roadmap calls for).
//   • Mutating a struct held by `@Observable AppState` reassigns the property,
//     which is exactly the signal SwiftUI/the canvas watch to redraw.
//   • It keeps the model UI-free: this file imports only Foundation/CoreGraphics,
//     so the same model could be rendered, exported to SVG, or tested headless.
//
//  Shape on the screen, in CSS terms: Document is the stylesheet + markup, an
//  Artboard is a page, Nodes are the DOM tree, and a component instance is like
//  `<use href="#source">` in SVG — a reference plus a few overrides.
//
//  NOTE: the component/instance types exist now but aren't *edited* until
//  Phase 4. They live here today only so the model never has to be rewritten
//  to add references later — that retrofit is the project-killer we're avoiding.
//

import Foundation
import CoreGraphics

// MARK: - Code/component interop provenance

/// Hidden document metadata that lets a rendered import retain its identity in
/// the source system. This is deliberately separate from Notes and canvas nodes:
/// people edit the design; connectors use this receipt to make later handoff or
/// sync decisions without pretending anonymous pixels identify source code.
///
/// Connector/kind/ownership values are strings rather than closed enums. A newer
/// connector can therefore survive an older EXP decoder without making the whole
/// design file unreadable. Unknown fields are ignored by Codable; all known
/// collections decode with empty defaults for additive schema evolution.
struct CodeBridgeManifest: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var id: UUID
    var schemaVersion: Int
    var connector: String
    var source: CodeBridgeSource
    var resources: [CodeBridgeResource]
    var bindings: [CodeBridgeBinding]
    var behaviorContracts: [CodeBridgeBehaviorContract]
    var baseline: CodeBridgeBaseline?
    var metadata: [String: String]

    init(id: UUID = UUID(), schemaVersion: Int = Self.currentSchemaVersion,
         connector: String, source: CodeBridgeSource,
         resources: [CodeBridgeResource] = [], bindings: [CodeBridgeBinding] = [],
         behaviorContracts: [CodeBridgeBehaviorContract] = [],
         baseline: CodeBridgeBaseline? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.connector = connector
        self.source = source
        self.resources = resources
        self.bindings = bindings
        self.behaviorContracts = behaviorContracts
        self.baseline = baseline
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, schemaVersion, connector, source, resources, bindings
        case behaviorContracts, baseline, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        connector = try c.decodeIfPresent(String.self, forKey: .connector) ?? "unknown"
        source = try c.decodeIfPresent(CodeBridgeSource.self, forKey: .source)
            ?? CodeBridgeSource(displayName: "Unknown source")
        resources = try c.decodeIfPresent([CodeBridgeResource].self,
                                          forKey: .resources) ?? []
        bindings = try c.decodeIfPresent([CodeBridgeBinding].self,
                                         forKey: .bindings) ?? []
        behaviorContracts = try c.decodeIfPresent([CodeBridgeBehaviorContract].self,
                                                   forKey: .behaviorContracts) ?? []
        baseline = try c.decodeIfPresent(CodeBridgeBaseline.self, forKey: .baseline)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

struct CodeBridgeSource: Codable, Equatable, Sendable {
    var displayName: String
    var stableID: String?
    var entryPath: String?
    var repositoryURL: String?
    var branch: String?
    var revision: String?
    var packagePath: String?
    var framework: String?
    var frameworkVersion: String?
    var buildTool: String?
    var buildToolVersion: String?
    var metadata: [String: String]

    init(displayName: String, stableID: String? = nil, entryPath: String? = nil,
         repositoryURL: String? = nil, branch: String? = nil,
         revision: String? = nil, packagePath: String? = nil,
         framework: String? = nil, frameworkVersion: String? = nil,
         buildTool: String? = nil, buildToolVersion: String? = nil,
         metadata: [String: String] = [:]) {
        self.displayName = displayName
        self.stableID = stableID
        self.entryPath = entryPath
        self.repositoryURL = repositoryURL
        self.branch = branch
        self.revision = revision
        self.packagePath = packagePath
        self.framework = framework
        self.frameworkVersion = frameworkVersion
        self.buildTool = buildTool
        self.buildToolVersion = buildToolVersion
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case displayName, stableID, entryPath, repositoryURL, branch, revision
        case packagePath, framework, frameworkVersion, buildTool, buildToolVersion, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            ?? "Unknown source"
        stableID = try c.decodeIfPresent(String.self, forKey: .stableID)
        entryPath = try c.decodeIfPresent(String.self, forKey: .entryPath)
        repositoryURL = try c.decodeIfPresent(String.self, forKey: .repositoryURL)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        packagePath = try c.decodeIfPresent(String.self, forKey: .packagePath)
        framework = try c.decodeIfPresent(String.self, forKey: .framework)
        frameworkVersion = try c.decodeIfPresent(String.self, forKey: .frameworkVersion)
        buildTool = try c.decodeIfPresent(String.self, forKey: .buildTool)
        buildToolVersion = try c.decodeIfPresent(String.self, forKey: .buildToolVersion)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

/// One consumed browser resource or one explicitly inventoried connector-package
/// file. Text source may be retained byte-for-byte under the importer cap;
/// binary assets retain a digest/receipt and continue through normal EXP nodes.
struct CodeBridgeResource: Codable, Equatable, Sendable {
    var path: String
    var role: String
    var mimeType: String?
    var byteCount: Int?
    var sha256: String?
    var preservedData: Data?
    var metadata: [String: String]

    init(path: String, role: String, mimeType: String? = nil,
         byteCount: Int? = nil, sha256: String? = nil,
         preservedData: Data? = nil, metadata: [String: String] = [:]) {
        self.path = path
        self.role = role
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.preservedData = preservedData
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case path, role, mimeType, byteCount, sha256, preservedData, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "unknown"
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "resource"
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
        preservedData = try c.decodeIfPresent(Data.self, forKey: .preservedData)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

/// A stable association between one EXP object and one external identity. Empty
/// `writableProperties` means receipt-only: a future exporter must not infer a
/// source edit merely because the rendered node changed.
struct CodeBridgeBinding: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var expNodeID: UUID?
    var expArtboardID: UUID?
    var externalID: String
    var externalKind: String
    var sourcePath: String?
    var confidence: Double
    var ownership: String
    var observedProperties: [String]
    var writableProperties: [String]
    var baselineDigest: String?
    var metadata: [String: String]

    init(id: UUID = UUID(), expNodeID: UUID? = nil, expArtboardID: UUID? = nil,
         externalID: String, externalKind: String, sourcePath: String? = nil,
         confidence: Double = 1, ownership: String = "source",
         observedProperties: [String] = [], writableProperties: [String] = [],
         baselineDigest: String? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.expNodeID = expNodeID
        self.expArtboardID = expArtboardID
        self.externalID = externalID
        self.externalKind = externalKind
        self.sourcePath = sourcePath
        self.confidence = min(1, max(0, confidence))
        self.ownership = ownership
        self.observedProperties = observedProperties
        self.writableProperties = writableProperties
        self.baselineDigest = baselineDigest
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, expNodeID, expArtboardID, externalID, externalKind, sourcePath
        case confidence, ownership, observedProperties, writableProperties
        case baselineDigest, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        expNodeID = try c.decodeIfPresent(UUID.self, forKey: .expNodeID)
        expArtboardID = try c.decodeIfPresent(UUID.self, forKey: .expArtboardID)
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID) ?? "unknown"
        externalKind = try c.decodeIfPresent(String.self, forKey: .externalKind) ?? "unknown"
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath)
        confidence = min(1, max(0,
            try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0))
        ownership = try c.decodeIfPresent(String.self, forKey: .ownership) ?? "source"
        observedProperties = try c.decodeIfPresent([String].self,
                                                   forKey: .observedProperties) ?? []
        writableProperties = try c.decodeIfPresent([String].self,
                                                   forKey: .writableProperties) ?? []
        baselineDigest = try c.decodeIfPresent(String.self, forKey: .baselineDigest)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

/// One opacity mutation shared by canvas and Layers-panel keyboard handling.
/// Both selection surfaces use the same recursive tree semantics, so selecting
/// a nested group from the panel cannot behave differently from clicking it on
/// the artboard merely because a different view owns keyboard focus.
enum LayerOpacityMutation {
    @discardableResult
    static func apply(_ requestedOpacity: Double, to ids: Set<UUID>,
                      in nodes: inout [Node]) -> Bool {
        guard !ids.isEmpty else { return false }
        let opacity = min(1, max(0, requestedOpacity))
        var changed = false
        for index in nodes.indices {
            if ids.contains(nodes[index].id), nodes[index].opacity != opacity {
                nodes[index].opacity = opacity
                changed = true
            }
            if case .group(var children) = nodes[index].content,
               apply(opacity, to: ids, in: &children) {
                nodes[index].content = .group(children: children)
                changed = true
            }
        }
        return changed
    }
}

struct CodeBridgeBehaviorContract: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var externalID: String
    var kind: String
    var name: String
    var payload: [String: String] = [:]
}

struct CodeBridgeBaseline: Codable, Equatable, Sendable {
    var importedAt: Date
    var sourceRevision: String?
    var sourceDigest: String?
    var snapshotVersion: Int?
    var metadata: [String: String]

    init(importedAt: Date = Date(), sourceRevision: String? = nil,
         sourceDigest: String? = nil, snapshotVersion: Int? = nil,
         metadata: [String: String] = [:]) {
        self.importedAt = importedAt
        self.sourceRevision = sourceRevision
        self.sourceDigest = sourceDigest
        self.snapshotVersion = snapshotVersion
        self.metadata = metadata
    }
}

// MARK: - Canvas page

/// One independent infinite canvas inside an EXP document. Pages are peers of
/// the canvas, not entries in the layer tree: each owns its own artboards, wall
/// layers, guides, and root relationships, while component sources and the
/// Design Language remain shared by the whole document.
struct CanvasPage: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var artboards: [Artboard]
    var nodes: [Node]
    var guides: [Guide]
    var anchoredRelationships: [AnchoredRelationship]

    init(id: UUID = UUID(), name: String = "Page 1",
         artboards: [Artboard] = [], nodes: [Node] = [], guides: [Guide] = [],
         anchoredRelationships: [AnchoredRelationship] = []) {
        self.id = id
        self.name = name
        self.artboards = artboards
        self.nodes = nodes
        self.guides = guides
        self.anchoredRelationships = anchoredRelationships
    }
}

// MARK: - Document

/// The whole design file: its artboards plus the library of component sources
/// they can reference. This is what will be read/written by the document
/// system (native DocumentGroup) in the next cycle.
struct Document: Codable, Sendable {

    /// Public file-schema marker for future interop/handoff readers. This is
    /// distinct from `formatVersion`, which tracks internal model migrations.
    /// History: 1 = v1.4 baseline; 2 = v1.6 component contract (states,
    /// relationships, public override props); 3 = document-level canvas pages;
    /// 4 = hidden code/component bridge provenance.
    static let currentSchemaVersion = 4

    /// The schema version this in-memory document was DECODED from (kept for
    /// diagnostics), or the current version for new documents. Encoding always
    /// writes `currentSchemaVersion` — saving migrates a file forward.
    var schemaVersion: Int = Document.currentSchemaVersion

    /// Bumped when the on-disk shape changes. v2 moved shapes out of artboards
    /// into the document-level `nodes` list (the "wall" model).
    var formatVersion: Int = 3

    /// Browser-tab-like canvas workspaces. Only the active page participates in
    /// rendering, hit-testing, Layers, and selection; shared libraries stay at
    /// document scope.
    var pages: [CanvasPage]

    /// Compatibility accessors for older call sites and import/export helpers.
    /// They address the first page. Interactive surfaces use the page-id helpers
    /// below, so switching tabs never leaks inactive content into the canvas.
    var artboards: [Artboard] {
        get { pages.first?.artboards ?? [] }
        set { ensureFirstPage(); pages[0].artboards = newValue }
    }
    var nodes: [Node] {
        get { pages.first?.nodes ?? [] }
        set { ensureFirstPage(); pages[0].nodes = newValue }
    }

    /// Reusable component definitions. An instance node refers to one of these
    /// by `id` — the reference-based heart of the model. Empty until Phase 4.
    var sources: [ComponentSource]

    /// Hidden source receipts and bindings for code/component imports. This is
    /// not rendered and never contains credentials or executable app state.
    var codeBridges: [CodeBridgeManifest]

    /// Ruler guides (document coordinates), persisted with the file like Photoshop.
    var guides: [Guide] {
        get { pages.first?.guides ?? [] }
        set { ensureFirstPage(); pages[0].guides = newValue }
    }

    /// The document-local design language: named colors/gradients + recent paints
    /// that travel with the file. Empty until the user saves swatches (Phase 18).
    var designLanguage: DesignLanguage = DesignLanguage()

    /// Relationships anchored at the DOCUMENT root — the fallback anchor for two
    /// top-level nodes that share no group. Authoring never creates one of these
    /// (the neighborhood rule requires a group), but migration can, so the case
    /// exists rather than silently dropping a legacy link. FEAT-012 chunk I-b.
    var anchoredRelationships: [AnchoredRelationship] {
        get { pages.first?.anchoredRelationships ?? [] }
        set { ensureFirstPage(); pages[0].anchoredRelationships = newValue }
    }

    init(artboards: [Artboard] = Document.starter,
         nodes: [Node] = [],
         sources: [ComponentSource] = [],
         guides: [Guide] = [],
         designLanguage: DesignLanguage = DesignLanguage(),
         anchoredRelationships: [AnchoredRelationship] = [],
         codeBridges: [CodeBridgeManifest] = [],
         pageID: UUID = UUID()) {
        self.pages = [CanvasPage(id: pageID, artboards: artboards, nodes: nodes, guides: guides,
                                 anchoredRelationships: anchoredRelationships)]
        self.sources = sources
        self.codeBridges = codeBridges
        self.designLanguage = designLanguage
    }

    // Custom decode so files saved before `guides` existed still open.
    enum CodingKeys: String, CodingKey {
        case schemaVersion, formatVersion, pages, artboards, nodes, sources, guides,
             designLanguage, anchoredRelationships, codeBridges
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 2
        if let decodedPages = try c.decodeIfPresent([CanvasPage].self, forKey: .pages),
           !decodedPages.isEmpty {
            pages = decodedPages
        } else {
            let legacyArtboards = try c.decode([Artboard].self, forKey: .artboards)
            let legacyNodes = try c.decode([Node].self, forKey: .nodes)
            let legacyGuides = try c.decodeIfPresent([Guide].self, forKey: .guides) ?? []
            let legacyAnchors = ((try? c.decodeIfPresent([AnchoredRelationship].self,
                                                         forKey: .anchoredRelationships)) ?? nil) ?? []
            pages = [CanvasPage(artboards: legacyArtboards, nodes: legacyNodes,
                                guides: legacyGuides,
                                anchoredRelationships: legacyAnchors)]
        }
        sources = try c.decodeIfPresent([ComponentSource].self, forKey: .sources) ?? []
        // A malformed optional connector receipt must never brick the artwork.
        // The source can be re-imported; the design itself remains primary.
        codeBridges = ((try? c.decodeIfPresent([CodeBridgeManifest].self,
                                               forKey: .codeBridges)) ?? nil) ?? []
        designLanguage = try c.decodeIfPresent(DesignLanguage.self, forKey: .designLanguage) ?? DesignLanguage()
        // FEAT-012 chunk I-b. Derive the anchored form for anything still stored
        // the old way. Deliberately ADDITIVE: the legacy arrays are left intact and
        // still encoded, so a wrong migration is recoverable instead of destroying
        // a document the first time it is saved. Nothing reads the anchored form
        // until chunk I-d, so this is invisible at runtime.
        migrateRelationshipsToAnchors()
        // schema 1…3 documents inferred artboard membership from geometry on every
        // read. Seed v2.2's persistent hysteresis state once on open so an item
        // already on a board does not jump to the wall merely because a later group
        // resize makes its coverage fall below the entry threshold.
        for pageID in pages.map(\.id) { reconcileArtboardOwnership(on: pageID) }
    }

    // Custom encode so a re-saved older file upgrades its declared schema
    // version to the shape this app actually writes (schemaVersion migration).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Document.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(3, forKey: .formatVersion)
        try c.encode(pages, forKey: .pages)
        try c.encode(sources, forKey: .sources)
        if !codeBridges.isEmpty { try c.encode(codeBridges, forKey: .codeBridges) }
        try c.encode(designLanguage, forKey: .designLanguage)
    }

    private mutating func ensureFirstPage() {
        if pages.isEmpty { pages = [CanvasPage()] }
    }

    /// Resolve stale/session-only ids safely after open, delete, or undo.
    func pageID(resolving requested: UUID?) -> UUID? {
        if let requested, pages.contains(where: { $0.id == requested }) { return requested }
        return pages.first?.id
    }

    func pageIndex(for requested: UUID?) -> Int? {
        guard let id = pageID(resolving: requested) else { return nil }
        return pages.firstIndex { $0.id == id }
    }

    func page(for requested: UUID?) -> CanvasPage? {
        guard let index = pageIndex(for: requested) else { return nil }
        return pages[index]
    }

    func page(containingArtboard id: UUID) -> CanvasPage? {
        pages.first { page in page.artboards.contains { $0.id == id } }
    }

    var allArtboards: [Artboard] { pages.flatMap(\.artboards) }
    var allNodes: [Node] { pages.flatMap(\.nodes) }

    func contentBounds(on pageID: UUID?) -> CGRect {
        guard let boards = page(for: pageID)?.artboards, let first = boards.first else { return .zero }
        return boards.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Bounding box enclosing every artboard, in document coordinates. Used to
    /// center / fit the view.
    var contentBounds: CGRect {
        contentBounds(on: pages.first?.id)
    }

    /// Look up a component source by id (used when resolving an instance).
    func source(for id: UUID) -> ComponentSource? {
        sources.first { $0.id == id }
    }

    // MARK: Component source dependency graph (v2.1 / Chunk I)

    /// The component sources referenced directly by `nodes`. Group descendants
    /// are included; an instance contributes its source id but deliberately does
    /// not expand that source here. Keeping this as the graph's one edge reader
    /// means placement, Layers drag/drop, importers, and deletion checks can all
    /// ask the same question instead of growing subtly different walkers.
    func referencedSourceIDs(in nodes: [Node]) -> Set<UUID> {
        var result = Set<UUID>()
        func walk(_ nodes: [Node]) {
            for node in nodes {
                switch node.content {
                case .instance(let instance):
                    result.insert(instance.sourceID)
                case .group(let children):
                    walk(children)
                default:
                    break
                }
            }
        }
        walk(nodes)
        return result
    }

    /// Immediate outgoing edges for one component source (`parent -> child`).
    func directSourceDependencies(of sourceID: UUID) -> Set<UUID> {
        guard let source = source(for: sourceID) else { return [] }
        return referencedSourceIDs(in: source.children)
    }

    /// Whether `node` — or any roled component nested inside it — can carry a
    /// relationship. Lives on the model so the inspector, the Object menu, and the
    /// canvas context menu all answer from ONE place; they used to each carry their
    /// own copy of this test, which is how a menu item and a panel drift apart.
    ///
    /// Roles do not inherit, so a layer qualifies only through its OWN role, or by
    /// containing something that has one.
    func hasRelationshipParticipant(in node: Node, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        if let role = roleForExport(of: node),
           !role.authoredRelationshipKinds.isEmpty { return true }
        if !node.relationships.isEmpty { return true }
        switch node.content {
        case .group(let children):
            return children.contains { hasRelationshipParticipant(in: $0, depth: depth + 1) }
        case .instance(let instance):
            guard let source = source(for: instance.sourceID) else { return false }
            return source.children.contains { hasRelationshipParticipant(in: $0, depth: depth + 1) }
        default:
            return false
        }
    }

    /// The role emitted on the element hosting this node. Only a component instance
    /// carries one; every other layer exports as a plain container.
    func roleForExport(of node: Node) -> AriaRole? {
        if case .instance(let instance) = node.content {
            return source(for: instance.sourceID)?.a11y.role
        }
        return nil
    }

    // MARK: - Relationship anchors (FEAT-012 chunk I-b)

    /// Ancestor group ids for `id` within `nodes`, OUTERMOST first.
    /// Empty means the node sits directly in the scope root; nil means not found.
    private static func ancestorGroups(of id: UUID, in nodes: [Node],
                                       trail: [UUID] = []) -> [UUID]? {
        for node in nodes {
            if node.id == id { return trail }
            if case .group(let children) = node.content,
               let found = ancestorGroups(of: id, in: children, trail: trail + [node.id]) {
                return found
            }
        }
        return nil
    }

    /// The nearest group containing BOTH nodes, or nil when the only thing
    /// containing both is the scope root itself (a component source, or the
    /// document).
    ///
    /// Only GROUPS are considered, and component instances are opaque on purpose:
    /// a legacy relationship could only ever address a sibling, so it never
    /// crossed an instance boundary, and treating instances as containers here
    /// would invent nesting the stored data does not have.
    static func nearestCommonAncestorGroup(of a: UUID, and b: UUID,
                                           in nodes: [Node]) -> UUID? {
        guard let left = ancestorGroups(of: a, in: nodes),
              let right = ancestorGroups(of: b, in: nodes) else { return nil }
        var shared: UUID?
        for (x, y) in zip(left, right) {
            guard x == y else { break }
            shared = x
        }
        return shared
    }

    /// Drop anchored relationships naming any of `ids` at EITHER end.
    ///
    /// Only for an EXPLICIT delete. That is not the silent loss BUG-012 was about:
    /// the designer removed the layer, a link to something that no longer exists is
    /// meaningless, and one undo restores both together. What must never happen is
    /// discarding a link whose ends both still exist — which is why this takes a
    /// specific id set rather than "prune anything that does not currently resolve."
    /// A mid-edit tree can be briefly unresolvable, and a general sweep would eat
    /// real work.
    static func removingAnchors(referencing ids: Set<UUID>,
                                in list: [AnchoredRelationship]) -> [AnchoredRelationship] {
        list.filter { relationship in
            let touched = Set(relationship.subject.path + relationship.target.path)
            return touched.isDisjoint(with: ids)
        }
    }

    /// Same, applied through a whole subtree.
    static func removingAnchors(referencing ids: Set<UUID>, in nodes: inout [Node]) {
        for i in nodes.indices {
            nodes[i].anchoredRelationships =
                removingAnchors(referencing: ids, in: nodes[i].anchoredRelationships)
            if case .group(var children) = nodes[i].content {
                removingAnchors(referencing: ids, in: &children)
                nodes[i].content = .group(children: children)
            }
        }
    }

    /// Rewrite one endpoint through an id map. Ids NOT in the map are left alone,
    /// which is what makes this correct rather than merely convenient: a source
    /// child id is stable across every placement and must never be renamed, and a
    /// link that genuinely points OUTSIDE the copied subtree should keep pointing
    /// outside it.
    static func remapped(_ endpoint: RelationshipEndpoint,
                         map: [UUID: UUID]) -> RelationshipEndpoint {
        RelationshipEndpoint(
            instanceChain: endpoint.instanceChain.map { map[$0] ?? $0 },
            nodeID: map[endpoint.nodeID] ?? endpoint.nodeID)
    }

    /// Rewrite every anchored relationship in `node`'s subtree through `map`.
    ///
    /// Copying a group has to relink to the COPY. Without this, a duplicated group
    /// keeps entries naming the ORIGINAL's nodes — so the copy either shows nothing
    /// or, worse, quietly describes the original's structure. The designer's mental
    /// model is a relative link ("this tab opens the panel next to it"), and
    /// anchoring already expresses that; this is the step that carries it through
    /// duplication. BUG-010.
    static func remappingAnchors(_ node: Node, map: [UUID: UUID]) -> Node {
        var copy = node
        copy.anchoredRelationships = copy.anchoredRelationships.map {
            AnchoredRelationship(id: $0.id,
                                 kind: $0.kind,
                                 subject: remapped($0.subject, map: map),
                                 target: remapped($0.target, map: map))
        }
        if case .group(let children) = copy.content {
            copy.content = .group(children: children.map { remappingAnchors($0, map: map) })
        }
        return copy
    }

    /// Clone one layer subtree for Duplicate / copy-paste, assigning fresh node
    /// AND relationship ids and retargeting relationships whose destinations live
    /// inside the copied subtree. Component-instance override ids are deliberately
    /// left alone: they address the referenced source, which is not being copied.
    static func duplicatingNode(_ node: Node) -> Node {
        var map: [UUID: UUID] = [:]
        let fresh = reidentifyingForCopy(node, map: &map)
        return remappingCopiedReferences(fresh, map: map)
    }

    static func duplicatingNodesForTransfer(_ nodes: [Node]) -> [Node] {
        duplicatingNodesForTransferWithMap(nodes).nodes
    }

    static func duplicatingNodesForTransferWithMap(_ nodes: [Node])
        -> (nodes: [Node], idMap: [UUID: UUID]) {
        var map: [UUID: UUID] = [:]
        let fresh = nodes.map { reidentifyingForCopy($0, map: &map) }
        return (fresh.map { remappingCopiedReferences($0, map: map) }, map)
    }

    /// Deep-copy an entire canvas page. Building one shared id map before the
    /// rewrite preserves relationships between separate top-level layers rather
    /// than leaving the duplicate pointed back at the original page.
    static func duplicatingPage(_ page: CanvasPage, named name: String) -> CanvasPage {
        var map: [UUID: UUID] = [:]
        let freshNodes = page.nodes.map { reidentifyingForCopy($0, map: &map) }
        let nodes = freshNodes.map { remappingCopiedReferences($0, map: map) }
        let anchors = page.anchoredRelationships.map {
            AnchoredRelationship(kind: $0.kind,
                                 subject: remapped($0.subject, map: map),
                                 target: remapped($0.target, map: map))
        }
        var artboardMap: [UUID: UUID] = [:]
        let artboards = page.artboards.map { original -> Artboard in
            var copy = original
            copy.id = UUID()
            artboardMap[original.id] = copy.id
            return copy
        }
        let guides = page.guides.map { original -> Guide in
            var copy = original
            copy.id = UUID()
            return copy
        }
        let ownedNodes = nodes.map { original -> Node in
            var copy = original
            copy.artboardID = original.artboardID.flatMap { artboardMap[$0] }
            return copy
        }
        return CanvasPage(name: name, artboards: artboards, nodes: ownedNodes,
                          guides: guides, anchoredRelationships: anchors)
    }

    /// Duplicate selected layers beside their originals in the SAME parent array.
    /// A nested child therefore stays inside its group; selecting that child never
    /// clones the enclosing group. If an ancestor and descendant are both present
    /// in `ids`, the ancestor owns the copied subtree and the child is not copied a
    /// second time. Shared by canvas Command-D and the Layers row action.
    static func duplicatingNodes(_ ids: Set<UUID>, in nodes: [Node],
                                 offset: CGPoint = CGPoint(x: 10, y: 10))
        -> (nodes: [Node], copiedIDs: [UUID]) {
        guard !ids.isEmpty else { return (nodes, []) }
        var result = nodes
        var copiedIDs: [UUID] = []

        func duplicate(in siblings: inout [Node]) {
            var index = 0
            while index < siblings.count {
                if ids.contains(siblings[index].id) {
                    var copy = duplicatingNode(siblings[index])
                    copy.frame.origin.x += offset.x
                    copy.frame.origin.y += offset.y
                    siblings.insert(copy, at: index + 1)
                    copiedIDs.append(copy.id)
                    // Skip both the original and its copy. In particular, do not
                    // descend into a selected group and duplicate a selected child
                    // a second time.
                    index += 2
                    continue
                }
                if case .group(var children) = siblings[index].content {
                    duplicate(in: &children)
                    siblings[index].content = .group(children: children)
                }
                index += 1
            }
        }

        duplicate(in: &result)
        return (result, copiedIDs)
    }

    /// First pass for a copy. The complete map must exist before relationships are
    /// rewritten because one sibling may point at a sibling visited later.
    private static func reidentifyingForCopy(_ node: Node,
                                             map: inout [UUID: UUID]) -> Node {
        var copy = node
        copy.id = UUID()
        map[node.id] = copy.id
        if case .group(let children) = copy.content {
            copy.content = .group(children: children.map {
                reidentifyingForCopy($0, map: &map)
            })
        }
        return copy
    }

    /// Second pass for a copy: retarget both the current anchored form and the
    /// backwards-compatible subject-stored form. New relationship ids avoid two
    /// independently editable copies sharing identity in exported diagnostics.
    private static func remappingCopiedReferences(_ node: Node,
                                                   map: [UUID: UUID]) -> Node {
        var copy = node
        copy.relationships = copy.relationships.map {
            NodeRelationship(kind: $0.kind, target: remapped($0.target, map: map))
        }
        copy.anchoredRelationships = copy.anchoredRelationships.map {
            AnchoredRelationship(kind: $0.kind,
                                 subject: remapped($0.subject, map: map),
                                 target: remapped($0.target, map: map))
        }
        if case .group(let children) = copy.content {
            copy.content = .group(children: children.map {
                remappingCopiedReferences($0, map: map)
            })
        }
        return copy
    }

    /// Duplicate a component DEFINITION, not one of its placed instances. The new
    /// source is completely independent: source/layer/state/relationship ids are
    /// fresh, while references to OTHER component sources remain live references.
    /// Returns nil when the requested source does not exist.
    func duplicatingComponentSource(_ sourceID: UUID)
        -> (document: Document, sourceID: UUID)? {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return nil
        }

        let original = sources[index]
        var copy = original
        copy.id = UUID()
        copy.name = duplicateSourceName(original.name)

        var map: [UUID: UUID] = [original.id: copy.id]
        copy.children = original.children.map {
            Self.reidentifyingForCopy($0, map: &map)
        }.map {
            Self.remappingCopiedReferences($0, map: map)
        }

        copy.a11y.accessibleNameLayerID = original.a11y.accessibleNameLayerID.map {
            map[$0] ?? $0
        }
        copy.a11y.rootRelationships = original.a11y.rootRelationships.map {
            NodeRelationship(kind: $0.kind,
                             target: Self.remapped($0.target, map: map))
        }
        copy.states = original.states.map { state in
            var state = state
            state.id = UUID()
            state.overrides = state.overrides.map {
                InstanceOverride(targetNodeID: map[$0.targetNodeID] ?? $0.targetNodeID,
                                 value: $0.value)
            }
            state.layerVisibility = state.layerVisibility.map {
                LayerVisibilityOverride(layerID: map[$0.layerID] ?? $0.layerID,
                                        isVisible: $0.isVisible)
            }
            return state
        }
        copy.anchoredRelationships = original.anchoredRelationships.map {
            AnchoredRelationship(kind: $0.kind,
                                 subject: Self.remapped($0.subject, map: map),
                                 target: Self.remapped($0.target, map: map))
        }

        var result = self
        result.sources.insert(copy, at: index + 1)
        return (result, copy.id)
    }

    /// Finder-style copy naming, with a stable suffix when copies already exist.
    private func duplicateSourceName(_ name: String) -> String {
        let root = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Component" : name
        let used = Set(sources.map { $0.name.lowercased() })
        let first = "\(root) copy"
        guard used.contains(first.lowercased()) else { return first }
        var number = 2
        while used.contains("\(first) \(number)".lowercased()) { number += 1 }
        return "\(first) \(number)"
    }

    /// Rewrite every legacy, subject-stored relationship into the anchored form.
    ///
    /// ADDITIVE BY DESIGN. `Node.relationships` and `A11ySemantics.rootRelationships`
    /// are left exactly as they were and are still encoded, so this cannot destroy
    /// a document even if it is wrong — and nothing READS the anchored form until
    /// chunk I-d, so a mistake here cannot change what the app draws or exports
    /// either. Idempotent: an anchor already holding a matching entry is left
    /// alone, so open/save cycles do not accumulate duplicates.
    ///
    /// Everything below works on local copies and writes back at the end, so no
    /// call reads a stored property while another writes it.
    mutating func migrateRelationshipsToAnchors() {
        for index in sources.indices {
            var anchored = sources[index].anchoredRelationships
            var children = sources[index].children
            let scope = children

            // The component's OWN links. The subject is the element hosting the
            // instance; the source id stands for it.
            for relationship in sources[index].a11y.rootRelationships {
                Self.add(AnchoredRelationship(
                            kind: relationship.kind,
                            subject: RelationshipEndpoint(nodeID: sources[index].id),
                            target: relationship.target),
                         to: &anchored)
            }

            Self.collectLegacy(in: scope, scope: scope,
                               rootAnchored: &anchored, groupAnchors: &children)
            sources[index].children = children
            sources[index].anchoredRelationships = anchored
        }

        for index in pages.indices {
            var pageAnchored = pages[index].anchoredRelationships
            var pageNodes = pages[index].nodes
            let pageScope = pageNodes
            Self.collectLegacy(in: pageScope, scope: pageScope,
                               rootAnchored: &pageAnchored, groupAnchors: &pageNodes)
            pages[index].nodes = pageNodes
            pages[index].anchoredRelationships = pageAnchored
        }
    }

    /// Walk one scope, placing each legacy relationship on its nearest common
    /// ancestor group, or on the scope root when the two ends share no group.
    private static func collectLegacy(in nodes: [Node], scope: [Node],
                                      rootAnchored: inout [AnchoredRelationship],
                                      groupAnchors: inout [Node]) {
        for node in nodes {
            for relationship in node.relationships {
                let entry = AnchoredRelationship(
                    kind: relationship.kind,
                    subject: RelationshipEndpoint(nodeID: node.id),
                    target: relationship.target)
                if let groupID = nearestCommonAncestorGroup(
                    of: node.id, and: relationship.target.nodeID, in: scope) {
                    addToGroup(entry, groupID: groupID, in: &groupAnchors)
                } else {
                    add(entry, to: &rootAnchored)
                }
            }
            if case .group(let children) = node.content {
                collectLegacy(in: children, scope: scope,
                              rootAnchored: &rootAnchored, groupAnchors: &groupAnchors)
            }
        }
    }

    /// Identity for de-duplication is (kind, subject, target) — NOT `id`, which is
    /// freshly minted on every migration run and would defeat the check.
    private static func matches(_ a: AnchoredRelationship,
                                _ b: AnchoredRelationship) -> Bool {
        a.kind == b.kind && a.subject == b.subject && a.target == b.target
    }

    private static func add(_ entry: AnchoredRelationship,
                            to list: inout [AnchoredRelationship]) {
        guard !list.contains(where: { matches($0, entry) }) else { return }
        list.append(entry)
    }

    private static func addToGroup(_ entry: AnchoredRelationship, groupID: UUID,
                                   in nodes: inout [Node]) {
        for i in nodes.indices {
            if nodes[i].id == groupID {
                guard !nodes[i].anchoredRelationships.contains(where: { matches($0, entry) })
                else { return }
                nodes[i].anchoredRelationships.append(entry)
                return
            }
            if case .group(var children) = nodes[i].content {
                addToGroup(entry, groupID: groupID, in: &children)
                nodes[i].content = .group(children: children)
            }
        }
    }

    // MARK: - Relationship endpoints (FEAT-012 chunk I-a)

    /// Walk an endpoint's path down from a set of anchor children and return the
    /// node it addresses, or nil when the path no longer resolves.
    ///
    /// Each step of `instanceChain` must name a component INSTANCE in the tree at
    /// that level; the walk then continues into that instance's resolved children,
    /// which is the same tree the canvas draws and the exporter emits. Plain groups
    /// are transparent — they are structure, not identity, so a path never has to
    /// mention them and stays stable when someone regroups.
    ///
    /// Depth is capped for the same reason the dependency walker caps it: a
    /// damaged or legacy document may already contain a cycle, and this must
    /// terminate rather than recurse forever.
    /// As `resolveEndpoint(_:in:)`, but an endpoint naming `anchorID` resolves to
    /// the anchor itself rather than to one of its children. That is how a
    /// component's OWN relationships are expressed: the element carrying the role
    /// is the one hosting the instance, which is the anchor, not anything under it.
    /// Returns nil for the anchor case when the caller wants a child node, so
    /// callers must check `endpoint.nodeID == anchorID` when that distinction
    /// matters.
    func endpointNamesAnchor(_ endpoint: RelationshipEndpoint,
                             anchorID: UUID) -> Bool {
        endpoint.isDirect && endpoint.nodeID == anchorID
    }

    func resolveEndpoint(_ endpoint: RelationshipEndpoint,
                         in anchorChildren: [Node]) -> Node? {
        func find(_ id: UUID, in nodes: [Node]) -> Node? {
            for node in nodes {
                if node.id == id { return node }
                // Descend through groups only. Stepping into an instance without
                // an explicit chain entry would make two different paths resolve
                // to the same node, which is precisely the ambiguity this type
                // exists to remove.
                if case .group(let children) = node.content,
                   let found = find(id, in: children) { return found }
            }
            return nil
        }

        var level = anchorChildren
        var depth = 0
        for instanceID in endpoint.instanceChain {
            guard depth < 24 else { return nil }
            depth += 1
            guard let host = find(instanceID, in: level),
                  case .instance(let instance) = host.content else { return nil }
            level = resolvedChildren(of: instance)
        }
        return find(endpoint.nodeID, in: level)
    }

    /// True when an endpoint still addresses something. Used to report a broken
    /// link instead of silently dropping it.
    func endpointResolves(_ endpoint: RelationshipEndpoint,
                          in anchorChildren: [Node]) -> Bool {
        resolveEndpoint(endpoint, in: anchorChildren) != nil
    }

    /// Whether `sourceID` already reaches `targetID` through one or more nested
    /// component references. The visited set makes this total even for a damaged
    /// or legacy document that already contains a cycle.
    func source(_ sourceID: UUID, dependsOn targetID: UUID) -> Bool {
        var visited = Set<UUID>()
        func reaches(_ current: UUID) -> Bool {
            guard visited.insert(current).inserted else { return false }
            for dependency in directSourceDependencies(of: current) {
                if dependency == targetID || reaches(dependency) { return true }
            }
            return false
        }
        return reaches(sourceID)
    }

    /// True when adding `parent -> nested` would preserve an acyclic source
    /// graph. Adding the edge is illegal when both ids are equal or when the
    /// proposed child already reaches the parent (`A -> B -> A`).
    func canNestComponent(_ nestedSourceID: UUID, in parentSourceID: UUID) -> Bool {
        guard nestedSourceID != parentSourceID,
              source(for: nestedSourceID) != nil,
              source(for: parentSourceID) != nil else { return false }
        return !source(nestedSourceID, dependsOn: parentSourceID)
    }

    /// Graph-safe form used when an existing layer/group is moved into a source.
    /// Plain shapes have no references and are always safe; every component
    /// reference inside the moved subtree must be legal in the destination.
    func canInsert(_ nodes: [Node], intoSource parentSourceID: UUID) -> Bool {
        guard source(for: parentSourceID) != nil else { return false }
        return referencedSourceIDs(in: nodes).allSatisfy {
            canNestComponent($0, in: parentSourceID)
        }
    }

    // MARK: Deleting a component source (v2.1 / Chunk I)

    /// Every component source that references `sourceID`, directly or through
    /// another source. Deleting a source edits all of these, so the panels,
    /// menu validation, and the headless check ask this one question instead of
    /// each growing its own walker.
    func sourcesDepending(on sourceID: UUID) -> [UUID] {
        sources.map(\.id).filter { $0 != sourceID && source($0, dependsOn: sourceID) }
    }

    /// How many instances of `sourceID` exist on the canvas and inside other
    /// sources, at any depth. Deleting a source rewrites exactly this many
    /// layers, so this is the number any warning copy or report should quote.
    func instanceCount(of sourceID: UUID) -> Int {
        func count(_ nodes: [Node]) -> Int {
            nodes.reduce(0) { total, node in
                switch node.content {
                case .instance(let instance):
                    return total + (instance.sourceID == sourceID ? 1 : 0)
                case .group(let children):
                    return total + count(children)
                default:
                    return total
                }
            }
        }
        return pages.reduce(0) { $0 + count($1.nodes) }
            + sources.reduce(0) { $0 + count($1.children) }
    }

    /// Fresh ids for one flattened subtree, recording old -> new so an ancestor
    /// instance's `nestedStateOverrides` paths can be re-rooted. Ids INSIDE a
    /// `.instance` are deliberately untouched: those paths address that nested
    /// source's own children, which this edit does not renumber.
    private func reidentified(_ node: Node, map: inout [UUID: UUID]) -> Node {
        var copy = node
        copy.id = UUID()
        map[node.id] = copy.id
        if case .group(let children) = copy.content {
            copy.content = .group(children: children.map { reidentified($0, map: &map) })
        }
        return copy
    }

    /// Turn one instance node into an ordinary group of what it was drawing.
    /// The node KEEPS its id, name, frame, opacity, rotation, effects, blend
    /// mode, flips, mask flags, relationships, lock, and visibility — only
    /// `content` changes — so everything that addressed this layer (visibility
    /// overrides, relationships, Layers selection/expansion) keeps working.
    /// Children come from the same `resolvedChildren` the canvas draws and the
    /// Detach command bakes, so the flatten is visually a no-op.
    private func flattened(_ node: Node, instance: ComponentInstance,
                           idMap: inout [UUID: UUID]) -> Node {
        var copy = node
        let children = resolvedChildren(of: instance).map { child -> Node in
            reidentified(child, map: &idMap)
        }
        copy.content = .group(children: children)
        // `resolvedChildren` are source-local, and the replacement group keeps the
        // instance's frame. Group rendering adds that frame as the child offset.
        // Adding it here as well moved every child TWICE, often completely off the
        // visible canvas — which made source deletion look as if it removed every
        // instance even though the layers still existed in the model (BUG-014).
        // The flattened children were re-identified, so anything anchored inside
        // them must follow — same reasoning as BUG-010.
        copy = Self.remappingAnchors(copy, map: idMap)

        // Carry the COMPONENT ROOT's relationships onto the group that replaces
        // this instance, retargeted through the same id map the children were
        // renumbered with — otherwise deleting a source would silently strand
        // links that were part of the component contract.
        //
        // Naming is deliberately NOT carried: the group has no role, and
        // `aria-labelledby` is prohibited on a roleless (generic) element.
        // `aria-controls` / `aria-describedby` are global properties and stay
        // valid, so those survive. Same distinction as the exporter — see
        // BACKLOG BUG-008.
        if let source = source(for: instance.sourceID) {
            for relationship in source.a11y.rootRelationships
            where !relationship.kind.isProhibitedWithoutRole {
                guard let mapped = idMap[relationship.targetID] else { continue }
                copy.relationships.append(
                    NodeRelationship(kind: relationship.kind, targetID: mapped))
            }
        }
        return copy
    }

    /// Replace every instance of `sourceID` in `nodes`, at any depth, with a
    /// plain group. Instances of OTHER sources are left as instances — including
    /// ones nested inside the flattened content, which arrive from
    /// `resolvedChildren` already carrying the state they were displaying.
    private func flatteningInstances(of sourceID: UUID, in nodes: [Node],
                                     idMap: inout [UUID: UUID],
                                     dissolved: inout Set<UUID>) -> [Node] {
        nodes.map { node -> Node in
            switch node.content {
            case .instance(let instance) where instance.sourceID == sourceID:
                dissolved.insert(node.id)
                return flattened(node, instance: instance, idMap: &idMap)
            case .group(let children):
                var copy = node
                copy.content = .group(children: flatteningInstances(
                    of: sourceID, in: children, idMap: &idMap, dissolved: &dissolved))
                return copy
            default:
                return node
            }
        }
    }

    /// Re-root nested state selections that pointed through a now-dissolved
    /// instance. A selection FOR the dissolved instance is dropped (a plain
    /// group has no states to select); a selection for something nested BELOW it
    /// moves onto that layer's new id, so a state chosen two levels down is not
    /// silently lost. Paths that never touched the deleted source are untouched.
    private func repairingStatePaths(in nodes: [Node], dissolved: Set<UUID>,
                                     idMap: [UUID: UUID]) -> [Node] {
        nodes.map { node -> Node in
            var copy = node
            switch copy.content {
            case .instance(var instance):
                instance.nestedStateOverrides = instance.nestedStateOverrides.compactMap {
                    override -> NestedInstanceStateOverride? in
                    guard let head = override.instancePath.first,
                          dissolved.contains(head) else { return override }
                    let rest = override.instancePath.dropFirst()
                    guard let next = rest.first, let mapped = idMap[next] else { return nil }
                    return NestedInstanceStateOverride(
                        instancePath: [mapped] + rest.dropFirst(),
                        stateID: override.stateID)
                }
                // Nested VALUE overrides follow exactly the same rule (FEAT-017).
                // Not doing this here is the BUG-010 mistake one level over: a
                // dissolved instance renumbers the layers beneath it, and a path
                // running through it would otherwise address nothing while looking
                // perfectly valid. An override FOR the dissolved instance itself is
                // dropped, since the plain group that replaces it has no source to
                // override against.
                instance.nestedOverrides = instance.nestedOverrides.compactMap {
                    override -> NestedInstanceOverride? in
                    guard let head = override.instancePath.first,
                          dissolved.contains(head) else { return override }
                    let rest = override.instancePath.dropFirst()
                    guard let next = rest.first, let mapped = idMap[next] else { return nil }
                    return NestedInstanceOverride(
                        instancePath: [mapped] + rest.dropFirst(),
                        targetNodeID: idMap[override.targetNodeID] ?? override.targetNodeID,
                        value: override.value)
                }
                copy.content = .instance(instance)
            case .group(let children):
                copy.content = .group(children: repairingStatePaths(
                    in: children, dissolved: dissolved, idMap: idMap))
            default:
                break
            }
            return copy
        }
    }

    /// Delete a component source, leaving every place it was used looking
    /// exactly as it did: each instance becomes an ordinary group of the layers
    /// it was drawing, wherever it lived — the canvas, inside a group, or inside
    /// another component source. Nothing disappears from the document, and
    /// components nested below the deleted one survive as live instances.
    /// Returns a new document; the caller owns the single undo step.
    func deletingComponentSource(_ sourceID: UUID) -> Document {
        guard source(for: sourceID) != nil else { return self }
        var idMap: [UUID: UUID] = [:]
        var dissolved: Set<UUID> = []
        var result = self
        for index in result.pages.indices {
            result.pages[index].nodes = flatteningInstances(
                of: sourceID, in: result.pages[index].nodes,
                idMap: &idMap, dissolved: &dissolved)
        }
        for index in result.sources.indices {
            result.sources[index].children = flatteningInstances(
                of: sourceID, in: result.sources[index].children,
                idMap: &idMap, dissolved: &dissolved)
        }
        if !dissolved.isEmpty {
            for index in result.pages.indices {
                result.pages[index].nodes = repairingStatePaths(
                    in: result.pages[index].nodes, dissolved: dissolved, idMap: idMap)
            }
            for index in result.sources.indices {
                result.sources[index].children = repairingStatePaths(
                    in: result.sources[index].children, dissolved: dissolved, idMap: idMap)
            }
        }
        result.sources.removeAll { $0.id == sourceID }
        return result
    }

    /// A source behaves as a dynamic component when its top level is exactly one
    /// managed frame (typical button/tag components). More complex sources keep
    /// SVG-style stable viewBox bounds.
    /// Deliberately uses the PURE engine: this asks a structural question — is
    /// the top level exactly one managed group — and the answer cannot change
    /// with instance sizes. Resolving instances here would recurse on every
    /// layout for no difference in result.
    func sourceUsesManagedBounds(_ source: ComponentSource) -> Bool {
        managedRootBounds(in: AutoLayoutEngine.reflowed(source.children)) != nil
    }

    func managedRootBounds(in children: [Node]) -> CGRect? {
        let visible = children.filter(\.isVisible)
        guard visible.count == 1, let root = visible.first,
              case .group = root.content,
              root.autoLayout != nil || root.autoPadding != nil else { return nil }
        return root.frame
    }

    /// Instance resolution recurses through nested components. The source graph
    /// is kept acyclic (Chunk I), but a damaged or legacy file may already
    /// contain a cycle — the dependency walker above is explicitly total for
    /// that case, and so is this: past the cap, instances keep their stored
    /// frames instead of recursing forever.
    static let maxInstanceResolveDepth = 24

    /// Give every component instance in `nodes` its REAL size before layout runs.
    ///
    /// An instance's size is a function of its source plus this instance's
    /// overrides and state — not of its stored frame. `AutoLayoutEngine` is a
    /// pure `[Node] -> [Node]` with no document, so it cannot look a source up
    /// and leaves `.instance` nodes untouched. Without this pass an instance
    /// DRAWS at one size (every canvas path uses `resolvedSize(of:)`) and is
    /// LAID OUT at another (its stale stored frame), so an overridden label
    /// grows over its siblings instead of pushing them along. That was BUG-007.
    func instanceSized(_ nodes: [Node], depth: Int = 0) -> [Node] {
        // Identity fast path: most trees hold no instances, and rebuilding them
        // on every reflow would cost more than the walk saves.
        guard depth < Document.maxInstanceResolveDepth,
              nodes.contains(where: Document.containsInstance) else { return nodes }
        return nodes.map { node -> Node in
            var copy = node
            switch node.content {
            case .instance(let instance):
                if let layout = resolvedLayout(of: instance, depth: depth + 1),
                   layout.bounds.width > 0, layout.bounds.height > 0 {
                    copy.frame.size = layout.bounds.size
                }
            case .group(let children):
                copy.content = .group(children: instanceSized(children, depth: depth))
            default:
                break
            }
            return copy
        }
    }

    private static func containsInstance(_ node: Node) -> Bool {
        switch node.content {
        case .instance: return true
        case .group(let kids): return kids.contains(where: containsInstance)
        default: return false
        }
    }

    /// Reflow that knows how big component instances actually are. Every caller
    /// holding a document should use THIS rather than `AutoLayoutEngine.reflowed`
    /// directly; the pure engine entry point remains for contexts with no
    /// document (the thumbnail extension) and for structure-only checks.
    func reflowed(_ nodes: [Node]) -> [Node] {
        reflowed(nodes, depth: 0)
    }

    private func reflowed(_ nodes: [Node], depth: Int) -> [Node] {
        AutoLayoutEngine.reflowed(instanceSized(nodes, depth: depth))
    }

    private func resolvedLayout(of inst: ComponentInstance,
                                depth: Int = 0) -> (children: [Node], bounds: CGRect)? {
        guard let source = source(for: inst.sourceID) else { return nil }
        // Fold in the instance's selected state (nil = base) before resolving, so
        // an instance placed on the wall can display any of the source's states.
        let eff = inst.applyingState(inst.activeStateID.flatMap { sid in
            source.states.first { $0.id == sid }
        })
        let resolved = source.children
            .filter { eff.isLayerVisible($0.id, sourceDefault: $0.isVisible) }
            .map { eff.applyingOverrides(to: $0) }
            // FEAT-017 chunk J-b. Hand each nested instance the overrides addressed
            // to it, BEFORE the reflow below — so a re-hug measures the overridden
            // content rather than the source's original, which is the same ordering
            // mistake BUG-007 was about.
            .map { Self.pushingNestedOverrides(eff.nestedOverrides, into: $0) }
        // Re-hug auto-layout / auto-padding frames for THIS instance's overrides.
        // (AutoLayoutEngine.swift must be a member of BOTH the app AND the
        // EXPThumbnail targets, or this won't compile — do not stub this out.)
        let laid = reflowed(resolved, depth: depth)
        let bounds = sourceUsesManagedBounds(source)
            ? (managedRootBounds(in: laid) ?? source.bounds)
            : source.bounds

        // Position children relative to the bounds the instance occupies: the stable
        // viewBox for regular sources, or the re-hugged root frame for dynamic
        // single-frame components.
        let o = bounds.origin
        var shifted = laid
        if o.x != 0 || o.y != 0 {
            shifted = shifted.map { var n = $0; n.frame.origin.x -= o.x; n.frame.origin.y -= o.y; return n }
        }
        return (shifted, bounds)
    }

    /// Push an instance's nested overrides one level down, onto the nested instance
    /// each one addresses.
    ///
    /// This is the whole of J-b, and it is deliberately one level: an override whose
    /// path is `[a]` becomes an ORDINARY override on `a`, and one whose path is
    /// `[a, b]` becomes a nested override on `a` with the head stripped. `a` then
    /// resolves through this same function, so arbitrary depth falls out of the
    /// recursion that already exists rather than needing its own walk.
    ///
    /// Appended LAST on purpose. `applyingOverrides` applies in order with the later
    /// value winning, so a nested override from the outer placement beats whatever
    /// the source baked in — which is what "override" has to mean, and what makes
    /// reset (drop the entry) fall back to the nearest source value for free.
    ///
    /// Groups are descended but never named: a path contains instance ids only, so
    /// a nested instance sitting inside a layout group is still reachable and stays
    /// reachable when that group is rearranged. Same rule as relationship endpoints.
    ///
    /// An override with an EMPTY path matches nothing here, since no node id equals
    /// nil. That is the `isAddressable` contract from J-a holding by construction
    /// rather than by a filter someone could later remove.
    static func pushingNestedOverrides(_ overrides: [NestedInstanceOverride],
                                       into node: Node) -> Node {
        guard !overrides.isEmpty else { return node }
        var copy = node
        switch copy.content {
        case .instance(var nested):
            for override in overrides where override.instancePath.first == node.id {
                let rest = Array(override.instancePath.dropFirst())
                if rest.isEmpty {
                    nested.overrides.append(
                        InstanceOverride(targetNodeID: override.targetNodeID,
                                         value: override.value))
                } else {
                    nested.nestedOverrides.append(
                        NestedInstanceOverride(instancePath: rest,
                                               targetNodeID: override.targetNodeID,
                                               value: override.value))
                }
            }
            copy.content = .instance(nested)
        case .group(let children):
            copy.content = .group(children: children.map {
                pushingNestedOverrides(overrides, into: $0)
            })
        default:
            break
        }
        return copy
    }

    /// The fully-resolved children to draw for an instance: the source's children
    /// with this instance's overrides + visibility applied, then run through the
    /// auto-layout/padding engine so a button frame re-hugs an overridden label.
    /// Children are normalised to start at (0,0) in instance-local space, so the
    /// instance draws them at its own origin. Empty if the source is missing.
    func resolvedChildren(of inst: ComponentInstance) -> [Node] {
        resolvedLayout(of: inst)?.children ?? []
    }

    /// The size an instance occupies: the source viewBox, or a re-hugged managed
    /// root frame for dynamic single-frame components.
    func resolvedSize(of inst: ComponentInstance) -> CGSize {
        resolvedLayout(of: inst)?.bounds.size ?? .zero
    }

    /// The fully-resolved children of a component SOURCE in a named state —
    /// the state's override-diff applied through the exact machinery instances
    /// use (an ephemeral instance), so re-hug and nested overrides behave
    /// identically. `nil` = base state. Feeds the v1.6 state-preview switcher
    /// and per-state contrast checks.
    func resolvedChildren(of source: ComponentSource, in state: ComponentState?) -> [Node] {
        let ephemeral = ComponentInstance(
            sourceID: source.id,
            overrides: state?.overrides ?? [],
            layerVisibility: state?.layerVisibility ?? [])
        return resolvedChildren(of: ephemeral)
    }

    /// The candidate artboard for previously-unattached geometry. This is the
    /// ENTRY half of the artboard-membership rule: more than 50% overlap attaches
    /// a wall layer. Node-aware callers should use `owningArtboard(of:on:)`, which
    /// also remembers an existing attachment until its overlap reaches zero.
    func owningArtboard(of frame: CGRect) -> Artboard? {
        owningArtboard(of: frame, on: pages.first?.id)
    }

    func owningArtboard(of frame: CGRect, on pageID: UUID?) -> Artboard? {
        let area = frame.width * frame.height
        guard area > 0 else { return nil }
        var best: (artboard: Artboard, coverage: CGFloat)?
        for artboard in page(for: pageID)?.artboards ?? [] {
            let overlap = artboard.frame.intersection(frame)
            guard !overlap.isNull else { continue }
            let coverage = overlap.width * overlap.height
            // Own the node when the overlap covers >50% of the NODE *or* >50% of the
            // BOARD. Using min() of the two areas fixes the "group popped onto the
            // wall" bug: a group whose bounding FRAME is much larger than the board
            // (e.g. an imported logo carrying a big transparent/stray element) still
            // covers the whole board, so it stays owned even though it's <50% of its
            // own inflated frame. A node fully on the wall (no overlap) is unaffected.
            let boardArea = artboard.frame.width * artboard.frame.height
            guard coverage > 0.5 * Swift.min(area, boardArea) else { continue }
            if best == nil || coverage > best!.coverage { best = (artboard, coverage) }
        }
        return best?.artboard
    }

    /// Geometry used specifically for artboard membership. Ordinary unmanaged
    /// groups follow their descendants rather than a possibly stale container
    /// frame. A mask follows the visible crop (mask-shape bounds intersected with
    /// its content bounds), so "Mask with Top Shape" genuinely reduces the size
    /// used by the ownership test. Effects stay out of this calculation: a soft
    /// shadow should not decide which board owns an object.
    func artboardOwnershipBounds(of node: Node) -> CGRect {
        func transformed(_ bounds: CGRect, by node: Node, frame: CGRect) -> CGRect {
            guard !bounds.isNull else { return frame }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let radians = node.rotation * .pi / 180
            let sine = sin(radians), cosine = cos(radians)
            func map(_ point: CGPoint) -> CGPoint {
                var x = point.x, y = point.y
                if node.flipH { x = 2 * center.x - x }
                if node.flipV { y = 2 * center.y - y }
                guard node.rotation != 0 else { return CGPoint(x: x, y: y) }
                let dx = x - center.x, dy = y - center.y
                return CGPoint(x: center.x + dx * cosine - dy * sine,
                               y: center.y + dx * sine + dy * cosine)
            }
            let corners = [
                CGPoint(x: bounds.minX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.maxY),
                CGPoint(x: bounds.minX, y: bounds.maxY)
            ].map(map)
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min() ?? frame.minX, y: ys.min() ?? frame.minY,
                          width: (xs.max() ?? frame.maxX) - (xs.min() ?? frame.minX),
                          height: (ys.max() ?? frame.maxY) - (ys.min() ?? frame.minY))
        }

        func bounds(_ node: Node, parentOrigin: CGPoint) -> CGRect {
            let frame = node.frame.offsetBy(dx: parentOrigin.x, dy: parentOrigin.y)
            let inner: CGRect
            switch node.content {
            case .group(let children) where !children.isEmpty:
                let childOrigin = frame.origin
                func union(_ selected: [Node]) -> CGRect? {
                    selected.reduce(nil as CGRect?) { partial, child in
                        let childBounds = bounds(child, parentOrigin: childOrigin)
                        return partial?.union(childBounds) ?? childBounds
                    }
                }
                if node.isMask {
                    let mask = union(children.filter(\.isMaskShape))
                    let content = union(children.filter { !$0.isMaskShape })
                    if let mask, let content {
                        let clipped = mask.intersection(content)
                        inner = clipped.isNull || clipped.width <= 0 || clipped.height <= 0
                            ? mask : clipped
                    } else {
                        inner = mask ?? content ?? frame
                    }
                } else if node.autoLayout != nil || node.autoPadding != nil {
                    inner = frame
                } else {
                    inner = union(children) ?? frame
                }
            case .instance(let instance):
                inner = CGRect(origin: frame.origin, size: resolvedSize(of: instance))
            default:
                inner = frame
            }
            return transformed(inner, by: node, frame: frame)
        }
        return bounds(node, parentOrigin: .zero)
    }

    /// Resolve one top-level node's current board with hysteresis:
    /// - wall -> board requires the existing >50% entry threshold;
    /// - board -> wall requires zero remaining overlap.
    /// This preserves intentional cropped/sliver placements while still allowing
    /// a layer to be dragged completely back onto the wall.
    func owningArtboard(of node: Node, on pageID: UUID?) -> Artboard? {
        let boards = page(for: pageID)?.artboards ?? []
        if let assigned = node.artboardID,
           let board = boards.first(where: { $0.id == assigned }) {
            // Fast path for the common case: the persisted top-level frame itself
            // still touches its board. Masks deliberately skip it because their
            // whole point is that visible ownership may be much smaller than the
            // container/content union. This avoids a recursive descendant walk on
            // every canvas frame for ordinary large attached groups.
            if !node.isMask {
                let frameOverlap = board.frame.intersection(node.frame)
                if !frameOverlap.isNull, frameOverlap.width > 0, frameOverlap.height > 0 {
                    return board
                }
            }
            let geometry = artboardOwnershipBounds(of: node)
            let overlap = board.frame.intersection(geometry)
            if !overlap.isNull, overlap.width > 0, overlap.height > 0 { return board }
        }
        let geometry = artboardOwnershipBounds(of: node)
        return owningArtboard(of: geometry, on: pageID)
    }

    func owningArtboard(of node: Node) -> Artboard? {
        owningArtboard(of: node, on: pages.first?.id)
    }

    /// Persist the node-aware ownership answer after geometry/structure changes.
    /// Membership belongs only to top-level canvas nodes; nested children inherit
    /// their top-level container's clip and carry no competing assignment.
    mutating func reconcileArtboardOwnership(on pageID: UUID?) {
        guard let pageIndex = pageIndex(for: pageID) else { return }
        let resolvedPageID = pages[pageIndex].id
        func clearNested(_ node: inout Node) {
            guard case .group(var children) = node.content else { return }
            for index in children.indices {
                children[index].artboardID = nil
                clearNested(&children[index])
            }
            node.content = .group(children: children)
        }
        for index in pages[pageIndex].nodes.indices {
            let owner = owningArtboard(of: pages[pageIndex].nodes[index],
                                       on: resolvedPageID)
            pages[pageIndex].nodes[index].artboardID = owner?.id
            clearNested(&pages[pageIndex].nodes[index])
        }
    }

    /// A fresh document's starting artboards: a single board at the origin. The
    /// canvas's initial fit centers it in the view.
    static var starter: [Artboard] {
        [ Artboard(name: "Artboard 1", frame: CGRect(x: 0, y: 0, width: 393, height: 852)) ]
    }
}

// MARK: - Layout grid

/// A per-artboard layout grid (Figma-style): vertical columns, horizontal rows, or
/// a baseline grid. Persisted on the artboard.
struct LayoutGrid: Identifiable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case columns, rows, baseline }
    var id = UUID()
    var kind: Kind = .columns
    var count: Int = 12         // columns / rows
    var gutter: CGFloat = 16    // gap between columns / rows
    var margin: CGFloat = 0     // outer margin (columns / rows)
    var size: CGFloat = 8       // baseline line spacing
    var color: RGBAColor = RGBAColor(r: 1, g: 0, b: 0, a: 0.1)
    var visible: Bool = true

    init(id: UUID = UUID(), kind: Kind = .columns, count: Int = 12, gutter: CGFloat = 16,
         margin: CGFloat = 0, size: CGFloat = 8,
         color: RGBAColor = RGBAColor(r: 1, g: 0, b: 0, a: 0.1), visible: Bool = true) {
        self.id = id; self.kind = kind; self.count = count; self.gutter = gutter
        self.margin = margin; self.size = size; self.color = color; self.visible = visible
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .columns
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 12
        gutter = try c.decodeIfPresent(CGFloat.self, forKey: .gutter) ?? 16
        margin = try c.decodeIfPresent(CGFloat.self, forKey: .margin) ?? 0
        size = try c.decodeIfPresent(CGFloat.self, forKey: .size) ?? 8
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? RGBAColor(r: 1, g: 0, b: 0, a: 0.1)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }
}

// MARK: - Guide

/// A ruler guide: an infinite straight line at a fixed document coordinate.
/// `horizontal` guides run left-right at a given y; `vertical` guides run
/// top-bottom at a given x.
struct Guide: Identifiable, Codable, Sendable {
    enum Axis: String, Codable, Sendable { case horizontal, vertical }
    var id = UUID()
    var axis: Axis
    var position: CGFloat   // y for horizontal, x for vertical (document coords)
}

// MARK: - Artboard

/// A named frame on the canvas. Shapes enter through the >50% overlap rule, retain
/// that membership while any portion remains on the board, and return to the wall
/// when completely outside (see `Document.owningArtboard(of:on:)`).
struct Artboard: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var frame: CGRect           // document coordinates (points)
    /// Structured handoff notes attached to this board (NOT a node/artboard).
    /// Travels with the board on move/duplicate/delete because it lives here.
    var notes: String = ""

    /// The board's background fill (solid or gradient). Defaults to white (a board
    /// is a screen, not a themed surface — see the architecture note).
    var background: Paint = .white

    /// Layout grids (columns / rows / baseline) drawn over this board.
    var layoutGrids: [LayoutGrid] = []

    init(id: UUID = UUID(), name: String, frame: CGRect, notes: String = "",
         background: Paint = .white, layoutGrids: [LayoutGrid] = []) {
        self.id = id
        self.name = name
        self.frame = frame
        self.notes = notes
        self.background = background
        self.layoutGrids = layoutGrids
    }

    // Custom decode so files saved before these fields existed still open.
    enum CodingKeys: String, CodingKey { case id, name, frame, notes, background, layoutGrids }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        frame = try c.decode(CGRect.self, forKey: .frame)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        background = try c.decodeIfPresent(Paint.self, forKey: .background) ?? .white
        layoutGrids = try c.decodeIfPresent([LayoutGrid].self, forKey: .layoutGrids) ?? []
    }
}

// MARK: - Node (a shape / layer)

/// One shape. Common attributes (name, frame, visibility, lock) live here; what
/// the node *is* lives in `content`. `frame` is in DOCUMENT coordinates now.
/// Group children remain nested via the `.group` case.
/// Source semantics recovered from rendered HTML or another code connector.
///
/// This is deliberately data, not executable behavior. Authored `aria-*` values
/// survive byte-for-value so a future code bridge can round-trip them, while
/// `role` contains only the curated EXP role we can reason about today. An invalid
/// or unsupported authored role remains in `authoredRole` instead of being guessed.
struct NodeSemantics: Codable, Equatable, Sendable {
    var role: AriaRole?
    var authoredRole: String?
    var implicitRole: String?
    var ariaAttributes: [String: String]
    var sourceTag: String?
    var explicitRoleConformsToHost: Bool?
    var headingLevel: Int?

    init(role: AriaRole? = nil, authoredRole: String? = nil,
         implicitRole: String? = nil,
         ariaAttributes: [String: String] = [:], sourceTag: String? = nil,
         explicitRoleConformsToHost: Bool? = nil, headingLevel: Int? = nil) {
        self.role = role
        self.authoredRole = authoredRole
        self.implicitRole = implicitRole
        self.ariaAttributes = ariaAttributes
        self.sourceTag = sourceTag
        self.explicitRoleConformsToHost = explicitRoleConformsToHost
        self.headingLevel = headingLevel
    }

    enum CodingKeys: String, CodingKey {
        case role, authoredRole, implicitRole, ariaAttributes, sourceTag
        case explicitRoleConformsToHost, headingLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? c.decodeIfPresent(AriaRole.self, forKey: .role)) ?? nil
        authoredRole = try c.decodeIfPresent(String.self, forKey: .authoredRole)
        implicitRole = try c.decodeIfPresent(String.self, forKey: .implicitRole)
        ariaAttributes = try c.decodeIfPresent([String: String].self,
                                               forKey: .ariaAttributes) ?? [:]
        sourceTag = try c.decodeIfPresent(String.self, forKey: .sourceTag)
        explicitRoleConformsToHost = try c.decodeIfPresent(
            Bool.self, forKey: .explicitRoleConformsToHost)
        headingLevel = try c.decodeIfPresent(Int.self, forKey: .headingLevel)
    }
}

struct Node: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var frame: CGRect           // DOCUMENT coordinates (points)
    /// Persistent top-level artboard membership. nil means the wall. This small
    /// amount of memory provides the 50%-in / 100%-out hysteresis designers expect;
    /// nested nodes inherit their top-level container and keep this nil.
    var artboardID: UUID? = nil
    var isVisible: Bool = true
    var isLocked: Bool = false
    /// Rotation in degrees, clockwise, about the frame's center. 0 = upright.
    var rotation: Double = 0
    /// Whole-layer opacity, 0...1 (1 = fully opaque). Multiplies everything the
    /// node draws — fill, stroke, text, and its effects.
    var opacity: Double = 1
    /// Post-composite effects (drop/inner shadow), drawn back-to-front.
    var effects: [Effect] = []
    /// How the node composites with everything beneath it (Photoshop-style).
    var blendMode: BlendMode = .normal
    /// When non-nil AND this node is a `.group`, the group STACKS its children
    /// (direction + spacing + alignment). nil = no automatic arrangement.
    var autoLayout: AutoLayout? = nil
    /// When non-nil AND this node is a `.group`, the group HUGS its children with
    /// per-side padding and can draw its own background (the button/tag surface).
    /// Independent of `autoLayout` — either, both, or neither.
    var autoPadding: AutoPadding? = nil
    /// Keeps an item in its parent's coordinate space without making it one of the
    /// parent's auto-layout stack items. Figma calls this absolute positioning;
    /// it is also how an enclosing surface can remain behind a row of controls
    /// without consuming a row slot of its own.
    var isAbsoluteInAutoLayout: Bool = false
    /// Mirror flags, applied at draw time about the frame's center (like rotation).
    /// A flip is a render transform so it works uniformly for images, text, paths,
    /// and groups without rewriting their geometry.
    var flipH: Bool = false
    var flipV: Bool = false
    /// When true AND this node is a `.group`, the group is a MASK container: its
    /// children marked `isMaskShape` form the clip (their silhouettes, additive),
    /// and the remaining children (the masked content) are drawn clipped to it.
    /// Non-destructive — both the mask shape(s) and the content stay editable, like
    /// a component. nil/false = an ordinary group.
    var isMask: Bool = false
    /// When true, this node is part of its mask container's clip shape (not drawn as
    /// fill; only its silhouette clips). Only meaningful inside an `isMask` group.
    var isMaskShape: Bool = false
    /// Typed ARIA-style relationships to other nodes (Chunk H behavior contract).
    /// Export maps these to attributes like `aria-controls` / `aria-labelledby`;
    /// the app stores ids only, never interaction implementation code.
    var relationships: [NodeRelationship] = []
    /// Relationships ANCHORED at this node, meaningful only when it is a `.group`.
    /// The group is the nearest container holding both ends, so each end is stored
    /// as a path relative to it. See `AnchoredRelationship` and BACKLOG FEAT-012.
    ///
    /// FEAT-012 chunk I-b: this is populated by migration and by future authoring,
    /// but NOTHING reads it yet — the exporter still reads `relationships` until
    /// chunk I-d switches the read path over. Keeping the legacy array intact and
    /// still written means a bad migration is recoverable rather than destructive.
    var anchoredRelationships: [AnchoredRelationship] = []
    /// Which overridable fields on this node are public component props for
    /// downstream codegen / Storybook args. A false value keeps the override local
    /// to EXP; a true value advertises it as part of the source's public contract.
    var publicProps: PublicOverrideProps = PublicOverrideProps()
    /// Structured, non-executable semantics recovered from code imports.
    /// Ordinary EXP-authored nodes leave this nil; component semantics continue
    /// to live on `ComponentSource.a11y` and remain the user-facing contract.
    var semantics: NodeSemantics? = nil
    var content: NodeContent

    init(id: UUID = UUID(), name: String, frame: CGRect, artboardID: UUID? = nil,
         isVisible: Bool = true,
         isLocked: Bool = false, rotation: Double = 0, opacity: Double = 1,
         effects: [Effect] = [], blendMode: BlendMode = .normal,
         autoLayout: AutoLayout? = nil, autoPadding: AutoPadding? = nil,
         isAbsoluteInAutoLayout: Bool = false,
         flipH: Bool = false, flipV: Bool = false,
         isMask: Bool = false, isMaskShape: Bool = false,
         relationships: [NodeRelationship] = [],
         anchoredRelationships: [AnchoredRelationship] = [],
         publicProps: PublicOverrideProps = PublicOverrideProps(),
         semantics: NodeSemantics? = nil,
         content: NodeContent) {
        self.id = id; self.name = name; self.frame = frame
        self.artboardID = artboardID
        self.isVisible = isVisible; self.isLocked = isLocked
        self.rotation = rotation; self.opacity = opacity
        self.effects = effects; self.blendMode = blendMode
        self.autoLayout = autoLayout; self.autoPadding = autoPadding
        self.isAbsoluteInAutoLayout = isAbsoluteInAutoLayout
        self.flipH = flipH; self.flipV = flipV
        self.isMask = isMask; self.isMaskShape = isMaskShape
        self.relationships = relationships
        self.anchoredRelationships = anchoredRelationships
        self.publicProps = publicProps
        self.semantics = semantics
        self.content = content
    }

    // Custom decode so the newer fields (rotation/opacity/effects/blendMode/
    // autoLayout/autoPadding/flip/mask) default cleanly when absent — synthesized
    // Codable would throw on a missing key.
    enum CodingKeys: String, CodingKey {
        case id, name, frame, artboardID, isVisible, isLocked, rotation, opacity, effects, blendMode
        case autoLayout, autoPadding, isAbsoluteInAutoLayout, flipH, flipV, isMask, isMaskShape
        case relationships, anchoredRelationships, publicProps, semantics, content
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        frame = try c.decode(CGRect.self, forKey: .frame)
        artboardID = try c.decodeIfPresent(UUID.self, forKey: .artboardID)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        autoLayout = try c.decodeIfPresent(AutoLayout.self, forKey: .autoLayout)
        autoPadding = try c.decodeIfPresent(AutoPadding.self, forKey: .autoPadding)
        isAbsoluteInAutoLayout = try c.decodeIfPresent(Bool.self,
                                                       forKey: .isAbsoluteInAutoLayout) ?? false
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        isMask = try c.decodeIfPresent(Bool.self, forKey: .isMask) ?? false
        isMaskShape = try c.decodeIfPresent(Bool.self, forKey: .isMaskShape) ?? false
        relationships = ((try? c.decodeIfPresent([NodeRelationship].self, forKey: .relationships)) ?? nil) ?? []
        anchoredRelationships = ((try? c.decodeIfPresent([AnchoredRelationship].self,
                                                         forKey: .anchoredRelationships)) ?? nil) ?? []
        publicProps = try c.decodeIfPresent(PublicOverrideProps.self, forKey: .publicProps) ?? PublicOverrideProps()
        semantics = try c.decodeIfPresent(NodeSemantics.self, forKey: .semantics)
        content = try c.decode(NodeContent.self, forKey: .content)
    }
}

/// A relationship stored at its ANCHOR — the nearest node containing BOTH ends —
/// rather than on the subject.
///
/// This is the shape FEAT-012 exists to reach. A relationship kept on the subject
/// node breaks the moment the subject lives inside a component: everything stored
/// in a source applies to every PLACEMENT of that source, so all placements would
/// point at the same target. Anchoring it above both ends fixes that by
/// construction — place the anchor twice and each copy resolves its own ends,
/// with no cross-placement leak and no colliding DOM ids.
///
/// `subject` may name the anchor ITSELF (for a component's own relationships,
/// where the element carrying the role is the one hosting the instance). That is
/// not a special case in the data — it is just an endpoint whose `nodeID` is the
/// anchor's — and `Document.resolveEndpoint(_:in:anchorID:)` handles it.
struct AnchoredRelationship: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: NodeRelationship.Kind
    /// The end that CARRIES the attribute (the tab, in `tab -> controls -> panel`).
    var subject: RelationshipEndpoint
    /// The end the attribute POINTS AT (the panel).
    var target: RelationshipEndpoint

    init(id: UUID = UUID(), kind: NodeRelationship.Kind,
         subject: RelationshipEndpoint, target: RelationshipEndpoint) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.target = target
    }

    enum CodingKeys: String, CodingKey { case id, kind, subject, target }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(NodeRelationship.Kind.self, forKey: .kind)
        subject = try c.decode(RelationshipEndpoint.self, forKey: .subject)
        target = try c.decode(RelationshipEndpoint.self, forKey: .target)
    }
}

// MARK: - Component behavior contract

/// A typed id-to-id relationship from one node to another. These are the behavior
/// leg of the component contract: ARIA role + relationships imply the WAI-APG
/// interaction pattern on export, without storing brittle JS in the design file.
/// Where one end of a relationship points.
///
/// A layer inside a component has no single identity — it exists once per
/// PLACEMENT, and the DOM id the exporter mints for it is composed from the
/// instance chain above it. A raw node id can therefore only ever name the first
/// placement, which is how two uses of the same component collide. An endpoint is
/// a PATH instead: the instance nodes to descend through, outermost first, then
/// the addressed node.
///
///     RelationshipEndpoint(nodeID: panelInstance)                    // a sibling
///     RelationshipEndpoint(instanceChain: [tabBar], nodeID: tabOne)  // inside a placed component
///
/// FEAT-012 chunk I-a. This type exists BEFORE anything uses the chain, on
/// purpose: every relationship written today has an empty chain and behaves
/// exactly as it did, so the type can land and be verified without moving any
/// storage. See BACKLOG FEAT-012 for the full plan and for why widening the
/// target picker is NOT the fix this replaces.
struct RelationshipEndpoint: Codable, Equatable, Hashable, Sendable {
    /// Component-instance nodes to descend through, OUTERMOST FIRST.
    /// Empty means the addressed node is a plain sibling within the anchor.
    var instanceChain: [UUID] = []
    /// The node actually being addressed. Non-optional by construction, so an
    /// endpoint can never be malformed the way a bare `[UUID]` path could.
    var nodeID: UUID

    init(instanceChain: [UUID] = [], nodeID: UUID) {
        self.instanceChain = instanceChain
        self.nodeID = nodeID
    }

    /// Full path, innermost LAST — the form the exporter and the id minter want.
    var path: [UUID] { instanceChain + [nodeID] }

    /// True when there is nothing to descend through.
    var isDirect: Bool { instanceChain.isEmpty }

    enum CodingKeys: String, CodingKey { case instanceChain, nodeID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceChain = try c.decodeIfPresent([UUID].self, forKey: .instanceChain) ?? []
        nodeID = try c.decode(UUID.self, forKey: .nodeID)
    }
}

struct NodeRelationship: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case controls
        case labelledby
        case describedby

        /// Internal/technical name. Used for undo action names and diagnostics —
        /// NOT as an inspector label. See `friendlyLabel(for:)`; FEAT-011 is
        /// explicit that no ARIA attribute name appears as a primary label.
        var label: String {
            switch self {
            case .controls:    return "Controls"
            case .labelledby:  return "Labelled By"
            case .describedby: return "Described By"
            }
        }

        var ariaAttribute: String {
            switch self {
            case .controls:    return "aria-controls"
            case .labelledby:  return "aria-labelledby"
            case .describedby: return "aria-describedby"
            }
        }

        /// Plain-language PRIMARY label, phrased for the role when we know it
        /// (FEAT-011). The emitted attribute never changes — only the words. The
        /// literal attribute stays discoverable in the help tip and the handoff,
        /// so the mapping is learnable rather than hidden.
        ///
        /// Wording is checked against the WAI-APG pattern for each role so a
        /// rename can never make the field WRONG: a tab controls its panel, a
        /// tabpanel is named by its tab.
        func friendlyLabel(for role: AriaRole?) -> String {
            switch self {
            case .controls:
                switch role {
                case .tab:            return "Opens this panel"
                case .button, .link:  return "Opens or changes"
                case .menuitem, .option: return "Opens or changes"
                default:              return "Operates"
                }
            case .labelledby:
                switch role {
                case .tabpanel:                 return "Named by its tab"
                case .dialog, .alertdialog:     return "Named by its title"
                default:                        return "Gets its name from"
                }
            case .describedby:
                switch role {
                case .textbox, .searchbox, .checkbox, .radio, .switch,
                     .slider, .spinbutton:      return "Helper or error text"
                default:                        return "Extra explanation"
                }
            }
        }

        /// Help-tip body. Explains the relationship in designer terms and names
        /// the attribute LAST, so someone who wants the ARIA token can find it
        /// without it being the thing they must decode first.
        func friendlyHelp(for role: AriaRole?) -> String {
            switch self {
            case .controls:
                let lead = role == .tab
                    ? "Point this at the panel this tab shows."
                    : "Point this at the layer this one opens, closes, or changes."
                return lead + " Exported as \(ariaAttribute)."
            case .labelledby:
                let lead = role == .tabpanel
                    ? "Point this at the tab that names this panel."
                    : "Point this at the visible text a screen reader should read as this layer\u{2019}s name."
                return lead + " Exported as \(ariaAttribute)."
            case .describedby:
                return "Point this at hint, helper, or error text. A screen reader reads it AFTER the name, as extra explanation \u{2014} not as the name itself. Exported as \(ariaAttribute)."
            }
        }

        /// True when ARIA PROHIBITS this property on an element that carries no
        /// role — i.e. one that exports as a plain `<div>` with the implicit
        /// `generic` role.
        ///
        /// Only naming is prohibited there: "Because the generic role is
        /// nameless, the aria-labelledby and aria-label attributes are
        /// prohibited" (MDN, generic role; WAI-ARIA 1.2 5.2.5 Prohibited States
        /// and Properties). `aria-controls` and `aria-describedby` are GLOBAL
        /// properties, valid on every role — they are merely POINTLESS on a
        /// nameless container, which is a quality judgment, not a conformance
        /// one. Do not conflate the two: the UI must not tell anyone that a
        /// description is invalid when it is not.
        /// Verified 2026-07-24 against MDN / WAI-ARIA 1.2 — see BACKLOG BUG-008,
        /// which also records what was NOT verified.
        var isProhibitedWithoutRole: Bool { self == .labelledby }
    }

    var id = UUID()
    var kind: Kind
    var target: RelationshipEndpoint

    /// Compatibility accessor for every call site that predates FEAT-012.
    /// Those all address a sibling by raw id — an endpoint with an empty chain —
    /// so this stays exact for them, and for a deeper endpoint it returns the
    /// addressed node, which is the right answer for anything asking "what does
    /// this point AT." Writing through it resets the chain, because a raw id
    /// cannot express one; that is deliberate, not a lossy accident.
    var targetID: UUID {
        get { target.nodeID }
        set { target = RelationshipEndpoint(nodeID: newValue) }
    }

    init(id: UUID = UUID(), kind: Kind, target: RelationshipEndpoint) {
        self.id = id
        self.kind = kind
        self.target = target
    }

    init(id: UUID = UUID(), kind: Kind, targetID: UUID) {
        self.init(id: id, kind: kind, target: RelationshipEndpoint(nodeID: targetID))
    }

    enum CodingKeys: String, CodingKey { case id, kind, targetID, target }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        // `target` is the v2.1 form; `targetID` is every file written before it,
        // where a relationship could only ever address a sibling. A legacy id
        // becomes an endpoint with an empty instance chain, which resolves and
        // exports identically — so old documents are not merely readable, they
        // behave the same.
        if let endpoint = try c.decodeIfPresent(RelationshipEndpoint.self, forKey: .target) {
            target = endpoint
        } else {
            target = RelationshipEndpoint(nodeID: try c.decode(UUID.self, forKey: .targetID))
        }
    }

    /// Writes BOTH forms. `targetID` is redundant for anything this build reads,
    /// but it keeps a v2.1 file openable by a v2.0 build — which degrades to the
    /// sibling behavior rather than failing to decode the document at all. Cheap
    /// insurance; drop it only once no shipped build reads `targetID`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(target, forKey: .target)
        try c.encode(target.nodeID, forKey: .targetID)
    }
}

/// Per-field public prop flags for the bounded override vocabulary. Today the
/// overrideable fields are text and fill; adding stroke or other override kinds
/// later extends this struct without changing existing files.
struct PublicOverrideProps: Codable, Equatable, Sendable {
    var text: Bool = false
    var fill: Bool = false

    init(text: Bool = false, fill: Bool = false) {
        self.text = text
        self.fill = fill
    }

    enum CodingKeys: String, CodingKey { case text, fill }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(Bool.self, forKey: .text) ?? false
        fill = try c.decodeIfPresent(Bool.self, forKey: .fill) ?? false
    }

    var isEmpty: Bool { !text && !fill }
}

/// Stacking settings for a `.group` node (Figma-style "auto layout" — the
/// spacing/arrangement half). When present, the group arranges its children along
/// one axis with a gap or even distribution and a cross-axis alignment. Padding
/// and the frame background live separately in `AutoPadding`, so the two can be
/// used independently or together.
///
/// Geometry note: children are laid out in the group's LOCAL space (origin at the
/// group's top-left, matching how `.group` renders children at `frame.origin`).
/// Items are ordered by their on-canvas position along the axis, so dragging one
/// past another reorders the stack.
struct AutoLayout: Codable, Equatable, Sendable {
    enum Direction: String, Codable, Sendable { case horizontal, vertical }
    /// How items are spaced along the primary (layout) axis.
    enum Distribution: String, Codable, Sendable {
        case packed        // fixed `gap` between items, grouped by `primary` alignment
        case spaceBetween  // first/last pinned to edges, equal gaps fill the rest
    }
    /// Alignment along an axis (start = left/top, end = right/bottom).
    enum Align: String, Codable, Sendable { case start, center, end }

    var direction: Direction = .horizontal
    var distribution: Distribution = .packed
    var gap: CGFloat = 8            // used when distribution == .packed
    /// Primary-axis grouping for `.packed` (ignored for `.spaceBetween`).
    var primary: Align = .start
    /// Cross-axis alignment of each item (e.g. vertical centering in a row).
    var cross: Align = .center

    init() {}

    enum CodingKeys: String, CodingKey { case direction, distribution, gap, primary, cross }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .horizontal
        distribution = try c.decodeIfPresent(Distribution.self, forKey: .distribution) ?? .packed
        gap = try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? 8
        primary = try c.decodeIfPresent(Align.self, forKey: .primary) ?? .start
        cross = try c.decodeIfPresent(Align.self, forKey: .cross) ?? .center
    }
}

/// Padding settings for a `.group` node — the "hug your contents with padding and
/// a background" half. When present, the group hugs its children with per-side
/// padding and can draw its own background (fill/corner/stroke) BEHIND them. This
/// is what makes a button / tag / card: a padded surface around content. Works on
/// its own (pads around the children's current arrangement) or alongside
/// `AutoLayout` (which supplies the arrangement; padding insets it).
struct AutoPadding: Codable, Equatable, Sendable {
    // CSS box model. Inside → out:
    //   content (children)  →  PADDING  →  background box (fill/stroke)  →  MARGIN  →  frame edge
    // Padding is the gap between the content and the background-box edge; the
    // background grows with it. Margin is transparent space OUTSIDE the background.
    var paddingTop: CGFloat = 8
    var paddingRight: CGFloat = 12
    var paddingBottom: CGFloat = 8
    var paddingLeft: CGFloat = 12

    var marginTop: CGFloat = 0
    var marginRight: CGFloat = 0
    var marginBottom: CGFloat = 0
    var marginLeft: CGFloat = 0

    // The background, drawn at the PADDING box (frame inset by the margin).
    // nil fill = transparent.
    var fill: Paint? = nil
    var cornerRadius: CGFloat = 0
    var stroke: RGBAColor? = nil
    var strokeWidth: CGFloat = 0
    var strokeAlignment: StrokeAlignment = .center
    var strokePattern: StrokePattern = .solid

    init() {}

    enum CodingKeys: String, CodingKey {
        case paddingTop, paddingRight, paddingBottom, paddingLeft
        case marginTop, marginRight, marginBottom, marginLeft
        case fill, cornerRadius, stroke, strokeWidth, strokeAlignment, strokePattern
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paddingTop = try c.decodeIfPresent(CGFloat.self, forKey: .paddingTop) ?? 8
        paddingRight = try c.decodeIfPresent(CGFloat.self, forKey: .paddingRight) ?? 12
        paddingBottom = try c.decodeIfPresent(CGFloat.self, forKey: .paddingBottom) ?? 8
        paddingLeft = try c.decodeIfPresent(CGFloat.self, forKey: .paddingLeft) ?? 12
        marginTop = try c.decodeIfPresent(CGFloat.self, forKey: .marginTop) ?? 0
        marginRight = try c.decodeIfPresent(CGFloat.self, forKey: .marginRight) ?? 0
        marginBottom = try c.decodeIfPresent(CGFloat.self, forKey: .marginBottom) ?? 0
        marginLeft = try c.decodeIfPresent(CGFloat.self, forKey: .marginLeft) ?? 0
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill)
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke)
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paddingTop, forKey: .paddingTop); try c.encode(paddingRight, forKey: .paddingRight)
        try c.encode(paddingBottom, forKey: .paddingBottom); try c.encode(paddingLeft, forKey: .paddingLeft)
        try c.encode(marginTop, forKey: .marginTop); try c.encode(marginRight, forKey: .marginRight)
        try c.encode(marginBottom, forKey: .marginBottom); try c.encode(marginLeft, forKey: .marginLeft)
        try c.encodeIfPresent(fill, forKey: .fill); try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encodeIfPresent(stroke, forKey: .stroke); try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeAlignment, forKey: .strokeAlignment)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
    }

    var marginW: CGFloat { marginLeft + marginRight }
    var marginH: CGFloat { marginTop + marginBottom }
}

/// Whole-layer blend mode — how a node composites with everything beneath it.
/// Maps to `CGBlendMode` for drawing and CSS `mix-blend-mode` for SVG export.
enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn: return "Color Burn"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .color: return "Color"
        case .luminosity: return "Luminosity"
        }
    }

    var cg: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        }
    }

    /// CSS `mix-blend-mode` value for SVG export.
    var cssName: String {
        switch self {
        case .colorDodge: return "color-dodge"
        case .colorBurn:  return "color-burn"
        case .softLight:  return "soft-light"
        case .hardLight:  return "hard-light"
        default:          return rawValue
        }
    }
}

// MARK: - Layer style (copy/paste appearance)

/// The portable "look" of a layer — everything Copy Style carries from one node
/// to another: its post-composite effects, how it blends with what's beneath it,
/// and its whole-layer transparency. Appearance ONLY: it deliberately leaves
/// geometry, fill/stroke, and content untouched (matching how every other tool
/// treats "paste style"). Codable/Sendable so it could also ride a pasteboard
/// later if cross-document copy is wanted.
struct LayerStyle: Codable, Sendable {
    var opacity: Double
    var blendMode: BlendMode
    var effects: [Effect]
}

extension Node {
    /// This node's copyable appearance (effects + blend mode + opacity).
    var layerStyle: LayerStyle {
        LayerStyle(opacity: opacity, blendMode: blendMode, effects: effects)
    }

    /// Overwrite this node's appearance with a copied `LayerStyle`. Effects get
    /// FRESH ids so each target owns its own copies (ids stay unique per node for
    /// the inspector's `ForEach`); geometry / fill / content are left as-is.
    mutating func applyLayerStyle(_ style: LayerStyle) {
        opacity = style.opacity
        blendMode = style.blendMode
        effects = style.effects.map { var e = $0; e.id = UUID(); return e }
    }
}

// MARK: - Effects

/// A post-composite visual effect on a node. Drop + inner shadow mirror CSS
/// `box-shadow` (offset x/y, blur, spread). Layer blur mirrors SVG
/// `feGaussianBlur` on SourceGraphic. Noise + dissolve are procedural
/// texture effects whose parameters deliberately mirror SVG `<feTurbulence>`
/// (type / baseFrequency / numOctaves / seed) so the canvas render and the SVG
/// export share one spec'd algorithm (see `TurbulenceNoise`):
///   • noise    — turbulence composited over the node's own pixels, clipped to
///                its silhouette, with a per-effect blend mode + amount. Stack
///                several (different frequencies/blends) to build up texture.
///   • dissolve — the same turbulence thresholded at `amount` and used as an
///                alpha mask: the classic scattered-pixel dissolve. Frequency
///                sets clump size; amount is the fraction dissolved away.
struct Effect: Identifiable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case dropShadow, innerShadow, layerBlur, backgroundBlur, noise, dissolve
    }
    /// SVG `feTurbulence type=` — fractalNoise is smoother (signed octaves
    /// averaged around mid-gray, ideal for grain overlays); turbulence takes
    /// |noise| per octave (billowy, marble-like).
    enum TurbulenceType: String, Codable, Sendable { case fractalNoise, turbulence }
    var id = UUID()
    var kind: Kind = .dropShadow
    var color: RGBAColor = RGBAColor(r: 0, g: 0, b: 0, a: 0.33)
    var dx: CGFloat = 0
    var dy: CGFloat = 2
    var blur: CGFloat = 4
    var spread: CGFloat = 0
    var isEnabled: Bool = true
    /// Drop shadow only: when true, the shadow is knocked out from behind the
    /// object, so a semi-transparent fill no longer sits on its own shadow and
    /// go muddy/black. Default false = legacy behavior (shadow visible through
    /// transparency), so existing documents render unchanged.
    var preserveTransparency: Bool = false
    // Noise / dissolve (ignored by the shadow kinds). Defaults chosen so a
    // freshly added effect is immediately visible.
    var turbulenceType: TurbulenceType = .fractalNoise
    var frequency: CGFloat = 0.9   // feTurbulence baseFrequency, per model point
    var octaves: Int = 4           // feTurbulence numOctaves (1...8)
    var seed: Int = 0              // feTurbulence seed
    var monochrome: Bool = true    // grayscale grain vs independent RGB channels
    var amount: CGFloat = 0.35     // noise: overlay opacity 0–1; dissolve: fraction gone 0–1
    var blend: BlendMode = .normal // per-effect blend (noise only; node blend is separate)

    nonisolated init(id: UUID = UUID(), kind: Kind = .dropShadow,
         color: RGBAColor = RGBAColor(r: 0, g: 0, b: 0, a: 0.33),
         dx: CGFloat = 0, dy: CGFloat = 2, blur: CGFloat = 4, spread: CGFloat = 0,
         isEnabled: Bool = true, preserveTransparency: Bool = false,
         turbulenceType: TurbulenceType = .fractalNoise, frequency: CGFloat = 0.9,
         octaves: Int = 4, seed: Int = 0, monochrome: Bool = true,
         amount: CGFloat = 0.35, blend: BlendMode = .normal) {
        self.id = id; self.kind = kind; self.color = color
        self.dx = dx; self.dy = dy; self.blur = blur; self.spread = spread
        self.isEnabled = isEnabled; self.preserveTransparency = preserveTransparency
        self.turbulenceType = turbulenceType; self.frequency = frequency
        self.octaves = octaves; self.seed = seed; self.monochrome = monochrome
        self.amount = amount; self.blend = blend
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .dropShadow
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? RGBAColor(r: 0, g: 0, b: 0, a: 0.33)
        dx = try c.decodeIfPresent(CGFloat.self, forKey: .dx) ?? 0
        dy = try c.decodeIfPresent(CGFloat.self, forKey: .dy) ?? 2
        blur = try c.decodeIfPresent(CGFloat.self, forKey: .blur) ?? 4
        spread = try c.decodeIfPresent(CGFloat.self, forKey: .spread) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        preserveTransparency = try c.decodeIfPresent(Bool.self, forKey: .preserveTransparency) ?? false
        turbulenceType = try c.decodeIfPresent(TurbulenceType.self, forKey: .turbulenceType) ?? .fractalNoise
        frequency = try c.decodeIfPresent(CGFloat.self, forKey: .frequency) ?? 0.9
        octaves = try c.decodeIfPresent(Int.self, forKey: .octaves) ?? 4
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        monochrome = try c.decodeIfPresent(Bool.self, forKey: .monochrome) ?? true
        amount = try c.decodeIfPresent(CGFloat.self, forKey: .amount) ?? 0.35
        blend = try c.decodeIfPresent(BlendMode.self, forKey: .blend) ?? .normal
    }
}

/// What a node actually is. Swift synthesises Codable for enums with labeled
/// associated values, so this stays declarative. Phase 3 fleshes out the shape
/// payloads; Phase 4 starts editing `.instance`.
enum NodeContent: Codable, Sendable {
    case group(children: [Node])
    case rectangle(RectangleShape)
    case ellipse(EllipseShape)
    case polygon(PolygonShape)
    case line(LineShape)
    case path(PathShape)
    case text(TextContent)
    case instance(ComponentInstance)
    case image(ImageContent)
}

/// A placed raster image (PNG/JPEG/GIF/…). The bytes live in the document (base64
/// in the JSON), so a `.design` file is self-contained. The image is drawn to
/// fill the node's frame; `naturalSize` is its intrinsic pixel size (for aspect).
struct ImageContent: Codable, Sendable {
    var data: Data
    var naturalSize: CGSize
}

// MARK: - Shape payloads

/// Per-corner radii for a rectangle (v1.3 "advanced corners"). The DEFAULT
/// remains one uniform `cornerRadius` on the shape — this struct only exists
/// on a rectangle once the designer opens Advanced and diverges a corner, and
/// it collapses back to nil the moment all four match again (so the simple
/// field keeps working with zero extra actions, per the owner's spec).
/// Corner names are visual (y-down document space): topLeft = min-x/min-y.
struct CornerRadii: Codable, Equatable, Sendable {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomRight: CGFloat = 0
    var bottomLeft: CGFloat = 0

    init(topLeft: CGFloat = 0, topRight: CGFloat = 0,
         bottomRight: CGFloat = 0, bottomLeft: CGFloat = 0) {
        self.topLeft = max(0, topLeft); self.topRight = max(0, topRight)
        self.bottomRight = max(0, bottomRight); self.bottomLeft = max(0, bottomLeft)
    }
    init(all r: CGFloat) { self.init(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

    var isUniform: Bool { topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft }
    var isZero: Bool { topLeft == 0 && topRight == 0 && bottomRight == 0 && bottomLeft == 0 }

    func scaled(by s: CGFloat) -> CornerRadii {
        CornerRadii(topLeft: topLeft * s, topRight: topRight * s,
                    bottomRight: bottomRight * s, bottomLeft: bottomLeft * s)
    }
    /// Grow/shrink every radius (spread, stroke offsets); clamps at 0.
    func offset(by d: CGFloat) -> CornerRadii {
        CornerRadii(topLeft: max(0, topLeft + d), topRight: max(0, topRight + d),
                    bottomRight: max(0, bottomRight + d), bottomLeft: max(0, bottomLeft + d))
    }
    /// CSS overlap rule: if two adjacent radii overflow their shared edge, scale
    /// ALL radii by the worst ratio so arcs never cross.
    func clamped(to size: CGSize) -> CornerRadii {
        var f: CGFloat = 1
        func limit(_ a: CGFloat, _ b: CGFloat, _ edge: CGFloat) {
            let sum = a + b
            if sum > edge, sum > 0 { f = Swift.min(f, edge / sum) }
        }
        limit(topLeft, topRight, size.width)
        limit(bottomLeft, bottomRight, size.width)
        limit(topLeft, bottomLeft, size.height)
        limit(topRight, bottomRight, size.height)
        return f < 1 ? scaled(by: f) : self
    }

    /// The rounded-rect outline (CoreGraphics only — safe for the shared
    /// model target). `scale` multiplies the radii first (view = doc × zoom).
    func path(in rect: CGRect, scale: CGFloat = 1) -> CGPath {
        let c = scaled(by: scale).clamped(to: rect.size)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX + c.topLeft, y: rect.minY))
        if c.topRight > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: c.topRight)
        } else { p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)) }
        if c.bottomRight > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: c.bottomRight)
        } else { p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) }
        if c.bottomLeft > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: c.bottomLeft)
        } else { p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) }
        if c.topLeft > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: c.topLeft)
        } else { p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)) }
        p.closeSubpath()
        return p
    }

    // Tolerant decode (future fields never break older builds).
    enum CodingKeys: String, CodingKey { case topLeft, topRight, bottomRight, bottomLeft }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topLeft = max(0, try c.decodeIfPresent(CGFloat.self, forKey: .topLeft) ?? 0)
        topRight = max(0, try c.decodeIfPresent(CGFloat.self, forKey: .topRight) ?? 0)
        bottomRight = max(0, try c.decodeIfPresent(CGFloat.self, forKey: .bottomRight) ?? 0)
        bottomLeft = max(0, try c.decodeIfPresent(CGFloat.self, forKey: .bottomLeft) ?? 0)
    }
}

/// Where a stroke sits relative to the shape's edge (v1.3). CSS/SVG only do
/// `center`; EXP renders inside/outside exactly (clip + double-width on
/// canvas/raster; geometry offset or clipPath/mask in the SVG export). Only
/// meaningful on CLOSED outlines — lines and open paths are always centered.
enum StrokeAlignment: String, Codable, Sendable, CaseIterable {
    case center, inside, outside
    var label: String {
        switch self {
        case .center:  return "Center"
        case .inside:  return "Inside"
        case .outside: return "Outside"
        }
    }
    /// How far past the frame the stroke paints, per edge, for width `w` —
    /// drives hit-test tolerance and cull margins.
    func reach(for w: CGFloat) -> CGFloat {
        switch self {
        case .center:  return w / 2
        case .inside:  return 0
        case .outside: return w
        }
    }
}

/// Reusable outline rhythm for lines, open paths, closed-shape borders, and
/// auto-padding group backgrounds. Presets intentionally stay semantic instead
/// of persisting device-specific dash arrays, so dots remain round and readable
/// when stroke width or export scale changes.
enum StrokePattern: String, Codable, Sendable, CaseIterable {
    case solid, dashed, dotted

    var label: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dash"
        case .dotted: return "Dot"
        }
    }
}

/// `strokeWidth == 0` means no stroke (matches a plain filled shape). Custom
/// decoders default the newer stroke fields so older files still open.
struct RectangleShape: Codable, Sendable {
    var fill: Paint = .white
    var cornerRadius: CGFloat = 0
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 0
    var strokeAlignment: StrokeAlignment = .center
    var strokePattern: StrokePattern = .solid
    /// Per-corner radii (v1.3). nil = uniform `cornerRadius` (the default,
    /// simple case). Setting the plain Corner field clears this back to nil.
    var cornerRadii: CornerRadii? = nil

    enum CodingKeys: String, CodingKey {
        case fill, cornerRadius, stroke, strokeWidth, strokeAlignment, strokePattern, cornerRadii
    }

    /// The four radii actually in effect (uniform expands to all corners).
    var effectiveRadii: CornerRadii { cornerRadii ?? CornerRadii(all: cornerRadius) }
    /// True when corners genuinely differ (drives the per-corner render path).
    var hasPerCornerRadii: Bool {
        guard let r = cornerRadii else { return false }
        return !r.isUniform
    }

    init(fill: Paint = .white, cornerRadius: CGFloat = 0,
         stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center, strokePattern: StrokePattern = .solid,
         cornerRadii: CornerRadii? = nil) {
        self.fill = fill; self.cornerRadius = cornerRadius
        self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.strokePattern = strokePattern
        self.cornerRadii = cornerRadii
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
        cornerRadii = try c.decodeIfPresent(CornerRadii.self, forKey: .cornerRadii)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fill, forKey: .fill); try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(stroke, forKey: .stroke); try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeAlignment, forKey: .strokeAlignment)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
        try c.encodeIfPresent(cornerRadii, forKey: .cornerRadii)
    }
}

struct EllipseShape: Codable, Sendable {
    var fill: Paint = .white
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 0
    var strokeAlignment: StrokeAlignment = .center
    var strokePattern: StrokePattern = .solid

    enum CodingKeys: String, CodingKey {
        case fill, stroke, strokeWidth, strokeAlignment, strokePattern
    }

    init(fill: Paint = .white, stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center, strokePattern: StrokePattern = .solid) {
        self.fill = fill; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.strokePattern = strokePattern
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fill, forKey: .fill); try c.encode(stroke, forKey: .stroke)
        try c.encode(strokeWidth, forKey: .strokeWidth); try c.encode(strokeAlignment, forKey: .strokeAlignment)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
    }
}

/// A regular N-sided polygon inscribed in the node's frame (point-up). `sides` is
/// clamped 3...25. Geometry is derived from the frame at render time, so resizing
/// the box reshapes it like rectangle/ellipse.
struct PolygonShape: Codable, Sendable {
    var sides: Int = 3
    var fill: Paint = .white
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 0

    var strokeAlignment: StrokeAlignment = .center
    var strokePattern: StrokePattern = .solid

    enum CodingKeys: String, CodingKey {
        case sides, fill, stroke, strokeWidth, strokeAlignment, strokePattern
    }

    init(sides: Int = 3, fill: Paint = .white, stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center, strokePattern: StrokePattern = .solid) {
        self.sides = Swift.min(25, Swift.max(3, sides))
        self.fill = fill; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.strokePattern = strokePattern
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sides = Swift.min(25, Swift.max(3, try c.decodeIfPresent(Int.self, forKey: .sides) ?? 3))
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sides, forKey: .sides); try c.encode(fill, forKey: .fill)
        try c.encode(stroke, forKey: .stroke); try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeAlignment, forKey: .strokeAlignment)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
    }

    /// Vertices (point-up) inscribed in `rect`, in that rect's coordinate space.
    func vertices(in rect: CGRect) -> [CGPoint] {
        let n = Swift.min(25, Swift.max(3, sides))
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        return (0..<n).map { i in
            let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(n)
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }
}

/// A straight line. Endpoints are in the node's LOCAL space (relative to
/// frame.origin), so moving the node moves the line for free; `frame` is kept as
/// the tight bounding box of the two points.
struct LineShape: Codable, Sendable {
    var start: CGPoint
    var end: CGPoint
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 2
    var strokePattern: StrokePattern = .solid

    enum CodingKeys: String, CodingKey { case start, end, stroke, strokeWidth, strokePattern }
    init(start: CGPoint, end: CGPoint, stroke: RGBAColor = .black,
         strokeWidth: CGFloat = 2, strokePattern: StrokePattern = .solid) {
        self.start = start; self.end = end; self.stroke = stroke
        self.strokeWidth = strokeWidth; self.strokePattern = strokePattern
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
        try c.encode(stroke, forKey: .stroke); try c.encode(strokeWidth, forKey: .strokeWidth)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
    }
}

/// One anchor of a path, in the node's LOCAL space (relative to frame.origin).
/// `controlIn` / `controlOut` are the absolute local positions of the bézier
/// handles; nil means a corner (no curve on that side).
struct PathPoint: Codable, Sendable {
    var point: CGPoint
    var controlIn: CGPoint? = nil
    var controlOut: CGPoint? = nil
}

/// A vector path. Open paths render as a stroked line; closed paths fill.
/// Anchors are LOCAL (like LineShape); `frame` is kept as the anchors' bbox.
///
/// `contours` (optional) holds MULTIPLE closed subpaths filled with the even-odd
/// rule — used by "convert text to shapes" so glyph counters (the hole in an "o")
/// punch through. When present it drives rendering; `points` mirrors the first
/// contour so single-path tools still have something to show.
struct PathShape: Codable, Sendable {
    var points: [PathPoint]
    var closed: Bool = false
    var fill: Paint = .white
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 2
    var strokeAlignment: StrokeAlignment = .center
    var strokePattern: StrokePattern = .solid
    var contours: [[PathPoint]]? = nil

    enum CodingKeys: String, CodingKey {
        case points, closed, fill, stroke, strokeWidth, strokeAlignment, strokePattern, contours
    }

    /// Alignment is only meaningful on a closed outline; open paths render center.
    var effectiveStrokeAlignment: StrokeAlignment {
        (closed || isMultiContour) ? strokeAlignment : .center
    }

    init(points: [PathPoint], closed: Bool = false, fill: Paint = .white,
         stroke: RGBAColor = .black, strokeWidth: CGFloat = 2,
         strokeAlignment: StrokeAlignment = .center, strokePattern: StrokePattern = .solid,
         contours: [[PathPoint]]? = nil) {
        self.points = points; self.closed = closed; self.fill = fill
        self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.strokePattern = strokePattern
        self.contours = contours
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([PathPoint].self, forKey: .points)
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        strokePattern = try c.decodeIfPresent(StrokePattern.self, forKey: .strokePattern) ?? .solid
        contours = try c.decodeIfPresent([[PathPoint]].self, forKey: .contours)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points); try c.encode(closed, forKey: .closed)
        try c.encode(fill, forKey: .fill); try c.encode(stroke, forKey: .stroke)
        try c.encode(strokeWidth, forKey: .strokeWidth); try c.encode(strokeAlignment, forKey: .strokeAlignment)
        if strokePattern != .solid { try c.encode(strokePattern, forKey: .strokePattern) }
        try c.encodeIfPresent(contours, forKey: .contours)
    }

    /// Anchors for a rounded rectangle in LOCAL space (v1.3 — fixes "convert
    /// to path drops the corner radius"). Each rounded corner becomes two
    /// anchors whose handles trace the standard κ ≈ 0.5523 quarter-circle
    /// approximation; a zero corner stays one plain anchor. Clockwise from
    /// the top-left, matching the un-rounded conversion's winding.
    static func roundedRectPoints(size: CGSize, radii: CornerRadii) -> [PathPoint] {
        let w = size.width, h = size.height
        let c = radii.clamped(to: size)
        let k: CGFloat = 0.5522847498   // circle-to-bézier constant
        var pts: [PathPoint] = []
        // Top-left
        if c.topLeft > 0 {
            let r = c.topLeft
            pts.append(PathPoint(point: CGPoint(x: 0, y: r), controlOut: CGPoint(x: 0, y: r * (1 - k))))
            pts.append(PathPoint(point: CGPoint(x: r, y: 0), controlIn: CGPoint(x: r * (1 - k), y: 0)))
        } else { pts.append(PathPoint(point: .zero)) }
        // Top-right
        if c.topRight > 0 {
            let r = c.topRight
            pts.append(PathPoint(point: CGPoint(x: w - r, y: 0), controlOut: CGPoint(x: w - r * (1 - k), y: 0)))
            pts.append(PathPoint(point: CGPoint(x: w, y: r), controlIn: CGPoint(x: w, y: r * (1 - k))))
        } else { pts.append(PathPoint(point: CGPoint(x: w, y: 0))) }
        // Bottom-right
        if c.bottomRight > 0 {
            let r = c.bottomRight
            pts.append(PathPoint(point: CGPoint(x: w, y: h - r), controlOut: CGPoint(x: w, y: h - r * (1 - k))))
            pts.append(PathPoint(point: CGPoint(x: w - r, y: h), controlIn: CGPoint(x: w - r * (1 - k), y: h)))
        } else { pts.append(PathPoint(point: CGPoint(x: w, y: h))) }
        // Bottom-left
        if c.bottomLeft > 0 {
            let r = c.bottomLeft
            pts.append(PathPoint(point: CGPoint(x: r, y: h), controlOut: CGPoint(x: r * (1 - k), y: h)))
            pts.append(PathPoint(point: CGPoint(x: 0, y: h - r), controlIn: CGPoint(x: 0, y: h - r * (1 - k))))
        } else { pts.append(PathPoint(point: CGPoint(x: 0, y: h))) }
        return pts
    }

    /// All contours to render: the multi-contour set if present, else the single
    /// `points` contour. Each is treated as closed when filling.
    var renderContours: [[PathPoint]] {
        if let contours, !contours.isEmpty { return contours }
        return points.isEmpty ? [] : [points]
    }
    var isMultiContour: Bool { (contours?.isEmpty == false) }

    // MARK: Point editing across contours
    //
    // Single-contour paths edit `points`; multi-contour (outlined-text) paths edit
    // every contour. These helpers give both a uniform (contour, index) address so
    // the Edit-Points tool can touch *all* shapes in a glyph, not just the first.

    /// Contours for editing/hit-testing: the multi set, or `points` as one contour.
    var editContours: [[PathPoint]] { isMultiContour ? (contours ?? []) : [points] }

    /// Whether the contour at `c` is closed (outlined glyphs are always closed).
    func contourClosed(_ c: Int) -> Bool { isMultiContour ? true : closed }

    func editPoint(contour c: Int, index i: Int) -> PathPoint? {
        let cs = editContours
        guard cs.indices.contains(c), cs[c].indices.contains(i) else { return nil }
        return cs[c][i]
    }

    /// Mutate one anchor, writing back to `contours` (multi) or `points` (single),
    /// keeping `points` mirrored to the first contour either way.
    mutating func mutatePoint(contour c: Int, index i: Int, _ change: (inout PathPoint) -> Void) {
        var cs = editContours
        guard cs.indices.contains(c), cs[c].indices.contains(i) else { return }
        change(&cs[c][i])
        writeEditContours(cs)
    }

    /// Replace all edit contours (keeping `points` = first contour).
    mutating func writeEditContours(_ cs: [[PathPoint]]) {
        if isMultiContour { contours = cs; points = cs.first ?? [] }
        else { points = cs.first ?? [] }
    }
}

/// One styled span of text. `fontName` is a PostScript face ("" = system); bold/
/// italic are captured by the face. `underline` is its own attribute.
struct TextRun: Codable, Equatable, Sendable {
    var string: String
    var fontName: String = ""
    var fontSize: CGFloat = 16
    var color: RGBAColor = .black
    var underline: Bool = false
    /// Optional destination for an imported inline link. Keeping this on the run
    /// preserves one manageable rich-text box instead of overlapping link/text
    /// nodes, and semantic HTML export can reconstruct the anchor.
    var linkURL: String? = nil

    init(string: String, fontName: String = "", fontSize: CGFloat = 16,
         color: RGBAColor = .black, underline: Bool = false,
         linkURL: String? = nil) {
        self.string = string; self.fontName = fontName; self.fontSize = fontSize
        self.color = color; self.underline = underline; self.linkURL = linkURL
    }
}

enum TextAlign: String, Codable, Sendable { case left, center, right }
/// `auto` grows to fit one line; `fixed` wraps to a set width (Build 2).
enum TextBox: String, Codable, Sendable { case auto, fixed }

/// CSS-style line-height units. `auto` = the font's natural leading; `multiple`
/// = unitless (relative to text size, the CSS favorite); `px` = absolute points;
/// `em` = multiple of the (first run's) font size.
enum LineHeightUnit: String, Codable, Sendable { case auto, multiple, px, em }

/// CSS `text-transform`, applied **non-destructively** at display/measure/export
/// time — the stored run text is never altered, so toggling back to `none`
/// restores the original casing exactly.
enum TextCase: String, Codable, Sendable {
    case none, upper, lower, sentence, title

    /// Transform a string for display. `sentence` capitalizes the first letter of
    /// each sentence; `title` capitalizes each word (CSS-ish capitalize).
    func apply(_ s: String) -> String {
        switch self {
        case .none:  return s
        case .upper: return s.localizedUppercase
        case .lower: return s.localizedLowercase
        case .title: return s.localizedCapitalized
        case .sentence:
            var result = ""
            var capitalizeNext = true
            for ch in s {
                if capitalizeNext, ch.isLetter {
                    result += String(ch).localizedUppercase
                    capitalizeNext = false
                } else {
                    result.append(ch)
                    if ch == "." || ch == "!" || ch == "?" || ch == "\n" { capitalizeNext = true }
                }
            }
            return result
        }
    }
}

/// What the words *are* in the page hierarchy, independent of how they look.
/// Type Styles remain reusable presentation; this value is the native HTML
/// contract used by semantic handoff.
enum TextContentRole: String, Codable, CaseIterable, Sendable {
    case plain
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6

    var friendlyLabel: String {
        switch self {
        case .plain:     return "Plain text"
        case .paragraph: return "Paragraph"
        case .heading1:  return "Heading 1"
        case .heading2:  return "Heading 2"
        case .heading3:  return "Heading 3"
        case .heading4:  return "Heading 4"
        case .heading5:  return "Heading 5"
        case .heading6:  return "Heading 6"
        }
    }

    var htmlTag: String {
        switch self {
        case .plain:     return "span"
        case .paragraph: return "p"
        case .heading1:  return "h1"
        case .heading2:  return "h2"
        case .heading3:  return "h3"
        case .heading4:  return "h4"
        case .heading5:  return "h5"
        case .heading6:  return "h6"
        }
    }

    var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        case .plain, .paragraph: return nil
        }
    }
}

/// Rich text: a list of styled runs plus paragraph-level settings. Backward
/// compatible — older single-style text (`{string,fontSize,color,fontName}`)
/// decodes into one run.
struct TextContent: Codable, Sendable {
    var runs: [TextRun]
    var align: TextAlign = .left
    var lineHeight: CGFloat = 1.3       // value; meaning depends on lineHeightUnit
    var lineHeightUnit: LineHeightUnit = .auto
    var tracking: CGFloat = 0           // letter spacing in points
    var box: TextBox = .auto
    var textCase: TextCase = .none      // non-destructive CSS text-transform
    var contentRole: TextContentRole = .plain
    /// New text uses CSS-style centered leading for fixed px/em line boxes.
    /// Older saved documents decode this as false so the v2.2 correction does
    /// not silently move typography authored against TextKit's legacy baseline.
    var centersFixedLineHeightLeading: Bool = true

    /// Legacy-shaped initializer (one run) so existing call sites keep working.
    init(string: String = "", fontSize: CGFloat = 16, color: RGBAColor = .black, fontName: String = "") {
        runs = [TextRun(string: string, fontName: fontName, fontSize: fontSize, color: color)]
    }
    init(runs: [TextRun], align: TextAlign = .left, lineHeight: CGFloat = 1.3,
         lineHeightUnit: LineHeightUnit = .auto, tracking: CGFloat = 0, box: TextBox = .auto,
         textCase: TextCase = .none, contentRole: TextContentRole = .plain,
         centersFixedLineHeightLeading: Bool = true) {
        self.runs = runs.isEmpty ? [TextRun(string: "")] : runs
        self.align = align; self.lineHeight = lineHeight; self.lineHeightUnit = lineHeightUnit
        self.tracking = tracking; self.box = box; self.textCase = textCase
        self.contentRole = contentRole
        self.centersFixedLineHeightLeading = centersFixedLineHeightLeading
    }

    // MARK: convenience

    var plainString: String { runs.map(\.string).joined() }
    var isEmpty: Bool { plainString.isEmpty }
    var firstRun: TextRun { runs.first ?? TextRun(string: "") }

    /// The value to show in the inspector, or nil = "Multiple".
    var uniformFontSize: CGFloat? { let v = Set(runs.map { $0.fontSize }); return v.count == 1 ? v.first : nil }
    var uniformFontName: String? { let v = Set(runs.map { $0.fontName }); return v.count == 1 ? v.first : nil }
    var uniformColorKey: String? {
        let keys = Set(runs.map { "\($0.color.r),\($0.color.g),\($0.color.b),\($0.color.a)" })
        return keys.count == 1 ? keys.first : nil
    }

    /// Replace all text with a single run, keeping the first run's styling.
    mutating func setPlainString(_ s: String) {
        let a = firstRun
        runs = [TextRun(string: s, fontName: a.fontName, fontSize: a.fontSize, color: a.color, underline: a.underline)]
    }
    mutating func applyToAllRuns(_ change: (inout TextRun) -> Void) {
        for i in runs.indices { change(&runs[i]) }
    }

    // MARK: Codable (decode legacy single-style; encode runs + paragraph props)

    enum CodingKeys: String, CodingKey {
        case runs, align, lineHeight, lineHeightUnit, tracking, box, textCase, contentRole
        case centersFixedLineHeightLeading
        case string, fontName, fontSize, color   // legacy
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try? c.decode([TextRun].self, forKey: .runs), !r.isEmpty {
            runs = r
        } else {
            let s = (try? c.decode(String.self, forKey: .string)) ?? ""
            let fn = (try? c.decode(String.self, forKey: .fontName)) ?? ""
            let fs = (try? c.decode(CGFloat.self, forKey: .fontSize)) ?? 16
            let col = (try? c.decode(RGBAColor.self, forKey: .color)) ?? .black
            runs = [TextRun(string: s, fontName: fn, fontSize: fs, color: col)]
        }
        align = (try? c.decode(TextAlign.self, forKey: .align)) ?? .left
        lineHeight = (try? c.decode(CGFloat.self, forKey: .lineHeight)) ?? 1.3
        lineHeightUnit = (try? c.decode(LineHeightUnit.self, forKey: .lineHeightUnit)) ?? .auto
        tracking = (try? c.decode(CGFloat.self, forKey: .tracking)) ?? 0
        box = (try? c.decode(TextBox.self, forKey: .box)) ?? .auto
        textCase = (try? c.decode(TextCase.self, forKey: .textCase)) ?? .none
        // Missing or future/unknown values stay readable as plain text.
        contentRole = (try? c.decode(TextContentRole.self, forKey: .contentRole)) ?? .plain
        centersFixedLineHeightLeading = (try? c.decode(
            Bool.self, forKey: .centersFixedLineHeightLeading)) ?? false
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(runs, forKey: .runs)
        try c.encode(align, forKey: .align)
        try c.encode(lineHeight, forKey: .lineHeight)
        try c.encode(lineHeightUnit, forKey: .lineHeightUnit)
        try c.encode(tracking, forKey: .tracking)
        try c.encode(box, forKey: .box)
        try c.encode(textCase, forKey: .textCase)
        try c.encode(contentRole, forKey: .contentRole)
        try c.encode(centersFixedLineHeightLeading,
                     forKey: .centersFixedLineHeightLeading)
    }
}

// MARK: - Components (reference-based; edited in Phase 4)

/// A reusable definition — the single source of truth for its instances, which
/// reference it by `id` and never copy it (change the source, every instance
/// updates). `children` are stored in source-local coordinates (origin 0,0) so
/// the source editor's canvas can treat them exactly like a document's nodes.
struct ComponentSource: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    /// The component's viewBox ORIGIN in source-local coordinates (SVG min-x/min-y).
    /// Together with `size` it forms the bounds the source editor shows and that an
    /// instance renders. Defaults to .zero so older files (size-only) keep working.
    var origin: CGPoint = .zero
    var size: CGSize
    var children: [Node]

    /// Accessibility semantics (Phase 19a). Day one this is the component's
    /// CATEGORY — an ARIA role used as an organizing filter. Underneath, the
    /// same choice anchors accessible code export later. Defaults empty so
    /// every legacy `.design`/`.exp` file opens unchanged.
    var a11y: A11ySemantics = A11ySemantics()

    /// Named states (v1.6 Chunk H): hover, pressed, focus, disabled, plus
    /// custom (open/selected/error…). Each is an override-diff against the
    /// base — the SAME diff structure instances use — so states can export as
    /// CSS pseudo-classes / `data-state` without ever storing implementations.
    /// Defaults empty so every schemaVersion-1 file opens unchanged.
    var states: [ComponentState] = []

    /// Relationships anchored at the SOURCE — links between this component's own
    /// children, and the component's own links where the subject names the source
    /// itself. The source is the outermost anchor available inside a component;
    /// anything needing a wider one belongs on a group out in the document.
    /// FEAT-012 chunk I-b. Not read yet; see `Node.anchoredRelationships`.
    var anchoredRelationships: [AnchoredRelationship] = []

    /// The component's viewBox — what an instance renders, like an SVG viewBox.
    var bounds: CGRect { CGRect(origin: origin, size: size) }

    init(id: UUID = UUID(), name: String, origin: CGPoint = .zero,
         size: CGSize, children: [Node], a11y: A11ySemantics = A11ySemantics(),
         states: [ComponentState] = [],
         anchoredRelationships: [AnchoredRelationship] = []) {
        self.id = id; self.name = name; self.origin = origin
        self.size = size; self.children = children; self.a11y = a11y
        self.states = states
        self.anchoredRelationships = anchoredRelationships
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        origin = try c.decodeIfPresent(CGPoint.self, forKey: .origin) ?? .zero
        size = try c.decode(CGSize.self, forKey: .size)
        children = try c.decode([Node].self, forKey: .children)
        a11y = try c.decodeIfPresent(A11ySemantics.self, forKey: .a11y) ?? A11ySemantics()
        states = try c.decodeIfPresent([ComponentState].self, forKey: .states) ?? []
        anchoredRelationships = ((try? c.decodeIfPresent([AnchoredRelationship].self,
                                                         forKey: .anchoredRelationships)) ?? nil) ?? []
    }
}

// MARK: - Accessibility semantics (Phase 19a — "the health food in the dessert")

/// Per-component accessibility semantics. Phase 1 surfaces the ROLE only (the
/// component "category"); the accessible-name hook is modeled NOW so export has
/// something real to work with later, even though no UI sets it yet.
///
/// Lives in Document.swift on purpose: `ComponentSource` references it, and this
/// file is shared with the EXPThumbnail extension target (see CLAUDE.md gotcha).
struct A11ySemantics: Codable, Equatable, Sendable {
    /// The component's category. nil = uncategorized. UI shows the friendly
    /// label ("Button"); the model persists the ARIA token ("button").
    var role: AriaRole?
    /// Which child layer supplies the accessible name (wired now, no UI yet).
    var accessibleNameLayerID: UUID?

    /// Relationships authored on the COMPONENT ROOT (BUG-008, v2.1).
    ///
    /// `role` is emitted on the element hosting the INSTANCE, not on anything
    /// inside the source — so the element that actually carries the role was
    /// never selectable from inside the component, and there was no conformant
    /// place to author the component's own links. These live here, on the
    /// source, so they are part of the component CONTRACT: every instance
    /// emits them, and two uses of the same component cannot drift apart.
    ///
    /// Targets are node ids inside this source's own children — resolved
    /// per-instance at export, so each instance points at its own copy.
    var rootRelationships: [NodeRelationship] = []

    // TODO(explore later): required/expressible states per role (aria-checked,
    // aria-selected, …), modeled once a component-state system exists.

    init(role: AriaRole? = nil, accessibleNameLayerID: UUID? = nil,
         rootRelationships: [NodeRelationship] = []) {
        self.role = role
        self.accessibleNameLayerID = accessibleNameLayerID
        self.rootRelationships = rootRelationships
    }

    enum CodingKeys: String, CodingKey {
        case role, accessibleNameLayerID, rootRelationships
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown future tokens decode to nil instead of failing the document.
        role = (try? c.decodeIfPresent(AriaRole.self, forKey: .role)) ?? nil
        accessibleNameLayerID = try c.decodeIfPresent(UUID.self, forKey: .accessibleNameLayerID)
        // Absent in every file written before v2.1 — decode to empty, never fail.
        rootRelationships = ((try? c.decodeIfPresent([NodeRelationship].self,
                                                     forKey: .rootRelationships)) ?? nil) ?? []
    }
}

/// Grouping for the category picker — mirrors how the ARIA spec organizes
/// non-abstract roles a designer actually places.
enum AriaCategory: String, Codable, Sendable, CaseIterable {
    case landmark, widget, composite, structure

    var label: String {
        switch self {
        case .landmark:  return "Landmarks"
        case .widget:    return "Widgets"
        case .composite: return "Composite"
        case .structure: return "Structure"
        }
    }
}

/// A curated, design-relevant subset of non-abstract ARIA roles. Abstract and
/// author-forbidden roles are never offered, so nothing invalid can ever reach
/// export. Raw values ARE the ARIA tokens (what the model persists and what the
/// semantic emitters will write); `friendlyLabel` is what designers see.
enum AriaRole: String, Codable, Sendable, CaseIterable {
    // Landmarks — page regions.
    case banner, navigation, main, complementary, contentinfo, search, form, region
    // Widgets — interactive controls.
    case button, link, checkbox, radio, `switch`, textbox, searchbox, slider,
         spinbutton, progressbar, tooltip
    // Composite — widgets made of parts.
    case tablist, tab, tabpanel, menu, menubar, menuitem, listbox, option,
         radiogroup, toolbar, dialog, alertdialog, alert
    // Composite — hierarchical and tabular widgets (v2.1 Chunk I containment).
    case tree, treeitem, grid
    // Structure — document structure.
    case heading, list, listitem, img, figure, table, separator, group
    // Structure — table/grid parts, so authored tables can own real rows and
    // cells instead of being reported as an unmet `tableStructure` requirement.
    case row, cell, columnheader, rowheader

    /// Designer-friendly display name. Shown in every picker/tag; the raw ARIA
    /// token is what's stored.
    var friendlyLabel: String {
        switch self {
        case .banner:        return "Header (Banner)"
        case .navigation:    return "Navigation"
        case .main:          return "Main Content"
        case .complementary: return "Sidebar (Complementary)"
        case .contentinfo:   return "Footer (Content Info)"
        case .search:        return "Search Area"
        case .form:          return "Form"
        case .region:        return "Region"
        case .button:        return "Button"
        case .link:          return "Link"
        case .checkbox:      return "Checkbox"
        case .radio:         return "Radio Button"
        case .switch:        return "Switch / Toggle"
        case .textbox:       return "Text Field"
        case .searchbox:     return "Search Field"
        case .slider:        return "Slider"
        case .spinbutton:    return "Stepper (Spin Button)"
        case .progressbar:   return "Progress Bar"
        case .tooltip:       return "Tooltip"
        case .tablist:       return "Tab Bar (Tab List)"
        case .tab:           return "Tab"
        case .tabpanel:      return "Tab Panel"
        case .menu:          return "Menu"
        case .menubar:       return "Menu Bar"
        case .menuitem:      return "Menu Item"
        case .listbox:       return "Dropdown List (Listbox)"
        case .option:        return "Dropdown Option"
        case .radiogroup:    return "Radio Group"
        case .toolbar:       return "Toolbar"
        case .dialog:        return "Dialog / Modal"
        case .alertdialog:   return "Alert Dialog"
        case .alert:         return "Alert / Banner Message"
        case .tree:          return "Tree"
        case .treeitem:      return "Tree Item"
        case .grid:          return "Grid (Interactive Table)"
        case .row:           return "Table Row"
        case .cell:          return "Table Cell"
        case .columnheader:  return "Column Header"
        case .rowheader:     return "Row Header"
        case .heading:       return "Heading"
        case .list:          return "List"
        case .listitem:      return "List Item"
        case .img:           return "Image (Non-text)"
        case .figure:        return "Figure"
        case .table:         return "Table"
        case .separator:     return "Divider (Separator)"
        case .group:         return "Group"
        }
    }

    /// One-line "is this the right one?" helper shown next to pickers (v1.3,
    /// owner request: similar options confuse people who don't live in ARIA).
    var blurb: String {
        switch self {
        case .banner:        return "The site-wide top area — logo, product name, global bar. One per page."
        case .navigation:    return "A set of links for moving around — a nav bar, sidebar menu, or breadcrumbs."
        case .main:          return "The page's primary content area. One per page."
        case .complementary: return "Supporting content that stands alone — a sidebar of related info."
        case .contentinfo:   return "The site-wide footer — copyright, legal, footer links. One per page."
        case .search:        return "The region wrapping search — field plus button. (The field itself is a Search Field.)"
        case .form:          return "A region of inputs that submit together. Use for the whole form, not one field."
        case .region:        return "A generic named section when nothing more specific fits. Use sparingly."
        case .button:        return "Triggers an action on the page — save, close, submit. If it navigates somewhere, it's a Link."
        case .link:          return "Navigates somewhere when clicked. If it performs an action instead, it's a Button."
        case .checkbox:      return "On/off choice; multiple can be checked at once. For exactly-one-of-a-set, use Radio."
        case .radio:         return "One choice among several — picking one deselects the others."
        case .switch:        return "An immediate on/off toggle (like Settings). A Checkbox is for forms; a Switch acts instantly."
        case .textbox:       return "A free-typing field — single or multi-line."
        case .searchbox:     return "A text field specifically for typing search queries."
        case .slider:        return "Picks a value from a range by dragging."
        case .spinbutton:    return "A number with increment/decrement steppers."
        case .progressbar:   return "Shows how far along something is. Display-only — not interactive."
        case .tooltip:       return "A small hover/focus bubble describing another element."
        case .tablist:       return "The row of tabs itself (the container). Each tab inside is a Tab."
        case .tab:           return "One clickable tab in a tab bar. The content it reveals is a Tab Panel."
        case .tabpanel:      return "The content area a tab reveals."
        case .menu:          return "A list of actions/commands that pops open. Not for site navigation — that's Navigation."
        case .menubar:       return "A persistent horizontal strip of menus (like an app's menu bar)."
        case .menuitem:      return "One command inside a menu."
        case .listbox:       return "A dropdown/select where the options are its children. Each choice is a Dropdown Option."
        case .option:        return "One selectable choice inside a dropdown list."
        case .radiogroup:    return "The container holding a set of radio buttons."
        case .toolbar:       return "A compact strip of frequently used controls/buttons."
        case .dialog:        return "A window/modal layered over the page that expects interaction."
        case .alertdialog:   return "A dialog that interrupts with something urgent and needs a response."
        case .alert:         return "An important inline message that appears without user action — errors, warnings. Not clickable."
        case .tree:          return "A hierarchy you can expand and collapse — a file tree or nested nav. Each entry is a Tree Item."
        case .treeitem:      return "One entry inside a Tree. It can hold a nested Tree of its own children."
        case .grid:          return "A table you navigate and interact with cell by cell. For data you only read, use Table."
        case .row:           return "One horizontal row inside a Table or Grid. Its cells go inside it."
        case .cell:          return "One piece of data inside a Table Row. If it labels the whole column or row, use a header instead."
        case .columnheader:  return "A cell that labels its entire column."
        case .rowheader:     return "A cell that labels its entire row — usually the first cell in it."
        case .heading:       return "A section title (h1–h6 territory)."
        case .list:          return "The container of a bulleted/numbered set. Each entry is a List Item."
        case .listitem:      return "One entry inside a List."
        case .img:           return "Graphic content that MEANS something (gets alt text). Purely decorative art needs no role."
        case .figure:        return "A self-contained illustration/diagram, often with a caption."
        case .table:         return "Real rows-and-columns data. Don't use for layout."
        case .separator:     return "A visual divider between sections."
        case .group:         return "Related controls that belong together but aren't a full region."
        }
    }

    /// Which picker section this role sits in.
    var ariaCategory: AriaCategory {
        switch self {
        case .banner, .navigation, .main, .complementary, .contentinfo, .search,
             .form, .region:
            return .landmark
        case .button, .link, .checkbox, .radio, .switch, .textbox, .searchbox,
             .slider, .spinbutton, .progressbar, .tooltip:
            return .widget
        case .tablist, .tab, .tabpanel, .menu, .menubar, .menuitem, .listbox,
             .option, .radiogroup, .toolbar, .dialog, .alertdialog, .alert,
             .tree, .treeitem, .grid:
            return .composite
        case .heading, .list, .listitem, .img, .figure, .table, .separator,
             .group, .row, .cell, .columnheader, .rowheader:
            return .structure
        }
    }

    /// What the FAR end of a relationship is normally expected to BE, given this
    /// role on the near end. Empty means the pattern imposes no expectation, which
    /// is the honest answer for most combinations.
    ///
    /// This drives ADVICE, never errors. Pointing somewhere unexpected produces
    /// valid markup — it is only likely to be a mistake, and a reader downstream
    /// (a developer, or a model writing component code) would otherwise get a
    /// plausible-but-wrong structure with nothing flagging it.
    ///
    /// Verified against the WAI-APG Tabs pattern, 2026-07-24
    /// (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/):
    ///   "Each element with role `tab` has the property `aria-controls` referring
    ///    to its associated `tabpanel` element."
    ///   "Each element with role `tabpanel` has the property `aria-labelledby`
    ///    referring to its associated `tab` element."
    /// Only entries with a citation like that belong here. Do NOT add a pairing
    /// because it feels right — an advisory that fires on correct work is worse
    /// than no advisory at all.
    func expectedRelationshipTargetRoles(
        for kind: NodeRelationship.Kind) -> [AriaRole] {
        switch (self, kind) {
        case (.tab, .controls):        return [.tabpanel]
        case (.tabpanel, .labelledby): return [.tab]
        default:                       return []
        }
    }

    /// Relationships that make sense for this role in the component contract.
    /// This guides the authoring UI; existing relationships remain preserved and
    /// editable if a component's role later changes.
    var authoredRelationshipKinds: [NodeRelationship.Kind] {
        switch self {
        case .button, .link, .checkbox, .radio, .switch, .textbox, .searchbox,
             .slider, .spinbutton, .tab, .menuitem, .option:
            return [.controls, .labelledby, .describedby]
        case .navigation, .search, .form, .region, .tablist, .tabpanel, .menu,
             .menubar, .listbox, .radiogroup, .toolbar, .dialog, .alertdialog,
             .group, .tree, .treeitem, .grid:
            return [.labelledby, .describedby]
        default:
            return []
        }
    }

    /// Roles grouped in picker order (stable, spec-shaped).
    static func grouped() -> [(category: AriaCategory, roles: [AriaRole])] {
        AriaCategory.allCases.map { cat in
            (cat, AriaRole.allCases.filter { $0.ariaCategory == cat })
        }
    }
    // MARK: Semantic containment (v2.1 / Chunk I)

    /// The roles this container is expected to OWN directly, in ARIA's
    /// "required owned elements" sense. Empty means the role imposes no
    /// expectation on its children, which is the honest answer for most roles —
    /// only containers whose meaning depends on their parts appear here.
    var expectedChildRoles: [AriaRole] {
        switch self {
        case .list:       return [.listitem]
        case .tablist:    return [.tab]
        case .menu:       return [.menuitem]
        case .menubar:    return [.menuitem]
        case .listbox:    return [.option]
        case .radiogroup: return [.radio]
        case .tree:       return [.treeitem]
        case .treeitem:   return [.treeitem]
        case .table:      return [.row]
        case .grid:       return [.row]
        case .row:        return [.cell, .columnheader, .rowheader]
        default:          return []
        }
    }

    /// The containers this role must sit inside to mean anything, in ARIA's
    /// "required context" sense. A role with an empty list is legal anywhere,
    /// so EXP stays quiet about it rather than inventing structure rules.
    /// `radio` is deliberately absent: a lone radio outside a group is poor
    /// practice but not invalid, so it earns a recommendation, never a warning.
    var requiredParentRoles: [AriaRole] {
        switch self {
        case .listitem:                          return [.list]
        case .tab:                               return [.tablist]
        case .menuitem:                          return [.menu, .menubar]
        case .option:                            return [.listbox]
        case .treeitem:                          return [.tree, .treeitem]
        case .row:                               return [.table, .grid]
        case .cell, .columnheader, .rowheader:   return [.row]
        default:                                 return []
        }
    }

    /// Plain-language sentence naming what this container expects to contain.
    /// nil when the role expects nothing in particular.
    var containmentGuidance: String? {
        let expected = expectedChildRoles
        guard !expected.isEmpty else { return nil }
        let names = expected.map(\.friendlyLabel)
        let list: String
        switch names.count {
        case 1:  list = names[0]
        case 2:  list = "\(names[0]) or \(names[1])"
        default: list = names.dropLast().joined(separator: ", ") + ", or " + names[names.count - 1]
        }
        return "A \(friendlyLabel) expects the components inside it to be \(list)."
    }

    /// Picker sections with the container's expected child roles promoted to a
    /// leading "Recommended" group. The full role list always follows, in its
    /// normal order: a recommendation narrows the path of least resistance, it
    /// never removes a choice the designer is entitled to make.
    static func sections(recommendedFor parentRole: AriaRole?) -> [AriaRoleSection] {
        let recommended = parentRole?.expectedChildRoles ?? []
        var result: [AriaRoleSection] = []
        if !recommended.isEmpty {
            result.append(AriaRoleSection(title: "Recommended here",
                                          roles: recommended,
                                          isRecommendation: true))
        }
        for group in AriaRole.grouped() where !group.roles.isEmpty {
            result.append(AriaRoleSection(title: group.category.label,
                                          roles: group.roles,
                                          isRecommendation: false))
        }
        return result
    }
}


/// One section of a role picker. `isRecommendation` marks the promoted group so
/// each surface can label it consistently without re-deriving the rules.
struct AriaRoleSection: Identifiable, Sendable {
    var title: String
    var roles: [AriaRole]
    var isRecommendation: Bool
    var id: String { title }
}

/// What EXP has to say about a component's role given where it is placed.
/// Advice is ADVICE: nothing here ever rewrites an authored role, and EXP never
/// invents `aria-owns` to paper over a structure the designer did not build.
struct AriaContainmentAdvice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The parent expects particular children and this one is uncategorized.
        case suggestion
        /// The child's role requires a container this parent is not.
        case invalidOwnership
        /// The parent expects particular children and has none of them yet.
        case containerHasNoExpectedChildren
    }

    var kind: Kind
    var parentRole: AriaRole
    /// Roles worth offering first. Never applied automatically.
    var recommended: [AriaRole]
    var message: String

    /// Warnings are things a screen-reader user would actually trip over.
    /// Suggestions are help, and must never be styled as errors.
    var isWarning: Bool { kind == .invalidOwnership }
}

extension Document {
    /// Advice for a component placed directly inside a component whose role is
    /// `parentRole`. Deliberately quiet: a parent with no ownership expectation,
    /// or a child already carrying an expected role, produces nothing at all.
    /// A child carrying an unrelated-but-legal role (a decorative Group inside a
    /// List, say) also produces nothing — EXP only warns when the child's own
    /// role DEMANDS a container this parent is not, which is the case a screen
    /// reader genuinely mis-announces.
    func containmentAdvice(forChildRole childRole: AriaRole?,
                           inParentRole parentRole: AriaRole?) -> AriaContainmentAdvice? {
        guard let parentRole else { return nil }
        let expected = parentRole.expectedChildRoles

        if let childRole {
            let required = childRole.requiredParentRoles
            if !required.isEmpty, !required.contains(parentRole) {
                let wanted = required.map(\.friendlyLabel).joined(separator: " or ")
                return AriaContainmentAdvice(
                    kind: .invalidOwnership,
                    parentRole: parentRole,
                    recommended: expected,
                    message: "\(childRole.friendlyLabel) has to be inside a \(wanted), "
                        + "but this is a \(parentRole.friendlyLabel). Assistive technology "
                        + "will not announce it as a \(childRole.friendlyLabel) here.")
            }
            return nil
        }

        guard !expected.isEmpty, let guidance = parentRole.containmentGuidance else { return nil }
        return AriaContainmentAdvice(
            kind: .suggestion,
            parentRole: parentRole,
            recommended: expected,
            message: guidance)
    }

    /// Advice for the CONTAINER itself: it expects specific children and none of
    /// its directly nested components carry an expected role yet. This is the
    /// authoring-time form of the `listStructure` / `tableStructure` gaps the
    /// semantic exporter reports, surfaced while it is still cheap to fix.
    func containmentAdvice(forSource sourceID: UUID) -> AriaContainmentAdvice? {
        guard let source = source(for: sourceID),
              let role = source.a11y.role,
              let guidance = role.containmentGuidance else { return nil }
        let expected = role.expectedChildRoles
        var nestedRoles: [AriaRole] = []
        var sawNestedComponent = false
        func walk(_ nodes: [Node]) {
            for node in nodes {
                switch node.content {
                case .instance(let instance):
                    sawNestedComponent = true
                    if let nested = self.source(for: instance.sourceID)?.a11y.role {
                        nestedRoles.append(nested)
                    }
                case .group(let children):
                    walk(children)
                default:
                    break
                }
            }
        }
        walk(source.children)
        // Nothing nested yet is an empty component, not a mistake.
        guard sawNestedComponent,
              !nestedRoles.contains(where: { expected.contains($0) }) else { return nil }
        return AriaContainmentAdvice(
            kind: .containerHasNoExpectedChildren,
            parentRole: role,
            recommended: expected,
            message: guidance + " None of the components inside it carry that role yet.")
    }
}

/// A named component state (v1.6 Chunk H) — hover, pressed, focus, disabled,
/// or custom (open/selected/error…). Modeled as an override-diff against the
/// base using the SAME machinery as instance overrides, so one mental model
/// covers both and the re-hug engine is untouched. On export (Chunk B) a
/// conventional name maps to a CSS pseudo-class; anything else becomes
/// `data-state="name"`. JS is never stored — behavior regenerates from the
/// contract (ARIA role + relationships), so it can't rot inside the file.
struct ComponentState: Identifiable, Codable, Sendable {
    var id = UUID()
    /// Display/export name ("hover", "pressed", "focus", "disabled", or custom).
    var name: String
    /// The visual diff against the base state (same shape as instance overrides).
    var overrides: [InstanceOverride] = []
    /// Per-state layer visibility (e.g. a focus ring shown only in `focus`).
    var layerVisibility: [LayerVisibilityOverride] = []
    /// Hook for Chunk H motion: name of the DTCG transition token used to
    /// ENTER this state. Modeled now (like `accessibleNameLayerID` was); no
    /// UI sets it yet.
    var enterTransitionToken: String?

    /// Conventional names offered first in the UI, in picker order.
    static let conventionalNames = ["hover", "pressed", "focus", "disabled"]

    init(id: UUID = UUID(), name: String,
         overrides: [InstanceOverride] = [],
         layerVisibility: [LayerVisibilityOverride] = [],
         enterTransitionToken: String? = nil) {
        self.id = id; self.name = name; self.overrides = overrides
        self.layerVisibility = layerVisibility
        self.enterTransitionToken = enterTransitionToken
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overrides, layerVisibility, enterTransitionToken
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        overrides = try c.decodeIfPresent([InstanceOverride].self, forKey: .overrides) ?? []
        layerVisibility = try c.decodeIfPresent([LayerVisibilityOverride].self, forKey: .layerVisibility) ?? []
        enterTransitionToken = try c.decodeIfPresent(String.self, forKey: .enterTransitionToken)
    }
}

// MARK: - Component state EDITING (v1.6 Chunk H)

/// Pure helpers for editing a component STATE in the source editor. Instance
/// and preview rendering keep using the `ComponentInstance` machinery; these
/// exist because editing has different needs:
///  - `applied` never FILTERS hidden layers (the Layers panel and node
///    structure must stay intact while a state is shown), and
///  - `capture` splits an edited tree back into (base, state diff): appearance
///    changes become the state's overrides — the InstanceOverride
///    vocabulary — while everything else (geometry, structure, adds, deletes,
///    effects) belongs to the BASE shared by all states.
enum ComponentStateEditing {

    /// Source children with `state`'s appearance/visibility overrides applied for
    /// editing. Overridden text is re-measured (like instance rendering) so the
    /// label shows at its overridden size; layers are never filtered out, so the
    /// Layers panel can still show and re-toggle hidden state layers.
    ///
    /// This deliberately does NOT reflow. It has no document, so reflowing here
    /// would lay component instances out from their stale stored frames — the
    /// BUG-007 defect. Callers that want laid-out nodes wrap the result in
    /// `Document.reflowed(_:)`, which sizes instances first.
    static func applied(_ children: [Node], state: ComponentState) -> [Node] {
        children.map { apply($0, state: state) }
    }

    private static func apply(_ node: Node, state: ComponentState) -> Node {
        var node = node
        if let visibility = state.layerVisibility.first(where: { $0.layerID == node.id }) {
            node.isVisible = visibility.isVisible
        }
        for override in state.overrides where override.targetNodeID == node.id {
            switch override.value {
            case .text(let string):
                if case .text(var tc) = node.content {
                    tc.setPlainString(string)
                    node.content = .text(tc)
                    node.frame.size = tc.measuredSize(boxWidth: node.frame.width)
                }
            case .fill(let paint):
                setFill(paint, on: &node)
            case .textStyle(let style):
                if case .text(var tc) = node.content {
                    tc = style.applied(to: tc)
                    node.content = .text(tc)
                    // Paint-only state changes (most notably color) must not
                    // collapse a fixed text box back to the glyph's hug size.
                    // Metric changes may reflow, but fixed boxes retain their
                    // authored width.
                    if style.affectsMetrics {
                        node.frame.size = tc.measuredSize(boxWidth: node.frame.width)
                    }
                }
            case .opacity(let value):
                node.opacity = value
            case .blendMode(let value):
                node.blendMode = value
            case .stroke(let stroke):
                setStroke(stroke, on: &node)
            case .componentState(let stateID):
                if case .instance(var instance) = node.content {
                    instance.activeStateID = stateID
                    node.content = .instance(instance)
                }
            }
        }
        if case .group(let kids) = node.content {
            node.content = .group(children: kids.map { apply($0, state: state) })
        }
        return node
    }

    /// Split an edited tree (changed while `state` was active) into the new
    /// base children and the updated state. Rules:
    ///  - text differing from base → state text override; the base keeps its
    ///    own text AND frame size (override size is re-measured on application).
    ///  - fill differing from base → state fill override; base keeps its paint.
    ///  - opacity/blend mode differing from base → state appearance overrides.
    ///  - visibility differing from base → state layerVisibility override.
    ///  - everything else passes through to the base. New nodes join the base;
    ///    overrides for deleted nodes are pruned.
    /// Overrides are rebuilt from the diff each commit, so reverting a value
    /// back to the base's removes its override — no stale entries.
    static func capture(base: [Node], edited: [Node],
                        state: ComponentState) -> (base: [Node], state: ComponentState) {
        var baseByID: [UUID: Node] = [:]
        func index(_ nodes: [Node]) {
            for n in nodes {
                baseByID[n.id] = n
                if case .group(let k) = n.content { index(k) }
            }
        }
        index(base)

        var overrides: [InstanceOverride] = []
        var visibility: [LayerVisibilityOverride] = []
        func walk(_ nodes: [Node]) -> [Node] {
            nodes.map { n in
                var n = n
                if case .group(let kids) = n.content {
                    n.content = .group(children: walk(kids))
                }
                guard let b = baseByID[n.id] else { return n }   // new node → base as-is
                if case .text(let editedTC) = n.content,
                   case .text(let baseTC) = b.content {
                    // Text string → its own override (CSS can't implement content).
                    if editedTC.plainString != baseTC.plainString {
                        overrides.append(InstanceOverride(targetNodeID: n.id,
                                                          value: .text(editedTC.plainString)))
                    }
                    // Typography (color/face/size/underline/align/line-height/
                    // tracking/case) → a bounded text-style override. Only the
                    // properties that actually differ are recorded.
                    let styleDiff = TextStyleOverride.diff(base: baseTC, edited: editedTC)
                    if !styleDiff.isEmpty {
                        overrides.append(InstanceOverride(targetNodeID: n.id,
                                                          value: .textStyle(styleDiff)))
                    }
                    // Reset the base text node to its pristine content + frame. The
                    // state now carries every text difference as an override, so the
                    // shared base never absorbs a state-local text edit. This is the
                    // BUG-006 fix: previously any non-string text edit (color, size,
                    // …) fell through to the base and leaked into every state.
                    n.content = b.content
                    n.frame.size = b.frame.size
                }
                if let editedFill = fill(of: n), let baseFill = fill(of: b),
                   editedFill != baseFill {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .fill(editedFill)))
                    setFill(baseFill, on: &n)
                }
                // Whole-layer opacity (text, background, or the root group) →
                // an opacity override; the base keeps its own opacity.
                if n.opacity != b.opacity {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .opacity(n.opacity)))
                    n.opacity = b.opacity
                }
                // Blend mode is whole-layer appearance just like opacity. Keep it
                // in the active state's diff so changing Hover/Pressed/etc. never
                // leaks into Default or sibling states (BUG-015).
                if n.blendMode != b.blendMode {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .blendMode(n.blendMode)))
                    n.blendMode = b.blendMode
                }
                if let editedStroke = stroke(of: n), let baseStroke = stroke(of: b),
                   editedStroke != baseStroke {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .stroke(editedStroke)))
                    setStroke(baseStroke, on: &n)
                }
                if case .instance(var editedInstance) = n.content,
                   case .instance(let baseInstance) = b.content,
                   editedInstance.activeStateID != baseInstance.activeStateID {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .componentState(editedInstance.activeStateID)))
                    editedInstance.activeStateID = baseInstance.activeStateID
                    n.content = .instance(editedInstance)
                }
                if n.isVisible != b.isVisible {
                    visibility.append(LayerVisibilityOverride(layerID: n.id,
                                                              isVisible: n.isVisible))
                    n.isVisible = b.isVisible
                }
                return n
            }
        }
        let newBase = walk(edited)

        var newState = state
        newState.overrides = overrides
        newState.layerVisibility = visibility
        var liveIDs = Set<UUID>()
        func collect(_ nodes: [Node]) {
            for n in nodes {
                liveIDs.insert(n.id)
                if case .group(let k) = n.content { collect(k) }
            }
        }
        collect(newBase)
        newState.layerVisibility.removeAll { !liveIDs.contains($0.layerID) }
        return (newBase, newState)
    }

    private static func fill(of node: Node) -> Paint? {
        switch node.content {
        case .rectangle(let s): return s.fill
        case .ellipse(let s):   return s.fill
        case .polygon(let s):   return s.fill
        case .path(let s):      return s.fill
        case .group:            return node.autoPadding?.fill
        default:                return nil
        }
    }

    private static func setFill(_ paint: Paint, on node: inout Node) {
        switch node.content {
        case .rectangle(var s): s.fill = paint; node.content = .rectangle(s)
        case .ellipse(var s):   s.fill = paint; node.content = .ellipse(s)
        case .polygon(var s):   s.fill = paint; node.content = .polygon(s)
        case .path(var s):      s.fill = paint; node.content = .path(s)
        case .group:
            if node.autoPadding != nil { node.autoPadding?.fill = paint }
        default: break
        }
    }

    private static func stroke(of node: Node) -> StrokeStyleOverride? {
        switch node.content {
        case .rectangle(let s): return StrokeStyleOverride(color: s.stroke, width: s.strokeWidth, alignment: s.strokeAlignment, pattern: s.strokePattern)
        case .ellipse(let s):   return StrokeStyleOverride(color: s.stroke, width: s.strokeWidth, alignment: s.strokeAlignment, pattern: s.strokePattern)
        case .polygon(let s):   return StrokeStyleOverride(color: s.stroke, width: s.strokeWidth, alignment: s.strokeAlignment, pattern: s.strokePattern)
        case .path(let s):      return StrokeStyleOverride(color: s.stroke, width: s.strokeWidth, alignment: s.effectiveStrokeAlignment, pattern: s.strokePattern)
        case .line(let s):      return StrokeStyleOverride(color: s.stroke, width: s.strokeWidth, alignment: .center, pattern: s.strokePattern)
        case .group:
            guard let pad = node.autoPadding else { return nil }
            return StrokeStyleOverride(color: pad.stroke, width: pad.strokeWidth, alignment: pad.strokeAlignment, pattern: pad.strokePattern)
        default: return nil
        }
    }

    private static func setStroke(_ stroke: StrokeStyleOverride, on node: inout Node) {
        switch node.content {
        case .rectangle(var s): s.stroke = stroke.color ?? .clear; s.strokeWidth = stroke.width; s.strokeAlignment = stroke.alignment; s.strokePattern = stroke.pattern ?? .solid; node.content = .rectangle(s)
        case .ellipse(var s):   s.stroke = stroke.color ?? .clear; s.strokeWidth = stroke.width; s.strokeAlignment = stroke.alignment; s.strokePattern = stroke.pattern ?? .solid; node.content = .ellipse(s)
        case .polygon(var s):   s.stroke = stroke.color ?? .clear; s.strokeWidth = stroke.width; s.strokeAlignment = stroke.alignment; s.strokePattern = stroke.pattern ?? .solid; node.content = .polygon(s)
        case .path(var s):      s.stroke = stroke.color ?? .clear; s.strokeWidth = stroke.width; s.strokeAlignment = stroke.alignment; s.strokePattern = stroke.pattern ?? .solid; node.content = .path(s)
        case .line(var s):      s.stroke = stroke.color ?? .clear; s.strokeWidth = stroke.width; s.strokePattern = stroke.pattern ?? .solid; node.content = .line(s)
        case .group:
            if node.autoPadding != nil {
                node.autoPadding?.stroke = stroke.color
                node.autoPadding?.strokeWidth = stroke.width
                node.autoPadding?.strokeAlignment = stroke.alignment
                node.autoPadding?.strokePattern = stroke.pattern ?? .solid
            }
        default: break
        }
    }
}

/// A placed reference to a `ComponentSource`. Carries only what differs from the
/// source: a bounded set of overrides plus per-layer visibility overrides (the
/// InDesign-style behavior). It holds `sourceID`, never a copy of the source.
struct ComponentInstance: Codable, Sendable {
    var sourceID: UUID
    var overrides: [InstanceOverride] = []

    /// The source STATE this instance displays (nil = base/default). The state's
    /// override-diff is folded in UNDER this instance's own overrides, so instance
    /// tweaks still win. Old files without the key decode as nil (synthesized
    /// Codable uses decodeIfPresent for optionals).
    var activeStateID: UUID? = nil

    /// Per-layer visibility overrides for THIS instance. A true override can both
    /// show a source-hidden layer and hide a source-visible one. Layers with no
    /// entry here simply inherit the source's own visibility.
    var layerVisibility: [LayerVisibilityOverride] = []

    /// State choices for component instances nested inside this instance's source.
    /// Paths contain nested instance node IDs (groups are deliberately omitted),
    /// which keeps the override stable when layout groups are rearranged.
    var nestedStateOverrides: [NestedInstanceStateOverride] = []

    /// Value overrides for layers inside NESTED components (FEAT-017). Stored here,
    /// on the outermost placed instance, so two placements of the same component can
    /// carry different nested content without either touching the shared source.
    /// Chunk J-a: this is storage only — nothing resolves it yet, which is what
    /// makes it safe to land ahead of the resolution work in J-b.
    var nestedOverrides: [NestedInstanceOverride] = []

    init(sourceID: UUID, overrides: [InstanceOverride] = [], activeStateID: UUID? = nil,
         layerVisibility: [LayerVisibilityOverride] = [],
         nestedStateOverrides: [NestedInstanceStateOverride] = [],
         nestedOverrides: [NestedInstanceOverride] = []) {
        self.sourceID = sourceID
        self.overrides = overrides
        self.activeStateID = activeStateID
        self.layerVisibility = layerVisibility
        self.nestedStateOverrides = nestedStateOverrides
        self.nestedOverrides = nestedOverrides
    }

    enum CodingKeys: String, CodingKey {
        case sourceID, overrides, activeStateID, layerVisibility, nestedStateOverrides
        case nestedOverrides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try c.decode(UUID.self, forKey: .sourceID)
        overrides = try c.decodeIfPresent([InstanceOverride].self, forKey: .overrides) ?? []
        activeStateID = try c.decodeIfPresent(UUID.self, forKey: .activeStateID)
        layerVisibility = try c.decodeIfPresent([LayerVisibilityOverride].self, forKey: .layerVisibility) ?? []
        nestedStateOverrides = try c.decodeIfPresent([NestedInstanceStateOverride].self, forKey: .nestedStateOverrides) ?? []
        // Absent in every file written before v2.1 — decode to empty, never fail.
        nestedOverrides = ((try? c.decodeIfPresent([NestedInstanceOverride].self,
                                                   forKey: .nestedOverrides)) ?? nil) ?? []
    }

    /// Effective visibility of a source layer in this instance: the override if
    /// one exists, otherwise the source layer's own `isVisible`.
    func isLayerVisible(_ layerID: UUID, sourceDefault: Bool) -> Bool {
        layerVisibility.first { $0.layerID == layerID }?.isVisible ?? sourceDefault
    }

    /// This instance with a source STATE folded in: the state's diff sits UNDER
    /// the instance's own overrides so instance tweaks still win. `nil` returns
    /// self unchanged. Precedence mirrors the lookups: text/fill overrides apply
    /// in order (later wins → instance last); visibility takes the first match
    /// (→ instance first).
    func applyingState(_ state: ComponentState?) -> ComponentInstance {
        guard let state else { return self }
        var merged = self
        merged.overrides = state.overrides + overrides
        merged.layerVisibility = layerVisibility + state.layerVisibility
        return merged
    }
}

struct NestedInstanceStateOverride: Codable, Sendable, Equatable {
    var instancePath: [UUID]
    /// nil is an intentional selection of the source's Default state.
    var stateID: UUID?
}

/// An override applied to a layer inside a NESTED component (FEAT-017 chunk J-a).
///
/// `InstanceOverride` addresses a bare `targetNodeID` resolved against the
/// instance's own source children, so a layer one level further down — a tab
/// inside a placed tab bar — has no address at all. That is why a component's
/// nested content could not be varied per placement, and why the owner kept
/// having to fork a component instead of reusing it.
///
/// The fix follows a precedent already in this file rather than inventing one:
/// `NestedInstanceStateOverride` addresses nested instances by `instancePath` and
/// is stored on the OUTERMOST placed instance. This is the same idea applied to
/// VALUES instead of state selection, reusing `InstanceOverride.Value` unchanged
/// so no new vocabulary appears and every existing consumer already understands
/// the payload.
///
/// `instancePath` contains nested INSTANCE node ids, outermost first; groups are
/// deliberately omitted, which keeps an override stable when layout groups are
/// rearranged. An empty path would address the instance's own children, which
/// `overrides` already covers — so an empty path is meaningless here and
/// resolution ignores it rather than guessing.
///
/// HAZARD, learned the hard way from BUG-010: duplication and flatten MUST remap
/// these paths through their id map, exactly as anchored relationships required.
/// `Document.remappingAnchors` is the model to copy. This gets forgotten; the
/// headless checks in chunk J-e exist to catch it.
struct NestedInstanceOverride: Codable, Sendable {
    /// Nested instance node ids to descend through, OUTERMOST first.
    var instancePath: [UUID]
    /// The layer inside the innermost nested source that this overrides.
    var targetNodeID: UUID
    var value: InstanceOverride.Value

    init(instancePath: [UUID], targetNodeID: UUID, value: InstanceOverride.Value) {
        self.instancePath = instancePath
        self.targetNodeID = targetNodeID
        self.value = value
    }

    /// Addresses nothing resolvable. Kept as an explicit question rather than a
    /// silent filter so callers have to decide what to do about it.
    var isAddressable: Bool { !instancePath.isEmpty }
}

/// One per-instance visibility override for a source layer.
struct LayerVisibilityOverride: Codable, Sendable {
    var layerID: UUID
    var isVisible: Bool
}

/// A bounded set of TYPOGRAPHY properties overridden by a component state (or,
/// in principle, an instance). Every field is optional: only the properties that
/// actually differ from the base are stored, so the diff stays minimal and old
/// files decode tolerantly — a missing key means "inherit the base." Run-level
/// properties (color, face, size, underline) apply UNIFORMLY to every run: a
/// component label is edited as a whole in the inspector, so representing per-run
/// state styling is deliberately out of scope. Paragraph-level properties (align,
/// line height + unit, tracking, case) set the matching `TextContent` field.
///
/// Synthesized `Codable` uses `encodeIfPresent`/`decodeIfPresent` for optionals,
/// so nil fields are omitted from JSON and any absent/older key decodes as nil.
struct TextStyleOverride: Codable, Sendable, Equatable {
    // Run-level (applied to every run)
    var color: RGBAColor?
    var fontName: String?
    var fontSize: CGFloat?
    var underline: Bool?
    // Paragraph-level
    var align: TextAlign?
    var lineHeight: CGFloat?
    var lineHeightUnit: LineHeightUnit?
    var tracking: CGFloat?
    var textCase: TextCase?

    var isEmpty: Bool {
        color == nil && fontName == nil && fontSize == nil && underline == nil
            && align == nil && lineHeight == nil && lineHeightUnit == nil
            && tracking == nil && textCase == nil
    }

    /// Whether applying this override can change glyph or line geometry.
    /// Color and underline are paint/decoration only; remeasuring for them made
    /// fixed component-state text boxes unexpectedly shrink.
    var affectsMetrics: Bool {
        fontName != nil || fontSize != nil || lineHeight != nil
            || lineHeightUnit != nil || tracking != nil || textCase != nil
    }

    /// Overlay the set properties onto `text`, returning the styled copy. Only
    /// non-nil fields change; everything else inherits from `text` (the base).
    func applied(to text: TextContent) -> TextContent {
        var t = text
        if let color { t.applyToAllRuns { $0.color = color } }
        if let fontName { t.applyToAllRuns { $0.fontName = fontName } }
        if let fontSize { t.applyToAllRuns { $0.fontSize = fontSize } }
        if let underline { t.applyToAllRuns { $0.underline = underline } }
        if let align { t.align = align }
        if let lineHeight { t.lineHeight = lineHeight }
        if let lineHeightUnit { t.lineHeightUnit = lineHeightUnit }
        if let tracking { t.tracking = tracking }
        if let textCase { t.textCase = textCase }
        return t
    }

    /// The diff of `edited` against `base`: a field is recorded only when the
    /// edited value differs. Run-level props compare the UNIFORM value across runs
    /// (nil = mixed runs, which the bounded vocabulary can't represent, so that
    /// property is left to the base rather than guessed).
    static func diff(base: TextContent, edited: TextContent) -> TextStyleOverride {
        func uniformColor(_ t: TextContent) -> RGBAColor? {
            let first = t.runs.first?.color
            return t.runs.allSatisfy { $0.color == first } ? first : nil
        }
        func uniformUnderline(_ t: TextContent) -> Bool? {
            let first = t.runs.first?.underline
            return t.runs.allSatisfy { $0.underline == first } ? first : nil
        }
        var o = TextStyleOverride()
        if let e = uniformColor(edited), e != uniformColor(base) { o.color = e }
        if let e = edited.uniformFontName, e != base.uniformFontName { o.fontName = e }
        if let e = edited.uniformFontSize, e != base.uniformFontSize { o.fontSize = e }
        if let e = uniformUnderline(edited), e != uniformUnderline(base) { o.underline = e }
        if edited.align != base.align { o.align = edited.align }
        if edited.lineHeight != base.lineHeight { o.lineHeight = edited.lineHeight }
        if edited.lineHeightUnit != base.lineHeightUnit { o.lineHeightUnit = edited.lineHeightUnit }
        if edited.tracking != base.tracking { o.tracking = edited.tracking }
        if edited.textCase != base.textCase { o.textCase = edited.textCase }
        return o
    }
}

/// The complete outline appearance stored by a component state. Color includes
/// alpha, and an optional color lets a state remove a group background outline.
struct StrokeStyleOverride: Codable, Sendable, Equatable {
    var color: RGBAColor?
    var width: CGFloat
    var alignment: StrokeAlignment
    /// Optional so v2.0/v2.1 documents whose state override predates stroke
    /// patterns continue to decode as a solid outline.
    var pattern: StrokePattern? = nil
}

/// One bounded override targeting a node inside the resolved instance.
/// Kept as an explicit list (not a dictionary) so the JSON stays readable.
struct InstanceOverride: Codable, Sendable {
    enum Value: Codable, Sendable {
        case text(String)
        case fill(Paint)        // solid OR gradient (Paint decodes a legacy bare RGBAColor)
        case textStyle(TextStyleOverride)   // bounded per-state/instance typography
        case opacity(Double)                // whole-layer opacity (any node type)
        case blendMode(BlendMode)           // whole-layer compositing mode (any node type)
        case stroke(StrokeStyleOverride)    // color/alpha + width + inside/center/outside
        case componentState(UUID?)          // state of a nested component layer

        var textValue: String? { if case .text(let s) = self { return s }; return nil }
        var fillValue: Paint? { if case .fill(let p) = self { return p }; return nil }
        var textStyleValue: TextStyleOverride? { if case .textStyle(let o) = self { return o }; return nil }
        var opacityValue: Double? { if case .opacity(let v) = self { return v }; return nil }
        var blendModeValue: BlendMode? { if case .blendMode(let v) = self { return v }; return nil }
    }
    var targetNodeID: UUID
    var value: Value
}

extension ComponentInstance {
    /// The per-instance text override for a layer, if any.
    func textOverride(for layerID: UUID) -> String? {
        overrides.first { $0.targetNodeID == layerID }?.value.textValue
    }
    /// The per-instance fill override for a layer, if any.
    func fillOverride(for layerID: UUID) -> Paint? {
        overrides.first { $0.targetNodeID == layerID && $0.value.fillValue != nil }?.value.fillValue
    }

    /// A source layer with this instance's text/fill overrides applied — RECURSIVELY,
    /// so overrides on layers nested inside groups resolve too (a text inside a
    /// button frame). An overridden auto-size text node is re-measured so the frame
    /// around it can re-hug. Instance-hidden nested layers are dropped. Used by
    /// rendering and detach so an instance can differ from its source.
    func applyingOverrides(to node: Node) -> Node {
        var node = node
        for override in overrides where override.targetNodeID == node.id {
            switch override.value {
            case .text(let string):
                if case .text(var tc) = node.content {
                    tc.setPlainString(string)
                    node.content = .text(tc)
                    // Auto-width labels keep hugging so button/frame layouts can
                    // re-hug. Fixed text boxes retain their authored width, which
                    // preserves the space needed for center/right paragraph alignment.
                    node.frame.size = tc.measuredSize(boxWidth: node.frame.width)
                }
            case .fill(let paint):
                switch node.content {
                case .rectangle(var shape): shape.fill = paint; node.content = .rectangle(shape)
                case .ellipse(var shape):   shape.fill = paint; node.content = .ellipse(shape)
                case .polygon(var shape):   shape.fill = paint; node.content = .polygon(shape)
                case .path(var shape):      shape.fill = paint; node.content = .path(shape)
                case .group:
                    // A frame's background (its auto-padding fill) — the button surface.
                    if node.autoPadding != nil { node.autoPadding?.fill = paint }
                default: break
                }
            case .textStyle(let style):
                if case .text(var tc) = node.content {
                    tc = style.applied(to: tc)
                    node.content = .text(tc)
                    // Reflow only when typography metrics can actually change.
                    // A color-only state/instance override is paint, not layout.
                    if style.affectsMetrics {
                        node.frame.size = tc.measuredSize(boxWidth: node.frame.width)
                    }
                }
            case .opacity(let value):
                node.opacity = value
            case .blendMode(let value):
                node.blendMode = value
            case .stroke(let stroke):
                switch node.content {
                case .rectangle(var shape): shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .rectangle(shape)
                case .ellipse(var shape):   shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .ellipse(shape)
                case .polygon(var shape):   shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .polygon(shape)
                case .path(var shape):      shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokeAlignment = stroke.alignment; shape.strokePattern = stroke.pattern ?? .solid; node.content = .path(shape)
                case .line(var shape):      shape.stroke = stroke.color ?? .clear; shape.strokeWidth = stroke.width; shape.strokePattern = stroke.pattern ?? .solid; node.content = .line(shape)
                case .group:
                    if node.autoPadding != nil {
                        node.autoPadding?.stroke = stroke.color
                        node.autoPadding?.strokeWidth = stroke.width
                        node.autoPadding?.strokeAlignment = stroke.alignment
                        node.autoPadding?.strokePattern = stroke.pattern ?? .solid
                    }
                default: break
                }
            case .componentState(let stateID):
                if case .instance(var instance) = node.content {
                    instance.activeStateID = stateID
                    node.content = .instance(instance)
                }
            }
        }
        if case .instance(var nested) = node.content {
            for override in nestedStateOverrides where override.instancePath.first == node.id {
                if override.instancePath.count == 1 {
                    nested.activeStateID = override.stateID
                } else {
                    let descendant = NestedInstanceStateOverride(
                        instancePath: Array(override.instancePath.dropFirst()),
                        stateID: override.stateID)
                    nested.nestedStateOverrides.removeAll { $0.instancePath == descendant.instancePath }
                    nested.nestedStateOverrides.append(descendant)
                }
            }
            node.content = .instance(nested)
        }
        if case .group(var kids) = node.content {
            kids = kids
                .filter { isLayerVisible($0.id, sourceDefault: $0.isVisible) }
                .map { applyingOverrides(to: $0) }
            node.content = .group(children: kids)
        }
        return node
    }
}

// MARK: - Color

/// A Codable color in straight sRGB components (0...1). CGColor/NSColor aren't
/// Codable, and storing plain numbers also makes good SVG/CSS export trivial
/// later (you already think in rgba()/hex). UI-space bridging to NSColor lives
/// with the drawing code, not here, to keep the model UI-free.
struct RGBAColor: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    nonisolated static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    nonisolated static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    nonisolated static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
}


// MARK: - Design Language (document-local color / gradient library)

/// The user's design language, living inside the `.design` document so it travels
/// with the file. Colors and gradients are organized by USER-DEFINED categories
/// (Primary, Secondary, Accent, ...) which are cross-cutting: a color AND a
/// gradient can both be "Primary". An entry with no category is uncategorized and
/// shows as "Other" once any category exists (Phase 18 refinements).
///
/// It lives here in Document.swift on purpose: this file is a member of BOTH the
/// app and the EXPThumbnail extension targets, and anything `Document` references
/// must compile in both.
struct DesignLanguage: Codable, Equatable, Sendable {

    /// User categories, in display / filter-pill order.
    var categories: [DLCategory]

    /// Named entries — colors and gradients.
    var assets: [DesignAsset]

    /// Named type styles (v1.3) — see `TypeStyle` for what one captures.
    var typeStyles: [TypeStyle]

    /// Recently used paints (most-recent first, capped).
    var recents: [Paint]

    static let recentsLimit = 12
    /// Label for the uncategorized bucket once categories exist.
    static let otherLabel = "Other"

    init(categories: [DLCategory] = [], assets: [DesignAsset] = [],
         typeStyles: [TypeStyle] = [], recents: [Paint] = []) {
        self.categories = categories
        self.assets = assets
        self.typeStyles = typeStyles
        self.recents = recents
    }

    // Tolerant decode so older files (no design language, or the pre-category
    // status model) and future files both open cleanly.
    enum CodingKeys: String, CodingKey { case categories, assets, typeStyles, recents }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent([DLCategory].self, forKey: .categories) ?? []
        assets     = try c.decodeIfPresent([DesignAsset].self, forKey: .assets) ?? []
        typeStyles = try c.decodeIfPresent([TypeStyle].self, forKey: .typeStyles) ?? []
        recents    = try c.decodeIfPresent([Paint].self, forKey: .recents) ?? []
        migrateLegacyStatusIfNeeded()
    }

    /// One-time migration from the old status model (official/candidate/archived).
    /// Owner's choice: seed a "Primary" category from anything that was "official";
    /// everything else becomes uncategorized. Legacy status is then cleared and the
    /// document saves clean on its next edit.
    private mutating func migrateLegacyStatusIfNeeded() {
        guard categories.isEmpty, assets.contains(where: { $0.legacyStatus != nil }) else {
            for i in assets.indices { assets[i].legacyStatus = nil }
            return
        }
        if assets.contains(where: { $0.legacyStatus == "official" }) {
            let primary = DLCategory(name: "Primary")
            categories = [primary]
            for i in assets.indices where assets[i].legacyStatus == "official" {
                assets[i].categoryID = primary.id
            }
        }
        for i in assets.indices { assets[i].legacyStatus = nil }
    }

    var isEmpty: Bool { assets.isEmpty && typeStyles.isEmpty && recents.isEmpty && categories.isEmpty }
    var hasCategories: Bool { !categories.isEmpty }

    // MARK: Grouped / filtered views

    var solids:    [DesignAsset] { assets.filter { !$0.value.isGradient } }
    var gradients: [DesignAsset] { assets.filter {  $0.value.isGradient } }

    func asset(_ id: UUID) -> DesignAsset? { assets.first { $0.id == id } }
    func category(_ id: UUID?) -> DLCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// Display label for an asset's category: the category name, "Other" when it's
    /// uncategorized but categories exist, or "" when there are no categories.
    func categoryLabel(for asset: DesignAsset) -> String {
        if let c = category(asset.categoryID) { return c.name }
        return hasCategories ? DesignLanguage.otherLabel : ""
    }

    func assets(in categoryID: UUID?) -> [DesignAsset] { assets.filter { $0.categoryID == categoryID } }
    func typeStyles(in categoryID: UUID?) -> [TypeStyle] { typeStyles.filter { $0.categoryID == categoryID } }
    func count(in categoryID: UUID?) -> Int {
        assets.reduce(0) { $0 + ($1.categoryID == categoryID ? 1 : 0) }
            + typeStyles.reduce(0) { $0 + ($1.categoryID == categoryID ? 1 : 0) }
    }
    var hasUncategorized: Bool {
        assets.contains { $0.categoryID == nil } || typeStyles.contains { $0.categoryID == nil }
    }

    /// The first saved entry whose value exactly matches (used by the picker link).
    func firstAsset(matching paint: Paint) -> DesignAsset? { assets.first { $0.value == paint } }

    // MARK: Recents

    mutating func remember(_ paint: Paint, limit: Int = DesignLanguage.recentsLimit) {
        recents.removeAll { $0 == paint }
        recents.insert(paint, at: 0)
        if recents.count > limit { recents.removeLast(recents.count - limit) }
    }

    // MARK: Asset mutations

    @discardableResult
    mutating func add(_ asset: DesignAsset) -> UUID { assets.append(asset); return asset.id }

    /// Save a value as an entry (optionally in a category).
    @discardableResult
    mutating func save(_ value: Paint, name: String = "", categoryID: UUID? = nil,
                       provenance: String = "") -> UUID {
        add(DesignAsset(name: name, categoryID: categoryID, value: value, provenance: provenance))
    }

    mutating func rename(_ id: UUID, to name: String) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[i].name = name
    }
    mutating func setValue(_ id: UUID, to value: Paint) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[i].value = value
    }
    mutating func setCategory(_ id: UUID, to categoryID: UUID?) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[i].categoryID = categoryID
    }
    mutating func remove(_ id: UUID) { assets.removeAll { $0.id == id } }

    // MARK: Type style mutations (v1.3 — same shape as the asset API)

    @discardableResult
    mutating func saveTypeStyle(_ style: TypeStyle) -> UUID {
        typeStyles.append(style)
        return style.id
    }
    func typeStyle(_ id: UUID) -> TypeStyle? { typeStyles.first { $0.id == id } }
    mutating func renameTypeStyle(_ id: UUID, to name: String) {
        guard let i = typeStyles.firstIndex(where: { $0.id == id }) else { return }
        typeStyles[i].name = name
    }
    mutating func setTypeStyleCategory(_ id: UUID, to categoryID: UUID?) {
        guard let i = typeStyles.firstIndex(where: { $0.id == id }) else { return }
        typeStyles[i].categoryID = categoryID
    }
    /// Re-capture a saved style from new values (e.g. "Update from Selection").
    mutating func setTypeStyleValues(_ id: UUID, from other: TypeStyle) {
        guard let i = typeStyles.firstIndex(where: { $0.id == id }) else { return }
        var updated = other
        updated.id = typeStyles[i].id
        updated.name = typeStyles[i].name
        updated.categoryID = typeStyles[i].categoryID
        typeStyles[i] = updated
    }
    mutating func removeTypeStyle(_ id: UUID) { typeStyles.removeAll { $0.id == id } }

    /// Merge imported type styles (mirrors `merge` for assets; one undo step at
    /// the call site). Categories are matched by name or created.
    @discardableResult
    mutating func mergeTypeStyles(_ incoming: [TypeStyle], categories incomingCats: [DLCategory] = [],
                                  mode: MergeMode) -> Int {
        var remap: [UUID: UUID] = [:]
        for cat in incomingCats { remap[cat.id] = ensureCategory(cat.name) }
        var changed = 0
        for var style in incoming {
            style.id = UUID()
            if let cid = style.categoryID { style.categoryID = remap[cid] }
            switch mode {
            case .keepBoth:
                typeStyles.append(style); changed += 1
            case .skipDuplicateValues:
                if !typeStyles.contains(where: { $0.sameValues(as: style) }) {
                    typeStyles.append(style); changed += 1
                }
            case .replaceByName:
                if !style.name.isEmpty,
                   let i = typeStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(style.name) == .orderedSame }) {
                    let keep = (typeStyles[i].id, typeStyles[i].name, typeStyles[i].categoryID)
                    typeStyles[i] = style
                    (typeStyles[i].id, typeStyles[i].name, typeStyles[i].categoryID) = keep
                    changed += 1
                } else { typeStyles.append(style); changed += 1 }
            }
        }
        return changed
    }

    // MARK: Category mutations

    @discardableResult
    mutating func addCategory(_ name: String) -> UUID {
        let cat = DLCategory(name: name.trimmingCharacters(in: .whitespaces))
        categories.append(cat)
        return cat.id
    }
    /// Return the id of a category with this (case-insensitive) name, creating it
    /// if needed.
    @discardableResult
    mutating func ensureCategory(_ name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing.id
        }
        return addCategory(trimmed)
    }
    mutating func renameCategory(_ id: UUID, to name: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[i].name = name.trimmingCharacters(in: .whitespaces)
    }
    /// Delete a category; its assets fall back to uncategorized (colors are kept).
    mutating func removeCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for i in assets.indices where assets[i].categoryID == id { assets[i].categoryID = nil }
        for i in typeStyles.indices where typeStyles[i].categoryID == id { typeStyles[i].categoryID = nil }
    }
    mutating func moveCategory(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { categories[$0] }
        var remaining = categories.indices.filter { !source.contains($0) }.map { categories[$0] }
        let adjusted = min(destination - source.filter { $0 < destination }.count, remaining.count)
        remaining.insert(contentsOf: moved, at: adjusted)
        categories = remaining
    }

    /// Move a category so it lands immediately before `targetID` (or to the end
    /// when nil). Explicit remove + insert — unambiguous for drag-and-drop reorder.
    mutating func moveCategory(_ id: UUID, before targetID: UUID?) {
        guard id != targetID, let from = categories.firstIndex(where: { $0.id == id }) else { return }
        let cat = categories.remove(at: from)
        if let t = targetID, let idx = categories.firstIndex(where: { $0.id == t }) {
            categories.insert(cat, at: idx)
        } else {
            categories.append(cat)
        }
    }

    // MARK: Merge (import)

    enum MergeMode: String, CaseIterable, Identifiable, Sendable {
        case keepBoth, skipDuplicateValues, replaceByName
        var id: String { rawValue }
        var label: String {
            switch self {
            case .keepBoth:            return "Keep both"
            case .skipDuplicateValues: return "Skip duplicate values"
            case .replaceByName:       return "Replace by name"
            }
        }
    }

    /// Merge imported entries + their categories in one shot (one undo step at the
    /// call site). Incoming categories are matched to existing ones by name (or
    /// created), and each entry's categoryID is remapped accordingly. Entries get
    /// fresh ids so imports never collide. Returns how many entries were added or
    /// replaced.
    @discardableResult
    mutating func merge(_ incoming: [DesignAsset], categories incomingCats: [DLCategory] = [],
                        mode: MergeMode) -> Int {
        var remap: [UUID: UUID] = [:]
        for cat in incomingCats { remap[cat.id] = ensureCategory(cat.name) }
        var changed = 0
        for var entry in incoming {
            entry.id = UUID()
            if let cid = entry.categoryID { entry.categoryID = remap[cid] }   // unknown -> nil
            switch mode {
            case .keepBoth:
                assets.append(entry); changed += 1
            case .skipDuplicateValues:
                if !assets.contains(where: { $0.value == entry.value }) { assets.append(entry); changed += 1 }
            case .replaceByName:
                if !entry.name.isEmpty,
                   let i = assets.firstIndex(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                    assets[i].value = entry.value
                    assets[i].categoryID = entry.categoryID
                    assets[i].provenance = entry.provenance
                    changed += 1
                } else { assets.append(entry); changed += 1 }
            }
        }
        return changed
    }
}

/// A user-defined grouping label for design-language entries. Cross-cutting: a
/// color and a gradient can share a category. Assets with no category are "Other".
struct DLCategory: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

/// One entry in a `DesignLanguage`: a solid color or a gradient in an optional user
/// category. `value` is a `Paint`, so solids and gradients share one shape.
struct DesignAsset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// The user category this belongs to (nil = uncategorized / "Other").
    var categoryID: UUID?
    var value: Paint
    var notes: String
    var tags: [String]
    var provenance: String

    /// Decode-only carrier for the pre-category `status` field, consumed once by
    /// `DesignLanguage`'s migration then cleared. Never encoded.
    var legacyStatus: String?

    init(id: UUID = UUID(), name: String = "", categoryID: UUID? = nil,
         value: Paint, notes: String = "", tags: [String] = [], provenance: String = "") {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.value = value
        self.notes = notes
        self.tags = tags
        self.provenance = provenance
        self.legacyStatus = nil
    }

    var representativeColor: RGBAColor { value.representativeColor }

    // `status` is decode-only (old files); `legacyStatus` is never encoded.
    enum CodingKeys: String, CodingKey { case id, name, categoryID, value, notes, tags, provenance, status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name  = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        value = try c.decode(Paint.self, forKey: .value)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags  = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        provenance = try c.decodeIfPresent(String.self, forKey: .provenance) ?? ""
        legacyStatus = try c.decodeIfPresent(String.self, forKey: .status)   // old files only
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(categoryID, forKey: .categoryID)
        try c.encode(value, forKey: .value)
        try c.encode(notes, forKey: .notes)
        try c.encode(tags, forKey: .tags)
        try c.encode(provenance, forKey: .provenance)
        // legacyStatus intentionally NOT encoded.
    }
}

/// A saved, named text treatment in the Design Language (v1.3).
///
/// Captures EVERYTHING except color — owner decision 2026-07-09: color stays
/// with the Design Language colors so type and color choices remain
/// independently reusable (matching how text styles work in other tools, and
/// how CSS separates `font-*` from `color`).
///
/// FUTURE (needs discovery before speccing): per-style "color notes" /
/// variations — e.g. a heading style that RECOMMENDS pairings from the color
/// library without owning them. Parked until the workflow is designed.
///
/// Character properties come from `TextRun` (minus color); paragraph
/// properties from `TextContent` (minus `box`, which is layout, not style).
/// Lives in Document.swift on purpose — shared with the EXPThumbnail target.
struct TypeStyle: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// Shares the SAME cross-cutting categories as colors/gradients.
    var categoryID: UUID?
    var notes: String
    var provenance: String

    // Character (TextRun minus color)
    var fontName: String        // PostScript face; "" = system font
    var fontSize: CGFloat
    var underline: Bool

    // Paragraph (TextContent minus box + color)
    var align: TextAlign
    var lineHeight: CGFloat
    var lineHeightUnit: LineHeightUnit
    var tracking: CGFloat
    var textCase: TextCase

    init(id: UUID = UUID(), name: String = "", categoryID: UUID? = nil,
         notes: String = "", provenance: String = "",
         fontName: String = "", fontSize: CGFloat = 16, underline: Bool = false,
         align: TextAlign = .left, lineHeight: CGFloat = 1.3,
         lineHeightUnit: LineHeightUnit = .auto, tracking: CGFloat = 0,
         textCase: TextCase = .none) {
        self.id = id; self.name = name; self.categoryID = categoryID
        self.notes = notes; self.provenance = provenance
        self.fontName = fontName; self.fontSize = fontSize; self.underline = underline
        self.align = align; self.lineHeight = lineHeight
        self.lineHeightUnit = lineHeightUnit; self.tracking = tracking
        self.textCase = textCase
    }

    // Tolerant decode so future fields never break older builds.
    enum CodingKeys: String, CodingKey {
        case id, name, categoryID, notes, provenance
        case fontName, fontSize, underline
        case align, lineHeight, lineHeightUnit, tracking, textCase
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        provenance = try c.decodeIfPresent(String.self, forKey: .provenance) ?? ""
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? ""
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 16
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        align = try c.decodeIfPresent(TextAlign.self, forKey: .align) ?? .left
        lineHeight = try c.decodeIfPresent(CGFloat.self, forKey: .lineHeight) ?? 1.3
        lineHeightUnit = try c.decodeIfPresent(LineHeightUnit.self, forKey: .lineHeightUnit) ?? .auto
        tracking = try c.decodeIfPresent(CGFloat.self, forKey: .tracking) ?? 0
        textCase = try c.decodeIfPresent(TextCase.self, forKey: .textCase) ?? .none
    }

    // MARK: Capture / apply

    /// Capture a style from a text layer's content. Character values come from
    /// the FIRST run (the inspector's convention for mixed-style text).
    static func capture(from tc: TextContent, name: String = "",
                        categoryID: UUID? = nil, provenance: String = "selection") -> TypeStyle {
        let run = tc.firstRun
        return TypeStyle(name: name, categoryID: categoryID, provenance: provenance,
                         fontName: run.fontName, fontSize: run.fontSize,
                         underline: run.underline,
                         align: tc.align, lineHeight: tc.lineHeight,
                         lineHeightUnit: tc.lineHeightUnit, tracking: tc.tracking,
                         textCase: tc.textCase)
    }

    /// Apply this style to text content. Every run takes the style's character
    /// values (a style is one treatment — per-run face/size differences flatten
    /// by design); run COLORS are untouched (color is not part of a type style).
    /// `box` is untouched (layout). Call sites re-hug auto-box frames.
    func apply(to tc: inout TextContent) {
        tc.applyToAllRuns {
            $0.fontName = fontName
            $0.fontSize = fontSize
            $0.underline = underline
        }
        tc.align = align
        tc.lineHeight = lineHeight
        tc.lineHeightUnit = lineHeightUnit
        if lineHeightUnit == .px || lineHeightUnit == .em {
            tc.centersFixedLineHeightLeading = true
        }
        tc.tracking = tracking
        tc.textCase = textCase
    }

    /// Value equality ignoring identity/labels (import de-duplication).
    func sameValues(as other: TypeStyle) -> Bool {
        fontName == other.fontName && fontSize == other.fontSize
            && underline == other.underline && align == other.align
            && lineHeight == other.lineHeight && lineHeightUnit == other.lineHeightUnit
            && tracking == other.tracking && textCase == other.textCase
    }

    /// A readable fallback label when unnamed, e.g. "Avenir 24" / "System 16".
    var fallbackLabel: String {
        let face = fontName.isEmpty ? "System" : fontName
        return "\(face) \(Int(fontSize.rounded()))"
    }
}

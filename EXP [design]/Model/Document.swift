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

// MARK: - Document

/// The whole design file: its artboards plus the library of component sources
/// they can reference. This is what will be read/written by the document
/// system (native DocumentGroup) in the next cycle.
struct Document: Codable, Sendable {

    /// Public file-schema marker for future interop/handoff readers. This is
    /// distinct from `formatVersion`, which tracks internal model migrations.
    /// History: 1 = v1.4 baseline; 2 = v1.6 component contract (states,
    /// relationships, public override props).
    static let currentSchemaVersion = 2

    /// The schema version this in-memory document was DECODED from (kept for
    /// diagnostics), or the current version for new documents. Encoding always
    /// writes `currentSchemaVersion` — saving migrates a file forward.
    var schemaVersion: Int = Document.currentSchemaVersion

    /// Bumped when the on-disk shape changes. v2 moved shapes out of artboards
    /// into the document-level `nodes` list (the "wall" model).
    var formatVersion: Int = 2

    /// The canvases the user designs on. Artboards are just named frames now —
    /// they don't own their shapes; ownership is derived geometrically.
    var artboards: [Artboard]

    /// EVERY shape lives here, in document coordinates, in z-order (first =
    /// back). Whether a shape "belongs to" an artboard — and therefore crops to
    /// it — is computed live from the >50%-overlap rule (see `owningArtboard`),
    /// not stored. Shapes not >50% inside any artboard live on the "wall".
    var nodes: [Node]

    /// Reusable component definitions. An instance node refers to one of these
    /// by `id` — the reference-based heart of the model. Empty until Phase 4.
    var sources: [ComponentSource]

    /// Ruler guides (document coordinates), persisted with the file like Photoshop.
    var guides: [Guide]

    /// The document-local design language: named colors/gradients + recent paints
    /// that travel with the file. Empty until the user saves swatches (Phase 18).
    var designLanguage: DesignLanguage = DesignLanguage()

    init(artboards: [Artboard] = Document.starter,
         nodes: [Node] = [],
         sources: [ComponentSource] = [],
         guides: [Guide] = [],
         designLanguage: DesignLanguage = DesignLanguage()) {
        self.artboards = artboards
        self.nodes = nodes
        self.sources = sources
        self.guides = guides
        self.designLanguage = designLanguage
    }

    // Custom decode so files saved before `guides` existed still open.
    enum CodingKeys: String, CodingKey { case schemaVersion, formatVersion, artboards, nodes, sources, guides, designLanguage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 2
        artboards = try c.decode([Artboard].self, forKey: .artboards)
        nodes = try c.decode([Node].self, forKey: .nodes)
        sources = try c.decodeIfPresent([ComponentSource].self, forKey: .sources) ?? []
        guides = try c.decodeIfPresent([Guide].self, forKey: .guides) ?? []
        designLanguage = try c.decodeIfPresent(DesignLanguage.self, forKey: .designLanguage) ?? DesignLanguage()
    }

    // Custom encode so a re-saved older file upgrades its declared schema
    // version to the shape this app actually writes (schemaVersion migration).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Document.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(artboards, forKey: .artboards)
        try c.encode(nodes, forKey: .nodes)
        try c.encode(sources, forKey: .sources)
        try c.encode(guides, forKey: .guides)
        try c.encode(designLanguage, forKey: .designLanguage)
    }

    /// Bounding box enclosing every artboard, in document coordinates. Used to
    /// center / fit the view.
    var contentBounds: CGRect {
        guard let first = artboards.first else { return .zero }
        return artboards.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Look up a component source by id (used when resolving an instance).
    func source(for id: UUID) -> ComponentSource? {
        sources.first { $0.id == id }
    }

    /// A source behaves as a dynamic component when its top level is exactly one
    /// managed frame (typical button/tag components). More complex sources keep
    /// SVG-style stable viewBox bounds.
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

    private func resolvedLayout(of inst: ComponentInstance) -> (children: [Node], bounds: CGRect)? {
        guard let source = source(for: inst.sourceID) else { return nil }
        // Fold in the instance's selected state (nil = base) before resolving, so
        // an instance placed on the wall can display any of the source's states.
        let eff = inst.applyingState(inst.activeStateID.flatMap { sid in
            source.states.first { $0.id == sid }
        })
        let resolved = source.children
            .filter { eff.isLayerVisible($0.id, sourceDefault: $0.isVisible) }
            .map { eff.applyingOverrides(to: $0) }
        // Re-hug auto-layout / auto-padding frames for THIS instance's overrides.
        // (AutoLayoutEngine.swift must be a member of BOTH the app AND the
        // EXPThumbnail targets, or this won't compile — do not stub this out.)
        let laid = AutoLayoutEngine.reflowed(resolved)
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

    /// The artboard that owns a shape with the given document-space frame, or
    /// nil if it's on the wall. Rule: an artboard owns the shape when it covers
    /// MORE THAN HALF of the shape's area; ties broken by largest coverage.
    func owningArtboard(of frame: CGRect) -> Artboard? {
        let area = frame.width * frame.height
        guard area > 0 else { return nil }
        var best: (artboard: Artboard, coverage: CGFloat)?
        for artboard in artboards {
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

/// A named frame on the canvas. Artboards no longer own their shapes — a shape
/// belongs to whichever artboard covers >50% of it (see Document.owningArtboard),
/// which is what makes a shape crop the instant it crosses inside.
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
struct Node: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var frame: CGRect           // DOCUMENT coordinates (points)
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
    /// Which overridable fields on this node are public component props for
    /// downstream codegen / Storybook args. A false value keeps the override local
    /// to EXP; a true value advertises it as part of the source's public contract.
    var publicProps: PublicOverrideProps = PublicOverrideProps()
    var content: NodeContent

    init(id: UUID = UUID(), name: String, frame: CGRect, isVisible: Bool = true,
         isLocked: Bool = false, rotation: Double = 0, opacity: Double = 1,
         effects: [Effect] = [], blendMode: BlendMode = .normal,
         autoLayout: AutoLayout? = nil, autoPadding: AutoPadding? = nil,
         flipH: Bool = false, flipV: Bool = false,
         isMask: Bool = false, isMaskShape: Bool = false,
         relationships: [NodeRelationship] = [],
         publicProps: PublicOverrideProps = PublicOverrideProps(),
         content: NodeContent) {
        self.id = id; self.name = name; self.frame = frame
        self.isVisible = isVisible; self.isLocked = isLocked
        self.rotation = rotation; self.opacity = opacity
        self.effects = effects; self.blendMode = blendMode
        self.autoLayout = autoLayout; self.autoPadding = autoPadding
        self.flipH = flipH; self.flipV = flipV
        self.isMask = isMask; self.isMaskShape = isMaskShape
        self.relationships = relationships; self.publicProps = publicProps
        self.content = content
    }

    // Custom decode so the newer fields (rotation/opacity/effects/blendMode/
    // autoLayout/autoPadding/flip/mask) default cleanly when absent — synthesized
    // Codable would throw on a missing key.
    enum CodingKeys: String, CodingKey {
        case id, name, frame, isVisible, isLocked, rotation, opacity, effects, blendMode
        case autoLayout, autoPadding, flipH, flipV, isMask, isMaskShape
        case relationships, publicProps, content
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        frame = try c.decode(CGRect.self, forKey: .frame)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        autoLayout = try c.decodeIfPresent(AutoLayout.self, forKey: .autoLayout)
        autoPadding = try c.decodeIfPresent(AutoPadding.self, forKey: .autoPadding)
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        isMask = try c.decodeIfPresent(Bool.self, forKey: .isMask) ?? false
        isMaskShape = try c.decodeIfPresent(Bool.self, forKey: .isMaskShape) ?? false
        relationships = (try? c.decodeIfPresent([NodeRelationship].self, forKey: .relationships)) ?? []
        publicProps = try c.decodeIfPresent(PublicOverrideProps.self, forKey: .publicProps) ?? PublicOverrideProps()
        content = try c.decode(NodeContent.self, forKey: .content)
    }
}

// MARK: - Component behavior contract

/// A typed id-to-id relationship from one node to another. These are the behavior
/// leg of the component contract: ARIA role + relationships imply the WAI-APG
/// interaction pattern on export, without storing brittle JS in the design file.
struct NodeRelationship: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case controls
        case labelledby
        case describedby

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
    }

    var id = UUID()
    var kind: Kind
    var targetID: UUID

    init(id: UUID = UUID(), kind: Kind, targetID: UUID) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
    }

    enum CodingKeys: String, CodingKey { case id, kind, targetID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        targetID = try c.decode(UUID.self, forKey: .targetID)
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

    init() {}

    enum CodingKeys: String, CodingKey {
        case paddingTop, paddingRight, paddingBottom, paddingLeft
        case marginTop, marginRight, marginBottom, marginLeft
        case fill, cornerRadius, stroke, strokeWidth
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
/// `box-shadow` (offset x/y, blur, spread). Noise + dissolve are procedural
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
    enum Kind: String, Codable, Sendable { case dropShadow, innerShadow, backgroundBlur, noise, dissolve }
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

    init(id: UUID = UUID(), kind: Kind = .dropShadow,
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

/// `strokeWidth == 0` means no stroke (matches a plain filled shape). Custom
/// decoders default the newer stroke fields so older files still open.
struct RectangleShape: Codable, Sendable {
    var fill: Paint = .white
    var cornerRadius: CGFloat = 0
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 0
    var strokeAlignment: StrokeAlignment = .center
    /// Per-corner radii (v1.3). nil = uniform `cornerRadius` (the default,
    /// simple case). Setting the plain Corner field clears this back to nil.
    var cornerRadii: CornerRadii? = nil

    /// The four radii actually in effect (uniform expands to all corners).
    var effectiveRadii: CornerRadii { cornerRadii ?? CornerRadii(all: cornerRadius) }
    /// True when corners genuinely differ (drives the per-corner render path).
    var hasPerCornerRadii: Bool {
        guard let r = cornerRadii else { return false }
        return !r.isUniform
    }

    init(fill: Paint = .white, cornerRadius: CGFloat = 0,
         stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center, cornerRadii: CornerRadii? = nil) {
        self.fill = fill; self.cornerRadius = cornerRadius
        self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.cornerRadii = cornerRadii
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        cornerRadii = try c.decodeIfPresent(CornerRadii.self, forKey: .cornerRadii)
    }
}

struct EllipseShape: Codable, Sendable {
    var fill: Paint = .white
    var stroke: RGBAColor = .black
    var strokeWidth: CGFloat = 0
    var strokeAlignment: StrokeAlignment = .center

    init(fill: Paint = .white, stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center) {
        self.fill = fill; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
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

    init(sides: Int = 3, fill: Paint = .white, stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
         strokeAlignment: StrokeAlignment = .center) {
        self.sides = Swift.min(25, Swift.max(3, sides))
        self.fill = fill; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sides = Swift.min(25, Swift.max(3, try c.decodeIfPresent(Int.self, forKey: .sides) ?? 3))
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 0
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
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
    var contours: [[PathPoint]]? = nil

    /// Alignment is only meaningful on a closed outline; open paths render center.
    var effectiveStrokeAlignment: StrokeAlignment {
        (closed || isMultiContour) ? strokeAlignment : .center
    }

    init(points: [PathPoint], closed: Bool = false, fill: Paint = .white,
         stroke: RGBAColor = .black, strokeWidth: CGFloat = 2,
         strokeAlignment: StrokeAlignment = .center, contours: [[PathPoint]]? = nil) {
        self.points = points; self.closed = closed; self.fill = fill
        self.stroke = stroke; self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment; self.contours = contours
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([PathPoint].self, forKey: .points)
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? .white
        stroke = try c.decodeIfPresent(RGBAColor.self, forKey: .stroke) ?? .black
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2
        strokeAlignment = try c.decodeIfPresent(StrokeAlignment.self, forKey: .strokeAlignment) ?? .center
        contours = try c.decodeIfPresent([[PathPoint]].self, forKey: .contours)
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

    init(string: String, fontName: String = "", fontSize: CGFloat = 16,
         color: RGBAColor = .black, underline: Bool = false) {
        self.string = string; self.fontName = fontName; self.fontSize = fontSize
        self.color = color; self.underline = underline
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

    /// Legacy-shaped initializer (one run) so existing call sites keep working.
    init(string: String = "", fontSize: CGFloat = 16, color: RGBAColor = .black, fontName: String = "") {
        runs = [TextRun(string: string, fontName: fontName, fontSize: fontSize, color: color)]
    }
    init(runs: [TextRun], align: TextAlign = .left, lineHeight: CGFloat = 1.3,
         lineHeightUnit: LineHeightUnit = .auto, tracking: CGFloat = 0, box: TextBox = .auto,
         textCase: TextCase = .none) {
        self.runs = runs.isEmpty ? [TextRun(string: "")] : runs
        self.align = align; self.lineHeight = lineHeight; self.lineHeightUnit = lineHeightUnit
        self.tracking = tracking; self.box = box; self.textCase = textCase
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
        case runs, align, lineHeight, lineHeightUnit, tracking, box, textCase
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

    /// The component's viewBox — what an instance renders, like an SVG viewBox.
    var bounds: CGRect { CGRect(origin: origin, size: size) }

    init(id: UUID = UUID(), name: String, origin: CGPoint = .zero,
         size: CGSize, children: [Node], a11y: A11ySemantics = A11ySemantics(),
         states: [ComponentState] = []) {
        self.id = id; self.name = name; self.origin = origin
        self.size = size; self.children = children; self.a11y = a11y
        self.states = states
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
    // TODO(explore later): required/expressible states per role (aria-checked,
    // aria-selected, …), modeled once a component-state system exists.

    init(role: AriaRole? = nil, accessibleNameLayerID: UUID? = nil) {
        self.role = role
        self.accessibleNameLayerID = accessibleNameLayerID
    }

    enum CodingKeys: String, CodingKey { case role, accessibleNameLayerID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown future tokens decode to nil instead of failing the document.
        role = (try? c.decodeIfPresent(AriaRole.self, forKey: .role)) ?? nil
        accessibleNameLayerID = try c.decodeIfPresent(UUID.self, forKey: .accessibleNameLayerID)
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
    // Structure — document structure.
    case heading, list, listitem, img, figure, table, separator, group

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
             .option, .radiogroup, .toolbar, .dialog, .alertdialog, .alert:
            return .composite
        case .heading, .list, .listitem, .img, .figure, .table, .separator,
             .group:
            return .structure
        }
    }

    /// Roles grouped in picker order (stable, spec-shaped).
    static func grouped() -> [(category: AriaCategory, roles: [AriaRole])] {
        AriaCategory.allCases.map { cat in
            (cat, AriaRole.allCases.filter { $0.ariaCategory == cat })
        }
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
///  - `capture` splits an edited tree back into (base, state diff): text and
///    fill changes become the state's overrides — the InstanceOverride
///    vocabulary — while everything else (geometry, structure, adds, deletes,
///    effects) belongs to the BASE shared by all states.
enum ComponentStateEditing {

    /// Source children with `state`'s text/fill/visibility overrides applied for
    /// editing. Overridden text is re-measured (like instance rendering) so the
    /// label shows at its overridden size; layers are never filtered out, so the
    /// Layers panel can still show and re-toggle hidden state layers.
    static func applied(_ children: [Node], state: ComponentState,
                        reflow: Bool = false) -> [Node] {
        let applied = children.map { apply($0, state: state) }
        return reflow ? AutoLayoutEngine.reflowed(applied) : applied
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
                    node.frame.size = tc.measuredSize()
                }
            case .fill(let paint):
                setFill(paint, on: &node)
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
                   case .text = b.content,
                   editedTC.plainString != textPlainString(of: b) {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .text(editedTC.plainString)))
                    n.content = b.content
                    n.frame.size = b.frame.size
                }
                if let editedFill = fill(of: n), let baseFill = fill(of: b),
                   editedFill != baseFill {
                    overrides.append(InstanceOverride(targetNodeID: n.id,
                                                      value: .fill(editedFill)))
                    setFill(baseFill, on: &n)
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

    private static func textPlainString(of node: Node) -> String? {
        if case .text(let tc) = node.content { return tc.plainString }
        return nil
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

/// One per-instance visibility override for a source layer.
struct LayerVisibilityOverride: Codable, Sendable {
    var layerID: UUID
    var isVisible: Bool
}

/// One bounded override targeting a node inside the resolved instance.
/// Kept as an explicit list (not a dictionary) so the JSON stays readable.
struct InstanceOverride: Codable, Sendable {
    enum Value: Codable, Sendable {
        case text(String)
        case fill(Paint)        // solid OR gradient (Paint decodes a legacy bare RGBAColor)

        var textValue: String? { if case .text(let s) = self { return s }; return nil }
        var fillValue: Paint? { if case .fill(let p) = self { return p }; return nil }
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
                    // Hug the overridden label to a single line (grow width), so the
                    // surrounding auto-padding/layout frame re-hugs it. Done for ANY
                    // box mode — an overridden component label should fit its content,
                    // which is what makes a button grow with its text.
                    node.frame.size = tc.measuredSize()
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
            }
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

    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
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

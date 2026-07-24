//
//  LayersPanel.swift
//  EXP [design]
//
//  The left Layers panel. Because shape ownership is geometric (the wall model),
//  the panel GROUPS shapes by whichever artboard currently owns them, plus a
//  "Wall" group for free-floating shapes. Front-of-stack shows at the top
//  (matching every design tool), even though the document stores back-to-front.
//
//  Selection is two-way with the canvas via AppState.selectedNodeIDs, and the
//  panel adds explicit list-style multi-select:
//    • click        → select just that row (and set the range anchor)
//    • Shift-click  → select the whole range between the anchor and this row
//    • Option/⌘-click → toggle this row in/out of the selection
//  We manage selection ourselves (rather than List's native selection) so the
//  modifiers behave exactly as asked — Shift for range, Option to pick & choose.
//
//  Visibility, lock, rename, and reorder each route through ExpDocument.setModel
//  → one undo step apiece. Like every panel it's self-contained and state-driven,
//  ready to become a floating window in v2 without changes.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Visual treatment for the Layers section whose artboard is currently "active"
/// — the board in focus, or the board that owns the active selection. Kept as a
/// small, isolated set of constants so it folds cleanly into the design-token
/// system when that lands (this is part of the token-prep pass).
private enum LayersActiveStyle {
    /// Thin accent rule down the ACTIVE ARTBOARD section's far-left edge.
    static let borderWidth: CGFloat = EXPMetric.strokeSelection   // 1.5 — hairline-ish group rule
    /// Thicker accent bar marking the ACTIVE (selected) layer row.
    static let activeLayerBar: CGFloat = 3
    /// Accent for both (follows the system accent / app override).
    static let tint = EXPColor.accent
}

struct LayersPanel: View {
    @ObservedObject var document: ExpDocument
    var scope: CanvasScope = .document
    /// When hosted in a dock group, the group header already shows the title, so
    /// the panel suppresses its own. The source-editor window keeps it (default).
    var showsTitle: Bool = true
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @State private var expanded: Set<UUID> = []   // expanded group / instance rows
    @State private var collapsedSections: Set<String> = []   // collapsed artboard/Wall sections
    @State private var draggingID: UUID?           // layer being dragged
    @State private var dropIndicator: LayerDropIndicator?   // where it will land

    // MARK: Scoped node access (document's nodes, or a source's children)

    private var activeEditingState: ComponentState? {
        guard case .source(let sid) = scope,
              let stateID = app.activeComponentStateID else { return nil }
        return document.model.source(for: sid)?.states.first { $0.id == stateID }
    }

    private var scopeNodes: [Node] {
        switch scope {
        case .document: return document.model.nodes
        case .source(let sid):
            let children = document.model.source(for: sid)?.children ?? []
            if let state = activeEditingState {
                return ComponentStateEditing.applied(children, state: state)
            }
            return children
        }
    }

    private func commitNodes(_ nodes: [Node], _ actionName: String) {
        var model = document.model
        switch scope {
        case .document:
            model.nodes = nodes
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            if let state = activeEditingState,
               let sti = model.sources[si].states.firstIndex(where: { $0.id == state.id }) {
                let (newBase, newState) = ComponentStateEditing.capture(
                    base: model.sources[si].children, edited: nodes, state: state)
                let reflowed = AutoLayoutEngine.reflowed(newBase)
                model.sources[si].children = reflowed
                model.sources[si].states[sti] = newState
                if fitSourceBounds,
                   let bounds = model.managedRootBounds(in: reflowed) {
                    model.sources[si].origin = bounds.origin
                    model.sources[si].size = bounds.size
                }
            } else {
                let reflowed = AutoLayoutEngine.reflowed(nodes)
                model.sources[si].children = reflowed
                if fitSourceBounds,
                   let bounds = model.managedRootBounds(in: reflowed) {
                    model.sources[si].origin = bounds.origin
                    model.sources[si].size = bounds.size
                }
            }
        }
        document.setModel(model, undoManager: undoManager, actionName: actionName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: optional title + an options (•••) menu. The menu is always
            // present (even when docked, where the title is suppressed) so collapse/
            // expand-all is reachable; room to grow with more layer options later.
            HStack(spacing: 6) {
                if showsTitle { Text("Layers").expPanelTitle() }
                Spacer(minLength: 0)
                Menu {
                    Button("Expand All") { expandAll() }
                    Button("Collapse All") { collapseAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Layer options")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, showsTitle ? 12 : 6)
            Divider()

            // Native List selection + drag-reorder: clicking, Shift-range,
            // ⌘-toggle, and dragging a row (from anywhere on it) all come for
            // free and crisp. Rename lives in the row's context menu so no
            // custom gesture competes with the drag.
            ScrollViewReader { proxy in
            // PERF round 10 (docs/PERF-LOG.md): compute the section groups and
            // the active-section id ONCE per body evaluation. They used to be
            // computed properties re-evaluated by EVERY row and header — and
            // `activeSectionID` recomputed `groups` internally — which the
            // round-10 stack sample caught mid-layout as the ~6.2s main-thread
            // hang: hundreds of full O(nodes x artboards) group builds per
            // List rebuild. The locals shadow the old property names so the
            // row/header code below is unchanged.
            let groups = self.groups
            let activeSectionID = self.activeSectionID(in: groups)
            List {
                ForEach(groups) { group in
                    // Collapsible section per artboard / Wall (chevron in the header).
                    Section(isExpanded: sectionExpanded(group.id)) {
                        ForEach(group.nodes) { node in
                            LayerOutlineRow(
                                node: node,
                                document: document,
                                expanded: $expanded,
                                draggingID: $draggingID,
                                dropIndicator: $dropIndicator,
                                inActiveSection: group.id == activeSectionID,
                                onToggleVisible: { toggleVisible($0) },
                                onToggleLock: { toggleLock($0) },
                                onRename: { rename($0, $1) },
                                onRenameComponent: { renameComponent($0, $1) },
                                onSetInstanceState: { setInstanceState($0, stateID: $1) },
                                onSetNestedInstanceState: { setNestedInstanceState($0, path: $1, stateID: $2) },
                                onToggleInstanceLayer: { toggleInstanceLayer(instanceID: $0, childID: $1) },
                                onDrop: { handleDrop($0, onto: $1, place: $2) },
                                onDelete: { deleteLayers(selectionOrRow($0)) },
                                onCopyStyle: { copyStyleFromRow($0) },
                                onPasteStyle: { pasteStyleToRows(selectionOrRow($0)) },
                                onSelect: { selectNested($0) }
                            )
                            // Flush rows (no extra vertical insets / separators) so the
                            // drop line's before/after positions coincide into ONE line.
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        let active = group.id == activeSectionID
                        HStack(spacing: 6) {
                            // Clear (not absent) when inactive so the title never
                            // shifts; the border simply reveals on the active board.
                            Rectangle()
                                .fill(active ? LayersActiveStyle.tint : Color.clear)
                                .frame(width: LayersActiveStyle.borderWidth)
                                .frame(maxHeight: .infinity)
                            Text(group.title)
                                .font(.system(size: EXPType.small, weight: active ? .medium : .regular))
                                .foregroundStyle(active ? EXPColor.accent : EXPColor.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(active ? "\(group.title), active artboard" : group.title)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)   // transparent list → panel surface shows
            // Selecting a nested layer (e.g. from the canvas) opens its ancestor
            // groups + un-collapses its section. The AUTO-SCROLL that used to
            // ride along here is disabled (PERF round 8, docs/PERF-LOG.md):
            // `proxy.scrollTo` on this sectioned/expandable List is the prime
            // suspect for the ~6.2s main-thread hangs the watchdog caught on
            // every selection change — and owner UX verdict says the panel
            // shouldn't yank on single click anyway. Follow-up (next session):
            // an explicit "Reveal in Layers" action (canvas double-click and/or
            // context menu, full command-coverage wiring) that calls
            // `revealScroll` deliberately.
            .onChange(of: app.selectedNodeIDs) { _, sel in
                revealSelectedLayers(sel)
            }
            // Delete key while the panel is focused removes the selected layers —
            // previously only worked when they were selected on the canvas.
            .onDeleteCommand { deleteLayers(app.selectedNodeIDs) }
            // Arrow keys nudge the selected layers. The focused List swallows key
            // events, so the canvas's keyDown never sees them — same focus gap the
            // onDeleteCommand above works around. ⇧ = 10pt step (via current event).
            .onMoveCommand { direction in nudgeSelectedLayers(direction) }
            .onAppear {
                if case .document = scope {
                    app.layersRevealSelection = {
                        let sel = app.selectedNodeIDs
                        revealSelectedLayers(sel)
                        revealScroll(sel, proxy: proxy)
                    }
                }
            }
            }   // ScrollViewReader
        }
        .background(.clear)
        // The document panel owns the View-menu expand/collapse-all hook.
        .onAppear {
            if case .document = scope {
                app.layersExpandAll = { expand in expand ? expandAll() : collapseAll() }
            }
        }
    }

    /// Open every group/instance + every section.
    private func expandAll() {
        expanded = allExpandableIDs()
        collapsedSections = []
    }
    /// Close every group/instance + every section.
    private func collapseAll() {
        expanded = []
        collapsedSections = Set(groups.map(\.id))
    }
    /// All group + instance ids in scope (the rows that have a disclosure triangle).
    private func allExpandableIDs() -> Set<UUID> {
        var ids: Set<UUID> = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                switch n.content {
                case .group(let k): ids.insert(n.id); walk(k)
                case .instance:     ids.insert(n.id)
                default: break
                }
            }
        }
        walk(scopeNodes)
        return ids
    }

    /// Expanded/collapsed binding for one section (keyed by artboard id / "wall").
    private func sectionExpanded(_ id: String) -> Binding<Bool> {
        Binding(get: { !collapsedSections.contains(id) },
                set: { open in
                    if open { collapsedSections.remove(id) } else { collapsedSections.insert(id) }
                })
    }

    /// Open ancestor groups + the owning section for each selected layer.
    /// Scroll the panel so the selected layer is visible. Only fires for a SINGLE
    /// selected node (clicking one layer) — a marquee multi-select shouldn't yank
    /// the panel around. Scrolls to the top-level ancestor row (always present in
    /// the List; nested rows live inside their parent row and aren't scroll targets)
    /// after expansion has had a tick to render.
    /// PERF round 8: no longer called automatically on selection change (see
    /// the .onChange above). Kept for the upcoming explicit Reveal action.
    private func revealScroll(_ sel: Set<UUID>, proxy: ScrollViewProxy) {
        guard sel.count == 1, let id = sel.first else { return }
        let top = ancestorGroupIDs(of: id).first ?? id
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(top, anchor: .center) }
        }
    }

    private func revealSelectedLayers(_ sel: Set<UUID>) {
        guard !sel.isEmpty else { return }
        for id in sel {
            let chain = ancestorGroupIDs(of: id)
            expanded.formUnion(chain)
            let topID = chain.first ?? id
            if let topNode = findNode(topID) { collapsedSections.remove(sectionID(for: topNode)) }
        }
    }

    /// Ancestor group ids of `id`, outermost first (empty if top-level).
    private func ancestorGroupIDs(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        func walk(_ nodes: [Node], _ stack: [UUID]) -> Bool {
            for n in nodes {
                if n.id == id { result = stack; return true }
                if case .group(let k) = n.content, walk(k, stack + [n.id]) { return true }
            }
            return false
        }
        _ = walk(scopeNodes, [])
        return result
    }

    /// The section id (artboard uuid string or "wall"/"source") that displays a
    /// TOP-LEVEL node (pass the node's outermost ancestor).
    private func sectionID(for node: Node) -> String {
        switch scope {
        case .source: return "source"
        case .document:
            if let ab = document.model.owningArtboard(of: node.frame) { return ab.id.uuidString }
            return "wall"
        }
    }

    /// Flattened top-to-bottom order of every selectable layer row currently VISIBLE
    /// in the panel — honouring collapsed sections and which groups are expanded.
    /// Drives Shift-range selection for nested rows (the List manages its own rows,
    /// but hand-rolled DisclosureGroup children don't). A component instance's
    /// per-instance layer rows aren't real nodes, so an instance contributes only its
    /// own row.
    private var visibleSelectableIDs: [UUID] {
        var out: [UUID] = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                out.append(n.id)
                if case .group(let kids) = n.content, expanded.contains(n.id) {
                    walk(Array(kids.reversed()))   // display order: front-of-stack first
                }
            }
        }
        for g in groups where !collapsedSections.contains(g.id) { walk(g.nodes) }
        return out
    }

    /// Select a NESTED layer row honouring the click's modifier keys — the native
    /// `List(selection:)` only manages top-level rows, so without this you couldn't
    /// multi-select inside a group. ⌘ toggles this row, ⇧ extends from the anchor
    /// across the visible order, a plain click replaces. Keeps the canvas + panel in
    /// lockstep through AppState.
    private func selectNested(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        app.selectedArtboardID = nil
        if flags.contains(.command) {
            if app.selectedNodeIDs.contains(id) { app.selectedNodeIDs.remove(id) }
            else { app.selectedNodeIDs.insert(id) }
            app.selectionAnchorID = id
        } else if flags.contains(.shift), let anchor = app.selectionAnchorID, anchor != id,
                  let a = visibleSelectableIDs.firstIndex(of: anchor),
                  let b = visibleSelectableIDs.firstIndex(of: id) {
            app.selectedNodeIDs.formUnion(visibleSelectableIDs[min(a, b)...max(a, b)])
        } else {
            app.selectedNodeIDs = [id]
            app.selectionAnchorID = id
        }
    }

    // MARK: Grouping (front-of-stack first)

    private struct LayerGroup: Identifiable {
        let id: String
        let title: String
        let nodes: [Node]   // display order: front (top) first
    }

    private var groups: [LayerGroup] {
        let model = document.model
        switch scope {
        case .source(let sid):
            // A component source: one flat group of its children.
            guard let source = model.source(for: sid) else { return [] }
            return [LayerGroup(id: "source", title: source.name, nodes: scopeNodes.reversed())]
        case .document:
            // PERF round 10: ONE pass over the nodes, bucketing each by its
            // owning artboard (nil = wall). The previous shape filtered ALL
            // nodes once PER artboard, and owningArtboard itself scans the
            // artboards — O(artboards x nodes x artboards) rect walks with
            // Node array copies, per call. Ordering semantics unchanged:
            // model order within each bucket, reversed so front is first.
            var byBoard: [UUID: [Node]] = [:]
            var wall: [Node] = []
            for node in model.nodes {
                if let owner = model.owningArtboard(of: node.frame) {
                    byBoard[owner.id, default: []].append(node)
                } else {
                    wall.append(node)
                }
            }
            var result: [LayerGroup] = []
            for artboard in model.artboards {
                result.append(LayerGroup(id: artboard.id.uuidString, title: artboard.name,
                                         nodes: (byBoard[artboard.id] ?? []).reversed()))
            }
            if !wall.isEmpty {
                result.append(LayerGroup(id: "wall", title: "Wall", nodes: wall.reversed()))
            }
            return result
        }
    }

    // MARK: Active section (the artboard in focus / owning the selection)

    /// The id of the section to emphasise: the board owning the current node
    /// selection if any, else a directly-selected artboard, else none. The source
    /// scope has no artboards, so it never highlights.
    /// PERF round 10: takes the groups already built for this body pass
    /// instead of recomputing them (the old computed property rebuilt
    /// `groups` on every access — and it was accessed per row AND header).
    private func activeSectionID(in groups: [LayerGroup]) -> String? {
        guard case .document = scope else { return nil }
        if !app.selectedNodeIDs.isEmpty {
            if let g = groups.first(where: { grp in grp.nodes.contains { nodeSubtreeIsSelected($0) } }) {
                return g.id
            }
        }
        if let abID = app.selectedArtboardID { return abID.uuidString }
        return nil
    }

    /// True if `node` — or anything nested inside it — is in the selection.
    private func nodeSubtreeIsSelected(_ node: Node) -> Bool {
        if app.selectedNodeIDs.contains(node.id) { return true }
        if case .group(let kids) = node.content { return kids.contains { nodeSubtreeIsSelected($0) } }
        return false
    }

    /// Flip a source layer's visibility in THIS instance — a true override that
    /// can show a source-hidden layer or hide a source-visible one. If the new
    /// value matches the source default, we drop the override so the instance
    /// goes back to inheriting (and follows future source changes).
    private func toggleInstanceLayer(instanceID: UUID, childID: UUID) {
        let sourceDefault: Bool = {
            guard case .instance(let inst)? = findNode(instanceID)?.content,
                  let source = document.model.source(for: inst.sourceID),
                  let child = Self.nodeInTree(childID, in: source.children) else { return true }
            return child.isVisible
        }()
        updateNodeTree(instanceID, action: "Toggle Component Layer") { node in
            guard case .instance(var inst) = node.content else { return }
            let current = inst.isLayerVisible(childID, sourceDefault: sourceDefault)
            let newValue = !current
            inst.layerVisibility.removeAll { $0.layerID == childID }
            if newValue != sourceDefault {
                inst.layerVisibility.append(LayerVisibilityOverride(layerID: childID, isVisible: newValue))
            }
            node.content = .instance(inst)
        }
    }

    // MARK: Edits (each a single undo step; recurse so nested group layers work)

    /// Find and mutate a node anywhere in the tree (top-level or inside groups).
    private func updateNodeTree(_ id: UUID, action: String, _ change: (inout Node) -> Void) {
        func recurse(_ nodes: [Node]) -> [Node] {
            nodes.map { node in
                var node = node
                if node.id == id {
                    change(&node)
                } else if case .group(let children) = node.content {
                    node.content = .group(children: recurse(children))
                }
                return node
            }
        }
        commitNodes(recurse(scopeNodes), action)
    }

    /// Find a node anywhere in an arbitrary tree (used to read a component source's
    /// nested layer defaults — the source's children live outside `scopeNodes`).
    private static func nodeInTree(_ id: UUID, in nodes: [Node]) -> Node? {
        for n in nodes {
            if n.id == id { return n }
            if case .group(let k) = n.content, let f = nodeInTree(id, in: k) { return f }
        }
        return nil
    }

    private func findNode(_ id: UUID) -> Node? {
        func recurse(_ nodes: [Node]) -> Node? {
            for node in nodes {
                if node.id == id { return node }
                if case .group(let children) = node.content, let found = recurse(children) { return found }
            }
            return nil
        }
        return recurse(scopeNodes)
    }

    private func toggleVisible(_ id: UUID) {
        let willShow = !(findNode(id)?.isVisible ?? true)
        updateNodeTree(id, action: willShow ? "Show" : "Hide") { $0.isVisible.toggle() }
    }

    private func toggleLock(_ id: UUID) {
        let willLock = !(findNode(id)?.isLocked ?? false)
        updateNodeTree(id, action: willLock ? "Lock" : "Unlock") { $0.isLocked.toggle() }
    }

    private func rename(_ id: UUID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateNodeTree(id, action: "Rename") { $0.name = trimmed }
    }

    private func renameComponent(_ sourceID: UUID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let si = document.model.sources.firstIndex(where: { $0.id == sourceID }),
              document.model.sources[si].name != trimmed else { return }
        var model = document.model
        model.sources[si].name = trimmed
        document.setModel(model, undoManager: undoManager, actionName: "Rename Component")
    }

    private func setInstanceState(_ instanceID: UUID, stateID: UUID?) {
        updateNodeTree(instanceID, action: "Set Component State") { node in
            guard case .instance(var instance) = node.content else { return }
            instance.activeStateID = stateID
            node.content = .instance(instance)
        }
    }

    private func setNestedInstanceState(_ rootInstanceID: UUID, path: [UUID], stateID: UUID?) {
        guard !path.isEmpty else { return }
        updateNodeTree(rootInstanceID, action: "Set Nested Component State") { node in
            guard case .instance(var instance) = node.content else { return }
            instance.nestedStateOverrides.removeAll { $0.instancePath == path }
            instance.nestedStateOverrides.append(
                NestedInstanceStateOverride(instancePath: path, stateID: stateID))
            node.content = .instance(instance)
        }
    }

    /// Instance names are independent from their source component names.
    private func displayName(_ node: Node) -> String {
        guard node.name.isEmpty else { return node.name }
        if case .instance = node.content { return "Instance" }
        return "Layer"
    }

    /// For a right-clicked row: act on the whole selection if the row is part of it,
    /// otherwise just that one row (matches Finder / every layer list).
    private func selectionOrRow(_ id: UUID) -> Set<UUID> {
        app.selectedNodeIDs.contains(id) ? app.selectedNodeIDs : [id]
    }

    /// Copy Style from a row — capture its effects + blend mode + opacity into the
    /// shared clipboard. Reimplemented here (like Delete) so it works whatever has
    /// focus; the canvas owns the equivalent action for canvas-side use.
    private func copyStyleFromRow(_ id: UUID) {
        guard let n = findNode(id) else { return }
        app.copiedLayerStyle = n.layerStyle
    }

    /// Paste Style onto `ids` (and any nested descendants matched) as one undo step,
    /// touching appearance only. Mirrors the canvas's Paste Style.
    private func pasteStyleToRows(_ ids: Set<UUID>) {
        guard let style = app.copiedLayerStyle, !ids.isEmpty else { return }
        func recurse(_ nodes: [Node]) -> [Node] {
            nodes.map { node in
                var node = node
                if ids.contains(node.id) {
                    node.applyLayerStyle(style)
                } else if case .group(let children) = node.content {
                    node.content = .group(children: recurse(children))
                }
                return node
            }
        }
        commitNodes(recurse(scopeNodes), "Paste Style")
    }

    /// Delete `ids` (and any nested descendants) from the scoped node list as one
    /// undo step, reflowing so an auto-layout parent re-packs. Mirrors the canvas's
    /// Delete so layers picked in THIS panel can be removed without canvas focus.
    /// Arrow-key nudge for layers selected in THIS panel (canvas keyDown can't
    /// fire while the List holds focus). Moves in doc space; ⇧ steps by 10pt.
    /// (Ancestor-group rotation isn't compensated here — the canvas handles that
    /// case; panel nudging targets the common unrotated layout.)
    private func nudgeSelectedLayers(_ direction: MoveCommandDirection) {
        let ids = app.selectedNodeIDs
        guard !ids.isEmpty else { return }
        let large = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let step: CGFloat = large ? 10 : 1
        var d = CGPoint.zero
        switch direction {
        case .left:  d.x = -step
        case .right: d.x =  step
        case .up:    d.y = -step
        case .down:  d.y =  step
        @unknown default: return
        }
        var nodes = scopeNodes
        Self.moveIDs(ids, by: d, in: &nodes)
        commitNodes(AutoLayoutEngine.reflowed(nodes), ids.count == 1 ? "Move Shape" : "Move Shapes")
    }

    /// Add `d` to the frame origin of every node in `ids`, recursing into groups
    /// (a node's origin is in its parent's space).
    private static func moveIDs(_ ids: Set<UUID>, by d: CGPoint, in nodes: inout [Node]) {
        for i in nodes.indices {
            if ids.contains(nodes[i].id) {
                nodes[i].frame.origin.x += d.x
                nodes[i].frame.origin.y += d.y
            }
            if case .group(var k) = nodes[i].content {
                moveIDs(ids, by: d, in: &k)
                nodes[i].content = .group(children: k)
            }
        }
    }

    private func deleteLayers(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var nodes = scopeNodes
        Self.removeIDs(ids, from: &nodes)
        commitNodes(AutoLayoutEngine.reflowed(nodes), ids.count == 1 ? "Delete" : "Delete Layers")
        app.selectedNodeIDs = []
    }

    /// Remove nodes with these ids anywhere in the tree (recursing into groups).
    private static func removeIDs(_ ids: Set<UUID>, from nodes: inout [Node]) {
        nodes.removeAll { ids.contains($0.id) }
        for i in nodes.indices {
            if case .group(var k) = nodes[i].content {
                removeIDs(ids, from: &k)
                nodes[i].content = .group(children: k)
            }
        }
    }

    // MARK: Drag & drop — reorder, drop INTO a group, or INTO a component source
    //
    // `place` is in DISPLAY terms (before = visually above). Model order is the
    // reverse of display, so "above" maps to a LATER model index. Frames are kept at
    // their absolute position when a node changes parent (group children are stored
    // relative to the group's origin).

    /// Accumulated parent-group origin of a node in doc space (`.zero` if top-level).
    private func parentOffset(of id: UUID, in nodes: [Node], _ off: CGPoint = .zero) -> CGPoint? {
        for n in nodes {
            if n.id == id { return off }
            if case .group(let k) = n.content,
               let r = parentOffset(of: id, in: k, CGPoint(x: off.x + n.frame.minX, y: off.y + n.frame.minY)) { return r }
        }
        return nil
    }

    /// The id of the group that directly contains `id`, or nil if it's top-level.
    private func parentNodeID(of id: UUID, in nodes: [Node], _ current: UUID? = nil) -> UUID? {
        for n in nodes {
            if n.id == id { return current }
            if case .group(let k) = n.content, let r = parentNodeID(of: id, in: k, n.id) { return r }
        }
        return nil
    }

    private func subtreeContains(_ id: UUID, _ node: Node) -> Bool {
        if node.id == id { return true }
        if case .group(let k) = node.content { return k.contains { subtreeContains(id, $0) } }
        return false
    }

    @discardableResult
    private static func extract(_ id: UUID, from nodes: inout [Node]) -> Node? {
        if let i = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: i) }
        for j in nodes.indices {
            if case .group(var k) = nodes[j].content {
                if let found = extract(id, from: &k) { nodes[j].content = .group(children: k); return found }
            }
        }
        return nil
    }

    /// Insert `node` at the BACK of a group's children (model index 0 = display
    /// bottom — Photoshop-style "added to the bottom of the group").
    @discardableResult
    private static func insertIntoGroup(_ node: Node, group groupID: UUID, in nodes: inout [Node]) -> Bool {
        for j in nodes.indices {
            if nodes[j].id == groupID, case .group(var k) = nodes[j].content {
                k.insert(node, at: 0); nodes[j].content = .group(children: k); return true
            }
            if case .group(var k) = nodes[j].content {
                if insertIntoGroup(node, group: groupID, in: &k) { nodes[j].content = .group(children: k); return true }
            }
        }
        return false
    }

    /// Insert `node` next to `targetID` in whatever array holds it. `afterInModel`
    /// places it at the higher model index (= visually above, since display reverses).
    @discardableResult
    private static func insertSibling(_ node: Node, near targetID: UUID, afterInModel: Bool, in nodes: inout [Node]) -> Bool {
        if let i = nodes.firstIndex(where: { $0.id == targetID }) {
            nodes.insert(node, at: afterInModel ? i + 1 : i); return true
        }
        for j in nodes.indices {
            if case .group(var k) = nodes[j].content {
                if insertSibling(node, near: targetID, afterInModel: afterInModel, in: &k) {
                    nodes[j].content = .group(children: k); return true
                }
            }
        }
        return false
    }

    /// Handle a drop of `draggedID` onto `targetID` at `place`.
    func handleDrop(_ draggedID: UUID, onto targetID: UUID, place: DropPlace) {
        guard draggedID != targetID, let dragged = findNode(draggedID) else { return }
        // Never drop a group into its own descendant (would orphan the subtree).
        if subtreeContains(targetID, dragged) { return }

        let original = scopeNodes
        let oldOff = parentOffset(of: draggedID, in: original) ?? .zero

        // Into a component INSTANCE → add to its shared source (affects all instances).
        if place == .into, case .instance(let inst)? = findNode(targetID)?.content {
            moveIntoSource(draggedID, instance: targetID, sourceID: inst.sourceID, oldOffset: oldOff)
            return
        }

        var nodes = original
        guard var moved = Self.extract(draggedID, from: &nodes) else { return }
        let abs = CGPoint(x: moved.frame.minX + oldOff.x, y: moved.frame.minY + oldOff.y)

        if place == .into, case .group? = findNode(targetID)?.content {
            let gAbsOff = parentOffset(of: targetID, in: original) ?? .zero
            let gOrigin = findNode(targetID)?.frame.origin ?? .zero
            moved.frame.origin = CGPoint(x: abs.x - gAbsOff.x - gOrigin.x, y: abs.y - gAbsOff.y - gOrigin.y)
            guard Self.insertIntoGroup(moved, group: targetID, in: &nodes) else { return }
        } else {
            // Reorder as a sibling of the target (same parent the target lives in).
            let parentID = parentNodeID(of: targetID, in: original)
            let pAbsOff = parentID.flatMap { parentOffset(of: $0, in: original) } ?? .zero
            let pOrigin = parentID.flatMap { findNode($0)?.frame.origin } ?? .zero
            moved.frame.origin = CGPoint(x: abs.x - pAbsOff.x - pOrigin.x, y: abs.y - pAbsOff.y - pOrigin.y)
            guard Self.insertSibling(moved, near: targetID, afterInModel: place == .before, in: &nodes) else { return }
        }
        commitNodes(nodes, "Move Layer")
        app.selectedNodeIDs = [draggedID]
    }

    /// Move a document node into a component source's children (source-local coords).
    private func moveIntoSource(_ draggedID: UUID, instance instanceID: UUID, sourceID: UUID, oldOffset: CGPoint) {
        guard case .document = scope,
              let instance = findNode(instanceID),
              let dragged = findNode(draggedID),
              document.model.canInsert([dragged], intoSource: sourceID),
              let si = document.model.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        var model = document.model
        var top = model.nodes
        guard var moved = Self.extract(draggedID, from: &top) else { return }
        // Source children render at the instance's origin; keep the node's position.
        let absX = moved.frame.minX + oldOffset.x, absY = moved.frame.minY + oldOffset.y
        moved.frame.origin = CGPoint(x: absX - instance.frame.minX, y: absY - instance.frame.minY)
        model.nodes = top
        model.sources[si].children.insert(moved, at: 0)
        document.setModel(model, undoManager: undoManager, actionName: "Add to Component")
        app.selectedNodeIDs = []
    }
}

/// Where a dragged layer will land relative to a target row (DISPLAY terms).
enum DropPlace { case before, after, into }
struct LayerDropIndicator: Equatable { let id: UUID; let place: DropPlace }

// MARK: - Outline row (handles expand/collapse for groups + instances)

private struct LayerOutlineRow: View {
    let node: Node
    let document: ExpDocument
    @Binding var expanded: Set<UUID>
    @Binding var draggingID: UUID?
    @Binding var dropIndicator: LayerDropIndicator?
    /// When the artboard owning this row is the active one, the row draws a thin
    /// accent border down its leading edge (set by the panel; nested rows inherit it).
    var inActiveSection: Bool = false
    /// Indentation depth (0 = a root layer). Drives the manual indent; the two
    /// leading accent slots stay pinned at the panel's far-left regardless of depth.
    var depth: Int = 0
    @Environment(AppState.self) private var app
    /// Fixed row height: every row is the same height and flush with its neighbours,
    /// so the drop thresholds are stable and the before/after insertion lines land at
    /// the exact same y (one line per gap, not two). A measured height jittered.
    private var rowH: CGFloat { instance == nil ? 28 : 42 }
    let onToggleVisible: (UUID) -> Void
    let onToggleLock: (UUID) -> Void
    let onRename: (UUID, String) -> Void
    let onRenameComponent: (UUID, String) -> Void
    let onSetInstanceState: (UUID, UUID?) -> Void
    let onSetNestedInstanceState: (UUID, [UUID], UUID?) -> Void
    let onToggleInstanceLayer: (UUID, UUID) -> Void
    let onDrop: (UUID, UUID, DropPlace) -> Void
    let onDelete: (UUID) -> Void
    let onCopyStyle: (UUID) -> Void
    let onPasteStyle: (UUID) -> Void
    let onSelect: (UUID) -> Void

    private func displayName(_ n: Node) -> String {
        if !n.name.isEmpty { return n.name }
        if case .instance = n.content { return "Instance" }
        return "Layer"
    }

    private var isExpanded: Bool { expanded.contains(node.id) }
    private func toggleExpanded() {
        if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
    }
    /// A group's child layers, or nil for a leaf.
    private var groupChildren: [Node]? {
        if case .group(let kids) = node.content { return kids }
        return nil
    }
    private var instance: ComponentInstance? {
        if case .instance(let inst) = node.content { return inst }
        return nil
    }
    private var instanceSource: ComponentSource? {
        guard let inst = instance else { return nil }
        return document.model.source(for: inst.sourceID)
    }
    /// Whether this row has an expand chevron (a group or a resolvable instance).
    private var hasDisclosure: Bool { groupChildren != nil || instanceSource != nil }

    var body: some View {
        VStack(spacing: 0) {
            rowDecorated
            // Manual disclosure: children render here (no native DisclosureGroup),
            // so the leading accent slots stay pinned to the panel's far-left and
            // indentation is fully under our control.
            if isExpanded {
                if let kids = groupChildren {
                    ForEach(Array(kids.reversed())) { child in
                        LayerOutlineRow(node: child, document: document, expanded: $expanded,
                                        draggingID: $draggingID, dropIndicator: $dropIndicator,
                                        inActiveSection: inActiveSection, depth: depth + 1,
                                        onToggleVisible: onToggleVisible, onToggleLock: onToggleLock,
                                        onRename: onRename, onRenameComponent: onRenameComponent,
                                        onSetInstanceState: onSetInstanceState,
                                        onSetNestedInstanceState: onSetNestedInstanceState,
                                        onToggleInstanceLayer: onToggleInstanceLayer,
                                        onDrop: onDrop, onDelete: onDelete,
                                        onCopyStyle: onCopyStyle, onPasteStyle: onPasteStyle,
                                        onSelect: onSelect)
                    }
                } else if let inst = instance, let source = instanceSource {
                    let effective = inst.applyingState(source.states.first { $0.id == inst.activeStateID })
                    ForEach(Array(source.children.reversed())) { child in
                        InstanceLayerRow(child: child, inst: effective, document: document,
                                         onSetState: { path, stateID in
                                             onSetNestedInstanceState(node.id, path, stateID)
                                         },
                                         onToggle: { onToggleInstanceLayer(node.id, $0) },
                                         depth: depth + 1)
                    }
                }
            }
        }
    }

    /// The single row: the visual `LayerRow` plus drag source / drop target and the
    /// before/after/into drop indicators.
    private var rowDecorated: some View {
        LayerRow(node: node,
                 displayName: displayName(node),
                 componentSource: instanceSource,
                 componentStateID: instance?.activeStateID,
                 depth: depth,
                 hasDisclosure: hasDisclosure,
                 isExpanded: isExpanded,
                 inActiveSection: inActiveSection,
                 onToggleVisible: { onToggleVisible(node.id) },
                 onToggleLock: { onToggleLock(node.id) },
                 onToggleExpanded: toggleExpanded,
                 onSelect: { onSelect(node.id) },
                 onRename: { onRename(node.id, $0) },
                 onRenameComponent: instanceSource.map { source in
                     { onRenameComponent(source.id, $0) }
                 },
                 onSetComponentState: instanceSource.map { _ in
                     { onSetInstanceState(node.id, $0) }
                 },
                 onDelete: { onDelete(node.id) },
                 onCopyStyle: { onCopyStyle(node.id) },
                 onPasteStyle: { onPasteStyle(node.id) },
                 onEditComponent: instance.map { instance in
                     {
                         SourceEditorWindowManager.shared.open(
                             sourceID: instance.sourceID,
                             document: document,
                             undoManager: nil)
                     }
                 })
            .frame(height: rowH)
            .background {
                if dropIndicator?.id == node.id, dropIndicator?.place == .into {
                    RoundedRectangle(cornerRadius: EXPMetric.radiusDrop).fill(EXPColor.accentSubtle2)
                }
            }
            .overlay(alignment: .top) {
                if dropIndicator?.id == node.id, dropIndicator?.place == .before { dropLine }
            }
            .overlay(alignment: .bottom) {
                if dropIndicator?.id == node.id, dropIndicator?.place == .after { dropLine }
            }
            .onDrag {
                draggingID = node.id
                return NSItemProvider(object: node.id.uuidString as NSString)
            }
            .onDrop(of: [.plainText, .text], delegate: LayerDropDelegate(
                targetID: node.id, acceptsInto: hasDisclosure, rowHeight: rowH,
                draggingID: $draggingID, indicator: $dropIndicator, perform: onDrop))
    }

    private var dropLine: some View {
        Capsule().fill(EXPColor.accent)
            .frame(height: EXPMetric.strokeDropline)
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
    }
}

/// Location-aware drop target: top/bottom edge → reorder (before/after), middle of a
/// group/instance row → drop INTO it.
private struct LayerDropDelegate: DropDelegate {
    let targetID: UUID
    let acceptsInto: Bool
    /// Actual height of the target row (measured), so the thresholds are correct.
    let rowHeight: CGFloat
    @Binding var draggingID: UUID?
    @Binding var indicator: LayerDropIndicator?
    let perform: (UUID, UUID, DropPlace) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let d = draggingID, d != targetID else { return DropProposal(operation: .forbidden) }
        let h = max(1, rowHeight)
        let y = info.location.y
        let place: DropPlace
        if acceptsInto {
            if y < h * 0.28 { place = .before }
            else if y > h * 0.72 { place = .after }
            else { place = .into }
        } else {
            place = y < h * 0.5 ? .before : .after
        }
        indicator = LayerDropIndicator(id: targetID, place: place)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if indicator?.id == targetID { indicator = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { indicator = nil; draggingID = nil }
        guard let d = draggingID, let ind = indicator, ind.id == targetID else { return false }
        perform(d, targetID, ind.place)
        return true
    }
}

// MARK: - Row

private struct LayerRow: View {
    let node: Node
    let displayName: String
    let componentSource: ComponentSource?
    let componentStateID: UUID?
    let depth: Int
    let hasDisclosure: Bool
    let isExpanded: Bool
    let inActiveSection: Bool
    let onToggleVisible: () -> Void
    let onToggleLock: () -> Void
    let onToggleExpanded: () -> Void
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onRenameComponent: ((String) -> Void)?
    let onSetComponentState: ((UUID?) -> Void)?
    let onDelete: () -> Void
    let onCopyStyle: () -> Void
    let onPasteStyle: () -> Void
    let onEditComponent: (() -> Void)?

    @State private var editing = false
    @State private var draft = ""
    @State private var editingComponent = false
    @State private var componentDraft = ""
    @State private var hovering = false
    @FocusState private var nameFocused: Bool
    @FocusState private var componentNameFocused: Bool
    @Environment(AppState.self) private var app

    private let chevronW: CGFloat = 10
    private let indentStep: CGFloat = 12

    var body: some View {
        // spacing 0 — every gap is an explicit token (per the row-layout spec).
        HStack(spacing: 0) {
            // 1) active-ARTBOARD rule — hairline, accent only when the section is
            //    active; transparent otherwise. First element → pinned far-left, and
            //    because rows are flush it reads as one continuous line down the group.
            Rectangle()
                .fill(inActiveSection ? EXPColor.accent : Color.clear)
                .frame(width: EXPMetric.strokeHairline)

            // 2) active-LAYER bar — xxs, accent only when THIS layer is selected.
            Rectangle()
                .fill(isActive ? EXPColor.accent : Color.clear)
                .frame(width: EXPMetric.xxs)

            // depth indent (the two accent slots above stay pinned at far-left).
            if depth > 0 { Color.clear.frame(width: CGFloat(depth) * indentStep) }

            // 3) chevron block — FIXED width so chevron rows and leaf rows align.
            if hasDisclosure {
                Color.clear.frame(width: EXPMetric.xxs)
                Button(action: onToggleExpanded) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(EXPColor.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: chevronW, height: chevronW)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Color.clear.frame(width: EXPMetric.xxs)
            } else {
                Color.clear.frame(width: EXPMetric.xxs + chevronW + EXPMetric.xxs)
            }

            // eye
            Button(action: onToggleVisible) {
                Image(systemName: node.isVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(node.isVisible ? EXPColor.textSecondary : EXPColor.textTertiary)
            .help(node.isVisible ? "Hide" : "Show")
            .accessibilityLabel(node.isVisible ? "Hide \(node.name)" : "Show \(node.name)")

            Color.clear.frame(width: EXPMetric.xs)

            // layer type glyph (a touch smaller than the eye/lock). Components
            // (instances) tint accent so they read clearly apart from ordinary
            // layers on the wall/artboard.
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(isComponentInstance ? EXPColor.accent : EXPColor.textTertiary)
                .frame(width: 14)

            Color.clear.frame(width: EXPMetric.xs)

            // name
            nameView

            Spacer(minLength: EXPMetric.sm)

            // lock — right edge
            Button(action: onToggleLock) {
                Image(systemName: node.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(node.isLocked ? EXPColor.textPrimary : EXPColor.textTertiary)
            .help(node.isLocked ? "Unlock" : "Lock")
            .accessibilityLabel(node.isLocked ? "Unlock \(node.name)" : "Lock \(node.name)")

            Color.clear.frame(width: EXPMetric.sm)   // trailing space.sm
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(node.isVisible ? 1 : 0.5)
        .background(isActive ? EXPColor.rowSelected : (hovering ? EXPColor.rowHover : Color.clear))
        .contentShape(Rectangle())
        // SINGLE click anywhere on the row (that isn't a button) selects this layer;
        // the name's double-click (below) renames. A single tap on the name falls
        // through to here because the name only claims the count:2 gesture.
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
        .contextMenu {
            if let onEditComponent {
                Button("Edit Component", action: onEditComponent)
                Button("Rename Component…") { beginComponentRename() }
                Divider()
            }
            Button("Rename") { beginRename() }
            Button("Center in Canvas") { centerInCanvas() }
            Divider()
            Button("Copy Style") { onCopyStyle() }
            Button("Paste Style") { onPasteStyle() }
                .disabled(app.copiedLayerStyle == nil)
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder private var nameView: some View {
        if editing {
            TextField("Name", text: $draft)
                .textFieldStyle(.exp)
                .font(EXPType.layerFont())
                .focused($nameFocused)
                .onSubmit { commit() }
                .onExitCommand { editing = false }   // Esc cancels (discard)
                .onChange(of: nameFocused) { _, focused in
                    if !focused, editing { commit() }
                }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    // SF Compact, medium when this layer is active (Session-133).
                    .expLayerName(active: isActive)
                    .foregroundStyle(node.isLocked ? EXPColor.textTertiary : EXPColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Double-click always renames the INSTANCE/layer, never its source.
                    .onTapGesture(count: 2) { beginRename() }
                if let source = componentSource {
                    HStack(spacing: 3) {
                        componentNameView(source)
                        componentStateMenu(source)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func componentNameView(_ source: ComponentSource) -> some View {
        if editingComponent {
            TextField("Component name", text: $componentDraft)
                .textFieldStyle(.plain)
                .font(.system(size: EXPType.micro))
                .foregroundStyle(EXPColor.accent)
                .focused($componentNameFocused)
                .onSubmit { commitComponentRename() }
                .onExitCommand { editingComponent = false }
                .onChange(of: componentNameFocused) { _, focused in
                    if !focused, editingComponent { commitComponentRename() }
                }
        } else {
            Text(source.name)
                .font(.system(size: EXPType.micro, weight: .medium))
                .foregroundStyle(EXPColor.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(EXPColor.accentSubtle2, in: Capsule())
                .help("Source component: \(source.name). Right-click to rename it.")
        }
    }

    private func componentStateMenu(_ source: ComponentSource) -> some View {
        Menu {
            Button {
                onSetComponentState?(nil)
            } label: {
                if componentStateID == nil { Label("Default", systemImage: "checkmark") }
                else { Text("Default") }
            }
            ForEach(source.states) { state in
                Button {
                    onSetComponentState?(state.id)
                } label: {
                    if componentStateID == state.id { Label(state.name, systemImage: "checkmark") }
                    else { Text(state.name) }
                }
            }
        } label: {
            Text(source.states.first { $0.id == componentStateID }?.name ?? "Default")
                .font(.system(size: EXPType.micro))
                .foregroundStyle(EXPColor.textSecondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Component state")
        .accessibilityLabel("State for \(displayName)")
    }

    private func beginRename() {
        draft = displayName
        editing = true
        // Focus the field, then select-all so typing replaces the name.
        DispatchQueue.main.async {
            nameFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.sendAction(NSSelectorFromString("selectAll:"), to: nil, from: nil)
            }
        }
    }

    private func commit() {
        onRename(draft)
        editing = false
    }

    private func beginComponentRename() {
        guard let source = componentSource else { return }
        componentDraft = source.name
        editingComponent = true
        DispatchQueue.main.async { componentNameFocused = true }
    }

    private func commitComponentRename() {
        onRenameComponent?(componentDraft)
        editingComponent = false
    }

    private func centerInCanvas() {
        app.centerOn(node.frame)
    }

    /// This row's layer is the active/selected one (drives the SF-Compact
    /// medium weight + the thick left accent bar drawn by the outline row).
    private var isActive: Bool { app.selectedNodeIDs.contains(node.id) }
    private var typeIcon: String { nodeTypeIcon(node) }
    /// True when this row is a placed component (instance) — drives the accent
    /// tint that sets components apart from ordinary layers.
    private var isComponentInstance: Bool {
        if case .instance = node.content { return true }
        return false
    }
}

/// SF Symbol for a node's content type (shared by layer rows).
func nodeTypeIcon(_ node: Node) -> String {
    switch node.content {
    case .rectangle: return "rectangle"
    case .ellipse:   return "circle"
    case .polygon:   return "triangle"
    case .line:      return "line.diagonal"
    case .path:      return "scribble"
    case .text:      return "textformat"
    case .group:     return "folder"
    case .instance:  return "rectangle.3.group"
    case .image:     return "photo"
    }
}

/// A row for one layer of a selected instance, with a per-instance visibility
/// toggle (writes the instance's `layerVisibility` override). Recurses into groups
/// so nested layers inside a grouped component can be toggled for this instance.
private struct InstanceLayerRow: View {
    let child: Node
    /// Effective instance for the source whose `child` belongs to. Its own active
    /// state has already been folded in by the parent row.
    let inst: ComponentInstance
    let document: ExpDocument
    /// Full path from the placed root instance to a nested component instance.
    let onSetState: ([UUID], UUID?) -> Void
    /// Toggle the per-instance visibility of the given layer id (this row or a
    /// nested descendant), routed up to the panel's `toggleInstanceLayer`.
    let onToggle: (UUID) -> Void
    /// Indentation depth (passed down from the owning instance row).
    var depth: Int = 0
    var instancePath: [UUID] = []
    var visibilityEditable = true
    @State private var expanded = false

    private var hidden: Bool { !inst.isLayerVisible(child.id, sourceDefault: child.isVisible) }
    private var effectiveChild: Node { inst.applyingOverrides(to: child) }
    private var nestedInstance: ComponentInstance? {
        if case .instance(let nested) = effectiveChild.content { return nested }
        return nil
    }
    private var nestedSource: ComponentSource? {
        guard let nested = nestedInstance else { return nil }
        return document.model.source(for: nested.sourceID)
    }
    private var displayName: String {
        if !child.name.isEmpty { return child.name }
        return nestedSource == nil ? "Layer" : "Instance"
    }
    private var currentInstancePath: [UUID] { instancePath + (nestedInstance == nil ? [] : [child.id]) }
    private var groupChildren: [Node]? {
        if case .group(let children) = child.content { return children }
        return nil
    }
    private var hasDisclosure: Bool { groupChildren != nil || nestedSource != nil }

    var body: some View {
        VStack(spacing: 0) {
            row
            if expanded, let kids = groupChildren {
                ForEach(Array(kids.reversed())) { k in
                    InstanceLayerRow(child: k, inst: inst, document: document,
                                     onSetState: onSetState,
                                     onToggle: onToggle, depth: depth + 1,
                                     instancePath: instancePath,
                                     visibilityEditable: visibilityEditable)
                }
            } else if expanded, let nested = nestedInstance, let source = nestedSource {
                let effective = nested.applyingState(source.states.first { $0.id == nested.activeStateID })
                ForEach(Array(source.children.reversed())) { nestedChild in
                    InstanceLayerRow(child: nestedChild, inst: effective, document: document,
                                     onSetState: onSetState,
                                     onToggle: onToggle, depth: depth + 1,
                                     instancePath: currentInstancePath,
                                     visibilityEditable: false)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            // Manual disclosure avoids native DisclosureGroup clipping inside the
            // outer List row and keeps every recursive level aligned predictably.
            Color.clear.frame(width: 4 + CGFloat(depth) * 12)
            if hasDisclosure {
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(EXPColor.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse \(displayName)" : "Expand \(displayName)")
                .accessibilityLabel(expanded ? "Collapse \(displayName)" : "Expand \(displayName)")
            } else {
                Color.clear.frame(width: 14)
            }
            Color.clear.frame(width: 4)
            Button { if visibilityEditable { onToggle(child.id) } } label: {
                Image(systemName: hidden ? "eye.slash.fill" : "eye.fill")
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(hidden ? EXPColor.textTertiary : EXPColor.textSecondary)
            .disabled(!visibilityEditable)
            .help(hidden ? "Show in this instance" : "Hide in this instance")
            .accessibilityLabel(hidden ? "Show \(child.name) in this instance"
                                       : "Hide \(child.name) in this instance")

            Color.clear.frame(width: EXPMetric.xs)
            Image(systemName: nodeTypeIcon(child))
                .font(.system(size: 10))
                .foregroundStyle(nestedSource == nil ? EXPColor.textTertiary : EXPColor.accent)
                .frame(width: 14)

            Color.clear.frame(width: EXPMetric.xs)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .expLayerName(active: false)
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let source = nestedSource, let nested = nestedInstance {
                    HStack(spacing: 3) {
                        Text(source.name)
                            .font(.system(size: EXPType.micro, weight: .medium))
                            .foregroundStyle(EXPColor.accent)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(EXPColor.accentSubtle2, in: Capsule())
                        nestedStateMenu(source: source, instance: nested)
                    }
                }
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: EXPMetric.sm)
        }
        .frame(height: nestedSource == nil ? 28 : 42)
        .opacity(hidden ? 0.5 : 1)
        .contextMenu {
            if let nestedSource {
                Button("Edit Component") {
                    SourceEditorWindowManager.shared.open(sourceID: nestedSource.id,
                                                          document: document,
                                                          undoManager: nil)
                }
            }
        }
        .help(nestedSource.map { "Nested component: \($0.name)" } ?? child.name)
    }

    private func nestedStateMenu(source: ComponentSource, instance: ComponentInstance) -> some View {
        Menu {
            Button {
                onSetState(currentInstancePath, nil)
            } label: {
                if instance.activeStateID == nil { Label("Default", systemImage: "checkmark") }
                else { Text("Default") }
            }
            ForEach(source.states) { state in
                Button {
                    onSetState(currentInstancePath, state.id)
                } label: {
                    if instance.activeStateID == state.id { Label(state.name, systemImage: "checkmark") }
                    else { Text(state.name) }
                }
            }
        } label: {
            Text(source.states.first { $0.id == instance.activeStateID }?.name ?? "Default")
                .font(.system(size: EXPType.micro))
                .foregroundStyle(EXPColor.textSecondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Nested component state")
        .accessibilityLabel("State for \(displayName)")
    }
}

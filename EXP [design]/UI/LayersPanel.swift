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
    /// Expansion for rows INSIDE a component instance, keyed by a per-placement
    /// path rather than a node id — the same source child appears under every
    /// placement of its component, so a plain id would expand them all together.
    ///
    /// This lives at panel level, NOT as `@State` on the row, and that is the whole
    /// point. `List` on macOS caches each row's measured height. A nested row
    /// holding its own private expansion state changes the outer row's height
    /// without the List ever being told, so the cached height goes stale and you
    /// get a wrong scrollbar until a scroll forces re-measurement. Routing it
    /// through a binding the panel owns means the change is observable from the
    /// List row itself. It also stops nested expansion resetting whenever SwiftUI
    /// recycles a row, which is why the old behavior was intermittent.
    @State private var expandedNested: Set<[UUID]> = []
    @State private var collapsedSections: Set<String> = []   // collapsed artboard/Wall sections
    /// Anchor for Shift-range selection of ARTBOARD sections. Deliberately separate
    /// from `app.selectionAnchorID`, which anchors node rows — one field holding
    /// either kind of id would let a node anchor a board range and vice versa.
    @State private var artboardAnchorID: UUID?
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
        case .document: return document.model.page(for: app.activeCanvasPageID)?.nodes ?? []
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
            guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
            model.pages[pageIndex].nodes = nodes
            model.reconcileArtboardOwnership(on: model.pages[pageIndex].id)
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            if let state = activeEditingState,
               let sti = model.sources[si].states.firstIndex(where: { $0.id == state.id }) {
                let (newBase, newState) = ComponentStateEditing.capture(
                    base: model.sources[si].children, edited: nodes, state: state)
                let reflowed = model.reflowed(newBase)
                model.sources[si].children = reflowed
                model.sources[si].states[sti] = newState
                if fitSourceBounds,
                   let bounds = model.managedRootBounds(in: reflowed) {
                    model.sources[si].origin = bounds.origin
                    model.sources[si].size = bounds.size
                }
            } else {
                let reflowed = model.reflowed(nodes)
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
                                expandedNested: $expandedNested,
                                draggingID: $draggingID,
                                dropIndicator: $dropIndicator,
                                inActiveSection: group.id == activeSectionID,
                                allowsPageTransfer: scope == .document,
                                onToggleVisible: { toggleVisible($0) },
                                onToggleLock: { toggleLock($0) },
                                onRename: { rename($0, $1) },
                                onRenameComponent: { renameComponent($0, $1) },
                                onSetInstanceState: { setInstanceState($0, stateID: $1) },
                                onSetNestedInstanceState: { setNestedInstanceState($0, path: $1, stateID: $2) },
                                onToggleInstanceLayer: { toggleInstanceLayer(instanceID: $0, childID: $1) },
                                onDrop: { handleDrop($0, onto: $1, place: $2) },
                                // A row's context menu belongs to that row. In
                                // particular, duplicating a child must not also
                                // duplicate an enclosing group left in the
                                // broader canvas selection. Keyboard Duplicate
                                // continues to operate on the full selection.
                                onDuplicate: { duplicateLayers([$0]) },
                                onCopy: { copyLayers(selectionOrRow($0)) },
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
                        layerSectionHeader(group, active: group.id == activeSectionID)
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
            // Like Delete and arrow keys above, opacity digits are consumed by
            // the focused List before the canvas can see them. Handle the same
            // 0→100%, 1…9→10…90% contract at the panel focus boundary.
            .onKeyPress(phases: [.down]) { press in
                guard !press.modifiers.contains(.command),
                      !press.modifiers.contains(.control),
                      !press.modifiers.contains(.option) else { return .ignored }
                // BUG-038: a row's rename field is `@State` INSIDE the row, so this
                // container cannot know one is open — and returning `.handled` for a
                // digit typed into a layer name both swallowed the character and set
                // the layer's opacity. Ask AppKit who actually holds focus instead.
                // Covers the rename field, the component-name field, and anything
                // added later without plumbing editing state up through every row.
                if isTypingInTextField() { return .ignored }
                let digit: Int
                switch press.key {
                case "0": digit = 0
                case "1": digit = 1
                case "2": digit = 2
                case "3": digit = 3
                case "4": digit = 4
                case "5": digit = 5
                case "6": digit = 6
                case "7": digit = 7
                case "8": digit = 8
                case "9": digit = 9
                default: return .ignored
                }
                setOpacityOnSelectedLayers(
                    digit == 0 ? 1 : Double(digit) / 10)
                return .handled
            }
            // A focused SwiftUI List is otherwise a responder-chain dead end for
            // the standard Copy/Paste menu commands. Register native command
            // handlers so keyboard shortcuts AND Edit-menu clicks use the same
            // clipboard payload as the canvas.
            .onCopyCommand {
                layerCopyProviders()
            }
            .onPasteCommand(of: [UTType(exportedAs: CanvasNSView.nodePasteboardType.rawValue)]) { _ in
                sendCanvasAction("paste:")
            }
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

    // MARK: Artboard section header — the name is a real control

    /// Kept outside `body` so the large recursive List remains tractable for the
    /// Swift type checker. The header itself is also a drop target, which makes an
    /// empty artboard reachable from Wall without requiring an existing row.
    @ViewBuilder
    private func layerSectionHeader(_ group: LayerGroup, active: Bool) -> some View {
        let boardID = UUID(uuidString: group.id)
        let selected = boardID.map { app.selectedArtboardIDs.contains($0) } ?? false
        HStack(spacing: 6) {
            Rectangle()
                .fill(active || selected ? LayersActiveStyle.tint : Color.clear)
                .frame(width: LayersActiveStyle.borderWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            if let boardID {
                artboardHeaderName(group.title, id: boardID,
                                   active: active, selected: selected,
                                   expanded: sectionExpanded(group.id))
            } else {
                Text(group.title)
                    .font(.system(size: EXPType.small, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? EXPColor.accent : EXPColor.textSecondary)
                    .accessibilityLabel(group.title)
            }
            Spacer(minLength: 0)
        }
        .background(selected ? EXPColor.rowSelected : Color.clear)
        .onDrop(of: [.plainText, .text], isTargeted: nil) { _ in
            acceptLayerDrop(on: boardID)
        }
    }

    /// The artboard name in a section header behaves like the board itself: click
    /// selects it (the same selection a canvas marquee around the whole board
    /// gives you), double-click also brings it into view, right-click exposes the
    /// board's commands.
    ///
    /// The gestures are attached to the NAME, not the whole header row, on purpose:
    /// a tap gesture across the header would swallow the List's own disclosure
    /// chevron. Expand/Collapse is in the context menu as a second route anyway.
    @ViewBuilder
    private func artboardHeaderName(_ title: String, id: UUID, active: Bool, selected: Bool,
                                    expanded: Binding<Bool>) -> some View {
        Text(title)
            .font(.system(size: EXPType.small, weight: (active || selected) ? .medium : .regular))
            .foregroundStyle((active || selected) ? EXPColor.accent : EXPColor.textSecondary)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { revealArtboard(id) }
            .onTapGesture { selectArtboardSection(id) }
            .contextMenu { artboardHeaderMenu(id: id, expanded: expanded) }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(active ? "\(title), active artboard" : title)
            .accessibilityHint("Selects this artboard. Command-click adds or removes it, "
                + "Shift-click selects the range, double-click also brings it into view.")
    }

    /// Select an artboard section honouring the click's modifiers, mirroring how
    /// node rows behave (`selectNested`): ⌘ toggles this board, ⇧ extends from the
    /// anchor across the displayed section order, a plain click replaces. Modifiers
    /// come from `NSEvent.modifierFlags` because a SwiftUI tap gesture doesn't carry
    /// them — same approach the node rows already use.
    private func selectArtboardSection(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        app.selectedNodeIDs = []

        if flags.contains(.command) {
            if app.selectedArtboardIDs.contains(id) { app.selectedArtboardIDs.remove(id) }
            else { app.selectedArtboardIDs.insert(id) }
            artboardAnchorID = id
            return
        }

        let ordered = orderedArtboardSectionIDs
        // Selecting a board on the CANVAS leaves no panel anchor, so fall back to
        // the selected board nearest the top of the list. Without this, Shift-click
        // after a canvas selection would silently behave like a plain click.
        let anchor = artboardAnchorID ?? ordered.first { app.selectedArtboardIDs.contains($0) }
        if flags.contains(.shift), let anchor, anchor != id,
           let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: id) {
            app.selectedArtboardIDs.formUnion(ordered[min(a, b)...max(a, b)])
            return
        }

        selectArtboardOnly(id)
    }

    /// Artboard sections in displayed order. Wall and source sections have no board
    /// id behind them, so they can't take part in a range.
    private var orderedArtboardSectionIDs: [UUID] {
        groups.compactMap { UUID(uuidString: $0.id) }
    }

    /// Unconditional single-board selection — for menu actions, which must not read
    /// whatever modifier key happens to be down when the item fires.
    private func selectArtboardOnly(_ id: UUID) {
        app.selectedNodeIDs = []
        app.selectedArtboardIDs = [id]
        artboardAnchorID = id
    }

    /// Mirrors the canvas right-click rule: a board already part of a multi-board
    /// selection keeps that selection, so Duplicate or Center in View acts on all of
    /// them instead of silently collapsing to the one you happened to right-click.
    private func selectArtboardForCommand(_ id: UUID) {
        if app.selectedArtboardIDs.contains(id) {
            app.selectedNodeIDs = []
        } else {
            selectArtboardOnly(id)
        }
    }

    /// Select AND bring on screen. `centerSelectionAction:` keeps the current zoom
    /// unless the board can't fit at it, so this never yanks the camera scale.
    private func revealArtboard(_ id: UUID) {
        selectArtboardForCommand(id)
        sendCanvasAction("centerSelectionAction:")
    }

    @ViewBuilder
    private func artboardHeaderMenu(id: UUID, expanded: Binding<Bool>) -> some View {
        Button("Select Artboard") { selectArtboardOnly(id) }
        Button("Center in View") { revealArtboard(id) }
        Divider()
        Button("Rename\u{2026}") {
            // The rename field is drawn ON the board, so bring it on screen first
            // or the user is typing into something they can't see.
            // Rename targets one board, so this one always narrows to it.
            selectArtboardOnly(id)
            sendCanvasAction("centerSelectionAction:")
            sendCanvasAction("renameArtboardAction:")
        }
        Button("Duplicate") {
            selectArtboardForCommand(id)
            sendCanvasAction("duplicateArtboardsAction:")
        }
        Button("Copy") {
            selectArtboardForCommand(id)
            sendCanvasAction("copy:")
        }
        let destinations = scope == .document
            ? document.model.pages.filter { $0.id != document.model.pageID(resolving: app.activeCanvasPageID) }
            : []
        if !destinations.isEmpty {
            Divider()
            Menu("Move to Page") {
                ForEach(destinations, id: \.id) { page in
                    Button(page.name) { transferArtboard(id, to: page.id, duplicate: false) }
                }
            }
            Menu("Duplicate to Page") {
                ForEach(destinations, id: \.id) { page in
                    Button(page.name) { transferArtboard(id, to: page.id, duplicate: true) }
                }
            }
        }
        Divider()
        Button(expanded.wrappedValue ? "Collapse Section" : "Expand Section") {
            expanded.wrappedValue.toggle()
        }
        Divider()
        Button("Delete") {
            selectArtboardForCommand(id)
            sendCanvasAction("delete:")
        }
    }

    private func transferArtboard(_ id: UUID, to pageID: UUID, duplicate: Bool) {
        selectArtboardOnly(id)
        sendCanvasAction(duplicate ? "duplicateSelectionToPageAction:" : "moveSelectionToPageAction:",
                         from: CanvasPageTransferRequest(pageID: pageID,
                                                         nodeIDs: [],
                                                         artboardIDs: [id]))
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
            if let ab = document.model.owningArtboard(of: node, on: app.activeCanvasPageID) {
                return ab.id.uuidString
            }
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
            let page = model.page(for: app.activeCanvasPageID)
            for node in page?.nodes ?? [] {
                if let owner = model.owningArtboard(of: node, on: page?.id) {
                    byBoard[owner.id, default: []].append(node)
                } else {
                    wall.append(node)
                }
            }
            var result: [LayerGroup] = []
            for artboard in page?.artboards ?? [] {
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

    /// Duplicate selected rows beside their originals, including rows nested in
    /// groups. A selected ancestor owns its whole subtree, so a selected child is
    /// not duplicated a second time when its selected parent is also copied.
    private func duplicateLayers(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let duplication = Document.duplicatingNodes(ids, in: scopeNodes)
        let nodes = duplication.nodes
        let copies = duplication.copiedIDs
        guard !copies.isEmpty else { return }
        commitNodes(document.model.reflowed(nodes),
                    copies.count == 1 ? "Duplicate" : "Duplicate Layers")
        app.selectedNodeIDs = Set(copies)
        app.selectedArtboardIDs = []
    }

    /// Copy selected rows in scope coordinates. Nested layers fold in ancestor
    /// offsets so a later paste lands where the layer was visibly drawn rather
    /// than at its group-local origin.
    private func copyLayers(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var copied: [Node] = []
        func collect(_ nodes: [Node], parentOffset: CGPoint) {
            for node in nodes {
                if ids.contains(node.id) {
                    var copy = node
                    copy.frame = node.frame.offsetBy(dx: parentOffset.x,
                                                     dy: parentOffset.y)
                    copied.append(copy)
                    continue
                }
                if case .group(let children) = node.content {
                    collect(children,
                            parentOffset: CGPoint(x: parentOffset.x + node.frame.minX,
                                                  y: parentOffset.y + node.frame.minY))
                }
            }
        }
        collect(scopeNodes, parentOffset: .zero)
        guard !copied.isEmpty else { return }

        var sourceOrigin: CGPoint?
        if case .document = scope {
            let owners = Set(copied.compactMap {
                document.model.owningArtboard(of: $0, on: app.activeCanvasPageID)?.id
            })
            if owners.count == 1, let owner = owners.first,
               let artboard = document.model.page(for: app.activeCanvasPageID)?.artboards.first(where: { $0.id == owner }) {
                sourceOrigin = artboard.frame.origin
            }
        }

        guard let data = try? JSONEncoder().encode(
            NodeClipboard(nodes: copied, sourceOrigin: sourceOrigin)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: CanvasNSView.nodePasteboardType)
    }

    /// SwiftUI's native Copy command exchanges item providers. The canvas uses a
    /// custom pasteboard type, so expose the exact encoded bytes under that type;
    /// Paste then routes to the canvas, which remains the one placement engine.
    private func layerCopyProviders() -> [NSItemProvider] {
        copyLayers(app.selectedNodeIDs)
        guard let data = NSPasteboard.general.data(forType: CanvasNSView.nodePasteboardType)
        else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: CanvasNSView.nodePasteboardType.rawValue,
            visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        return [provider]
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
        commitNodes(document.model.reflowed(nodes), ids.count == 1 ? "Move Shape" : "Move Shapes")
    }

    private func setOpacityOnSelectedLayers(_ opacity: Double) {
        let ids = app.selectedNodeIDs
        guard !ids.isEmpty else { return }
        var nodes = scopeNodes
        guard LayerOpacityMutation.apply(opacity, to: ids, in: &nodes) else { return }
        commitNodes(nodes, "Opacity")
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
        commitNodes(document.model.reflowed(nodes), ids.count == 1 ? "Delete" : "Delete Layers")
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

    /// Apply an explicit Layers-panel artboard destination to a whole moving run.
    /// The nodes are temporarily expressed in document coordinates so the same
    /// visible-bounds calculation works whether they came from the wall or from
    /// inside a group. A run that lands entirely outside the board is recentred as
    /// ONE block (union bounds, one shared delta) — centring each node on its own
    /// would stack a multi-selection into a pile and destroy the arrangement.
    private func attach(_ nodes: inout [Node], to board: Artboard) {
        guard !nodes.isEmpty else { return }
        var bounds = CGRect.null
        for i in nodes.indices {
            nodes[i].artboardID = board.id
            bounds = bounds.union(document.model.artboardOwnershipBounds(of: nodes[i]))
        }
        guard !bounds.isNull else { return }
        let overlap = board.frame.intersection(bounds)
        guard overlap.isNull || overlap.width <= 0 || overlap.height <= 0 else { return }
        let dx = board.frame.midX - bounds.midX, dy = board.frame.midY - bounds.midY
        for i in nodes.indices {
            nodes[i].frame.origin.x += dx
            nodes[i].frame.origin.y += dy
        }
    }

    /// The nodes a Layers drag should move, in MODEL order (index 0 = back of the
    /// stack). Expansion rule (Finder / Illustrator): dragging a row that IS part of
    /// the selection moves the whole selection; dragging a row outside it moves that
    /// row alone. A node whose ancestor is also selected is dropped from the run —
    /// moving the ancestor already carries it, and extracting both would orphan the
    /// child. Returning model order (not click order) is what lets the destination
    /// insert the run in one call and keep its relative stacking.
    private func dragSet(startingAt draggedID: UUID) -> [UUID] {
        let selection = app.selectedNodeIDs
        guard selection.count > 1, selection.contains(draggedID) else { return [draggedID] }
        var out: [UUID] = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if selection.contains(n.id) { out.append(n.id); continue }   // skip its subtree
                if case .group(let k) = n.content { walk(k) }
            }
        }
        walk(scopeNodes)
        return out
    }

    private func acceptLayerDrop(on boardID: UUID?) -> Bool {
        guard let boardID, let draggedID = draggingID else { return false }
        let ids = dragSet(startingAt: draggedID)
        draggingID = nil
        dropIndicator = nil
        return moveLayers(ids, toArtboard: boardID)
    }

    /// A section-header drop moves the layers to that artboard's top level. This is
    /// also the route for an empty board, where there is no child row to target.
    @discardableResult
    private func moveLayers(_ ids: [UUID], toArtboard boardID: UUID) -> Bool {
        guard case .document = scope, !ids.isEmpty,
              let board = document.model.page(for: app.activeCanvasPageID)?
                .artboards.first(where: { $0.id == boardID }) else { return false }
        let original = scopeNodes
        var nodes = original
        var moved: [Node] = []
        for id in ids {
            // Read each offset from the ORIGINAL tree: earlier extractions have
            // already changed `nodes`, and a node's frame is relative to its parent.
            let oldOffset = parentOffset(of: id, in: original) ?? .zero
            guard var node = Self.extract(id, from: &nodes) else { return false }
            node.frame.origin.x += oldOffset.x
            node.frame.origin.y += oldOffset.y
            moved.append(node)
        }
        attach(&moved, to: board)
        nodes.append(contentsOf: moved)   // model order preserved => stacking preserved
        commitNodes(nodes, moved.count == 1 ? "Move Layer to Artboard" : "Move Layers to Artboard")
        app.selectedNodeIDs = Set(ids)
        app.selectedArtboardIDs = []
        collapsedSections.remove(boardID.uuidString)
        return true
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

    /// Insert `run` at the BACK of a group's children (model index 0 = display
    /// bottom — Photoshop-style "added to the bottom of the group"). The run goes in
    /// with ONE `insert(contentsOf:)` so its internal order survives; inserting node
    /// by node at index 0 would reverse it.
    @discardableResult
    private static func insertIntoGroup(_ run: [Node], group groupID: UUID, in nodes: inout [Node]) -> Bool {
        for j in nodes.indices {
            if nodes[j].id == groupID, case .group(var k) = nodes[j].content {
                k.insert(contentsOf: run, at: 0); nodes[j].content = .group(children: k); return true
            }
            if case .group(var k) = nodes[j].content {
                if insertIntoGroup(run, group: groupID, in: &k) { nodes[j].content = .group(children: k); return true }
            }
        }
        return false
    }

    /// Insert `run` next to `targetID` in whatever array holds it, as one contiguous
    /// block. `afterInModel` places it at the higher model index (= visually above,
    /// since display reverses). Inserting the whole run in a single call is what
    /// keeps a multi-selection's relative order intact across that inversion — the
    /// alternative, re-anchoring on the target for each node, reverses the run.
    @discardableResult
    private static func insertSiblings(_ run: [Node], near targetID: UUID, afterInModel: Bool, in nodes: inout [Node]) -> Bool {
        if let i = nodes.firstIndex(where: { $0.id == targetID }) {
            nodes.insert(contentsOf: run, at: afterInModel ? i + 1 : i); return true
        }
        for j in nodes.indices {
            if case .group(var k) = nodes[j].content {
                if insertSiblings(run, near: targetID, afterInModel: afterInModel, in: &k) {
                    nodes[j].content = .group(children: k); return true
                }
            }
        }
        return false
    }

    /// Handle a drop of `draggedID` — or of the whole selection it belongs to, per
    /// `dragSet(startingAt:)` — onto `targetID` at `place`.
    ///
    /// Every moved node lands in the SAME destination parent (the target's parent,
    /// or the target itself for a drop INTO a group), as one contiguous run in its
    /// original relative order, in ONE undo step. A mixed-parent selection is
    /// therefore reparented rather than refused: each node is converted to document
    /// coordinates before the move and back into the destination parent's space
    /// after it, so nothing jumps on screen.
    func handleDrop(_ draggedID: UUID, onto targetID: UUID, place: DropPlace) {
        guard draggedID != targetID else { return }
        let movingIDs = dragSet(startingAt: draggedID)
        // The destination can never be one of the things being moved.
        guard !movingIDs.isEmpty, !movingIDs.contains(targetID) else { return }

        let original = scopeNodes
        // Never drop a group into its own descendant (would orphan the subtree).
        for id in movingIDs {
            guard let node = findNode(id) else { return }
            if subtreeContains(targetID, node) { return }
        }

        // A target row inherits its Layers section from its top-level ancestor.
        // Carry that destination explicitly so a wall layer can be dropped beside
        // (or inside) an artboard layer even when less than 50% currently overlaps.
        let destinationBoard: Artboard? = {
            guard case .document = scope,
                  let top = original.first(where: { subtreeContains(targetID, $0) }) else { return nil }
            return document.model.owningArtboard(of: top, on: app.activeCanvasPageID)
        }()

        // Into a component INSTANCE → add to its shared source (affects all instances).
        if place == .into, case .instance(let inst)? = findNode(targetID)?.content {
            moveIntoSource(movingIDs, instance: targetID, sourceID: inst.sourceID)
            return
        }

        // Absolute origins are read BEFORE anything is extracted: a node's frame is
        // relative to its parent group, and the parent is about to change.
        var absoluteOrigin: [UUID: CGPoint] = [:]
        for id in movingIDs {
            guard let node = findNode(id) else { return }
            let off = parentOffset(of: id, in: original) ?? .zero
            absoluteOrigin[id] = CGPoint(x: node.frame.minX + off.x, y: node.frame.minY + off.y)
        }

        var nodes = original
        var moved: [Node] = []
        for id in movingIDs {
            guard var node = Self.extract(id, from: &nodes), let abs = absoluteOrigin[id] else { return }
            node.frame.origin = abs
            moved.append(node)
        }
        if let destinationBoard { attach(&moved, to: destinationBoard) }

        var intoGroup = false
        if place == .into, case .group? = findNode(targetID)?.content { intoGroup = true }
        // Drop INTO a group reparents to the target; anything else reorders as a
        // sibling, i.e. into whatever parent the target itself lives in.
        let parentID: UUID? = intoGroup ? targetID : parentNodeID(of: targetID, in: original)
        let pAbsOff = parentID.flatMap { parentOffset(of: $0, in: original) } ?? .zero
        let pOrigin = parentID.flatMap { findNode($0)?.frame.origin } ?? .zero
        for i in moved.indices {
            moved[i].frame.origin = CGPoint(x: moved[i].frame.minX - pAbsOff.x - pOrigin.x,
                                            y: moved[i].frame.minY - pAbsOff.y - pOrigin.y)
        }

        if intoGroup {
            guard Self.insertIntoGroup(moved, group: targetID, in: &nodes) else { return }
        } else {
            guard Self.insertSiblings(moved, near: targetID, afterInModel: place == .before, in: &nodes) else { return }
        }
        commitNodes(nodes, moved.count == 1 ? "Move Layer" : "Move Layers")
        app.selectedNodeIDs = Set(movingIDs)
    }

    /// Move document nodes into a component source's children (source-local coords).
    /// All-or-nothing: if the source will not take every node, none of them move.
    private func moveIntoSource(_ ids: [UUID], instance instanceID: UUID, sourceID: UUID) {
        guard case .document = scope, !ids.isEmpty,
              let instance = findNode(instanceID),
              let si = document.model.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let original = scopeNodes
        let dragged = ids.compactMap { findNode($0) }
        guard dragged.count == ids.count,
              document.model.canInsert(dragged, intoSource: sourceID) else { return }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
        var top = model.pages[pageIndex].nodes
        var moved: [Node] = []
        for id in ids {
            let oldOffset = parentOffset(of: id, in: original) ?? .zero
            guard var node = Self.extract(id, from: &top) else { return }
            // Source children render at the instance's origin; keep the node's position.
            let absX = node.frame.minX + oldOffset.x, absY = node.frame.minY + oldOffset.y
            node.frame.origin = CGPoint(x: absX - instance.frame.minX, y: absY - instance.frame.minY)
            moved.append(node)
        }
        model.pages[pageIndex].nodes = top
        model.sources[si].children.insert(contentsOf: moved, at: 0)
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
    @Binding var expandedNested: Set<[UUID]>
    @Binding var draggingID: UUID?
    @Binding var dropIndicator: LayerDropIndicator?
    /// When the artboard owning this row is active, the top-level outline subtree
    /// draws one thin accent rail down its leading edge. Owning the rail here —
    /// outside the concrete/virtual child row implementations — keeps it continuous
    /// through expanded groups and component-instance layers alike.
    var inActiveSection: Bool = false
    let allowsPageTransfer: Bool
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
    let onDuplicate: (UUID) -> Void
    let onCopy: (UUID) -> Void
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
                                        expandedNested: $expandedNested,
                                        draggingID: $draggingID, dropIndicator: $dropIndicator,
                                        inActiveSection: inActiveSection,
                                        allowsPageTransfer: allowsPageTransfer, depth: depth + 1,
                                        onToggleVisible: onToggleVisible, onToggleLock: onToggleLock,
                                        onRename: onRename, onRenameComponent: onRenameComponent,
                                        onSetInstanceState: onSetInstanceState,
                                        onSetNestedInstanceState: onSetNestedInstanceState,
                                        onToggleInstanceLayer: onToggleInstanceLayer,
                                        onDrop: onDrop, onDuplicate: onDuplicate,
                                        onCopy: onCopy, onDelete: onDelete,
                                        onCopyStyle: onCopyStyle, onPasteStyle: onPasteStyle,
                                        onSelect: onSelect)
                    }
                } else if let inst = instance, let source = instanceSource {
                    let effective = inst.applyingState(source.states.first { $0.id == inst.activeStateID })
                    ForEach(Array(source.children.reversed())) { child in
                        InstanceLayerRow(child: child, inst: effective, document: document,
                                         expandedNested: $expandedNested,
                                         onSetState: { path, stateID in
                                             onSetNestedInstanceState(node.id, path, stateID)
                                         },
                                         onToggle: { onToggleInstanceLayer(node.id, $0) },
                                         depth: depth + 1,
                                         // Root the expansion key at the PLACED instance, so two
                                         // placements of the same component expand independently.
                                         rowKeyPath: [node.id])
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            // One rail per top-level outline subtree spans the parent row and every
            // disclosed descendant. Recursive LayerOutlineRows deliberately do not
            // draw another copy; their depth remains a layout concern inside rows.
            if depth == 0 {
                Rectangle()
                    .fill(inActiveSection ? LayersActiveStyle.tint : Color.clear)
                    .frame(width: LayersActiveStyle.borderWidth)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The single row: the visual `LayerRow` plus drag source / drop target and the
    /// before/after/into drop indicators.
    private var rowDecorated: some View {
        LayerRow(node: node,
                 document: document,
                 displayName: displayName(node),
                 componentSource: instanceSource,
                 componentStateID: instance?.activeStateID,
                 depth: depth,
                 hasDisclosure: hasDisclosure,
                 isExpanded: isExpanded,
                 inActiveSection: inActiveSection,
                 allowsPageTransfer: allowsPageTransfer,
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
                 onDuplicate: { onDuplicate(node.id) },
                 onCopy: { onCopy(node.id) },
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
                // Finder / Illustrator rule: dragging a row that is NOT in the
                // selection makes it the selection first, so the highlight always
                // shows exactly what the drop is about to move.
                if !app.selectedNodeIDs.contains(node.id) {
                    app.selectedNodeIDs = [node.id]
                    app.selectionAnchorID = node.id
                    app.selectedArtboardID = nil
                }
                draggingID = node.id
                return NSItemProvider(object: node.id.uuidString as NSString)
            }
            .onDrop(of: [.plainText, .text], delegate: LayerDropDelegate(
                targetID: node.id, acceptsInto: hasDisclosure, rowHeight: rowH,
                selectedIDs: app.selectedNodeIDs,
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
    /// The current layer selection. A drag that starts on a selected row moves the
    /// WHOLE selection, so every member of it is an invalid destination — this is
    /// what lets the panel say so with the cursor instead of silently doing nothing.
    let selectedIDs: Set<UUID>
    @Binding var draggingID: UUID?
    @Binding var indicator: LayerDropIndicator?
    let perform: (UUID, UUID, DropPlace) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let d = draggingID, d != targetID,
              !(selectedIDs.contains(d) && selectedIDs.contains(targetID)) else {
            if indicator?.id == targetID { indicator = nil }
            return DropProposal(operation: .forbidden)
        }
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

/// A pointer-only context-menu surface for one visual layer row.
///
/// Recursive layer rows are children of one SwiftUI `List` cell. AppKit's list
/// contextual-menu routing can therefore choose the cell's top-level menu even
/// when the pointer is over a nested child. This view only participates in hit
/// testing for secondary/control clicks, leaving selection, buttons, drag and
/// hover to the SwiftUI row for every ordinary pointer event.
private struct LayerRowContextMenuEntry {
    let title: String?
    let enabled: Bool
    let action: (() -> Void)?
    let children: [LayerRowContextMenuEntry]?

    static let separator = LayerRowContextMenuEntry(title: nil, enabled: false, action: nil, children: nil)

    static func action(_ title: String,
                       enabled: Bool = true,
                       _ action: @escaping () -> Void) -> LayerRowContextMenuEntry {
        LayerRowContextMenuEntry(title: title, enabled: enabled, action: action, children: nil)
    }

    static func submenu(_ title: String, children: [LayerRowContextMenuEntry]) -> LayerRowContextMenuEntry {
        LayerRowContextMenuEntry(title: title, enabled: !children.isEmpty,
                                 action: nil, children: children)
    }
}

private struct LayerRowContextMenuHost: NSViewRepresentable {
    let entries: [LayerRowContextMenuEntry]

    func makeNSView(context: Context) -> LayerRowContextMenuView {
        let view = LayerRowContextMenuView()
        view.entries = entries
        return view
    }

    func updateNSView(_ nsView: LayerRowContextMenuView, context: Context) {
        nsView.entries = entries
    }
}

private final class LayerRowContextMenuView: NSView {
    var entries: [LayerRowContextMenuEntry] = []
    private var activeActions: [() -> Void] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
        let isContextClick = event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        return isContextClick ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func showMenu(with event: NSEvent) {
        activeActions = []
        let menu = NSMenu()
        append(entries, to: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func append(_ entries: [LayerRowContextMenuEntry], to menu: NSMenu) {
        for entry in entries {
            guard let title = entry.title else {
                menu.addItem(.separator())
                continue
            }
            if let children = entry.children {
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                append(children, to: submenu)
                parent.submenu = submenu
                parent.isEnabled = entry.enabled
                menu.addItem(parent)
                continue
            }
            guard let action = entry.action else { continue }
            let item = NSMenuItem(title: title,
                                  action: #selector(performMenuAction(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = activeActions.count
            item.isEnabled = entry.enabled
            activeActions.append(action)
            menu.addItem(item)
        }
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard activeActions.indices.contains(sender.tag) else { return }
        activeActions[sender.tag]()
    }
}

// MARK: - Row

private struct LayerRow: View {
    let node: Node
    @ObservedObject var document: ExpDocument
    let displayName: String
    let componentSource: ComponentSource?
    let componentStateID: UUID?
    let depth: Int
    let hasDisclosure: Bool
    let isExpanded: Bool
    let inActiveSection: Bool
    let allowsPageTransfer: Bool
    let onToggleVisible: () -> Void
    let onToggleLock: () -> Void
    let onToggleExpanded: () -> Void
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onRenameComponent: ((String) -> Void)?
    let onSetComponentState: ((UUID?) -> Void)?
    let onDuplicate: () -> Void
    let onCopy: () -> Void
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
            // 1) active-ARTBOARD rail slot. LayerOutlineRow paints the actual rail
            //    across the WHOLE disclosed subtree so virtual component layers can
            //    never interrupt it; this clear slot preserves row alignment.
            Color.clear.frame(width: LayersActiveStyle.borderWidth)

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
            Button("Copy") { onCopy() }
            Button("Duplicate") { onDuplicate() }
            if !pageDestinations.isEmpty {
                Menu("Move to Page") {
                    ForEach(pageDestinations) { page in
                        Button(page.name) { transfer(to: page.id, duplicate: false) }
                    }
                }
                Menu("Duplicate to Page") {
                    ForEach(pageDestinations) { page in
                        Button(page.name) { transfer(to: page.id, duplicate: true) }
                    }
                }
            }
            Divider()
            Button("Copy Style") { onCopyStyle() }
            Button("Paste Style") { onPasteStyle() }
                .disabled(app.copiedLayerStyle == nil)
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        // Nested outline rows live inside one native List row. SwiftUI hoists a
        // contextMenu from that recursive subtree to the enclosing List cell, so
        // a secondary-click on a child can incorrectly run the GROUP row's menu.
        // This transparent AppKit catcher handles pointer context clicks at the
        // exact visual row. Keep the SwiftUI menu above for keyboard/accessibility
        // invocation; pointer clicks are consumed here before List can retarget.
        .overlay {
            LayerRowContextMenuHost(entries: contextMenuEntries)
                .accessibilityHidden(true)
        }
    }

    private var contextMenuEntries: [LayerRowContextMenuEntry] {
        var entries: [LayerRowContextMenuEntry] = []
        // Capture the complete selection while the native menu is constructed.
        // Its tracking loop can cause the enclosing SwiftUI List to retarget the
        // clicked row before an item fires; the command must still act on the
        // selection the user opened the menu with.
        let transferSelection = app.selectedNodeIDs.contains(node.id)
            ? app.selectedNodeIDs
            : Set([node.id])
        if let onEditComponent {
            entries.append(.action("Edit Component", onEditComponent))
            entries.append(.action("Rename Component…") { beginComponentRename() })
            entries.append(.separator)
        }
        entries.append(.action("Rename") { beginRename() })
        entries.append(.action("Center in Canvas") { centerInCanvas() })
        // BUG-033: the lock had NO context-menu entry at all — for locked or
        // unlocked rows — so the row button was the only route and a locked layer
        // read as a dead end. Always ENABLED, including on a locked row: being
        // un-actionable is the point of a lock, being un-UNLOCKABLE is a trap.
        // Title states what the command will do to the row that was right-clicked.
        entries.append(.action(node.isLocked ? "Unlock" : "Lock", onToggleLock))
        entries.append(.separator)
        entries.append(.action("Copy", onCopy))
        entries.append(.action("Duplicate", onDuplicate))
        if !pageDestinations.isEmpty {
            entries.append(.submenu("Move to Page", children: pageDestinations.map { page in
                .action(page.name) {
                    transfer(to: page.id, duplicate: false, selection: transferSelection)
                }
            }))
            entries.append(.submenu("Duplicate to Page", children: pageDestinations.map { page in
                .action(page.name) {
                    transfer(to: page.id, duplicate: true, selection: transferSelection)
                }
            }))
        }
        entries.append(.separator)
        entries.append(.action("Copy Style", onCopyStyle))
        entries.append(.action("Paste Style", enabled: app.copiedLayerStyle != nil, onPasteStyle))
        entries.append(.separator)
        entries.append(.action("Delete", onDelete))
        return entries
    }

    private var pageDestinations: [CanvasPage] {
        guard allowsPageTransfer else { return [] }
        guard let active = document.model.pageID(resolving: app.activeCanvasPageID) else { return [] }
        return document.model.pages.filter { $0.id != active }
    }

    private func transfer(to pageID: UUID,
                          duplicate: Bool,
                          selection requestedSelection: Set<UUID>? = nil) {
        let selection: Set<UUID>
        if let requestedSelection {
            selection = requestedSelection
        } else if app.selectedNodeIDs.contains(node.id) {
            selection = app.selectedNodeIDs
        } else {
            selection = [node.id]
        }
        if app.selectedNodeIDs != selection {
            app.selectedNodeIDs = selection
        }
        app.selectedArtboardIDs = []
        sendCanvasAction(duplicate ? "duplicateSelectionToPageAction:" : "moveSelectionToPageAction:",
                         from: CanvasPageTransferRequest(pageID: pageID,
                                                         nodeIDs: selection,
                                                         artboardIDs: []))
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
                sendCanvasAction("selectAll:")
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
    /// Owned by the panel, not by this row — see `LayersPanel.expandedNested` for
    /// why a private `@State` here made the List mis-measure its row heights.
    @Binding var expandedNested: Set<[UUID]>
    /// Full path from the placed root instance to a nested component instance.
    let onSetState: ([UUID], UUID?) -> Void
    /// Toggle the per-instance visibility of the given layer id (this row or a
    /// nested descendant), routed up to the panel's `toggleInstanceLayer`.
    let onToggle: (UUID) -> Void
    /// Indentation depth (passed down from the owning instance row).
    var depth: Int = 0
    var instancePath: [UUID] = []
    var visibilityEditable = true
    /// Identifies THIS row for expansion purposes, rooted at the placed instance.
    /// Distinct from `instancePath`, which addresses nested component instances for
    /// state overrides and must keep its own meaning — overloading it would have
    /// quietly changed which layer a state selection applied to.
    var rowKeyPath: [UUID] = []

    private var expansionKey: [UUID] { rowKeyPath + [child.id] }
    private var expanded: Bool { expandedNested.contains(expansionKey) }
    private func toggleExpanded() {
        if expandedNested.contains(expansionKey) { expandedNested.remove(expansionKey) }
        else { expandedNested.insert(expansionKey) }
    }

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
                                     expandedNested: $expandedNested,
                                     onSetState: onSetState,
                                     onToggle: onToggle, depth: depth + 1,
                                     instancePath: instancePath,
                                     visibilityEditable: visibilityEditable,
                                     rowKeyPath: expansionKey)
                }
            } else if expanded, let nested = nestedInstance, let source = nestedSource {
                let effective = nested.applyingState(source.states.first { $0.id == nested.activeStateID })
                ForEach(Array(source.children.reversed())) { nestedChild in
                    InstanceLayerRow(child: nestedChild, inst: effective, document: document,
                                     expandedNested: $expandedNested,
                                     onSetState: onSetState,
                                     onToggle: onToggle, depth: depth + 1,
                                     instancePath: currentInstancePath,
                                     visibilityEditable: false,
                                     rowKeyPath: expansionKey)
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
                Button { toggleExpanded() } label: {
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
        .contentShape(Rectangle())
        // Owner report: a layer name inside a component did NOTHING on click, while
        // the eye and the state picker beside it both worked — so the row read as
        // half-broken rather than as read-only. These layers genuinely cannot be
        // selected here (they belong to the source, not the document, and exist
        // once per placement), so the honest affordance is to go WHERE they can be
        // edited. Double-click opens that component.
        .onTapGesture(count: 2) { openComponent(editTarget) }
        .contextMenu {
            if let nestedSource {
                Button("Edit Component \u{201C}\(nestedSource.name)\u{201D}") {
                    openComponent(nestedSource.id)
                }
            }
            // Always offer the component this layer LIVES in, so the action is never
            // reachable only by double-click. For a nested component row both appear:
            // edit the nested thing, or the thing it sits in.
            if let owning = document.model.source(for: inst.sourceID),
               owning.id != nestedSource?.id {
                Button("Edit Component \u{201C}\(owning.name)\u{201D}") {
                    openComponent(owning.id)
                }
            }
        }
        // Double-click is pointer-only, so VoiceOver gets the same action by name
        // rather than being left with a row that announces but cannot act.
        .accessibilityAction(named: Text(editActionTitle)) { openComponent(editTarget) }
        .help(editHelp)
    }

    /// Which component a double-click opens. A NESTED component row opens itself —
    /// that row's identity is the nested component, and its badge and context menu
    /// already say so. Any other layer opens the component it lives in, which is
    /// the only place that layer can actually be edited.
    private var editTarget: UUID { nestedSource?.id ?? inst.sourceID }

    private var editTargetName: String? {
        nestedSource?.name ?? document.model.source(for: inst.sourceID)?.name
    }

    private var editActionTitle: String {
        editTargetName.map { "Edit Component \u{201C}\($0)\u{201D}" } ?? "Edit Component"
    }

    private var editHelp: String {
        let who = nestedSource.map { "Nested component: \($0.name)" } ?? child.name
        guard let editTargetName else { return who }
        return "\(who) \u{2014} double-click to edit \u{201C}\(editTargetName)\u{201D}"
    }

    private func openComponent(_ sourceID: UUID) {
        SourceEditorWindowManager.shared.open(sourceID: sourceID,
                                              document: document,
                                              undoManager: nil)
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

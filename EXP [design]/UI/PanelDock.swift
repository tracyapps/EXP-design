//
//  PanelDock.swift
//  EXP [design]
//
//  Phase 13 — Photoshop-style dockable panels.
//
//  This file owns the *data model* for the panel layout (which panels exist,
//  how they're grouped into tabbed groups, which dock column each group lives
//  in) and the SwiftUI views that render a dock column from that model.
//
//  Design notes:
//   • The model is intentionally a plain value type (Workspace → DockColumn →
//     PanelGroup) so a later phase (13d) can make named workspaces Codable and
//     persist them. AppState owns the live `workspace`.
//   • Every panel reads/writes only the shared AppState + document, so a panel
//     doesn't care where it's hosted — that's the groundwork for floating
//     panels (13c). A panel is just a `PanelID`; `panelContent(_:document:)`
//     maps an id to its view.
//   • 13a delivers: tabbed groups, collapse/expand, and column-width resize
//     (the HSplitView in MainWindow gives width resize for free). Drag-to-
//     rearrange is 13b, float is 13c, saved workspaces are 13d.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// Which dock column a group lives in. (Tools stay pinned outside the docks.)
enum DockSide: String, Codable, Hashable, Sendable { case left, right }

/// Every panel the dock system can host. Adding a panel = add a case here, give
/// it a title/icon, and a branch in `panelContent`. `implemented` lets reserved
/// panels (Color, …) appear as tabs without pretending to be finished.
enum PanelID: String, CaseIterable, Identifiable, Codable, Sendable {
    case layers
    case properties
    case designLanguage
    case components

    var id: String { rawValue }

    /// Short tab label.
    var title: String {
        switch self {
        case .layers:     return "Layers"
        case .properties: return "Properties"
        case .designLanguage: return "Design Language"
        case .components: return "Components"
        }
    }

    /// SF Symbol shown on the tab (swap freely during the icon polish pass).
    var icon: String {
        switch self {
        case .layers:     return "square.3.layers.3d.down.right"
        case .properties: return "slider.horizontal.3"
        case .designLanguage: return "swatchpalette"
        case .components: return "square.on.square.dashed"
        }
    }

    /// False = reserved slot with placeholder content (Color, for now).
    var implemented: Bool {
        switch self {
        case .layers, .properties, .components, .designLanguage: return true
        }
    }
}

/// A set of panels sharing one space, shown as tabs. Exactly one is active; the
/// whole group can be collapsed to just its header (Photoshop "minimize").
struct PanelGroup: Identifiable, Codable, Sendable {
    var id = UUID()
    var panels: [PanelID]
    var activeID: PanelID
    var collapsed: Bool = false
    /// Relative share of the column's leftover height among EXPANDED groups.
    /// Adjusted by dragging the divider between two groups.
    var weight: CGFloat = 1

    init(_ panels: [PanelID], active: PanelID? = nil, collapsed: Bool = false, weight: CGFloat = 1) {
        self.panels = panels
        self.activeID = active ?? panels.first ?? .layers
        self.collapsed = collapsed
        self.weight = weight
    }
}

/// One vertical dock column (left or right of the canvas). A stack of groups.
struct DockColumn: Codable, Sendable {
    var groups: [PanelGroup]
    var width: CGFloat = 280
}

/// A complete panel arrangement. 13d will make these nameable + saveable.
struct Workspace: Codable, Sendable {
    var name: String = "Default"
    var left: DockColumn
    var right: DockColumn

    /// The default arrangement for the compact single-window mode: every panel is
    /// its OWN stacked, headed section (no combined tabs) — Layers on the left;
    /// Properties above Components on the right. Tabs (multiple panels per group)
    /// are reserved for the multi-window mode. The Color panel is omitted here
    /// until it's built (it would only appear via contextual visibility anyway).
    static var `default`: Workspace {
        Workspace(
            name: "Default",
            left: DockColumn(groups: [
                PanelGroup([.layers])
            ], width: 264),
            right: DockColumn(groups: [
                PanelGroup([.properties]),
                PanelGroup([.components]),
                PanelGroup([.designLanguage])
            ], width: 332)   // wide enough for the full align/distribute row
        )
    }
}

/// A floating "tray" in Multi-Window mode: one macOS window holding a vertical
/// stack of panels with a grab bar on top. Panels can be merged into a tray,
/// reordered, torn out into their own tray, and individually collapsed
/// (Adobe-style — header shows, body hides). `frame` is the window frame
/// (.zero = "let the manager place it").
struct PanelTray: Identifiable, Codable, Equatable {
    var id = UUID()
    var panels: [PanelID]
    var collapsed: Set<PanelID> = []
    var frame: CGRect = .zero

    init(id: UUID = UUID(), panels: [PanelID], collapsed: Set<PanelID> = [], frame: CGRect = .zero) {
        self.id = id
        self.panels = panels
        self.collapsed = collapsed
        self.frame = frame
    }
}

// MARK: - Dock column view

private let dockHeaderH: CGFloat = 30
private let dockDividerH: CGFloat = 6

/// Renders one dock column from `app.workspace`.
///
/// Height model (fixes the "collapsed header flung to the bottom" problem):
/// every group's height is computed explicitly and the groups pack from the TOP.
/// A collapsed group is exactly its header tall; expanded groups divide the
/// leftover space by `weight`. Collapsing a group therefore keeps its header in
/// place and hands the freed space to the *expanded* groups — headers never jump
/// around. Collapse/expand animates (unless Reduce Motion is on); a draggable
/// divider between two expanded groups resizes them.
///
/// In single-window mode, panels that aren't applicable to the current context
/// are hidden entirely (e.g. Components until a component exists). In
/// multi-window mode (later) panels stay visible, so no filtering there.
/// Where a dragged panel section will land (for the insertion line).
struct DockDropIndicator: Equatable {
    let groupID: UUID
    let before: Bool
}

struct DockColumnView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var document: ExpDocument
    let side: DockSide

    // Drag-to-reorder state (a panel heading being dragged + where it'll drop).
    @State private var draggingGroupID: UUID?
    @State private var dropIndicator: DockDropIndicator?

    private var visibleGroups: [PanelGroup] {
        app.dockGroups(side).filter { g in
            app.workspaceMode != .single
            || g.panels.contains { isApplicable($0, app: app, document: document) }
        }
    }

    var body: some View {
        let groups = visibleGroups
        GeometryReader { geo in
            let metrics = columnMetrics(groups: groups, total: geo.size.height)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                    if idx > 0 {
                        DockGroupDivider(
                            side: side,
                            aboveID: groups[idx - 1].id,
                            belowID: group.id,
                            resizable: !groups[idx - 1].collapsed && !group.collapsed,
                            pointsPerWeight: metrics.pointsPerWeight
                        )
                    }
                    PanelGroupView(
                        document: document, side: side, group: group,
                        height: metrics.heights[group.id] ?? dockHeaderH,
                        draggingGroupID: $draggingGroupID,
                        dropIndicator: $dropIndicator
                    )
                }
                Spacer(minLength: 0)   // soaks leftover space when all groups are collapsed
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: groups.map(\.collapsed))
            // Remember the user's column width (set as the splitter is dragged).
            .onChange(of: geo.size.width) { _, w in app.setColumnWidth(side, w) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EXPColor.surfaceWindow)
    }

    /// Explicit per-group heights + the points-per-weight factor the dividers use
    /// to translate a drag into a weight change.
    private func columnMetrics(groups: [PanelGroup], total: CGFloat)
        -> (heights: [UUID: CGFloat], pointsPerWeight: CGFloat) {
        let n = groups.count
        guard n > 0 else { return ([:], 0) }
        let dividers = CGFloat(n - 1) * dockDividerH
        let headers = CGFloat(n) * dockHeaderH
        let avail = max(0, total - headers - dividers)
        let expanded = groups.filter { !$0.collapsed }
        let sumW = expanded.reduce(0) { $0 + $1.weight }
        var heights: [UUID: CGFloat] = [:]
        for g in groups {
            heights[g.id] = g.collapsed
                ? dockHeaderH
                : dockHeaderH + (sumW > 0 ? avail * (g.weight / sumW) : 0)
        }
        return (heights, sumW > 0 ? avail / sumW : 0)
    }
}

/// The line between two groups. A thin hairline; when both neighbors are expanded
/// it also acts as a drag handle that resizes them (up/down cursor on hover).
private struct DockGroupDivider: View {
    @Environment(AppState.self) private var app
    let side: DockSide
    let aboveID: UUID
    let belowID: UUID
    let resizable: Bool
    let pointsPerWeight: CGFloat
    @State private var lastY: CGFloat = 0

    var body: some View {
        let base = ZStack {
            Color.clear
            Rectangle().fill(EXPColor.hairline).frame(height: EXPMetric.strokeHairline)
        }
        .frame(height: dockDividerH)
        .contentShape(Rectangle())

        if resizable {
            base
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(resizeGesture)
        } else {
            base
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let dy = v.translation.height - lastY
                lastY = v.translation.height
                app.adjustGroupHeights(side: side, aboveID: aboveID, belowID: belowID,
                                       deltaPoints: dy, pointsPerWeight: pointsPerWeight)
            }
            .onEnded { _ in lastY = 0 }
    }
}

/// One collapsible group (a single panel in single-window mode; a tab set in
/// multi-window mode). Rendered at an explicit `height` by the column.
private struct PanelGroupView: View {
    @Environment(AppState.self) private var app
    @ObservedObject var document: ExpDocument
    let side: DockSide
    let group: PanelGroup
    let height: CGFloat
    @Binding var draggingGroupID: UUID?
    @Binding var dropIndicator: DockDropIndicator?

    private var isDragging: Bool { draggingGroupID == group.id }
    private var indicatorBefore: Bool? {
        dropIndicator?.groupID == group.id ? dropIndicator?.before : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(group.collapsed ? 0 : 1)
            // Content stays mounted and is clipped away when collapsed, so
            // expand/collapse reads as a smooth slide rather than a pop.
            panelContent(group.activeID, document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(group.collapsed ? 0 : 1)
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .opacity(isDragging ? 0.4 : 1)
        // Insertion line where a dragged section will land.
        .overlay(alignment: indicatorBefore == true ? .top : .bottom) {
            if indicatorBefore != nil {
                Rectangle().fill(EXPColor.accent).frame(height: EXPMetric.strokeDropline)
            }
        }
        .onDrop(of: [.text], delegate: GroupDropDelegate(
            targetID: group.id, height: height,
            draggingGroupID: $draggingGroupID, dropIndicator: $dropIndicator,
            perform: { dragged, before in
                let groups = app.dockGroups(side)
                var beforeID: UUID?
                if let ti = groups.firstIndex(where: { $0.id == group.id }) {
                    beforeID = before ? group.id : (ti + 1 < groups.count ? groups[ti + 1].id : nil)
                } else {
                    beforeID = group.id
                }
                app.moveGroup(dragged, toSide: side, before: beforeID)
            }))
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(group.panels) { pid in
                PanelTab(
                    title: pid.title,
                    icon: pid.icon,
                    isActive: pid == group.activeID && !group.collapsed,
                    showLabel: group.panels.count == 1 || pid == group.activeID
                ) {
                    app.setActivePanel(pid, inGroup: group.id, side: side)
                }
            }
            Spacer(minLength: 4)
            Button {
                app.toggleGroupCollapsed(group.id, side: side)
            } label: {
                Image(systemName: group.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EXPColor.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.collapsed ? "Expand panel" : "Collapse panel")
        }
        .padding(.horizontal, 6)
        .frame(height: dockHeaderH)
        .background(EXPColor.surfaceToolbar)   // header strip tint (token)
        .contentShape(Rectangle())
        // Drag the heading to reorder this section (within or across columns).
        .onDrag {
            draggingGroupID = group.id
            return NSItemProvider(object: group.id.uuidString as NSString)
        }
    }
}

/// Reorders panel sections by dragging their headings. Computes a before/after
/// insertion point from the pointer's position over the target section.
private struct GroupDropDelegate: DropDelegate {
    let targetID: UUID
    let height: CGFloat
    @Binding var draggingGroupID: UUID?
    @Binding var dropIndicator: DockDropIndicator?
    /// (draggedID, dropInUpperHalf) — the view does the model move (it owns the
    /// AppState reference), mirroring the Layers panel's drop delegate.
    let perform: (UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool { draggingGroupID != nil }

    func dropEntered(info: DropInfo) { updateIndicator(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator?.groupID == targetID { dropIndicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggingGroupID else { return false }
        perform(dragged, info.location.y < height / 2)
        draggingGroupID = nil
        dropIndicator = nil
        return true
    }

    private func updateIndicator(_ info: DropInfo) {
        dropIndicator = DockDropIndicator(groupID: targetID, before: info.location.y < height / 2)
    }
}

// MARK: - Contextual visibility

/// Whether a panel applies to the current context. In single-window mode an
/// inapplicable panel is hidden entirely; the rules are intentionally simple and
/// easy to extend as panels are added.
func isApplicable(_ id: PanelID, app: AppState, document: ExpDocument) -> Bool {
    // A panel the user has placed in the layout should stay reachable. Every panel
    // has a sensible empty state, so contextual auto-hiding is no longer used as a
    // LIVE filter — it used to trap empty panels (Components, Design Language) out
    // of reach with no way to show them. Presence is controlled explicitly through
    // the Window menu / dock toggles instead. Kept as an extension point.
    true
}

/// A single tab in a group header.
private struct PanelTab: View {
    let title: String
    let icon: String
    let isActive: Bool
    /// When false (an inactive tab in a multi-tab group), show only the icon to
    /// save width; the active tab and single-panel groups show the label too.
    let showLabel: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                if showLabel {
                    Text(title)
                        .font(.system(size: EXPType.base, weight: isActive ? .medium : .regular))
                        .textCase(.uppercase)
                        .tracking(EXPType.tracking(EXPType.trCaps, EXPType.base))
                }
            }
            .padding(.horizontal, EXPMetric.md)
            .frame(height: EXPMetric.controlH)
            .background(
                RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                    .fill(isActive ? EXPColor.accentSubtle
                          : (hovering ? EXPColor.rowHover : .clear))
            )
            .foregroundStyle(isActive ? EXPColor.accent : EXPColor.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Panel content router

/// Maps a `PanelID` to the view that fills its group body. Sub-panels read
/// AppState/document from the environment, so they work hosted anywhere.
@ViewBuilder
func panelContent(_ id: PanelID, document: ExpDocument) -> some View {
    switch id {
    case .layers:     LayersPanel(document: document, showsTitle: false)
    case .properties: RightPanel(document: document, showsTitle: false, showsZoom: false)
    case .components: ComponentsPanel(document: document)
    case .designLanguage: DesignLanguagePanel(document: document)
    }
}

// MARK: - Components panel

/// Lists the document's component sources. New components appear here
/// automatically (it reads `document.model.sources`). Clicking one opens its
/// source editor — the same window the canvas opens on double-click.
struct ComponentsPanel: View {
    @ObservedObject var document: ExpDocument
    @Environment(\.undoManager) private var undoManager

    /// Phase 19a: filter by component category (= curated ARIA role). "All" when
    /// nothing is chosen; "Uncategorized" is a real bucket, not an absence.
    enum CategoryFilter: Hashable { case all, uncategorized, role(AriaRole) }
    @State private var filter: CategoryFilter = .all

    /// Roles actually present in this document (the filter menu stays short).
    private var presentRoles: [AriaRole] {
        var seen: Set<AriaRole> = []
        var out: [AriaRole] = []
        for s in document.model.sources {
            if let r = s.a11y.role, seen.insert(r).inserted { out.append(r) }
        }
        return out.sorted { $0.friendlyLabel < $1.friendlyLabel }
    }

    private func matches(_ s: ComponentSource) -> Bool {
        switch filter {
        case .all:            return true
        case .uncategorized:  return s.a11y.role == nil
        case .role(let r):    return s.a11y.role == r
        }
    }

    private var filterLabel: String {
        switch filter {
        case .all:            return "All Categories"
        case .uncategorized:  return "Uncategorized"
        case .role(let r):    return r.friendlyLabel
        }
    }

    @ViewBuilder private var filterBar: some View {
        if !presentRoles.isEmpty || document.model.sources.contains(where: { $0.a11y.role == nil }) {
            HStack {
                Menu {
                    Button("All Categories") { filter = .all }
                    Button("Uncategorized") { filter = .uncategorized }
                    if !presentRoles.isEmpty { Divider() }
                    ForEach(presentRoles, id: \.self) { role in
                        Button(role.friendlyLabel) { filter = .role(role) }
                    }
                } label: {
                    Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: EXPType.mini))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Filter components by category")
                .accessibilityLabel("Filter components by category, currently \(filterLabel)")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 6)
        }
    }

    var body: some View {
        let sources = document.model.sources.filter(matches)
        Group {
            if document.model.sources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 26)).foregroundStyle(EXPColor.textTertiary)
                    Text("No components yet").font(.expLabel).foregroundStyle(EXPColor.textSecondary)
                    Text("Select layers, then Create Component — the source appears here.")
                        .font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    filterBar
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(sources) { src in
                                ComponentRow(source: src, document: document, undoManager: undoManager) {
                                    SourceEditorWindowManager.shared.open(
                                        sourceID: src.id, document: document, undoManager: undoManager)
                                }
                            }
                            if sources.isEmpty {
                                Text("No components in “\(filterLabel)”.")
                                    .font(.system(size: EXPType.mini))
                                    .foregroundStyle(EXPColor.textTertiary)
                                    .padding(8)
                            }
                        }
                        .padding(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ComponentRow: View {
    let source: ComponentSource
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    let open: () -> Void

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(EXPColor.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.exp)
                        .font(.system(size: 12, weight: .medium))
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { isRenaming = false }   // Esc cancels
                        .onChange(of: nameFocused) { if !$1 { commitRename() } }
                } else {
                    Text(source.name).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EXPColor.textPrimary)
                        .lineLimit(1)
                }
                Text("\(Int(source.size.width)) × \(Int(source.size.height)) · \(source.children.count) layer\(source.children.count == 1 ? "" : "s")")
                    .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textSecondary)
            }
            Spacer(minLength: 0)
            // v1.3: live instance count — click to select every instance on the
            // canvas (highlighting them). Hidden at zero to keep rows quiet.
            if instanceCount > 0 {
                Button(action: selectInstances) {
                    Text("×\(instanceCount)")
                        .font(.system(size: EXPType.micro, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(EXPColor.textSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(EXPColor.rowHover))
                }
                .buttonStyle(.plain)
                .help(instanceCount == 1 ? "1 instance on the canvas — click to select it"
                                         : "\(instanceCount) instances on the canvas — click to select them all")
                .accessibilityLabel("\(instanceCount) instance\(instanceCount == 1 ? "" : "s") on canvas. Select all.")
            }
            // Phase 19a: the category tag — a TEXT label (never color-only), read
            // by VoiceOver as part of the row.
            if let role = source.a11y.role {
                Text(role.friendlyLabel)
                    .font(.system(size: EXPType.micro, weight: .medium))
                    .foregroundStyle(EXPColor.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(EXPColor.rowHover))
                    .lineLimit(1)
                    .accessibilityLabel("Category: \(role.friendlyLabel)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
            .fill(hovering ? EXPColor.rowHover : .clear))
        .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous))
        .onHover { hovering = $0 }
        // Double-click renames; single click opens the source editor.
        .onTapGesture(count: 2) { beginRename() }
        .onTapGesture { if !isRenaming { open() } }
        .contextMenu {
            Button("Create Instance", action: createInstance)
            Button(instanceCount == 1 ? "Select Instance on Canvas"
                                      : "Select Instances on Canvas (\(instanceCount))",
                   action: selectInstances)
                .disabled(instanceCount == 0)
            Divider()
            Button("Open in Editor", action: open)
            Button("Rename", action: beginRename)
            Menu("Set Category") {
                Button {
                    setCategory(nil)
                } label: {
                    if source.a11y.role == nil { Label("Uncategorized", systemImage: "checkmark") }
                    else { Text("Uncategorized") }
                }
                ForEach(AriaRole.grouped(), id: \.category) { group in
                    Section(group.category.label) {
                        ForEach(group.roles, id: \.self) { role in
                            Button {
                                setCategory(role)
                            } label: {
                                if source.a11y.role == role { Label(role.friendlyLabel, systemImage: "checkmark") }
                                else { Text(role.friendlyLabel) }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Delete Component", role: .destructive, action: deleteComponent)
        }
        .onDrag {
            NSItemProvider(object: source.id.uuidString as NSString)
        }

        .help("Double-click to rename · click to open “\(source.name)”")
    }

    /// Delete this component source and every instance of it (recursing into groups
    /// + other sources), in one undo step.
    private func deleteComponent() {
        let sid = source.id
        var model = document.model
        model.sources.removeAll { $0.id == sid }
        func strip(_ nodes: inout [Node]) {
            nodes.removeAll { if case .instance(let i) = $0.content { return i.sourceID == sid }; return false }
            for idx in nodes.indices {
                if case .group(var kids) = nodes[idx].content {
                    strip(&kids); nodes[idx].content = .group(children: kids)
                }
            }
        }
        strip(&model.nodes)
        for i in model.sources.indices { strip(&model.sources[i].children) }
        document.setModel(model, undoManager: undoManager, actionName: "Delete Component")
    }

    private func beginRename() {
        draft = source.name
        isRenaming = true
        nameFocused = true
    }

    /// IDs of every instance of this component in the document (nested included).
    private var instanceIDs: [UUID] {
        var ids: [UUID] = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if case .instance(let i) = n.content, i.sourceID == source.id { ids.append(n.id) }
                if case .group(let kids) = n.content { walk(kids) }
            }
        }
        walk(document.model.nodes)
        return ids
    }
    private var instanceCount: Int { instanceIDs.count }

    /// Select (highlight) every canvas instance of this component.
    private func selectInstances() {
        let ids = instanceIDs
        guard !ids.isEmpty else { return }
        app.selectedNodeIDs = Set(ids)
        app.selectedArtboardIDs = []
    }

    /// Phase 19a: assign the category (ARIA token stored, friendly label shown).
    private func setCategory(_ role: AriaRole?) {
        guard let i = document.model.sources.firstIndex(where: { $0.id == source.id }),
              document.model.sources[i].a11y.role != role else { return }
        var model = document.model
        model.sources[i].a11y.role = role
        document.setModel(model, undoManager: undoManager, actionName: "Set Component Category")
    }

    private func commitRename() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        guard !name.isEmpty, name != source.name,
              let i = document.model.sources.firstIndex(where: { $0.id == source.id }) else { return }
        var model = document.model
        model.sources[i].name = name
        document.setModel(model, undoManager: undoManager, actionName: "Rename Component")
    }

    /// Create an instance of this component at the canvas center (or first artboard's center).
    private func createInstance() {
        var model = document.model
        // Place at the canvas center if there's a viewport, else at the first artboard's center.
        let center: CGPoint
        if app.viewportSize.width > 0, app.viewportSize.height > 0 {
            // Reverse the pan/zoom transform to find the document point at the view center.
            let viewCenter = CGPoint(x: app.viewportSize.width / 2, y: app.viewportSize.height / 2)
            center = CGPoint(x: (viewCenter.x - app.panOffset.x) / app.zoom,
                           y: (viewCenter.y - app.panOffset.y) / app.zoom)
        } else if let firstBoard = model.artboards.first {
            center = CGPoint(x: firstBoard.frame.midX, y: firstBoard.frame.midY)
        } else {
            center = .zero
        }
        // Create the instance node, centering its frame at the target point.
        let inst = ComponentInstance(sourceID: source.id)
        let size = source.size
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        let node = Node(name: source.name, frame: frame, content: .instance(inst))
        model.nodes.append(node)
        document.setModel(model, undoManager: undoManager, actionName: "Create Instance")
        app.selectedNodeIDs = [node.id]
        app.selectedArtboardIDs = []
    }
}

// MARK: - Reserved (placeholder) panel

// MARK: - Window menu (multi-window panels + single-window docks)

/// State + actions the Window menu needs, published via FocusedValue from the
/// document window (and tray windows) so the menu reflects the active document.
struct WindowMenuModel {
    var mode: AppState.WorkspaceMode
    var shownPanels: Set<PanelID>
    /// Show/hide a panel, honoring the current mode (dock in single, tray in multi).
    var toggle: (PanelID) -> Void
    var showLeft: Bool
    var showRight: Bool
    var toggleLeft: () -> Void
    var toggleRight: () -> Void
    /// The panels listed in the menu, in order.
    static let panelOrder: [PanelID] = [.layers, .properties, .components, .designLanguage]
}

private struct WindowMenuKey: FocusedValueKey { typealias Value = WindowMenuModel }
extension FocusedValues {
    var windowMenu: WindowMenuModel? {
        get { self[WindowMenuKey.self] }
        set { self[WindowMenuKey.self] = newValue }
    }
}

/// Build the menu model from the (shared) app state.
@MainActor
func makeWindowMenuModel(_ app: AppState) -> WindowMenuModel {
    WindowMenuModel(
        mode: app.workspaceMode,
        shownPanels: Set(WindowMenuModel.panelOrder.filter { app.isPanelShown($0) }),
        toggle: { panel in
            let willShow = !app.isPanelShown(panel)
            app.togglePanel(panel)
            guard willShow else { return }
            if app.workspaceMode == .multiWindow {
                DispatchQueue.main.async { PanelWindowManager.shared.focusPanel(panel) }
            } else {
                // The panel is appended to the right dock — make sure it's visible.
                app.showRightPanel = true
            }
        },
        showLeft: app.showLeftPanel,
        showRight: app.showRightPanel,
        toggleLeft: { app.showLeftPanel.toggle() },
        toggleRight: { app.showRightPanel.toggle() }
    )
}

/// Window-menu items appended after the system window list. Per-panel show/hide
/// works in BOTH modes (dock section in single-window, floating tray in
/// multi-window); the dock column Show/Hide only applies in single-window. The
/// model falls back to PanelHub's active document, so the menu stays usable even
/// when a floating panel window is key (which clears the document's scene value).
struct WindowMenuItems: View {
    @FocusedValue(\.windowMenu) private var focused

    private var menu: WindowMenuModel? {
        if let focused { return focused }
        if let app = PanelHub.shared.activeApp { return makeWindowMenuModel(app) }
        return nil
    }

    var body: some View {
        Divider()
        // Per-panel show/hide (works in both modes).
        ForEach(WindowMenuModel.panelOrder, id: \.self) { panel in
            Toggle(isOn: toggleBinding(panel)) {
                Label(panel.title, systemImage: panel.icon)
            }
            .disabled(menu == nil)
        }
        Divider()
        // Single-window dock column visibility — label flips Show ⇄ Hide.
        Button { menu?.toggleLeft() } label: {
            Label((menu?.showLeft ?? false) ? "Hide Left Panel" : "Show Left Panel",
                  systemImage: "sidebar.left")
        }
        .disabled(menu == nil || menu?.mode != .single)
        Button { menu?.toggleRight() } label: {
            Label((menu?.showRight ?? false) ? "Hide Right Panel" : "Show Right Panel",
                  systemImage: "sidebar.right")
        }
        .disabled(menu == nil || menu?.mode != .single)
    }

    private func toggleBinding(_ panel: PanelID) -> Binding<Bool> {
        Binding(
            get: { menu?.shownPanels.contains(panel) ?? false },
            set: { _ in menu?.toggle(panel) }
        )
    }
}

/// A reserved slot for a panel not yet built. Keeps the dock layout honest
/// without pretending the feature exists.
struct ReservedPanel: View {
    let title: String
    let systemImage: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(note).font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

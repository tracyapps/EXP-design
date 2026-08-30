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
import AppKit
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
    case handoff
    case sanaa

    var id: String { rawValue }

    /// Short tab label.
    var title: String {
        switch self {
        case .layers:     return "Layers"
        case .properties: return "Properties"
        case .designLanguage: return "Design Language"
        case .components: return "Components"
        case .handoff: return "Handoff"
        case .sanaa: return "Sanaa"
        }
    }

    /// SF Symbol shown on the tab (swap freely during the icon polish pass).
    var icon: String {
        switch self {
        case .layers:     return "square.2.layers.3d.top.filled"
        case .properties: return "slider.horizontal.3"
        case .designLanguage: return "swatchpalette"
        case .components: return "rectangle.3.group"
        case .handoff: return "shippingbox"
        case .sanaa: return "message.and.waveform"
        }
    }

    /// False = reserved slot with placeholder content (Color, for now).
    var implemented: Bool {
        switch self {
        case .layers, .properties, .components, .designLanguage, .handoff, .sanaa: return true
        }
    }

    /// Availability is separate from saved placement. A disabled conditional
    /// panel remains in the workspace/tray model so enabling can restore it.
    var isAvailable: Bool {
        self != .sanaa || SanaaPreferences.isEnabled
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
                PanelGroup([.designLanguage]),
                PanelGroup([.handoff]),
                PanelGroup([.sanaa])
            ], width: 332)   // wide enough for the full align/distribute row
        )
    }
}

/// A whole arrangement, captured as a value (FEAT-021).
///
/// The catch worth knowing: an arrangement lives in TWO places. The docks, the
/// workspace mode and dock visibility are per-document-window state on `AppState`;
/// the floating trays — and crucially their window FRAMES, which is where the
/// multi-monitor positions actually are — are app-wide on `PanelHub`. A preset that
/// captured only the first would restore the panel *order* and leave every window
/// exactly where it was, which is the opposite of the point.
struct WorkspaceSnapshot: Codable, Sendable {
    var workspace: Workspace
    var mode: AppState.WorkspaceMode
    var showLeft: Bool
    var showRight: Bool
    var trays: [PanelTray]

    /// Is the arrangement described by `other` what is on screen right now?
    ///
    /// The workspace checkmark used to track `activePresetID`, which is set when a
    /// preset is applied or saved and never cleared — so it sat beside a workspace
    /// name permanently, long after the layout had been dragged into something else
    /// (owner, 2026-08-20: *"a checkmark next to it pretty much always"*). It now
    /// means what a checkmark is supposed to mean: this is what you are looking at.
    ///
    /// `activePresetID` still exists and still drives Update / Rename / Delete —
    /// those act on the preset you are WORKING ON, which is a different question
    /// from what is currently displayed. Updating a preset you have drifted away
    /// from is the whole point of Update.
    func matches(_ other: WorkspaceSnapshot) -> Bool {
        guard mode == other.mode, showLeft == other.showLeft, showRight == other.showRight,
              Self.dockSignature(workspace) == Self.dockSignature(other.workspace),
              trays.count == other.trays.count,
              Self.groupSignature(trays) == Self.groupSignature(other.trays)
        else { return false }
        // Trays are matched by CONTENT, not by array position: the order in `trays`
        // is insertion order and says nothing about what the user sees.
        var unmatched = other.trays
        for tray in trays {
            guard let i = unmatched.firstIndex(where: {
                Self.traySignature($0) == Self.traySignature(tray) && Self.near($0.frame, tray.frame)
            }) else { return false }
            unmatched.remove(at: i)
        }
        return true
    }

    /// Frames compare with a tolerance. A workspace should not lose its tick over a
    /// one-point nudge, and macOS rounds frames itself when it clamps a window onto
    /// an attached screen (see `PanelHub.clampedToAttachedScreen`).
    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func traySignature(_ tray: PanelTray) -> String {
        tray.panels.map(\.rawValue).joined(separator: ",")
            + "|" + tray.collapsed.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Which trays are glued to which, expressed structurally rather than by group
    /// UUID — re-making the same pairing by hand should read as the same workspace.
    private static func groupSignature(_ trays: [PanelTray]) -> [String] {
        var groups: [UUID: [String]] = [:]
        var out: [String] = []
        for tray in trays {
            if let g = tray.groupID { groups[g, default: []].append(traySignature(tray)) }
            else { out.append("solo:" + traySignature(tray)) }
        }
        out += groups.values.map { "glued:" + $0.sorted().joined(separator: "+") }
        return out.sorted()
    }

    private static func dockSignature(_ workspace: Workspace) -> String {
        func column(_ c: DockColumn) -> String {
            String(format: "%.0f", c.width) + "[" + c.groups.map { g in
                g.panels.map(\.rawValue).joined(separator: ",")
                    + ":" + g.activeID.rawValue
                    + (g.collapsed ? ":c" : "")
                    + String(format: ":%.2f", g.weight)
            }.joined(separator: ";") + "]"
        }
        return column(workspace.left) + "/" + column(workspace.right)
    }
}

/// A named arrangement the user can switch back to ("Laptop", "Dual-monitor").
struct WorkspacePreset: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var snapshot: WorkspaceSnapshot
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

    // MARK: Glue groups (FEAT-022)

    /// Trays sharing a `groupID` are GLUED: still separate windows, at their own
    /// sizes and their own positions, that macOS moves and orders together.
    ///
    /// **This replaced a one-window/N-columns model, and the reason is worth
    /// keeping.** Merging two panels into one window forced that window to be the
    /// UNION of both, which meant: a bounding box spanning most of the screen when
    /// the two sat at different heights, a huge transparent region that swallowed
    /// every click aimed at whatever was behind it, and one set of traffic lights
    /// stranded in empty space belonging to no panel. The owner hit all three within
    /// a minute of using it (2026-08-20).
    ///
    /// `NSWindow.addChildWindow` gives the one thing the merge was for — drag one,
    /// they all move — without a shared rectangle. And it is NOT the Session 80
    /// mistake: that moved N windows from OUR code on every drag tick. Here the
    /// window server does it, and we move exactly one window.
    var groupID: UUID?

    var isGlued: Bool { groupID != nil }

    init(id: UUID = UUID(), panels: [PanelID], collapsed: Set<PanelID> = [],
         frame: CGRect = .zero, groupID: UUID? = nil) {
        self.id = id
        self.panels = panels
        self.collapsed = collapsed
        self.frame = frame
        self.groupID = groupID
    }

    // MARK: Codable, by hand and on purpose
    //
    // A `var` with a default does NOT get that default back from Swift's SYNTHESISED
    // decoder — a missing key throws. So the moment FEAT-022 added a field, every
    // tray already in `exp.trays.v1` failed to decode, `loadTrays()` swallowed the
    // error, and the user's whole panel arrangement silently reverted to the seeded
    // default. Decoding every post-v1 field with `decodeIfPresent` is what makes the
    // "old layouts decode unchanged" claim actually true.
    private enum CodingKeys: String, CodingKey {
        case id, panels, collapsed, frame, groupID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        panels = try c.decode([PanelID].self, forKey: .panels)
        collapsed = try c.decodeIfPresent(Set<PanelID>.self, forKey: .collapsed) ?? []
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame) ?? .zero
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
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
    @AppStorage(SanaaPreferences.enabled) private var sanaaEnabled = false

    // Drag-to-reorder state (a panel heading being dragged + where it'll drop).
    @State private var draggingGroupID: UUID?
    @State private var dropIndicator: DockDropIndicator?

    private var visibleGroups: [PanelGroup] {
        app.dockGroups(side).compactMap { stored in
            var group = stored
            group.panels = stored.panels.filter { panel in
                panel != .sanaa || sanaaEnabled
            }.filter { isApplicable($0, app: app, document: document) }
            guard !group.panels.isEmpty else { return nil }
            if !group.panels.contains(group.activeID) {
                group.activeID = group.panels[0]
            }
            return group
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
    id.isAvailable
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
    case .handoff: HandoffPanel(document: document)
    case .sanaa: SanaaPanel()
    }
}

// MARK: - Components panel

/// Components panel view mode. List stays the default; grid is the v1.6 visual
/// scanning mode with generated source previews and per-component state preview.
enum ComponentPanelViewMode: String, CaseIterable { case list, grid }

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
    @State private var previewStateBySource: [UUID: UUID?] = [:]
    @AppStorage("exp.components.viewMode") private var viewMode: ComponentPanelViewMode = .list

    private let grid = [GridItem(.adaptive(minimum: 118, maximum: 180), spacing: 8)]

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

    private func previewStateBinding(for source: ComponentSource) -> Binding<UUID?> {
        Binding(
            get: {
                guard let stored = previewStateBySource[source.id] ?? nil,
                      source.states.contains(where: { $0.id == stored }) else { return nil }
                return stored
            },
            set: { previewStateBySource[source.id] = $0 }
        )
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
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 26)).foregroundStyle(EXPColor.textTertiary)
                    Text("No components yet").font(.expLabel).foregroundStyle(EXPColor.textSecondary)
                    Text("Select layers, then Create Component — the source appears here.")
                        .font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                VStack(spacing: 0) { filterBar; Divider(); content(sources) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !document.model.sources.isEmpty { viewOptionsBar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func content(_ sources: [ComponentSource]) -> some View {
        ScrollView {
            switch viewMode {
            case .list:
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sources) { src in
                        ComponentRow(source: src,
                                     previewStateID: previewStateBinding(for: src),
                                     document: document,
                                     undoManager: undoManager) {
                            SourceEditorWindowManager.shared.open(
                                sourceID: src.id, document: document, undoManager: undoManager)
                        }
                    }
                    emptyFilterMessage(sources)
                }
                .padding(6)
                .padding(.bottom, 38)
            case .grid:
                LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                    ForEach(sources) { src in
                        ComponentCard(source: src,
                                      previewStateID: previewStateBinding(for: src),
                                      document: document,
                                      undoManager: undoManager) {
                            SourceEditorWindowManager.shared.open(
                                sourceID: src.id, document: document, undoManager: undoManager)
                        }
                    }
                    emptyFilterMessage(sources)
                }
                .padding(8)
                .padding(.bottom, 38)
            }
        }
    }

    @ViewBuilder private func emptyFilterMessage(_ sources: [ComponentSource]) -> some View {
        if sources.isEmpty {
            Text("No components in “\(filterLabel)”.")
                .font(.system(size: EXPType.mini))
                .foregroundStyle(EXPColor.textTertiary)
                .padding(8)
        }
    }

    /// Sticky bottom bar for list/grid mode. Mirrors the Design Language panel's
    /// view control so the two library panels share a learned interaction.
    private var viewOptionsBar: some View {
        HStack(spacing: 8) {
            EXPSegmented(selection: $viewMode, segments: [
                .init(value: ComponentPanelViewMode.list, icon: "list.bullet",
                      accessibilityLabel: "View components as list"),
                .init(value: ComponentPanelViewMode.grid, icon: "square.grid.2x2",
                      accessibilityLabel: "View components as grid"),
            ])
            .fixedSize()
            .help("View components as list or grid")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(EXPColor.surfaceToolbar)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Component panel shared controls

private struct ComponentStatePreviewMenu: View {
    let source: ComponentSource
    @Binding var previewStateID: UUID?
    var compact = false

    private var currentName: String {
        guard let id = previewStateID,
              let state = source.states.first(where: { $0.id == id }) else { return "default" }
        return state.name
    }

    var body: some View {
        if !source.states.isEmpty {
            Menu {
                Button {
                    previewStateID = nil
                } label: {
                    if previewStateID == nil { Label("default", systemImage: "checkmark") }
                    else { Text("default") }
                }
                ForEach(source.states) { state in
                    Button {
                        previewStateID = state.id
                    } label: {
                        if previewStateID == state.id { Label(state.name, systemImage: "checkmark") }
                        else { Text(state.name) }
                    }
                }
            } label: {
                if compact {
                    Text(currentName)
                        .font(.system(size: EXPType.micro, weight: .medium))
                        .lineLimit(1)
                } else {
                    Label(currentName, systemImage: "eye")
                        .font(.system(size: EXPType.micro, weight: .medium))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Preview a component state")
            .accessibilityLabel("Preview state, currently \(currentName)")
        }
    }
}

private struct ComponentSourcePreview: View {
    let source: ComponentSource
    let stateID: UUID?
    let model: Document

    private var state: ComponentState? {
        stateID.flatMap { id in source.states.first { $0.id == id } }
    }

    private var previewSize: CGSize {
        var inst = ComponentInstance(sourceID: source.id)
        inst.activeStateID = stateID
        let s = model.resolvedSize(of: inst)
        return s.width > 0 && s.height > 0 ? s : source.size
    }

    private var previewChildren: [Node] {
        model.resolvedChildren(of: source, in: state)
    }

    var body: some View {
        GeometryReader { geo in
            SwiftUI.Canvas { context, size in
                let viewBox = CGRect(origin: .zero, size: previewSize)
                let pad: CGFloat = 10
                guard viewBox.width > 0, viewBox.height > 0,
                      size.width > pad * 2, size.height > pad * 2 else { return }
                let scale = min((size.width - pad * 2) / viewBox.width,
                                (size.height - pad * 2) / viewBox.height)
                let offset = CGPoint(
                    x: (size.width - viewBox.width * scale) / 2,
                    y: (size.height - viewBox.height * scale) / 2)
                draw(previewChildren, origin: .zero, scale: scale, offset: offset, in: &context)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(
            RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
                .fill(EXPColor.surfaceField)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
                .strokeBorder(EXPColor.borderSoft, lineWidth: EXPMetric.strokeHairline)
        )
        .accessibilityHidden(true)
    }

    private func draw(_ nodes: [Node], origin: CGPoint, scale: CGFloat,
                      offset: CGPoint, in context: inout GraphicsContext) {
        for node in nodes where node.isVisible {
            draw(node, origin: origin, scale: scale, offset: offset, in: &context)
        }
    }

    private func draw(_ node: Node, origin: CGPoint, scale: CGFloat,
                      offset: CGPoint, in context: inout GraphicsContext) {
        let rect = mapped(node.frame.offsetBy(dx: origin.x, dy: origin.y),
                          scale: scale, offset: offset)
        var localContext = context
        localContext.opacity *= max(0, min(1, node.opacity))

        switch node.content {
        case .rectangle(let shape):
            let p = Path(shape.effectiveRadii.path(in: rect, scale: scale))
            fill(p, with: shape.fill, in: &localContext)
            if shape.strokeWidth > 0 {
                localContext.stroke(p, with: .color(shape.stroke.swiftUI),
                                    lineWidth: max(0.75, shape.strokeWidth * scale))
            }
        case .ellipse(let shape):
            let p = Path(ellipseIn: rect)
            fill(p, with: shape.fill, in: &localContext)
            if shape.strokeWidth > 0 {
                localContext.stroke(p, with: .color(shape.stroke.swiftUI),
                                    lineWidth: max(0.75, shape.strokeWidth * scale))
            }
        case .polygon(let shape):
            let p = polygonPath(shape.vertices(in: rect))
            fill(p, with: shape.fill, in: &localContext)
            if shape.strokeWidth > 0 {
                localContext.stroke(p, with: .color(shape.stroke.swiftUI),
                                    lineWidth: max(0.75, shape.strokeWidth * scale))
            }
        case .path(let shape):
            let p = pathShape(shape, rect: rect, scale: scale)
            if shape.closed || shape.isMultiContour { fill(p, with: shape.fill, in: &localContext) }
            localContext.stroke(p, with: .color(shape.stroke.swiftUI),
                                lineWidth: max(0.75, shape.strokeWidth * scale))
        case .line(let shape):
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + shape.start.x * scale,
                               y: rect.minY + shape.start.y * scale))
            p.addLine(to: CGPoint(x: rect.minX + shape.end.x * scale,
                                  y: rect.minY + shape.end.y * scale))
            localContext.stroke(p, with: .color(shape.stroke.swiftUI),
                                lineWidth: max(0.75, shape.strokeWidth * scale))
        case .text(let text):
            drawText(text, in: rect, context: &localContext, scale: scale)
        case .group(let kids):
            if let fill = node.autoPadding?.fill {
                let radius = max(0, (node.autoPadding?.cornerRadius ?? 0) * scale)
                let p = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
                self.fill(p, with: fill, in: &localContext)
            }
            draw(kids, origin: CGPoint(x: origin.x + node.frame.minX,
                                       y: origin.y + node.frame.minY),
                 scale: scale, offset: offset, in: &localContext)
        case .instance(let inst):
            let kids = model.resolvedChildren(of: inst)
            draw(kids, origin: CGPoint(x: origin.x + node.frame.minX,
                                       y: origin.y + node.frame.minY),
                 scale: scale, offset: offset, in: &localContext)
        case .image:
            let p = RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: rect)
            localContext.fill(p, with: .color(EXPColor.rowHover))
            localContext.stroke(p, with: .color(EXPColor.borderStrong),
                                lineWidth: EXPMetric.strokeHairline)
        }
    }

    private func drawText(_ text: TextContent, in rect: CGRect,
                          context: inout GraphicsContext, scale: CGFloat) {
        let label = text.plainString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            let p = RoundedRectangle(cornerRadius: 3, style: .continuous).path(in: rect)
            context.fill(p, with: .color(EXPColor.textTertiary.opacity(0.35)))
            return
        }
        let fontSize = min(max(7, text.firstRun.fontSize * scale), max(8, rect.height * 0.72))
        var resolved = context.resolve(Text(label).font(.system(size: fontSize, weight: .medium)))
        resolved.shading = .color(text.firstRun.color.swiftUI)
        context.draw(resolved, at: CGPoint(x: rect.minX, y: rect.midY), anchor: .leading)
    }

    private func fill(_ path: Path, with paint: Paint, in context: inout GraphicsContext) {
        switch paint {
        case .solid(let color):
            context.fill(path, with: .color(color.swiftUI))
        case .gradient(let gradient):
            let colors = gradient.sortedStops.map { $0.color.swiftUI }
            context.fill(path, with: .linearGradient(
                Gradient(colors: colors.isEmpty ? [.white, .black] : colors),
                startPoint: .zero,
                endPoint: CGPoint(x: 90, y: 90)))
        }
    }

    private func polygonPath(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
        p.closeSubpath()
        return p
    }

    private func pathShape(_ shape: PathShape, rect: CGRect, scale: CGFloat) -> Path {
        var p = Path()
        for contour in shape.renderContours {
            guard let first = contour.first else { continue }
            p.move(to: pathPoint(first.point, rect: rect, scale: scale))
            for point in contour.dropFirst() {
                let end = pathPoint(point.point, rect: rect, scale: scale)
                if let c1 = point.controlIn {
                    p.addQuadCurve(to: end, control: pathPoint(c1, rect: rect, scale: scale))
                } else {
                    p.addLine(to: end)
                }
            }
            if shape.closed || shape.isMultiContour { p.closeSubpath() }
        }
        return p
    }

    private func pathPoint(_ point: CGPoint, rect: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
    }

    private func mapped(_ rect: CGRect, scale: CGFloat, offset: CGPoint) -> CGRect {
        CGRect(x: offset.x + rect.minX * scale,
               y: offset.y + rect.minY * scale,
               width: max(0.5, rect.width * scale),
               height: max(0.5, rect.height * scale))
    }
}

private struct ComponentCard: View {
    let source: ComponentSource
    @Binding var previewStateID: UUID?
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    let open: () -> Void

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            preview
            titleRow
            metadata
            footer
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
                .fill(hovering ? EXPColor.rowHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
                .strokeBorder(EXPColor.borderSoft, lineWidth: EXPMetric.strokeHairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { beginRename() }
        .onTapGesture { if !isRenaming { open() } }
        .contextMenu { contextMenu }
        .onDrag { NSItemProvider(object: source.id.uuidString as NSString) }
        .help("Double-click to rename · click to open “\(source.name)”")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), component")
    }

    private var preview: some View {
        ComponentSourcePreview(source: source,
                               stateID: previewStateID,
                               model: document.model)
            .frame(height: 88)
            .overlay(alignment: .topTrailing) {
                if instanceCount > 0 { instanceBadge.padding(6) }
            }
    }

    private var instanceBadge: some View {
        Button(action: selectInstances) {
            Text("×\(instanceCount)")
                .font(.system(size: EXPType.micro, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(EXPColor.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Capsule().fill(EXPColor.surfaceRaised))
        }
        .buttonStyle(.plain)
        .help(instanceBadgeHelp)
    }

    private var titleRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 11))
                .foregroundStyle(EXPColor.accent)
                .accessibilityHidden(true)
            if isRenaming {
                TextField("Name", text: $draft)
                    .textFieldStyle(.exp)
                    .font(.system(size: 12, weight: .medium))
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .onChange(of: nameFocused) { if !$1 { commitRename() } }
            } else {
                Text(source.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private var metadata: some View {
        Text("\(Int(source.size.width)) × \(Int(source.size.height)) · \(source.children.count) layer\(source.children.count == 1 ? "" : "s")")
            .font(.system(size: EXPType.micro))
            .foregroundStyle(EXPColor.textSecondary)
            .lineLimit(1)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            ComponentStatePreviewMenu(source: source, previewStateID: $previewStateID)
            Spacer(minLength: 0)
            if let role = source.a11y.role {
                Text(role.friendlyLabel)
                    .font(.system(size: EXPType.micro, weight: .medium))
                    .foregroundStyle(EXPColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Create Instance", action: createInstance)
        Button(instanceCount == 1 ? "Select Instance on Canvas"
                                  : "Select Instances on Canvas (\(instanceCount))",
               action: selectInstances)
            .disabled(instanceCount == 0)
        Divider()
        Button("Open in Editor", action: open)
        Button("Duplicate Component", action: duplicateComponent)
        Button("Rename", action: beginRename)
        Menu("Preview State") {
            Button {
                previewStateID = nil
            } label: {
                if previewStateID == nil { Label("default", systemImage: "checkmark") }
                else { Text("default") }
            }
            ForEach(source.states) { state in
                Button {
                    previewStateID = state.id
                } label: {
                    if previewStateID == state.id { Label(state.name, systemImage: "checkmark") }
                    else { Text(state.name) }
                }
            }
        }
        .disabled(source.states.isEmpty)
        categoryMenu
        Divider()
        Button("Delete Component", role: .destructive, action: deleteComponent)
    }

    private var categoryMenu: some View {
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
    }

    private var instanceIDs: [UUID] {
        var ids: [UUID] = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if case .instance(let inst) = node.content, inst.sourceID == source.id {
                    ids.append(node.id)
                }
                if case .group(let kids) = node.content { walk(kids) }
            }
        }
        walk(document.model.page(for: app.activeCanvasPageID)?.nodes ?? [])
        return ids
    }
    private var instanceCount: Int { instanceIDs.count }
    private var instanceBadgeHelp: String {
        "\(instanceCount) instance\(instanceCount == 1 ? "" : "s") on the canvas — click to select"
    }

    private func beginRename() {
        draft = source.name
        isRenaming = true
        nameFocused = true
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

    private func selectInstances() {
        let ids = instanceIDs
        guard !ids.isEmpty else { return }
        app.selectedNodeIDs = Set(ids)
        app.selectedArtboardIDs = []
    }

    private func setCategory(_ role: AriaRole?) {
        guard let i = document.model.sources.firstIndex(where: { $0.id == source.id }),
              document.model.sources[i].a11y.role != role else { return }
        var model = document.model
        model.sources[i].a11y.role = role
        document.setModel(model, undoManager: undoManager, actionName: "Set Component Category")
    }

    private func deleteComponent() {
        deleteComponentSource(source.id)
    }

    private func duplicateComponent() {
        duplicateComponentSource(source.id)
    }

    private func createInstance() {
        requestComponentPlacement(source.id)
    }
}

private struct ComponentRow: View {
    let source: ComponentSource
    @Binding var previewStateID: UUID?
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    let open: () -> Void

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var draft = ""
    @State private var pagedInstanceID: UUID?
    @FocusState private var nameFocused: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
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
                    Text(source.name).font(.system(size: EXPType.base, weight: .semibold))
                        .foregroundStyle(EXPColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                Text("\(Int(source.size.width)) × \(Int(source.size.height)) · \(source.children.count) layer\(source.children.count == 1 ? "" : "s")")
                    .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ComponentStatePreviewMenu(source: source,
                                              previewStateID: $previewStateID,
                                              compact: true)
                    if let role = source.a11y.role {
                        Text(role.friendlyLabel)
                            .font(.system(size: EXPType.micro, weight: .medium))
                            .foregroundStyle(EXPColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityLabel("Category: \(role.friendlyLabel)")
                    }
                }
            }
            Spacer(minLength: 0)
            usageControl
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
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
            Button("Duplicate Component", action: duplicateComponent)
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

    private func deleteComponent() {
        deleteComponentSource(source.id)
    }

    private func duplicateComponent() {
        duplicateComponentSource(source.id)
    }

    private func beginRename() {
        draft = source.name
        isRenaming = true
        nameFocused = true
    }

    private struct InstanceRef {
        var id: UUID
        var frame: CGRect
    }

    /// Every instance of this component in document-ish coordinates. Nested
    /// groups are offset through their ancestors so centering lands near the
    /// visible instance; transformed ancestors remain an approximation until the
    /// v1.6 component-grid thumbnail pass shares a fuller transform helper.
    private var instanceRefs: [InstanceRef] {
        var refs: [InstanceRef] = []
        func walk(_ nodes: [Node], origin: CGPoint) {
            for n in nodes {
                let frame = n.frame.offsetBy(dx: origin.x, dy: origin.y)
                if case .instance(let i) = n.content, i.sourceID == source.id {
                    refs.append(InstanceRef(id: n.id, frame: frame))
                }
                if case .group(let kids) = n.content {
                    walk(kids, origin: CGPoint(x: frame.minX, y: frame.minY))
                }
            }
        }
        walk(document.model.page(for: app.activeCanvasPageID)?.nodes ?? [], origin: .zero)
        return refs
    }
    private var instanceIDs: [UUID] { instanceRefs.map(\.id) }
    private var instanceCount: Int { instanceIDs.count }
    private var selectedInstanceID: UUID? {
        guard app.selectedNodeIDs.count == 1,
              let id = app.selectedNodeIDs.first,
              instanceIDs.contains(id) else { return nil }
        return id
    }
    private var activeInstanceID: UUID? {
        if let selectedInstanceID { return selectedInstanceID }
        if let pagedInstanceID, instanceIDs.contains(pagedInstanceID) { return pagedInstanceID }
        return nil
    }
    private var activeInstanceIndex: Int? {
        guard let activeInstanceID else { return nil }
        return instanceRefs.firstIndex { $0.id == activeInstanceID }
    }
    private var instancePagerLabel: String {
        if let activeInstanceIndex { return "\(activeInstanceIndex + 1)/\(instanceCount)" }
        return "×\(instanceCount)"
    }

    @ViewBuilder private var usageControl: some View {
        if instanceCount == 1 {
            instanceCountButton
        } else if instanceCount > 1 {
            HStack(spacing: 0) {
                instancePagerButton("chevron.left",
                                    help: "Previous instance",
                                    accessibilityLabel: "Previous instance",
                                    delta: -1)
                instanceCountButton
                instancePagerButton("chevron.right",
                                    help: "Next instance",
                                    accessibilityLabel: "Next instance",
                                    delta: 1)
            }
            .fixedSize(horizontal: true, vertical: true)
            .contentShape(Rectangle())
        }
    }

    private var instanceCountButton: some View {
        Button(action: selectInstances) {
            Text(instancePagerLabel)
                .font(.system(size: EXPType.micro, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(EXPColor.textSecondary)
                .frame(minWidth: 28, minHeight: EXPMetric.iconBtn)
                .padding(.horizontal, 2)
                .background(Capsule().fill(EXPColor.rowHover))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(instanceCount == 1 ? "1 instance on the canvas — click to select it"
                                 : "\(instanceCount) instances on the canvas — click to select them all")
        .accessibilityLabel("\(instanceCount) instance\(instanceCount == 1 ? "" : "s") on canvas. Select all.")
    }

    private func instancePagerButton(_ systemName: String,
                                     help: String,
                                     accessibilityLabel: String,
                                     delta: Int) -> some View {
        Button { pageInstance(delta) } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(instanceCount <= 1 ? EXPColor.textTertiary : EXPColor.textSecondary)
                .frame(width: 16, height: EXPMetric.iconBtn)
                .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(instanceCount <= 1)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Select (highlight) every canvas instance of this component.
    private func selectInstances() {
        let ids = instanceIDs
        guard !ids.isEmpty else { return }
        pagedInstanceID = nil
        app.selectedNodeIDs = Set(ids)
        app.selectedArtboardIDs = []
    }

    /// Select one instance and center the canvas on it, wrapping at either end.
    private func pageInstance(_ delta: Int) {
        let refs = instanceRefs
        guard !refs.isEmpty else { return }
        let current = activeInstanceIndex ?? (delta < 0 ? 0 : -1)
        let next = (current + delta + refs.count) % refs.count
        let ref = refs[next]
        pagedInstanceID = ref.id
        app.selectedNodeIDs = [ref.id]
        app.selectedArtboardIDs = []
        if app.visibleDocumentRect?.intersects(ref.frame) != true {
            app.centerOn(ref.frame)
        }
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

    /// Ask the active canvas to place the instance. Routing through the canvas is
    /// what lets the same Components-panel command target either the document or
    /// a component source while preserving graph validation and one-step undo.
    private func createInstance() {
        requestComponentPlacement(source.id)
    }
}

/// Components panels may live in a dock or a separate tray window. Carry the
/// source id through the existing multi-window canvas router rather than writing
/// directly to document-level nodes, so a focused source editor receives it.
private func requestComponentPlacement(_ sourceID: UUID) {
    let item = NSMenuItem(title: "Create Instance", action: nil, keyEquivalent: "")
    item.representedObject = sourceID.uuidString
    sendCanvasAction("placeComponentAction:", from: item)
}

/// Delete a component source from a Components panel, which may live in a dock
/// or a separate tray window. Like component placement, this carries the source
/// id through the canvas router rather than editing the document here, so the
/// `@objc` action on the canvas stays the one implementation of the behavior and
/// the grid and list rows can never drift apart.
private func deleteComponentSource(_ sourceID: UUID) {
    let item = NSMenuItem(title: "Delete Component", action: nil, keyEquivalent: "")
    item.representedObject = sourceID.uuidString
    sendCanvasAction("deleteComponentSourceAction:", from: item)
}

/// Duplicate the source definition itself (not a placed instance). The canvas
/// action owns id remapping, undo, and opening the new component editor.
private func duplicateComponentSource(_ sourceID: UUID) {
    let item = NSMenuItem(title: "Duplicate Component", action: nil, keyEquivalent: "")
    item.representedObject = sourceID.uuidString
    sendCanvasAction("duplicateComponentSourceAction:", from: item)
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
    static let panelOrder: [PanelID] = [.layers, .properties, .components, .designLanguage, .handoff, .sanaa]
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
        shownPanels: Set(WindowMenuModel.panelOrder.filter { $0.isAvailable && app.isPanelShown($0) }),
        toggle: { panel in
            guard panel.isAvailable else { return }
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
/// The workspace-preset commands, in one place so the Window menu and the toolbar
/// control call exactly the same code (FEAT-021).
@MainActor
enum WorkspacePresetCommands {
    static var presets: [WorkspacePreset] { PanelHub.shared.presets }
    static var activeID: UUID? { PanelHub.shared.activePresetID }
    static var activeName: String {
        presets.first { $0.id == activeID }?.name ?? ""
    }

    static func saveAs(_ app: AppState) {
        guard let name = promptForName(title: "Save Workspace",
                                       message: "Save the current panel arrangement — including where each floating panel sits on which screen.",
                                       initial: suggestedName(), confirm: "Save") else { return }
        PanelHub.shared.savePreset(named: name, snapshot: app.workspaceSnapshot)
    }

    /// Explicit, never automatic. Switching away from a preset you nudged does NOT
    /// silently overwrite it (Photoshop's rule, and the less surprising one).
    static func update(_ app: AppState) {
        guard let id = activeID else { return }
        PanelHub.shared.updatePreset(id, snapshot: app.workspaceSnapshot)
    }

    static func rename() {
        guard let id = activeID,
              let name = promptForName(title: "Rename Workspace", message: "",
                                       initial: activeName, confirm: "Rename") else { return }
        PanelHub.shared.renamePreset(id, to: name)
    }

    static func delete() {
        guard let id = activeID else { return }
        PanelHub.shared.deletePreset(id)
    }

    static func apply(_ id: UUID, to app: AppState) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        app.applyWorkspaceSnapshot(preset.snapshot)
        PanelHub.shared.activePresetID = id
    }

    private static func suggestedName() -> String {
        let n = NSScreen.screens.count
        if n <= 1 { return "Laptop" }
        return n == 2 ? "Dual-monitor" : "\(n) monitors"
    }

    /// A standard alert rather than a SwiftUI sheet: this is invoked from the MENU
    /// BAR, where there is no reliable view to attach a sheet to. An alert is also
    /// keyboard-operable and VoiceOver-labelled without extra work.
    private static func promptForName(title: String, message: String,
                                      initial: String, confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = "Workspace name"
        field.setAccessibilityLabel("Workspace name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// The preset list + save/update/rename/delete, shared by the Window menu and the
/// toolbar's workspace control so there is one implementation of each command.
struct WorkspacePresetMenuItems: View {
    let app: AppState?
    private var hub: PanelHub { PanelHub.shared }

    var body: some View {
        // Computed ONCE per menu build, not once per preset.
        let current = app?.workspaceSnapshot
        ForEach(hub.presets) { preset in
            Button {
                if let app { WorkspacePresetCommands.apply(preset.id, to: app) }
            } label: {
                // A checkmark rather than a Toggle: applying a preset is an action,
                // not a state you can switch off. It marks the preset the current
                // arrangement actually MATCHES — not merely the last one touched.
                Label(preset.name,
                      systemImage: current?.matches(preset.snapshot) == true
                          ? "checkmark" : "rectangle.3.group")
            }
            .disabled(app == nil)
        }
        if !hub.presets.isEmpty { Divider() }
        Button("Save Workspace As…") { if let app { WorkspacePresetCommands.saveAs(app) } }
            .disabled(app == nil)
        Button(hub.activePresetID == nil ? "Update Workspace"
                                         : "Update “\(WorkspacePresetCommands.activeName)”") {
            if let app { WorkspacePresetCommands.update(app) }
        }
        .disabled(app == nil || hub.activePresetID == nil)
        Button("Rename Workspace…") { WorkspacePresetCommands.rename() }
            .disabled(hub.activePresetID == nil)
        Button("Delete Workspace") { WorkspacePresetCommands.delete() }
            .disabled(hub.activePresetID == nil)
    }
}

struct WindowMenuItems: View {
    @FocusedValue(\.windowMenu) private var focused
    @AppStorage(SanaaPreferences.enabled) private var sanaaEnabled = false

    private var menu: WindowMenuModel? {
        if let focused { return focused }
        if let app = PanelHub.shared.activeApp { return makeWindowMenuModel(app) }
        return nil
    }

    var body: some View {
        Divider()
        // Per-panel show/hide (works in both modes).
        ForEach(availablePanels, id: \.self) { panel in
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
        Divider()
        Menu {
            WorkspacePresetMenuItems(app: PanelHub.shared.activeApp)
        } label: {
            Label("Workspace", systemImage: "rectangle.3.group")
        }
    }

    private var availablePanels: [PanelID] {
        WindowMenuModel.panelOrder.filter { $0 != .sanaa || sanaaEnabled }
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

//
//  MainWindow.swift
//  EXP [design]
//
//  Created by tapps on 6/3/26.
//


import SwiftUI
import AppKit

/// The main editor window: a three-pane layout (left panel · canvas · right panel),
/// the arrangement every design tool uses. We use HSplitView rather than
/// NavigationSplitView because this is an editor, not a navigation app — the
/// side panels are persistent inspectors, not a navigation hierarchy.
struct MainWindow: View {
    // The document this window is editing (provided by DocumentGroup). The
    // design data lives in `document.model`.
    @ObservedObject var document: ExpDocument
    var fileURL: URL?

    // Per-window view state — camera, selection, panel layout. `@State` owns it
    // for the window's lifetime; `.environment(app)` hands it down so any panel
    // can read it without knowing where it's hosted (groundwork for v2 floating
    // panels).
    @State private var app = AppState()

    // The window's undo stack, injected by SwiftUI. Edits register with it so
    // ⌘Z works and the document knows it needs saving.
    @Environment(\.undoManager) private var undoManager

    // Whether THIS window is the key/active window — used to make the shared
    // floating panels point at this document when it comes to the front.
    @Environment(\.controlActiveState) private var controlActiveState

    // Document name + edited flag, observed from the NSWindow, for the heading.
    @State private var windowChrome = WindowChrome()

    var body: some View {
        VStack(spacing: 0) {
            headingBar
            HStack(spacing: 0) {
            // Fixed tools strip — pinned left, not part of the resizable split.
            ToolsStrip()
                .zIndex(1)   // so hover tooltips draw over the canvas to its right
            Divider()

            HSplitView {
                // Left dock column (Phase 13). In Multi-Window mode the docks are
                // empty — panels float in their own windows — so the canvas fills.
                if app.workspaceMode == .single, app.showLeftPanel {
                    DockColumnView(document: document, side: .left)
                        .frame(minWidth: 200, idealWidth: app.workspace.left.width, maxWidth: 420)
                }

                CanvasView(app: app, document: document, documentURL: fileURL)
                    .overlay(alignment: .topLeading) { ArtboardNotesOverlay(document: document) }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1) // canvas gets the leftover space

                // Right dock column (Properties + Components by default).
                if app.workspaceMode == .single, app.showRightPanel {
                    DockColumnView(document: document, side: .right)
                        .frame(minWidth: 260, idealWidth: app.workspace.right.width, maxWidth: 460)
                }
            }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .environment(app)
        // Publish state for the Window menu (panels + dock visibility). Scene
        // value = active whenever this window is frontmost (no focused control
        // required), so the menu items enable correctly.
        .focusedSceneValue(\.windowMenu, makeWindowMenuModel(app))
        // Multi-window mode: float panels into their own windows (and tear them
        // down when returning to single-window or closing this document window).
        // Shared floating panels point at the frontmost document. Claim them when
        // this window appears or becomes key, and reconcile windows on mode/tray
        // changes. (The tray set is global — PanelHub — so a 2nd document doesn't
        // open a 2nd set of panels.)
        .onAppear { activate() }
        .onChange(of: controlActiveState) { _, state in if state == .key { activate() } }
        .onChange(of: app.workspaceMode) { _, _ in activate() }
        .onChange(of: PanelHub.shared.trays) { _, _ in PanelWindowManager.shared.reconcile() }
        // Configure the NSWindow for a custom glass heading (transparent titlebar,
        // content under it, non-opaque so the heading's behind-window glass shows).
        .background(WindowConfigurator(chrome: windowChrome))
        .sheet(isPresented: Binding(get: { app.showingFeedback },
                                    set: { app.showingFeedback = $0 })) {
            FeedbackSheet(app: app, document: document,
                          isPresented: Binding(get: { app.showingFeedback },
                                               set: { app.showingFeedback = $0 }))
        }
    }

    /// Custom heading bar — full width, behind-window liquid glass + top gradient,
    /// hosting the New-Artboard menu and the system controls (these used to live in
    /// the native toolbar). Sits in the titlebar region (draggable); leading space
    /// clears the macOS window buttons.
    /// Compact one-line heading: stoplights (system, left) · New-Artboard (opt 1,
    /// just right of them) · centered doc name + Edited flag · system controls
    /// (right). All clusters TOP-aligned to the stoplight line so it reads as a
    /// single bar. Behind-window glass + top gradient.
    private var headingBar: some View {
        ZStack {
            // Centered document name (+ Edited underneath). Its own layer so it
            // stays truly centered regardless of the side clusters. The tiny
            // AppKit bridge in the overlay routes clicks to the native document
            // rename/location UI without asking AppKit to draw the title itself.
            VStack(spacing: 1) {
                HStack(spacing: 0) {
                    Text(windowChrome.name).foregroundStyle(EXPColor.textPrimary)
                    Text(windowChrome.ext).foregroundStyle(EXPColor.textPrimary.opacity(0.3))
                }
                .font(.expDocName)
                .lineLimit(1)
                if windowChrome.edited {
                    Text("Edited")
                        .font(.system(size: EXPType.micro))
                        .foregroundStyle(EXPColor.accent)
                }
            }
            .overlay(DocumentTitleClickBridge())
            .help("Rename or move document")
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Left + right clusters on the stoplight line.
            HStack(alignment: .top, spacing: EXPMetric.md) {
                Spacer().frame(width: 70)   // clear the macOS window buttons
                newArtboardMenu
                Spacer()
                TopSystemControls(app: app)
            }
            .padding(.horizontal, EXPMetric.lg)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 44)                  // compact — tune to taste
        .frame(maxWidth: .infinity)
        .background(WindowGlassBackground(active: controlActiveState == .key))
        .expTopEdge(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EXPColor.hairline).frame(height: EXPMetric.strokeHairline)
        }
    }

    /// New-Artboard split button (primary click = default board; menu = presets).
    private var newArtboardMenu: some View {
        Menu {
            ForEach(ArtboardPreset.all) { preset in
                Button {
                    addArtboard(width: preset.width, height: preset.height, name: preset.name)
                } label: { Text(preset.menuLabel) }
            }
        } label: {
            Label("New Artboard", systemImage: "plus.rectangle").labelStyle(.iconOnly)
        } primaryAction: {
            addArtboard(width: 375, height: 667, name: "Artboard")
        }
        .menuIndicator(.visible)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("New artboard (⇧⌘N for default; use the menu for sizes)")
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    @discardableResult
    private static func showNativeDocumentTitlePopover(for window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let versionsButton = window.standardWindowButton(.documentVersionsButton) {
            versionsButton.performClick(nil)
            return true
        }
        if NSApp.sendAction(#selector(NSDocument.rename(_:)), to: nil, from: window) {
            return true
        }
        return false
    }

    /// Transparent hit target sized to the styled title text. SwiftUI owns the
    /// visual title; AppKit still owns the document rename/location behavior.
    private struct DocumentTitleClickBridge: NSViewRepresentable {
        func makeNSView(context: Context) -> TitleHitView { TitleHitView() }
        func updateNSView(_ view: TitleHitView, context: Context) {}

        final class TitleHitView: NSView {
            override var acceptsFirstResponder: Bool { true }

            override func mouseDown(with event: NSEvent) {
                if MainWindow.showNativeDocumentTitlePopover(for: window) { return }
                super.mouseDown(with: event)
            }

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .arrow)
            }
        }
    }

    /// Observable doc-chrome (name / extension / edited) read from the NSWindow.
    @Observable final class WindowChrome: @unchecked Sendable {
        var name: String = "Untitled"
        var ext: String = ""
        var edited: Bool = false
        /// Change-guarded so it can be called on the chatty `didUpdate` signal
        /// without thrashing @Observable (only real changes re-render).
        func update(from window: NSWindow) {
            let newName: String, newExt: String
            if let url = window.representedURL {
                newName = url.deletingPathExtension().lastPathComponent
                let e = url.pathExtension
                newExt = e.isEmpty ? "" : ".\(e)"
            } else {
                newName = window.title.isEmpty ? "Untitled" : window.title
                newExt = ""
            }
            let newEdited = window.isDocumentEdited
            if newName != name { name = newName }
            if newExt != ext { ext = newExt }
            if newEdited != edited { edited = newEdited }
        }
    }

    /// Configures the NSWindow (transparent titlebar, full-size content, non-opaque
    /// for the heading glass) and streams its title/edited state into `chrome`.
    private struct WindowConfigurator: NSViewRepresentable {
        let chrome: WindowChrome
        func makeNSView(context: Context) -> NSView {
            let v = WindowTrackingView()
            v.onResolve = { window in
                configure(window)
                context.coordinator.attach(window, chrome: chrome)
            }
            return v
        }
        func updateNSView(_ v: NSView, context: Context) {}
        func makeCoordinator() -> Coordinator { Coordinator() }

        private func configure(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            Self.syncNativeDocumentTitleControls(in: window)
            DispatchQueue.main.async { Self.syncNativeDocumentTitleControls(in: window) }
        }

        /// The native document icon / versions button remains the only public
        /// AppKit anchor for the rename/location popover. Keep those controls
        /// alive, but visually transparent and centered under EXP's styled title.
        fileprivate static func syncNativeDocumentTitleControls(in window: NSWindow) {
            let iconButton = window.standardWindowButton(.documentIconButton)
            let versionsButton = window.standardWindowButton(.documentVersionsButton)
            [iconButton, versionsButton].compactMap { $0 }.forEach { button in
                button.alphaValue = 0.001
                button.isHidden = false
            }
            hideNativeTitleResidue(in: window)

            guard let versionsButton,
                  let container = versionsButton.superview else { return }

            let spacing: CGFloat = 4
            let totalWidth = versionsButton.frame.width + (iconButton?.frame.width ?? 0) + (iconButton == nil ? 0 : spacing)
            let startX = max(0, (container.bounds.width - totalWidth) / 2)

            if let iconButton {
                var iconFrame = iconButton.frame
                iconFrame.origin.x = startX
                iconButton.frame = iconFrame
            }

            var versionsFrame = versionsButton.frame
            versionsFrame.origin.x = startX + (iconButton?.frame.width ?? 0) + (iconButton == nil ? 0 : spacing)
            versionsButton.frame = versionsFrame
        }

        private static func hideNativeTitleResidue(in window: NSWindow) {
            guard let titleRoot = window.standardWindowButton(.closeButton)?.superview else { return }
            let protectedButtons = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton),
                window.standardWindowButton(.documentIconButton),
                window.standardWindowButton(.documentVersionsButton)
            ].compactMap { $0 }

            for view in deepSubviews(of: titleRoot) {
                guard !protectedButtons.contains(where: { contains(view: $0, descendant: view) }) else { continue }
                if let textField = view as? NSTextField {
                    let titleText = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if titleText == "—" || titleText.contains("Edited") || titleText.contains(window.title) {
                        textField.alphaValue = 0.001
                    }
                    continue
                }

                let size = view.frame.size
                if size.height <= 3, size.width >= 6, size.width <= 40 {
                    view.alphaValue = 0.001
                }
            }
        }

        private static func contains(view: NSView, descendant: NSView) -> Bool {
            if view === descendant { return true }
            return view.subviews.contains { contains(view: $0, descendant: descendant) }
        }

        private static func deepSubviews(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap { deepSubviews(of: $0) }
        }

        final class Coordinator {
            private var obs: [NSKeyValueObservation] = []
            private var notifs: [NSObjectProtocol] = []
            func attach(_ window: NSWindow, chrome: WindowChrome) {
                chrome.update(from: window)
                obs.forEach { $0.invalidate() }; obs = []
                notifs.forEach { NotificationCenter.default.removeObserver($0) }
                notifs = []
                obs.append(window.observe(\.title, options: [.new]) { w, _ in
                    MainActor.assumeIsolated { chrome.update(from: w) } })
                obs.append(window.observe(\.representedURL, options: [.new]) { w, _ in
                    MainActor.assumeIsolated { chrome.update(from: w) } })
                obs.append(window.observe(\.isDocumentEdited, options: [.new]) { w, _ in
                    MainActor.assumeIsolated { chrome.update(from: w) } })
                // `isDocumentEdited` isn't reliably KVO-observable, so re-read it on the
                // window's `didUpdate` (fires around edits/saves); the change-guard in
                // `update` keeps this from causing re-render churn.
                notifs.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification, object: window, queue: .main) { note in
                        guard let w = note.object as? NSWindow else { return }
                        MainActor.assumeIsolated {
                            chrome.update(from: w)
                            WindowConfigurator.syncNativeDocumentTitleControls(in: w)
                        }
                    })
                notifs.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main) { note in
                        guard let w = note.object as? NSWindow else { return }
                        MainActor.assumeIsolated { WindowConfigurator.syncNativeDocumentTitleControls(in: w) }
                    })
            }

            deinit {
                obs.forEach { $0.invalidate() }
                notifs.forEach { NotificationCenter.default.removeObserver($0) }
            }
        }
    }

    /// A zero-size NSView that reports when it lands in a window.
    private final class WindowTrackingView: NSView {
        var onResolve: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { onResolve?(w) }
        }
    }

    /// Make the shared panels target this document, then bring the tray windows
    /// in line with the current mode + arrangement.
    private func activate() {
        PanelHub.shared.setActive(app: app, document: document, undoManager: undoManager)
        PanelWindowManager.shared.reconcile()
    }

    /// Add an artboard to the right of existing content, through the document's
    /// undo-aware funnel, then select it.
    private func addArtboard(width: CGFloat, height: CGFloat, name: String) {
        var model = document.model
        let originX = model.artboards.isEmpty ? 0 : model.contentBounds.maxX + 100
        let artboard = Artboard(
            name: "\(name) \(model.artboards.count + 1)",
            frame: CGRect(x: originX, y: 0, width: width, height: height)
        )
        model.artboards.append(artboard)
        document.setModel(model, undoManager: undoManager, actionName: "New Artboard")
        app.selectedArtboardID = artboard.id
    }
}

/// Preset artboard sizes for the New Artboard menu. Points (1pt = 1px at @1x);
/// print sizes are at 72dpi. Easy to add to — just extend `all`.
struct ArtboardPreset: Identifiable {
    let id = UUID()
    let name: String
    let group: String
    let width: CGFloat
    let height: CGFloat

    var menuLabel: String { "\(name)  ·  \(Int(width)) × \(Int(height))" }

    static let all: [ArtboardPreset] = [
        ArtboardPreset(name: "Phone",        group: "Mobile",  width: 393,  height: 852),   // iPhone 16
        ArtboardPreset(name: "Phone Small",  group: "Mobile",  width: 375,  height: 667),   // legacy default
        ArtboardPreset(name: "Tablet",       group: "Mobile",  width: 834,  height: 1194),  // iPad 11"
        ArtboardPreset(name: "Desktop",      group: "Web",     width: 1440, height: 1024),
        ArtboardPreset(name: "Web 1280",     group: "Web",     width: 1280, height: 800),
        ArtboardPreset(name: "Square",       group: "Social",  width: 1080, height: 1080),
        ArtboardPreset(name: "Story",        group: "Social",  width: 1080, height: 1920),
        ArtboardPreset(name: "Slide 16:9",   group: "Present", width: 1920, height: 1080),
        ArtboardPreset(name: "A4 Portrait",  group: "Print",   width: 595,  height: 842),
        ArtboardPreset(name: "Letter",       group: "Print",   width: 612,  height: 792)
    ]
}

/// The always-visible system-control line in the window's top-right toolbar.
/// Holds the zoom cluster, the dock show/hide toggles, and the workspace-mode
/// switch — all on one line. These are system-level (can't be hidden/disabled).
struct TopSystemControls: View {
    /// The window's shared state. Passed explicitly (not via @Environment) so it
    /// resolves reliably in the toolbar; Observation still tracks reads here.
    let app: AppState

    var body: some View {
        HStack(spacing: 6) {
            // Zoom cluster
            Button { app.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out (⌘-)")
            TextField("", value: zoomPercentBinding, format: .number.precision(.fractionLength(0)))
                .labelsHidden()
                .textFieldStyle(.exp)
                .frame(width: 46)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .numericStepping(zoomPercentBinding, min: 5)
                .help("Zoom %")
            Button { app.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in (⌘+)")
            Menu {
                Button("Zoom to Fit") { sendCanvasAction("fitToScreen:") }
                Button("Actual Size (100%)") { app.zoomActual() }
                Divider()
                ForEach([25, 50, 100, 200, 400], id: \.self) { pct in
                    Button("\(pct)%") { app.zoomTo(CGFloat(pct) / 100) }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("Zoom presets")

            Divider().frame(height: 16)

            // Dock show/hide — disabled in Multi-Window mode (no docks; panels
            // live in their own windows).
            Button { app.showLeftPanel.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Show/hide the left panel")
                .disabled(app.workspaceMode == .multiWindow)
            Button { app.showRightPanel.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("Show/hide the right panel")
                .disabled(app.workspaceMode == .multiWindow)

            Divider().frame(height: 16)

            // Workspace mode
            Menu {
                Picker("Workspace", selection: workspaceModeBinding) {
                    ForEach(AppState.WorkspaceMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: app.workspaceMode.icon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Workspace: \(app.workspaceMode.label)")
        }
    }

    private var zoomPercentBinding: Binding<Double> {
        Binding(get: { Double((app.zoom * 100).rounded()) },
                set: { app.zoomTo(CGFloat($0 / 100)) })
    }

    private var workspaceModeBinding: Binding<AppState.WorkspaceMode> {
        Binding(get: { app.workspaceMode }, set: { app.workspaceMode = $0 })
    }
}

/// Right panel — the Inspector. X/Y/W/H are two-way: editing a field writes
/// back through the document's undo-aware funnel, so the shape/artboard moves
/// or resizes and the change is a single undo step. The canvas, reading the
/// same document, redraws automatically.
/// Send a canvas action wherever the canvas actually is. `sendAction(to: nil)`
/// only walks the KEY window's responder chain — in multi-window mode a click
/// on a panel button makes the PANEL key, the chain dead-ends there, and the
/// action never reaches the canvas (the "align/distribute do nothing" bug; the
/// selection was never lost, the message just had no route). Try the key
/// window first (single-window mode), then walk the MAIN document window's
/// responder chain explicitly. Tray windows override `canBecomeMain` to false,
/// so `NSApp.mainWindow` is always the document window.
func sendCanvasAction(_ selectorName: String) {
    let sel = Selector(selectorName)
    if NSApp.sendAction(sel, to: nil, from: nil) { return }
    var responder = NSApp.mainWindow?.firstResponder ?? NSApp.mainWindow
    while let r = responder {
        if r.responds(to: sel) {
            _ = NSApp.sendAction(sel, to: r, from: nil)
            return
        }
        responder = r.nextResponder
    }
}

struct RightPanel: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    /// Noise/Dissolve "Advanced" accordion — remembered across effects, panel
    /// rebuilds, and app launches, so it stays the way the designer left it.
    @AppStorage("inspector.effects.advancedOpen") private var effectsAdvancedOpen = false
    /// Per-corner radius accordion (v1.3) — same remembered-disclosure pattern.
    @AppStorage("inspector.corners.advancedOpen") private var cornersAdvancedOpen = false

    /// Which node list this inspector edits: the document's top-level nodes, or a
    /// component source's children (the source-editor window).
    var scope: CanvasScope = .document

    /// Hosted in a dock group, the group header shows the title and zoom lives in
    /// the window's top-right system line — so both are suppressed here. The
    /// source-editor window keeps them (defaults true).
    var showsTitle: Bool = true
    var showsZoom: Bool = true

    /// The node list for the current scope.
    private var scopedNodes: [Node] {
        switch scope {
        case .document: return document.model.nodes
        case .source(let sid): return document.model.source(for: sid)?.children ?? []
        }
    }

    /// Mutate the scoped node list in one undo step (the single write funnel so
    /// the inspector works identically in the document and source-editor windows).
    private func commitScoped(_ action: String, _ change: (inout [Node]) -> Void) {
        var model = document.model
        switch scope {
        case .document:
            change(&model.nodes)
            model.nodes = AutoLayoutEngine.reflowed(model.nodes)
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            change(&model.sources[si].children)
            let reflowed = AutoLayoutEngine.reflowed(model.sources[si].children)
            model.sources[si].children = reflowed
            if fitSourceBounds,
               let bounds = model.managedRootBounds(in: reflowed) {
                model.sources[si].origin = bounds.origin
                model.sources[si].size = bounds.size
            }
        }
        document.setModel(model, undoManager: undoManager, actionName: action)
    }

    /// Find a node by id, searching INTO groups (so nested children resolve).
    private func findScopedNode(_ id: UUID) -> Node? {
        func find(_ nodes: [Node]) -> Node? {
            for n in nodes {
                if n.id == id { return n }
                if case .group(let k) = n.content, let f = find(k) { return f }
            }
            return nil
        }
        return find(scopedNodes)
    }

    /// Recursively mutate a node by id (into groups) in one undo step, so the
    /// Inspector edits nested children too.
    private func mutateScopedNode(_ id: UUID, action: String, _ change: @escaping (inout Node) -> Void) {
        commitScoped(action) { nodes in _ = Self.mutateNestedNode(id, in: &nodes, change) }
    }
    @discardableResult
    private static func mutateNestedNode(_ id: UUID, in nodes: inout [Node], _ change: (inout Node) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id { change(&nodes[i]); return true }
            if case .group(var k) = nodes[i].content {
                if mutateNestedNode(id, in: &k, change) { nodes[i].content = .group(children: k); return true }
            }
        }
        return false
    }

    /// The selected artboard, resolved from the document + the current selection.
    /// (Source scope has no artboards.)
    private var selectedArtboard: Artboard? {
        guard case .document = scope, let id = app.selectedArtboardID else { return nil }
        return document.model.artboards.first { $0.id == id }
    }

    /// The single selected shape, if exactly one is selected (within the scope).
    private var selectedNode: Node? {
        guard let id = app.singleSelectedNodeID else { return nil }
        return findScopedNode(id)   // resolves nested children too
    }

    /// Document-space offset to subtract for display so a shape's X/Y read
    /// relative to its owning artboard (0 on the wall, and 0 in source scope).
    private func ownerOffset(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> CGFloat {
        guard case .document = scope,
              let node = selectedNode,
              let owner = document.model.owningArtboard(of: node.frame) else { return 0 }
        if keyPath == \CGRect.origin.x { return owner.frame.minX }
        if keyPath == \CGRect.origin.y { return owner.frame.minY }
        return 0   // width/height are not relative to the artboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                Text("Inspector")
                    .font(.headline)
                    .padding(12)
                Divider()
            }

            if showsZoom {
                zoomControls()
                Divider()
            }

            // Editable details for the current selection, in a ScrollView so a long
            // inspector stays fully reachable. Title + zoom stay pinned above.
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
            if let node = selectedNode {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Layer").expSectionLabel()
                        Spacer(minLength: 0)
                        // Lock toggle (also ⌘L / ⌘⇧L, the layer row, and right-click).
                        Button { toggleLockSelected(node) } label: {
                            Image(systemName: node.isLocked ? "lock.fill" : "lock.open")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(node.isLocked ? Color.primary : Color.secondary)
                        .help(node.isLocked ? "Unlock layer" : "Lock layer")
                        .accessibilityLabel(node.isLocked ? "Unlock layer" : "Lock layer")
                    }
                    TextField("Name", text: nodeNameBinding)
                        .textFieldStyle(.exp)
                        .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                if case .group = node.content {
                    // Group W/H scales the group AND its children (move keeps origin).
                    dimensions(
                        title: "",
                        x: nodeBinding(\.origin.x, action: "Move Group"),
                        y: nodeBinding(\.origin.y, action: "Move Group"),
                        w: groupSizeBinding(node, width: true),
                        h: groupSizeBinding(node, width: false)
                    )
                } else if case .line = node.content {
                    // Line W/H scales its endpoints (frame.size alone left it unchanged).
                    dimensions(
                        title: "",
                        x: nodeBinding(\.origin.x, action: "Move Line"),
                        y: nodeBinding(\.origin.y, action: "Move Line"),
                        w: lineSizeBinding(width: true),
                        h: lineSizeBinding(width: false)
                    )
                } else {
                    dimensions(
                        title: "",
                        x: nodeBinding(\.origin.x, action: "Move Shape"),
                        y: nodeBinding(\.origin.y, action: "Move Shape"),
                        w: nodeBinding(\.size.width, action: "Resize Shape"),
                        h: nodeBinding(\.size.height, action: "Resize Shape")
                    )
                }
                HStack(spacing: 4) {
                    Text("R").foregroundStyle(EXPColor.textSecondary).frame(width: 14, alignment: .leading)
                    TextField("", value: nodeRotationBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 64)
                        .numericStepping(nodeRotationBinding)
                    Text("°").foregroundStyle(EXPColor.textSecondary)
                    Spacer()
                    Text("Opacity").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: nodeOpacityBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 48)
                        .numericStepping(nodeOpacityBinding, min: 0, max: 100)
                    Text("%").foregroundStyle(EXPColor.textSecondary)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                HStack(spacing: 6) {
                    Text("Blend").foregroundStyle(EXPColor.textSecondary)
                    Picker("", selection: nodeBlendModeBinding) {
                        ForEach(BlendMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .help("How this layer blends with what's beneath it")
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                if case .group = node.content {
                    Divider()
                    autoLayoutControls()
                    Divider()
                    autoPaddingControls()
                }
                if case .text = node.content {
                    textControls()
                }
                if case .line = node.content {
                    lineControls()
                }
                if case .rectangle = node.content { shapeControls(corner: true) }
                if case .ellipse = node.content { shapeControls(corner: false) }
                if case .polygon = node.content { shapeControls(corner: false); polygonControls() }
                if case .path = node.content { pathControls() }
                if case .instance = node.content {
                    instanceControls()
                }
                Divider()
                alignControls()
                Divider()
                effectsControls()
            } else if app.selectedNodeIDs.count > 1 {
                Text("\(app.selectedNodeIDs.count) shapes selected")
                    .foregroundStyle(EXPColor.textSecondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 12)
                // X/Y/W/H act on the selection's bounding box: X/Y move all of it,
                // W/H scale the whole arrangement about its top-left.
                dimensions(
                    title: "",
                    x: multiMoveBinding(horizontal: true),
                    y: multiMoveBinding(horizontal: false),
                    w: multiSizeBinding(width: true),
                    h: multiSizeBinding(width: false)
                )
                // Font / fill / stroke applied to EVERY selected layer at once.
                multiStyleControls()
                Divider()
                alignControls()
            } else if app.selectedArtboardIDs.count > 1 {
                Text("\(app.selectedArtboardIDs.count) artboards selected")
                    .foregroundStyle(EXPColor.textSecondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if selectedArtboard != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Artboard").expSectionLabel()
                    TextField("Name", text: artboardNameBinding)
                        .textFieldStyle(.exp)
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 8) {
                        DimField(label: "X", value: artboardBinding(\.origin.x, action: "Move Artboard"))
                        DimField(label: "Y", value: artboardBinding(\.origin.y, action: "Move Artboard"))
                    }
                    HStack(spacing: 8) {
                        DimField(label: "W", value: artboardBinding(\.size.width, action: "Resize Artboard"))
                        DimField(label: "H", value: artboardBinding(\.size.height, action: "Resize Artboard"))
                    }
                    Divider()
                    PaintWell(label: "Background", paint: artboardBackgroundBinding, supportsOpacity: false)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                layoutGridControls()
            } else {
                Text("No selection")
                    .foregroundStyle(EXPColor.textSecondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 12)
                Divider()
                uniformGridControls()
            }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background)
    }

    // MARK: Zoom controls (editable %, presets, slider, ± buttons)

    @ViewBuilder
    private func zoomControls() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Zoom").foregroundStyle(EXPColor.textSecondary)
                Spacer()
                TextField("", value: zoomPercentBinding, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .textFieldStyle(.exp)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .numericStepping(zoomPercentBinding, min: 5)
                Text("%").foregroundStyle(EXPColor.textSecondary)
                Menu {
                    Button("Zoom to Fit") { fitZoom() }
                    Button("Actual Size (100%)") { app.zoomActual() }
                    Divider()
                    ForEach([25, 50, 100, 200, 400], id: \.self) { pct in
                        Button("\(pct)%") { app.zoomTo(CGFloat(pct) / 100) }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .help("Zoom presets")
            }
            HStack(spacing: 8) {
                Button { app.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless).help("Zoom out (⌘-)")
                Slider(value: zoomSliderBinding, in: 0...1)
                Button { app.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless).help("Zoom in (⌘+)")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func fitZoom() {
        sendCanvasAction("fitToScreen:")
    }

    private var zoomPercentBinding: Binding<Double> {
        Binding(get: { Double((app.zoom * 100).rounded()) },
                set: { app.zoomTo(CGFloat($0 / 100)) })
    }

    /// Logarithmic mapping so the slider feels even across 5 %–6400 %.
    private var zoomSliderBinding: Binding<Double> {
        Binding(
            get: {
                let lo = log(Double(app.minZoom)), hi = log(Double(app.maxZoom))
                return Swift.min(1, Swift.max(0, (log(Double(app.zoom)) - lo) / (hi - lo)))
            },
            set: { t in
                let lo = log(Double(app.minZoom)), hi = log(Double(app.maxZoom))
                app.zoomTo(CGFloat(exp(lo + t * (hi - lo))))
            }
        )
    }

    // MARK: Dimensions block

    private func dimensions(title: String,
                            x: Binding<Double>, y: Binding<Double>,
                            w: Binding<Double>, h: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.callout.weight(.semibold)) }
            HStack(spacing: 8) {
                DimField(label: "X", value: x)
                DimField(label: "Y", value: y)
            }
            HStack(spacing: 8) {
                DimField(label: "W", value: w)
                DimField(label: "H", value: h)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Two-way bindings (read the document; write through setModel + undo)

    private func nodeBinding(_ keyPath: WritableKeyPath<CGRect, CGFloat>,
                             action: String) -> Binding<Double> {
        Binding(
            get: {
                // Display artboard-relative when owned (subtract the offset).
                let raw = selectedNode?.frame[keyPath: keyPath] ?? 0
                return Double(raw - ownerOffset(keyPath))
            },
            set: { newValue in
                guard let id = app.singleSelectedNodeID else { return }
                mutateScopedNode(id, action: action) { node in
                    node.frame[keyPath: keyPath] = clamp(keyPath, CGFloat(newValue) + ownerOffset(keyPath))
                }
            }
        )
    }

    /// Two-way binding to the selected node's name — writes through the document,
    /// so the Layers panel (reading the same model) updates in lockstep.
    private var nodeNameBinding: Binding<String> {
        Binding(
            get: {
                guard let node = selectedNode else { return "" }
                // A component instance's name IS its source (component) name — shared
                // with the Layers + Components panels (one source of truth).
                if case .instance(let inst) = node.content,
                   let src = document.model.source(for: inst.sourceID) { return src.name }
                return node.name
            },
            set: { newValue in
                guard let id = app.singleSelectedNodeID, let node = selectedNode else { return }
                // Editing an instance's name renames the source so every instance +
                // the Components panel update together.
                if case .instance(let inst) = node.content,
                   let si = document.model.sources.firstIndex(where: { $0.id == inst.sourceID }) {
                    var model = document.model
                    model.sources[si].name = newValue
                    document.setModel(model, undoManager: undoManager, actionName: "Rename Component")
                    return
                }
                mutateScopedNode(id, action: "Rename Layer") { $0.name = newValue }
            }
        )
    }

    /// Lock / unlock the given node through the scoped undo funnel (so it works in
    /// the source-editor window too, and stays in lockstep with the Layers panel).
    private func toggleLockSelected(_ node: Node) {
        let willLock = !node.isLocked
        mutateScopedNode(node.id, action: willLock ? "Lock" : "Unlock") { $0.isLocked = willLock }
    }

    private var nodeRotationBinding: Binding<Double> {
        Binding(
            get: { selectedNode?.rotation ?? 0 },
            set: { v in
                guard let id = app.singleSelectedNodeID else { return }
                let norm = v.truncatingRemainder(dividingBy: 360)
                mutateScopedNode(id, action: "Rotate") { $0.rotation = norm < 0 ? norm + 360 : norm }
            }
        )
    }

    /// The node tool's point-selection rotation field. Unlike `nodeRotationBinding`
    /// this isn't a stored property on the node — it's a dial that sends each
    /// turn's DELTA straight to the canvas via `AppState.applyPointRotation`,
    /// which spins the selected points about their own centre and bakes the
    /// turn into their coordinates (see CanvasNSView.rotateSelectedPoints).
    private var pointRotationBinding: Binding<Double> {
        Binding(
            get: { app.pointSelectionRotation },
            set: { newValue in
                let delta = newValue - app.pointSelectionRotation
                app.pointSelectionRotation = newValue
                app.applyPointRotation?(delta)
            }
        )
    }

    /// The node's whole-layer blend mode.
    private var nodeBlendModeBinding: Binding<BlendMode> {
        Binding(
            get: { selectedNode?.blendMode ?? .normal },
            set: { v in
                guard let id = app.singleSelectedNodeID else { return }
                mutateScopedNode(id, action: "Blend Mode") { $0.blendMode = v }
            }
        )
    }

    // MARK: Auto Layout (stacking) bindings + controls

    private var selectedAutoLayout: AutoLayout? { selectedNode?.autoLayout }

    /// Mutate the selected group's auto-layout (creating defaults if somehow nil).
    private func mutateAL(_ action: String, _ change: @escaping (inout AutoLayout) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: action) { node in
            var al = node.autoLayout ?? AutoLayout()
            change(&al)
            node.autoLayout = al
        }
    }

    private var alEnabledBinding: Binding<Bool> {
        Binding(
            get: { selectedNode?.autoLayout != nil },
            set: { on in
                guard let id = app.singleSelectedNodeID else { return }
                mutateScopedNode(id, action: on ? "Add Auto Layout" : "Remove Auto Layout") {
                    $0.autoLayout = on ? AutoLayout() : nil
                }
            })
    }
    private var alDirectionBinding: Binding<AutoLayout.Direction> {
        Binding(get: { selectedAutoLayout?.direction ?? .horizontal },
                set: { v in mutateAL("Layout Direction") { $0.direction = v } })
    }
    /// Off = packed (fixed gap), On = space-between.
    private var alSpaceBetweenBinding: Binding<Bool> {
        Binding(get: { selectedAutoLayout?.distribution == .spaceBetween },
                set: { v in mutateAL("Layout Spacing") { $0.distribution = v ? .spaceBetween : .packed } })
    }
    private var alGapBinding: Binding<Double> {
        Binding(get: { Double(selectedAutoLayout?.gap ?? 0) },
                set: { v in mutateAL("Layout Gap") { $0.gap = Swift.max(0, CGFloat(v)) } })
    }
    private var alCrossBinding: Binding<AutoLayout.Align> {
        Binding(get: { selectedAutoLayout?.cross ?? .center },
                set: { v in mutateAL("Layout Alignment") { $0.cross = v } })
    }

    @ViewBuilder
    private func autoLayoutControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Auto Layout").expSectionLabel()
                Spacer()
                Toggle("", isOn: alEnabledBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .help("Stack the children in a row or column with spacing")
            }
            if let al = selectedAutoLayout {
                EXPSegmented(selection: alDirectionBinding, segments: [
                    .init(value: .horizontal, icon: "arrow.right"),
                    .init(value: .vertical, icon: "arrow.down"),
                ])
                .help("Lay children out in a row or a column")

                HStack(spacing: 6) {
                    EXPSegmented(selection: alSpaceBetweenBinding, segments: [
                        .init(value: false, label: "Gap"),
                        .init(value: true, label: "Space Between"),
                    ])
                    .frame(maxWidth: 170)
                    if al.distribution == .packed {
                        TextField("", value: alGapBinding, format: .number.precision(.fractionLength(0)))
                            .labelsHidden().textFieldStyle(.exp)
                            .multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(width: 52).numericStepping(alGapBinding, min: 0)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text("Align").foregroundStyle(EXPColor.textSecondary)
                    EXPSegmented(selection: alCrossBinding, segments: [
                        .init(value: .start, label: al.direction == .horizontal ? "Top" : "Left"),
                        .init(value: .center, label: "Center"),
                        .init(value: .end, label: al.direction == .horizontal ? "Bottom" : "Right"),
                    ])
                }
                .help("Align items across the layout axis (e.g. vertically center a row)")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Auto Padding (hug + background) bindings + controls

    private var selectedAutoPadding: AutoPadding? { selectedNode?.autoPadding }

    private func mutateAP(_ action: String, _ change: @escaping (inout AutoPadding) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: action) { node in
            var pad = node.autoPadding ?? AutoPadding()
            change(&pad)
            node.autoPadding = pad
        }
    }

    private var apEnabledBinding: Binding<Bool> {
        Binding(
            get: { selectedNode?.autoPadding != nil },
            set: { on in
                guard let id = app.singleSelectedNodeID else { return }
                mutateScopedNode(id, action: on ? "Add Auto Padding" : "Remove Auto Padding") { node in
                    if on { AutoLayoutEngine.enableAutoPadding(on: &node) }  // absorb the background
                    else { node.autoPadding = nil }
                }
            })
    }
    private func apPadBinding(_ kp: WritableKeyPath<AutoPadding, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(selectedAutoPadding?[keyPath: kp] ?? 0) },
                set: { v in mutateAP("Padding") { $0[keyPath: kp] = Swift.max(0, CGFloat(v)) } })
    }
    private var apFillBinding: Binding<Paint> {
        Binding(get: { selectedAutoPadding?.fill ?? .clear },
                set: { p in mutateAP("Frame Fill") { $0.fill = p } })
    }
    private var apCornerBinding: Binding<Double> {
        Binding(get: { Double(selectedAutoPadding?.cornerRadius ?? 0) },
                set: { v in mutateAP("Frame Corner") { $0.cornerRadius = Swift.max(0, CGFloat(v)) } })
    }
    private var apStrokeBinding: Binding<RGBAColor> {
        Binding(get: { selectedAutoPadding?.stroke ?? .black },
                set: { c in mutateAP("Frame Stroke") { $0.stroke = c } })
    }
    private var apStrokeWidthBinding: Binding<Double> {
        Binding(get: { Double(selectedAutoPadding?.strokeWidth ?? 0) },
                set: { v in mutateAP("Frame Stroke Width") { $0.strokeWidth = Swift.max(0, CGFloat(v)) } })
    }

    @ViewBuilder
    private func autoPaddingControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Auto Padding").expSectionLabel()
                Spacer()
                Toggle("", isOn: apEnabledBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .help("Hug the children with padding and a background (button / tag / card)")
            }
            if selectedAutoPadding != nil {
                Text("Padding (content → background)").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                HStack(spacing: 4) {
                    apPadField("T", \.paddingTop)
                    apPadField("R", \.paddingRight)
                    apPadField("B", \.paddingBottom)
                    apPadField("L", \.paddingLeft)
                }
                Text("Margin (outside background)").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                HStack(spacing: 4) {
                    apPadField("T", \.marginTop)
                    apPadField("R", \.marginRight)
                    apPadField("B", \.marginBottom)
                    apPadField("L", \.marginLeft)
                }
                PaintWell(label: "Fill", paint: apFillBinding)
                HStack(spacing: 8) {
                    Text("Corner").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: apCornerBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 52).numericStepping(apCornerBinding, min: 0)
                    Spacer()
                    Text("Stroke").foregroundStyle(EXPColor.textSecondary)
                    ColorWell(label: "", color: apStrokeBinding)
                    TextField("", value: apStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 40).numericStepping(apStrokeWidthBinding, min: 0)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func apPadField(_ label: String, _ kp: WritableKeyPath<AutoPadding, CGFloat>) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary).font(.caption2)
            TextField("", value: apPadBinding(kp), format: .number.precision(.fractionLength(0)))
                .labelsHidden().textFieldStyle(.exp)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .frame(width: 40).numericStepping(apPadBinding(kp), min: 0)
        }
    }

    /// Opacity shown as 0–100% in the Inspector, stored as 0–1 on the model.
    private var nodeOpacityBinding: Binding<Double> {
        Binding(
            get: { (selectedNode?.opacity ?? 1) * 100 },
            set: { v in
                guard let id = app.singleSelectedNodeID else { return }
                let frac = Swift.max(0, Swift.min(1, v / 100))
                mutateScopedNode(id, action: "Opacity") { $0.opacity = frac }
            }
        )
    }

    // MARK: Selection-transform bindings (group + multi-selection)

    /// Selected ids the union/transform acts on: any selected node whose ANCESTOR
    /// chain is unrotated (doc↔parent-local is then a pure translation), excluding
    /// nodes that have a selected ancestor (they'd transform twice via the parent).
    /// Mirrors the canvas so the panel and canvas agree.
    private var selectionTransformIDs: [UUID] {
        app.selectedNodeIDs.filter { id in
            findScopedNode(id) != nil
                && (scopedIsTopLevel(id) || scopedAncestorRotation(id) == 0)
                && !hasSelectedAncestorScoped(id)
        }
    }

    /// The selected nodes lifted into DOCUMENT space (parent offset folded in), so the
    /// union W/H — and the scale math — is uniform whether nodes are top-level or nested.
    private var selectionDocNodes: [Node] {
        selectionTransformIDs.compactMap { id in
            guard var n = findScopedNode(id) else { return nil }
            let off = scopedNodeOffset(id)
            n.frame = n.frame.offsetBy(dx: off.x, dy: off.y)
            return n
        }
    }

    /// Union bounds of the selected nodes (document space) — drives multi-selection W/H.
    private var multiSelectionBounds: CGRect? {
        SelectionTransform.unionBounds(selectionDocNodes)
    }

    /// True if `id` is a top-level node in this scope.
    private func scopedIsTopLevel(_ id: UUID) -> Bool {
        scopedNodes.contains { $0.id == id }
    }

    /// Accumulated document-space offset of a node (sum of ancestor group origins).
    private func scopedNodeOffset(_ id: UUID) -> CGPoint {
        Self.scopedOffset(of: id, in: scopedNodes) ?? .zero
    }

    /// Total rotation (deg) of a node's ANCESTOR groups (0 = unrotated chain).
    private func scopedAncestorRotation(_ id: UUID) -> Double {
        func find(_ nodes: [Node], _ acc: Double) -> Double? {
            for n in nodes {
                if n.id == id { return acc }
                if case .group(let k) = n.content, let r = find(k, acc + n.rotation) { return r }
            }
            return nil
        }
        return find(scopedNodes, 0) ?? 0
    }

    /// True if any ancestor group of `id` is itself selected.
    private func hasSelectedAncestorScoped(_ id: UUID) -> Bool {
        func walk(_ nodes: [Node], _ selectedAbove: Bool) -> Bool? {
            for n in nodes {
                if n.id == id { return selectedAbove }
                if case .group(let kids) = n.content,
                   let r = walk(kids, selectedAbove || app.selectedNodeIDs.contains(n.id)) { return r }
            }
            return nil
        }
        return walk(scopedNodes, false) ?? false
    }

    /// Document-space offset of `id` within an arbitrary node array — for use inside a
    /// commit closure where the live array (not `scopedNodes`) is in hand.
    private static func scopedOffset(of id: UUID, in nodes: [Node], base: CGPoint = .zero) -> CGPoint? {
        for n in nodes {
            if n.id == id { return base }
            if case .group(let k) = n.content,
               let r = scopedOffset(of: id, in: k, base: CGPoint(x: base.x + n.frame.minX, y: base.y + n.frame.minY)) { return r }
        }
        return nil
    }

    /// W/H for a single GROUP: scales the group AND its children (keeping the
    /// group's top-left fixed), via the shared transform. Works at any nesting.
    private func groupSizeBinding(_ node: Node, width: Bool) -> Binding<Double> {
        Binding(
            get: { Double(width ? node.frame.width : node.frame.height) },
            set: { v in
                mutateScopedNode(node.id, action: "Resize Group") { n in
                    let nv = max(1, CGFloat(v))
                    let sx = width ? nv / max(1, n.frame.width) : 1
                    let sy = width ? 1 : nv / max(1, n.frame.height)
                    n = SelectionTransform.scaled(n, about: n.frame.origin, sx: sx, sy: sy)
                }
            })
    }

    /// W/H for a single LINE: scales its endpoints to the new dimension (the
    /// endpoints are stored local to the frame, so setting `frame.size` alone left
    /// the visible line unchanged — the bug). Endpoints are 0-based within the
    /// frame, so scaling about 0 keeps the min at 0 and moves the max to the value.
    private func lineSizeBinding(width: Bool) -> Binding<Double> {
        Binding(
            get: { Double(width ? (selectedNode?.frame.width ?? 0) : (selectedNode?.frame.height ?? 0)) },
            set: { v in
                guard let id = app.singleSelectedNodeID else { return }
                let nv = max(1, CGFloat(v))
                mutateScopedNode(id, action: "Resize Line") { node in
                    guard case .line(var ls) = node.content else { return }
                    if width {
                        let s = nv / max(1, node.frame.width)
                        ls.start.x *= s; ls.end.x *= s
                        node.frame.size.width = nv
                    } else {
                        let s = nv / max(1, node.frame.height)
                        ls.start.y *= s; ls.end.y *= s
                        node.frame.size.height = nv
                    }
                    node.content = .line(ls)
                }
            })
    }

    /// X/Y for a multi-selection: moves every selected node so the selection
    /// bounds' corner lands at the typed value.
    private func multiMoveBinding(horizontal: Bool) -> Binding<Double> {
        Binding(
            get: { Double(horizontal ? (multiSelectionBounds?.minX ?? 0) : (multiSelectionBounds?.minY ?? 0)) },
            set: { v in
                guard let b = multiSelectionBounds else { return }
                let dx = horizontal ? CGFloat(v) - b.minX : 0
                let dy = horizontal ? 0 : CGFloat(v) - b.minY
                let ids = selectionTransformIDs
                commitScoped("Move") { nodes in
                    for id in ids {
                        _ = Self.mutateNestedNode(id, in: &nodes) {
                            $0.frame.origin.x += dx
                            $0.frame.origin.y += dy
                        }
                    }
                }
            })
    }

    /// W/H for a multi-selection: scales every selected node about the selection
    /// bounds' top-left, so the whole arrangement grows/shrinks as one.
    private func multiSizeBinding(width: Bool) -> Binding<Double> {
        Binding(
            get: { Double(width ? (multiSelectionBounds?.width ?? 0) : (multiSelectionBounds?.height ?? 0)) },
            set: { v in
                guard let b = multiSelectionBounds else { return }
                let nv = max(1, CGFloat(v))
                let sx = width ? nv / max(1, b.width) : 1
                let sy = width ? 1 : nv / max(1, b.height)
                let anchor = b.origin
                let ids = selectionTransformIDs
                commitScoped("Resize") { nodes in
                    for id in ids {
                        let off = Self.scopedOffset(of: id, in: nodes) ?? .zero
                        _ = Self.mutateNestedNode(id, in: &nodes) { n in
                            var doc = n
                            doc.frame = n.frame.offsetBy(dx: off.x, dy: off.y)
                            doc = SelectionTransform.scaled(doc, about: anchor, sx: sx, sy: sy)
                            doc.frame = doc.frame.offsetBy(dx: -off.x, dy: -off.y)
                            n = doc
                        }
                    }
                }
            })
    }

    // MARK: Multi-selection style editing (font / fill / stroke applied to ALL)

    private var selectedResolvedNodes: [Node] { app.selectedNodeIDs.compactMap { findScopedNode($0) } }

    /// Apply a change to EVERY selected node (recursing into groups), one undo step.
    private func mutateAllSelected(_ action: String, _ change: @escaping (inout Node) -> Void) {
        let ids = app.selectedNodeIDs
        commitScoped(action) { nodes in
            for id in ids { _ = Self.mutateNestedNode(id, in: &nodes, change) }
        }
    }
    private func applyToAllText(_ action: String, _ change: @escaping (inout TextContent) -> Void) {
        mutateAllSelected(action) { node in
            guard case .text(var tc) = node.content else { return }
            change(&tc)
            node.content = .text(tc)
            if tc.box == .auto { node.frame.size = tc.measuredSize() }
        }
    }

    private func nodeHasFill(_ n: Node) -> Bool {
        switch n.content {
        case .rectangle, .ellipse, .polygon, .path, .text: return true
        case .group: return n.autoPadding != nil
        default: return false
        }
    }
    private func nodeHasStroke(_ n: Node) -> Bool {
        switch n.content {
        case .rectangle, .ellipse, .polygon, .path, .line: return true
        case .group: return n.autoPadding != nil
        default: return false
        }
    }
    private var multiAnyFill: Bool { selectedResolvedNodes.contains(where: nodeHasFill) }
    private var multiAnyStroke: Bool { selectedResolvedNodes.contains(where: nodeHasStroke) }
    private var multiAnyText: Bool { selectedResolvedNodes.contains { if case .text = $0.content { return true }; return false } }

    // Representative current value (first matching node) for the multi controls.
    private var multiFill: Paint {
        for n in selectedResolvedNodes {
            switch n.content {
            case .rectangle(let s): return s.fill
            case .ellipse(let s): return s.fill
            case .polygon(let s): return s.fill
            case .path(let s): return s.fill
            case .text(let t): return .solid(t.firstRun.color)
            case .group: if let f = n.autoPadding?.fill { return f }
            default: break
            }
        }
        return .white
    }
    private var multiStroke: RGBAColor {
        for n in selectedResolvedNodes {
            switch n.content {
            case .rectangle(let s): return s.stroke
            case .ellipse(let s): return s.stroke
            case .polygon(let s): return s.stroke
            case .path(let s): return s.stroke
            case .line(let s): return s.stroke
            case .group: if let st = n.autoPadding?.stroke { return st }
            default: break
            }
        }
        return .black
    }
    private var multiStrokeWidth: CGFloat {
        for n in selectedResolvedNodes {
            switch n.content {
            case .rectangle(let s): return s.strokeWidth
            case .ellipse(let s): return s.strokeWidth
            case .polygon(let s): return s.strokeWidth
            case .path(let s): return s.strokeWidth
            case .line(let s): return s.strokeWidth
            case .group: if let w = n.autoPadding?.strokeWidth { return w }
            default: break
            }
        }
        return 0
    }
    private var multiTextSize: CGFloat {
        for n in selectedResolvedNodes { if case .text(let t) = n.content { return t.firstRun.fontSize } }
        return 16
    }

    private var multiFillBinding: Binding<Paint> {
        Binding(get: { multiFill }, set: { p in
            mutateAllSelected("Fill") { node in
                switch node.content {
                case .rectangle(var s): s.fill = p; node.content = .rectangle(s)
                case .ellipse(var s):   s.fill = p; node.content = .ellipse(s)
                case .polygon(var s):   s.fill = p; node.content = .polygon(s)
                case .path(var s):      s.fill = p; node.content = .path(s)
                case .text(var t):      t.applyToAllRuns { $0.color = p.representativeColor }; node.content = .text(t)
                case .group:            if node.autoPadding != nil { node.autoPadding?.fill = p }
                default: break
                }
            }
        })
    }
    private var multiStrokeBinding: Binding<RGBAColor> {
        Binding(get: { multiStroke }, set: { c in
            mutateAllSelected("Stroke Color") { node in
                switch node.content {
                case .rectangle(var s): s.stroke = c; node.content = .rectangle(s)
                case .ellipse(var s):   s.stroke = c; node.content = .ellipse(s)
                case .polygon(var s):   s.stroke = c; node.content = .polygon(s)
                case .path(var s):      s.stroke = c; node.content = .path(s)
                case .line(var s):      s.stroke = c; node.content = .line(s)
                case .group:            if node.autoPadding != nil { node.autoPadding?.stroke = c }
                default: break
                }
            }
        })
    }
    /// True when any selected node is a closed shape (alignment applies).
    private var multiHasClosedShape: Bool {
        selectedResolvedNodes.contains { n in
            switch n.content {
            case .rectangle, .ellipse, .polygon: return true
            case .path(let ps): return ps.closed || ps.isMultiContour
            default: return false
            }
        }
    }

    /// First selected closed shape's alignment (the picker's current value).
    private var multiStrokeAlignment: StrokeAlignment {
        for n in selectedResolvedNodes {
            switch n.content {
            case .rectangle(let s): return s.strokeAlignment
            case .ellipse(let s):   return s.strokeAlignment
            case .polygon(let s):   return s.strokeAlignment
            case .path(let s) where s.closed || s.isMultiContour: return s.strokeAlignment
            default: continue
            }
        }
        return .center
    }

    private var multiStrokeAlignmentBinding: Binding<StrokeAlignment> {
        Binding(get: { multiStrokeAlignment }, set: { a in
            mutateAllSelected("Stroke Position") { node in
                switch node.content {
                case .rectangle(var s): s.strokeAlignment = a; node.content = .rectangle(s)
                case .ellipse(var s):   s.strokeAlignment = a; node.content = .ellipse(s)
                case .polygon(var s):   s.strokeAlignment = a; node.content = .polygon(s)
                case .path(var s):      s.strokeAlignment = a; node.content = .path(s)
                default: break   // lines/open paths: no interior, stays centered
                }
            }
        })
    }

    private var multiStrokeWidthBinding: Binding<Double> {
        Binding(get: { Double(multiStrokeWidth) }, set: { v in
            let w = Swift.max(0, CGFloat(v))
            mutateAllSelected("Stroke Width") { node in
                switch node.content {
                case .rectangle(var s): s.strokeWidth = w; node.content = .rectangle(s)
                case .ellipse(var s):   s.strokeWidth = w; node.content = .ellipse(s)
                case .polygon(var s):   s.strokeWidth = w; node.content = .polygon(s)
                case .path(var s):      s.strokeWidth = w; node.content = .path(s)
                case .line(var s):      s.strokeWidth = w; node.content = .line(s)
                case .group:            if node.autoPadding != nil { node.autoPadding?.strokeWidth = w }
                default: break
                }
            }
        })
    }
    private var multiTextSizeBinding: Binding<Double> {
        Binding(get: { Double(multiTextSize) },
                set: { v in let sz = Swift.max(1, CGFloat(v)); applyToAllText("Text Size") { $0.applyToAllRuns { $0.fontSize = sz } } })
    }
    private func applyFontFamilyAll(_ family: String) {
        let ps = family.isEmpty ? "" : (FontCatalog.defaultFace(of: family) ?? "")
        applyToAllText("Font") { $0.applyToAllRuns { $0.fontName = ps } }
    }

    @ViewBuilder
    private func multiStyleControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if multiAnyText {
                Divider()
                Text("Type").expSectionLabel().padding(.top, 4)
                Menu {
                    Button("System") { applyFontFamilyAll("") }
                    Divider()
                    ForEach(FontCatalog.families, id: \.self) { fam in
                        Button { applyFontFamilyAll(fam) } label: {
                            Text(fam).font(fontMenuPreview(for: fam, size: 13))
                        }
                    }
                } label: {
                    HStack { Text("Font"); Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(EXPColor.textSecondary) }
                }
                .help("Set the typeface on every selected text layer")
                HStack(spacing: 8) {
                    Text("Size").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: multiTextSizeBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp).frame(width: 56)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .numericStepping(multiTextSizeBinding, min: 1)
                    Spacer()
                }
            }
            if multiAnyFill {
                Divider()
                Text("Fill").expSectionLabel().padding(.top, 4)
                PaintWell(label: "Fill", paint: multiFillBinding)
            }
            if multiAnyStroke {
                Divider()
                Text("Stroke").expSectionLabel().padding(.top, 4)
                ColorWell(label: "Color", color: multiStrokeBinding)
                HStack(spacing: 8) {
                    Text("Width").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: multiStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp).frame(width: 56)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .numericStepping(multiStrokeWidthBinding, min: 0)
                    Spacer()
                }
                if multiHasClosedShape {
                    // v1.3 stroke alignment: closed shapes only (lines and open
                    // paths have no interior — they always render centered).
                    EXPSegmented(selection: multiStrokeAlignmentBinding,
                                 segments: StrokeAlignment.allCases.map { .init(value: $0, label: $0.label) })
                    .expFieldTip("Stroke position",
                                 "Where the stroke sits on the shape's edge. **Center** straddles it (half in, half out — the classic default). **Inside** keeps the whole stroke within the shape's frame. **Outside** paints it entirely beyond the edge. Lines and open paths are always centered.")
                    .accessibilityLabel("Stroke position: center, inside, or outside the shape edge")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Align & distribute

    @ViewBuilder private func alignControls() -> some View {
        let count = app.selectedNodeIDs.count
        let alignOK = count >= 2 || app.alignTarget == .artboard
        VStack(alignment: .leading, spacing: 8) {
            Text("Align").expSectionLabel().padding(.top, 4)

            // "Relative to" scope on its own labeled row — a segmented control, so
            // it reads as a mode toggle and can't be confused with the icon buttons.
            HStack(spacing: 8) {
                Text("To").foregroundStyle(EXPColor.textSecondary)
                EXPSegmented(selection: alignTargetBinding, segments: [
                    .init(value: .selection, label: "Selection"),
                    .init(value: .artboard, label: "Artboard"),
                ])
                .help("Align relative to the selection's bounds or the artboard")
            }

            // Align edges/centers.
            HStack(spacing: 4) {
                alignOpButton("align.horizontal.left", "Align left edges", "alignLeftAction:", enabled: alignOK)
                alignOpButton("align.horizontal.center", "Align horizontal centers", "alignHCenterAction:", enabled: alignOK)
                alignOpButton("align.horizontal.right", "Align right edges", "alignRightAction:", enabled: alignOK)
                Divider().frame(height: 18)
                alignOpButton("align.vertical.top", "Align top edges", "alignTopAction:", enabled: alignOK)
                alignOpButton("align.vertical.center", "Align vertical centers", "alignVCenterAction:", enabled: alignOK)
                alignOpButton("align.vertical.bottom", "Align bottom edges", "alignBottomAction:", enabled: alignOK)
                Spacer()
            }

            // Distribute on its own clearly-labeled row, away from the scope control.
            HStack(spacing: 6) {
                Text("Distribute").foregroundStyle(EXPColor.textSecondary)
                alignOpButton("arrow.left.and.right", "Distribute horizontal spacing", "distributeHorizontallyAction:", enabled: count >= 3)
                alignOpButton("arrow.up.and.down", "Distribute vertical spacing", "distributeVerticallyAction:", enabled: count >= 3)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alignOpButton(_ symbol: String, _ help: String, _ selector: String, enabled: Bool = true) -> some View {
        InspectorIconButton(symbol: symbol, enabled: enabled) {
            sendCanvasAction(selector)
        }
        .help(help)
    }

    private var alignTargetBinding: Binding<AppState.AlignTarget> {
        Binding(get: { app.alignTarget }, set: { app.alignTarget = $0 })
    }

    // MARK: Grids — uniform (no selection) + layout grids (artboard)

    @ViewBuilder private func uniformGridControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grid").expSectionLabel()
            Toggle("Show grid", isOn: Binding(get: { app.showGrid }, set: { app.showGrid = $0 }))
            HStack(spacing: 8) {
                Text("Size").foregroundStyle(EXPColor.textSecondary)
                TextField("", value: gridSizeBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 52).multilineTextAlignment(.trailing)
                    .numericStepping(gridSizeBinding, min: 1)
                Text("Subdiv").foregroundStyle(EXPColor.textSecondary)
                TextField("", value: gridSubdivBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                    .numericStepping(gridSubdivBinding, min: 1)
            }
            Toggle("Snap to grid", isOn: Binding(get: { app.snapToGrid }, set: { app.snapToGrid = $0 }))
        }
        .font(.callout)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gridSizeBinding: Binding<Double> {
        Binding(get: { Double(app.gridSize) }, set: { app.gridSize = max(1, CGFloat($0)) })
    }
    private var gridSubdivBinding: Binding<Double> {
        Binding(get: { Double(app.gridSubdivisions) }, set: { app.gridSubdivisions = max(1, Int($0)) })
    }

    @ViewBuilder private func layoutGridControls() -> some View {
        let grids = selectedArtboard?.layoutGrids ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
				Text("Layout Grids").expSectionLabel().padding(.top, 4)

                Spacer()
                Menu {
                    Button("Columns") { addLayoutGrid(.columns) }
                    Button("Rows") { addLayoutGrid(.rows) }
                    Button("Baseline") { addLayoutGrid(.baseline) }
                } label: { Image(systemName: "plus.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("Add a layout grid")
            }
            if grids.isEmpty { Text("No layout grids").font(.caption2).foregroundStyle(EXPColor.textTertiary) }
            ForEach(Array(grids.enumerated()), id: \.element.id) { idx, g in
                layoutGridRow(idx: idx, grid: g)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func layoutGridRow(idx: Int, grid: LayoutGrid) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: lgBool(idx, \.visible)).labelsHidden().toggleStyle(.checkbox)
                Picker("", selection: lgKind(idx)) {
                    Text("Columns").tag(LayoutGrid.Kind.columns)
                    Text("Rows").tag(LayoutGrid.Kind.rows)
                    Text("Baseline").tag(LayoutGrid.Kind.baseline)
                }.labelsHidden().frame(width: 96)
                ColorWell(label: "", color: lgColor(idx))
                Spacer()
                Button { removeLayoutGrid(grid.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Remove")
            }
            if grid.kind == .baseline {
                HStack(spacing: 4) { lgNum("Size", idx, \.size, min: 1); Spacer() }.font(.caption)
            } else {
                HStack(spacing: 4) {
                    lgInt("Count", idx, \.count)
                    lgNum("Gutter", idx, \.gutter, min: 0)
                    lgNum("Margin", idx, \.margin, min: 0)
                    Spacer()
                }.font(.caption)
            }
        }
        .padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func lgAt(_ idx: Int) -> LayoutGrid? {
        guard let g = selectedArtboard?.layoutGrids, g.indices.contains(idx) else { return nil }
        return g[idx]
    }
    private func updateLayoutGrid(_ idx: Int, action: String, _ change: @escaping (inout LayoutGrid) -> Void) {
        guard let id = app.selectedArtboardID,
              let ai = document.model.artboards.firstIndex(where: { $0.id == id }),
              document.model.artboards[ai].layoutGrids.indices.contains(idx) else { return }
        var model = document.model
        change(&model.artboards[ai].layoutGrids[idx])
        document.setModel(model, undoManager: undoManager, actionName: action)
    }
    private func addLayoutGrid(_ kind: LayoutGrid.Kind) {
        guard let id = app.selectedArtboardID,
              let ai = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
        var model = document.model
        model.artboards[ai].layoutGrids.append(LayoutGrid(kind: kind))
        document.setModel(model, undoManager: undoManager, actionName: "Add Layout Grid")
    }
    private func removeLayoutGrid(_ gid: UUID) {
        guard let id = app.selectedArtboardID,
              let ai = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
        var model = document.model
        model.artboards[ai].layoutGrids.removeAll { $0.id == gid }
        document.setModel(model, undoManager: undoManager, actionName: "Remove Layout Grid")
    }
    private func lgBool(_ idx: Int, _ kp: WritableKeyPath<LayoutGrid, Bool>) -> Binding<Bool> {
        Binding(get: { lgAt(idx)?[keyPath: kp] ?? true },
                set: { v in updateLayoutGrid(idx, action: "Layout Grid") { $0[keyPath: kp] = v } })
    }
    private func lgKind(_ idx: Int) -> Binding<LayoutGrid.Kind> {
        Binding(get: { lgAt(idx)?.kind ?? .columns },
                set: { v in updateLayoutGrid(idx, action: "Layout Grid") { $0.kind = v } })
    }
    private func lgColor(_ idx: Int) -> Binding<RGBAColor> {
        Binding(get: { lgAt(idx)?.color ?? .black },
                set: { v in updateLayoutGrid(idx, action: "Layout Grid Color") { $0.color = v } })
    }
    private func lgNum(_ label: String, _ idx: Int, _ kp: WritableKeyPath<LayoutGrid, CGFloat>, min: Double? = nil) -> some View {
        let b = Binding<Double>(get: { Double(lgAt(idx)?[keyPath: kp] ?? 0) },
                                set: { v in updateLayoutGrid(idx, action: "Layout Grid") { $0[keyPath: kp] = CGFloat(v) } })
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            TextField("", value: b, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                .numericStepping(b, min: min)
        }
    }
    private func lgInt(_ label: String, _ idx: Int, _ kp: WritableKeyPath<LayoutGrid, Int>) -> some View {
        let b = Binding<Double>(get: { Double(lgAt(idx)?[keyPath: kp] ?? 0) },
                                set: { v in updateLayoutGrid(idx, action: "Layout Grid") { $0[keyPath: kp] = Swift.max(1, Int(v)) } })
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            TextField("", value: b, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                .numericStepping(b, min: 1)
        }
    }

    // MARK: Effects (drop / inner shadow) — applies to any node type

    @ViewBuilder private func effectsControls() -> some View {
        let effects = selectedNode?.effects ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Effects").expSectionLabel()
                Spacer()
                Menu {
                    Button("Drop Shadow") { addEffect(.dropShadow) }
                    Button("Inner Shadow") { addEffect(.innerShadow) }
                    Button("Noise") { addEffect(.noise) }
                    Button("Dissolve") { addEffect(.dissolve) }
                    // Background Blur intentionally omitted — disabled for performance
                    // (see CanvasNSView.backgroundBlurEnabled). Re-add when reworked.
                } label: { Image(systemName: "plus.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Add an effect")
            }
            .padding(.top, 4)
            if effects.isEmpty {
                Text("No effects").font(.caption2).foregroundStyle(EXPColor.textTertiary)
            }
            ForEach(Array(effects.enumerated()), id: \.element.id) { idx, eff in
                effectRow(idx: idx, effect: eff)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func effectRow(idx: Int, effect: Effect) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: effectEnabledBinding(idx)).labelsHidden().toggleStyle(.checkbox)
                    .expFieldTip("Enable effect",
                                 "Temporarily turn the effect off without losing its settings.")
                    .accessibilityLabel("Enable effect")
                Picker("", selection: effectKindBinding(idx)) {
                    Text("Drop").tag(Effect.Kind.dropShadow)
                    Text("Inner").tag(Effect.Kind.innerShadow)
                    Text("Noise").tag(Effect.Kind.noise)
                    Text("Dissolve").tag(Effect.Kind.dissolve)
                    // Bg Blur can't be ADDED (disabled for performance — see
                    // CanvasNSView.backgroundBlurEnabled), but a LEGACY effect in
                    // an old document must still be a valid selection, or AppKit
                    // logs 'selection "backgroundBlur" is invalid' and the picker
                    // misbehaves. Shown only while that legacy value is selected;
                    // switching to Drop/Inner makes it disappear from the menu.
                    if effect.kind == .backgroundBlur {
                        Text("Bg Blur (off)").tag(Effect.Kind.backgroundBlur)
                    }
                }.labelsHidden().frame(width: 84)
                // Only the shadows have a color; blur samples the backdrop and
                // noise/dissolve are procedural grain.
                if effect.kind == .dropShadow || effect.kind == .innerShadow {
                    ColorWell(label: "", color: effectColorBinding(idx))
                }
                Spacer()
                Button { removeEffect(effect.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .expFieldTip("Remove effect", "Deletes this effect and its settings from the layer.",
                                 align: .trailing)
                    .accessibilityLabel("Remove effect")
            }
            HStack(spacing: 4) {
                if effect.kind == .backgroundBlur {
                    effectNum("Amount", idx, \.blur, min: 0,
                              tip: "Blur amount",
                              tipDetail: "How strongly the backdrop behind the layer is blurred, in pixels.")
                } else if effect.kind == .noise || effect.kind == .dissolve {
                    // SIMPLE row — flavor, strength, and (noise) blend: all most
                    // people ever need. The feTurbulence dials (Freq/Oct/Seed/
                    // Mono) live in the Advanced accordion below, which also
                    // stops labels from clipping at the default panel width.
                    Picker("", selection: effectTurbulenceTypeBinding(idx)) {
                        Text("Fractal").tag(Effect.TurbulenceType.fractalNoise)
                        Text("Turbulent").tag(Effect.TurbulenceType.turbulence)
                    }.labelsHidden().frame(width: 82)
                        .expFieldTip("Noise type",
                                     "Fractal is smooth, film-grain-style noise. Turbulent is billowy and cloud-like — closer to smoke or marble.")
                        .accessibilityLabel("Noise type")
                    effectPercent(effect.kind == .noise ? "Amt %" : "Gone %", idx,
                                  tip: effect.kind == .noise ? "Amount" : "Amount dissolved",
                                  tipDetail: effect.kind == .noise
                                      ? "How visible the grain is, 0–100%. 0 is invisible; 100 lays fully opaque noise over the fill."
                                      : "How much of the shape is eaten away, 0–100%. 0 is fully intact; 100 removes it completely.")
                    if effect.kind == .noise {
                        Picker("", selection: effectBlendBinding(idx)) {
                            ForEach(BlendMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(minWidth: 72, maxWidth: 110)
                            .expFieldTip("Blend mode",
                                         "How the grain mixes with the fill beneath it. **Overlay** adds texture while keeping the fill's color; **Normal** paints the raw noise on top.",
                                         align: .trailing)
                            .accessibilityLabel("Noise blend mode")
                    }
                } else {
                    effectNum("X", idx, \.dx, tip: "Offset X",
                              tipDetail: "How far the shadow shifts horizontally, in pixels. Positive moves it right; negative moves it left.")
                    effectNum("Y", idx, \.dy, tip: "Offset Y",
                              tipDetail: "How far the shadow shifts vertically, in pixels. Positive moves it down; negative moves it up.")
                    effectNum("Blur", idx, \.blur, min: 0, tip: "Blur radius",
                              tipDetail: "How soft the shadow's edge is, in pixels. 0 is a hard edge; larger values spread and fade it.")
                    effectNum("Spr", idx, \.spread, tip: "Spread",
                              tipDetail: "Grows (positive) or shrinks (negative) the shadow before blurring, in pixels.")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            if effect.kind == .dropShadow {
                Toggle("Preserve transparency", isOn: effectPreserveTransparencyBinding(idx))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .expFieldTip("Preserve transparency",
                                 "Keeps the shadow from showing through a see-through object. On: the shadow is cast only OUTSIDE the shape, so a semi-transparent fill stays its own color instead of going dark on its own shadow. Off (default): classic behavior — the shadow is visible behind the object.")
                    .accessibilityLabel("Preserve transparency — cast the shadow only outside the object")
            }
            if effect.kind == .noise || effect.kind == .dissolve {
                // ADVANCED accordion — a disclosure most people never open.
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(EXPMotion.fast) { effectsAdvancedOpen.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .rotationEffect(.degrees(effectsAdvancedOpen ? 90 : 0))
                            Text("Advanced")
                        }
                        .font(.caption)
                        .foregroundStyle(EXPColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(effectsAdvancedOpen
                        ? "Hide advanced noise settings" : "Show advanced noise settings")
                    if effectsAdvancedOpen {
                        let freq = effectNum("Freq", idx, \.frequency, min: 0.01, digits: 2,
                                             tip: "Frequency",
                                             tipDetail: "How tightly the noise pattern repeats. **Higher** values make finer, denser grain; **lower** values make larger, softer blobs.\nMaps directly to SVG's baseFrequency.")
                        let oct = effectIntNum("Oct", idx, \.octaves, min: 1, max: 8,
                                               tip: "Octaves",
                                               tipDetail: "Layers of detail stacked onto the base noise, **1–8**. Each octave adds finer detail; more octaves look richer but render slower.\n1–3 covers most uses.")
                        let seed = effectIntNum("Seed", idx, \.seed, min: 0, max: 9999,
                                                tip: "Random seed",
                                                tipDetail: "The starting number for the random pattern, **0–9999**. The same seed always reproduces the exact same grain — change it for a different pattern with the same settings.")
                        let dice = Button {
                            updateEffect(idx, action: "Shuffle Seed") { $0.seed = Int.random(in: 1...9999) }
                        } label: { Image(systemName: "die.face.5") }
                            .buttonStyle(.borderless)
                            .expFieldTip("New random seed",
                                         "Rolls a different random pattern without changing any other setting.")
                            .accessibilityLabel("Shuffle noise seed")
                        let mono = Toggle("Mono", isOn: effectMonoBinding(idx)).toggleStyle(.checkbox)
                            .expFieldTip("Monochrome",
                                         "Grayscale grain. Turn off for independent red, green, and blue noise — a colorful, RGB-static look.")
                            .accessibilityLabel("Monochrome noise")
                        // ELASTIC: one line when the panel is wide enough, two
                        // when it isn't — ViewThatFits tries the layouts in order.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                freq; oct; seed; dice
                                if effect.kind == .noise { mono }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) { freq; oct }
                                HStack(spacing: 4) {
                                    seed; dice
                                    if effect.kind == .noise { mono }
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func effectNum(_ label: String, _ idx: Int, _ kp: WritableKeyPath<Effect, CGFloat>,
                           min: Double? = nil, max: Double? = nil, digits: Int = 0,
                           tip: String = "", tipDetail: String = "") -> some View {
        let b = effectNumBinding(idx, kp)
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            TextField("", value: b, format: .number.precision(.fractionLength(0...digits)))
                .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                .numericStepping(b, min: min, max: max)
                .accessibilityLabel(tip.isEmpty ? label : tip)
        }
        // Every field explains itself on hover — never assume the shorthand
        // label ("Spr", "Oct") is universally understood.
        .expFieldTip(tip.isEmpty ? label : tip, tipDetail)
    }

    private func effectIntNum(_ label: String, _ idx: Int, _ kp: WritableKeyPath<Effect, Int>,
                              min: Double, max: Double,
                              tip: String = "", tipDetail: String = "") -> some View {
        let b = Binding<Double>(
            get: { Double(effectAt(idx)?[keyPath: kp] ?? 0) },
            set: { v in updateEffect(idx, action: "Effect") {
                $0[keyPath: kp] = Int(Swift.min(max, Swift.max(min, v)))
            } })
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            TextField("", value: b, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                .numericStepping(b, min: min, max: max)
                .accessibilityLabel(tip.isEmpty ? label : tip)
        }
        .expFieldTip(tip.isEmpty ? label : tip, tipDetail)
    }

    /// `Effect.amount` (0–1) shown as a 0–100 percentage.
    private func effectPercent(_ label: String, _ idx: Int,
                               tip: String = "", tipDetail: String = "") -> some View {
        let b = Binding<Double>(
            get: { Double(effectAt(idx)?.amount ?? 0) * 100 },
            set: { v in updateEffect(idx, action: "Effect Amount") {
                $0.amount = CGFloat(Swift.min(100, Swift.max(0, v)) / 100)
            } })
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            TextField("", value: b, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp).frame(width: 40).multilineTextAlignment(.trailing)
                .numericStepping(b, min: 0, max: 100)
                .accessibilityLabel(tip.isEmpty ? label : tip)
        }
        .expFieldTip(tip.isEmpty ? label : tip, tipDetail)
    }

    private func effectAt(_ idx: Int) -> Effect? {
        guard let e = selectedNode?.effects, e.indices.contains(idx) else { return nil }
        return e[idx]
    }
    private func updateEffect(_ idx: Int, action: String, _ change: @escaping (inout Effect) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: action) { node in
            guard node.effects.indices.contains(idx) else { return }
            change(&node.effects[idx])
        }
    }
    private func addEffect(_ kind: Effect.Kind) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: "Add Effect") { node in
            var e = Effect(kind: kind)
            if kind == .innerShadow { e.color = RGBAColor(r: 0, g: 0, b: 0, a: 0.5) }
            if kind == .backgroundBlur { e.blur = 8 }   // visible by default; 0 = no-op
            if kind == .noise { e.blend = .overlay }    // classic grain-over-fill look
            if kind == .noise || kind == .dissolve { e.seed = Int.random(in: 1...9999) }
            node.effects.append(e)
        }
    }
    private func removeEffect(_ effectID: UUID) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: "Remove Effect") { node in
            node.effects.removeAll { $0.id == effectID }
        }
    }
    private func effectEnabledBinding(_ idx: Int) -> Binding<Bool> {
        Binding(get: { effectAt(idx)?.isEnabled ?? true },
                set: { v in updateEffect(idx, action: "Toggle Effect") { $0.isEnabled = v } })
    }
    private func effectKindBinding(_ idx: Int) -> Binding<Effect.Kind> {
        Binding(get: { effectAt(idx)?.kind ?? .dropShadow },
                set: { v in updateEffect(idx, action: "Effect Type") { $0.kind = v } })
    }
    private func effectColorBinding(_ idx: Int) -> Binding<RGBAColor> {
        Binding(get: { effectAt(idx)?.color ?? .black },
                set: { v in updateEffect(idx, action: "Effect Color") { $0.color = v } })
    }
    private func effectTurbulenceTypeBinding(_ idx: Int) -> Binding<Effect.TurbulenceType> {
        Binding(get: { effectAt(idx)?.turbulenceType ?? .fractalNoise },
                set: { v in updateEffect(idx, action: "Noise Type") { $0.turbulenceType = v } })
    }
    private func effectMonoBinding(_ idx: Int) -> Binding<Bool> {
        Binding(get: { effectAt(idx)?.monochrome ?? true },
                set: { v in updateEffect(idx, action: "Noise Color") { $0.monochrome = v } })
    }
    private func effectPreserveTransparencyBinding(_ idx: Int) -> Binding<Bool> {
        Binding(get: { effectAt(idx)?.preserveTransparency ?? false },
                set: { v in updateEffect(idx, action: "Shadow Transparency") { $0.preserveTransparency = v } })
    }
    private func effectBlendBinding(_ idx: Int) -> Binding<BlendMode> {
        Binding(get: { effectAt(idx)?.blend ?? .normal },
                set: { v in updateEffect(idx, action: "Noise Blend") { $0.blend = v } })
    }
    private func effectNumBinding(_ idx: Int, _ kp: WritableKeyPath<Effect, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(effectAt(idx)?[keyPath: kp] ?? 0) },
                set: { v in updateEffect(idx, action: "Effect") { $0[keyPath: kp] = CGFloat(v) } })
    }

    private var artboardBackgroundBinding: Binding<Paint> {
        Binding(
            get: { selectedArtboard?.background ?? .white },
            set: { c in
                guard let id = app.selectedArtboardID,
                      let i = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.artboards[i].background = c
                document.setModel(model, undoManager: undoManager, actionName: "Artboard Background")
            }
        )
    }

    private var artboardNameBinding: Binding<String> {
        Binding(
            get: { selectedArtboard?.name ?? "" },
            set: { newValue in
                guard let id = app.selectedArtboardID,
                      let i = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.artboards[i].name = newValue
                document.setModel(model, undoManager: undoManager, actionName: "Rename Artboard")
            }
        )
    }

    private func artboardBinding(_ keyPath: WritableKeyPath<CGRect, CGFloat>,
                                 action: String) -> Binding<Double> {
        Binding(
            get: { Double(selectedArtboard?.frame[keyPath: keyPath] ?? 0) },
            set: { newValue in
                guard let id = app.selectedArtboardID,
                      let i = document.model.artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.artboards[i].frame[keyPath: keyPath] = clamp(keyPath, CGFloat(newValue))
                document.setModel(model, undoManager: undoManager, actionName: action)
            }
        )
    }

    /// Keep width/height at least 1pt; positions pass through unchanged.
    private func clamp(_ keyPath: WritableKeyPath<CGRect, CGFloat>, _ value: CGFloat) -> CGFloat {
        if keyPath == \CGRect.size.width || keyPath == \CGRect.size.height {
            return max(1, value)
        }
        return value
    }

    // MARK: Text controls (single text shape selected)

    @ViewBuilder
    private func textControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Type").expSectionLabel().padding(.top, 2)

            // Typeface — families rendered in their own face.
            Menu {
                Button("System") { setTextFontName("") }
                Divider()
                ForEach(FontCatalog.families, id: \.self) { fam in
                    Button { setTextFamily(fam) } label: {
                        Text(fam).font(fontMenuPreview(for: fam, size: 13))
                    }
                }
            } label: {
                HStack {
                    Text(currentFamilyDisplay).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                }
            }
            .help("Typeface (applies to the whole text, or the selection while editing)")

            // Weight / style within the family — a Menu (not a Picker) so a
            // selection that isn't in the list never logs warnings / writes back.
            let faces = currentFaces
            if faces.count > 1 {
                Menu {
                    ForEach(faces) { face in
                        Button(face.faceName) { applyFontName(face.postScriptName) }
                    }
                } label: {
                    HStack {
                        Text(currentFaceName).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                    }
                }
                .help("Weight / style")
            }

            // Bold / Italic / Underline — selection while editing, else whole text.
            HStack(spacing: 6) {
                styleButton("bold", "Bold", "toggleBoldText:", active: boldActive)
                styleButton("italic", "Italic", "toggleItalicText:", active: italicActive)
                styleButton("underline", "Underline", "toggleUnderlineText:", active: underlineActive)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Size").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: fontSizeBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .numericStepping(fontSizeBinding, min: 1)
                if fontSizeIsMixed {
                    Text("Multiple").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                }
                Spacer()
            }
            ColorWell(label: "Color", color: colorBinding)

            Divider()
            // Box mode + alignment + line height + letter spacing.
            EXPSegmented(selection: boxBinding, segments: [
                .init(value: .auto, label: "Auto width"),
                .init(value: .fixed, label: "Text box"),
            ])
            .help("Auto-width hugs the text; Text box wraps to a fixed size")

            HStack(spacing: 6) {
                alignButton(.left, "text.alignleft")
                alignButton(.center, "text.aligncenter")
                alignButton(.right, "text.alignright")
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Line").foregroundStyle(EXPColor.textSecondary).font(.callout)
                Picker("", selection: lineHeightUnitBinding) {
                    Text("Auto").tag(LineHeightUnit.auto)
                    Text("×").tag(LineHeightUnit.multiple)
                    Text("px").tag(LineHeightUnit.px)
                    Text("em").tag(LineHeightUnit.em)
                }
                .labelsHidden().frame(width: 76)
                if (selectedTextContent?.lineHeightUnit ?? .auto) != .auto {
                    TextField("", value: lineHeightBinding, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.exp).frame(width: 52).multilineTextAlignment(.trailing)
                        .numericStepping(lineHeightBinding, min: 0)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Spacing").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: trackingBinding, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.exp).frame(width: 52).multilineTextAlignment(.trailing)
                    .numericStepping(trackingBinding)
                Text("px").foregroundStyle(EXPColor.textSecondary).font(.caption2)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Case").foregroundStyle(EXPColor.textSecondary).font(.callout)
                Picker("", selection: textCaseBinding) {
                    Text("As typed").tag(TextCase.none)
                    Text("UPPERCASE").tag(TextCase.upper)
                    Text("lowercase").tag(TextCase.lower)
                    Text("Capitalize Each").tag(TextCase.title)
                    Text("Sentence case").tag(TextCase.sentence)
                }
                .labelsHidden()
                .help("Non-destructive — changes how the text is displayed, not the stored characters")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func alignButton(_ a: TextAlign, _ symbol: String) -> some View {
        let active = (selectedTextContent?.align ?? .left) == a
        return InspectorIconButton(symbol: symbol, active: active) {
            updateTextContent(action: "Align", remeasure: false) { $0.align = a }
        }
    }

    private var boxBinding: Binding<TextBox> {
        Binding(get: { selectedTextContent?.box ?? .auto },
                set: { b in updateTextContent(action: "Text Box", remeasure: b == .auto) { $0.box = b } })
    }
    private var lineHeightBinding: Binding<Double> {
        Binding(get: { Double(selectedTextContent?.lineHeight ?? 1.3) },
                set: { v in updateTextContent(action: "Line Height", remeasure: true) { $0.lineHeight = max(0, CGFloat(v)) } })
    }
    private var lineHeightUnitBinding: Binding<LineHeightUnit> {
        Binding(get: { selectedTextContent?.lineHeightUnit ?? .auto },
                set: { u in updateTextContent(action: "Line Height", remeasure: true) { $0.lineHeightUnit = u } })
    }
    private var trackingBinding: Binding<Double> {
        Binding(get: { Double(selectedTextContent?.tracking ?? 0) },
                set: { v in updateTextContent(action: "Letter Spacing", remeasure: true) { $0.tracking = CGFloat(v) } })
    }
    private var textCaseBinding: Binding<TextCase> {
        Binding(get: { selectedTextContent?.textCase ?? .none },
                set: { c in updateTextContent(action: "Text Case", remeasure: true) { $0.textCase = c } })
    }

    private var boldActive: Bool {
        if let s = app.textSelection { return s.bold == true }
        if let tc = selectedTextContent { return NSFontManager.shared.traits(of: tc.firstRun.nsFont()).contains(.boldFontMask) }
        return false
    }
    private var italicActive: Bool {
        if let s = app.textSelection { return s.italic == true }
        if let tc = selectedTextContent { return NSFontManager.shared.traits(of: tc.firstRun.nsFont()).contains(.italicFontMask) }
        return false
    }
    private var underlineActive: Bool {
        if let s = app.textSelection { return s.underline == true }
        return selectedTextContent?.firstRun.underline ?? false
    }

    private func styleButton(_ symbol: String, _ help: String, _ selector: String, active: Bool) -> some View {
        InspectorIconButton(symbol: symbol, active: active) {
            sendCanvasAction(selector)
        }
        .help(help)
    }

    private var selectedTextContent: TextContent? {
        if let node = selectedNode, case .text(let tc) = node.content { return tc }
        return nil
    }

    // While editing, the canvas publishes the SELECTION's style to `app.textSelection`
    // and these controls drive it; otherwise they act on the whole text node.
    private var isEditingText: Bool { app.applyTextStyle != nil || app.textSelection != nil }

    private var currentFamilyDisplay: String {
        if let s = app.textSelection {
            guard let fn = s.fontName else { return "Mixed" }
            if FontCatalog.isSystemMonospaced(fn) { return FontCatalog.systemMonospacedFamily }
            return fn.isEmpty ? "System" : (NSFont(name: fn, size: 12)?.familyName ?? fn)
        }
        return selectedTextContent?.familyName ?? "System"
    }
    private var currentFontName: String {
        if let s = app.textSelection { return s.fontName ?? "" }
        return selectedTextContent?.uniformFontName ?? selectedTextContent?.firstRun.fontName ?? ""
    }
    private var currentFontSize: CGFloat {
        if let s = app.textSelection { return s.fontSize ?? selectedTextContent?.firstRun.fontSize ?? 16 }
        return selectedTextContent?.uniformFontSize ?? selectedTextContent?.firstRun.fontSize ?? 16
    }
    private var fontSizeIsMixed: Bool {
        if let s = app.textSelection { return s.fontSize == nil }
        return selectedTextContent.map { $0.uniformFontSize == nil } ?? false
    }
    private var currentTextColor: RGBAColor {
        if let s = app.textSelection { return s.color ?? .black }
        return selectedTextContent?.firstRun.color ?? .black
    }
    private var currentFaces: [FontCatalog.Face] {
        let fam = currentFamilyDisplay
        return (fam == "System" || fam == "Mixed") ? [] : FontCatalog.faces(of: fam)
    }

    private func applyFontName(_ ps: String) {
        if let applyTextStyle = app.applyTextStyle { applyTextStyle(.fontName(ps)) }
        else { updateTextContent(action: "Font", remeasure: true) { $0.applyToAllRuns { $0.fontName = ps } } }
    }
    private func setTextFamily(_ family: String) { applyFontName(FontCatalog.defaultFace(of: family) ?? "") }

    /// The face name (e.g. "Bold Italic") of the current selection within its
    /// family, for the weight Menu label.
    private var currentFaceName: String {
        let ps = currentFontName
        return currentFaces.first { $0.postScriptName == ps }?.faceName ?? "Regular"
    }
    private var fontSizeBinding: Binding<Double> {
        Binding(get: { Double(currentFontSize) },
                set: { v in
                    if let applyTextStyle = app.applyTextStyle { applyTextStyle(.fontSize(max(1, CGFloat(v)))) }
                    else { updateTextContent(action: "Font Size", remeasure: true) { $0.applyToAllRuns { $0.fontSize = max(1, CGFloat(v)) } } }
                })
    }
    private var colorBinding: Binding<RGBAColor> {
        Binding(get: { currentTextColor },
                set: { c in
                    if let applyTextStyle = app.applyTextStyle { applyTextStyle(.color(c)) }
                    else { updateTextContent(action: "Text Color", remeasure: false) { $0.applyToAllRuns { $0.color = c } } }
                })
    }
    private func setTextFontName(_ ps: String) { applyFontName(ps) }

    private func fontMenuPreview(for family: String, size: CGFloat) -> Font {
        family == FontCatalog.systemMonospacedFamily
            ? .system(size: size, design: .monospaced)
            : .custom(family, size: size)
    }

    /// Apply a change to the selected text node's TextContent (one undo step),
    /// optionally re-measuring the box to fit.
    private func updateTextContent(action: String, remeasure: Bool, _ change: @escaping (inout TextContent) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        let applyTextStyle = app.applyTextStyle
        mutateScopedNode(id, action: action) { node in
            guard case.text(var tc) = node.content else { return }
            change(&tc)
            node.content = .text(tc)
            if remeasure && tc.box == .auto {
                // Auto/line boxes hug their content. Fixed/paragraph boxes keep
                // their user-set size (text wraps inside and may show the overflow
                // badge).
                node.frame.size = tc.measuredSize()
            }
        }
        // These are paragraph-level (align / line-height / spacing) edits that
        // don't touch runs. While a text box is being edited inline, push the
        // change into the live editor so it shows immediately instead of only
        // after the box is deselected.
        applyTextStyle?(.paragraph)
    }

    // MARK: Line controls (single line selected)

    @ViewBuilder
    private func lineControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Stroke").expSectionLabel()
            HStack(spacing: 8) {
                Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: strokeWidthBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .numericStepping(strokeWidthBinding, min: 1)
                Spacer()
            }
            ColorWell(label: "Color", color: strokeColorBinding)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var selectedLineShape: LineShape? {
        if let node = selectedNode, case .line(let ls) = node.content { return ls }
        return nil
    }

    private var strokeWidthBinding: Binding<Double> {
        Binding(get: { Double(selectedLineShape?.strokeWidth ?? 2) },
                set: { newValue in updateLineContent { $0.strokeWidth = max(1, CGFloat(newValue)) } })
    }
    private var strokeColorBinding: Binding<RGBAColor> {
        Binding(get: { selectedLineShape?.stroke ?? .black },
                set: { c in updateLineContent { $0.stroke = c } })
    }

    private func updateLineContent(_ change: @escaping (inout LineShape) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: "Stroke") { node in
            guard case .line(var ls) = node.content else { return }
            change(&ls)
            node.content = .line(ls)
        }
    }

    // MARK: Instance overrides (single component instance selected)

    private var selectedInstanceContext: (instance: ComponentInstance, source: ComponentSource)? {
        guard let node = selectedNode, case .instance(let inst) = node.content,
              let source = document.model.source(for: inst.sourceID) else { return nil }
        return (inst, source)
    }

    /// Two-way binding to a component source's category (Phase 19a) — undoable
    /// through the document funnel like every other inspector edit.
    private func componentCategoryBinding(_ sourceID: UUID) -> Binding<AriaRole?> {
        Binding(
            get: { document.model.source(for: sourceID)?.a11y.role },
            set: { newRole in
                guard let si = document.model.sources.firstIndex(where: { $0.id == sourceID }),
                      document.model.sources[si].a11y.role != newRole else { return }
                var model = document.model
                model.sources[si].a11y.role = newRole
                document.setModel(model, undoManager: undoManager, actionName: "Set Component Category")
            }
        )
    }

    @ViewBuilder
    private func instanceControls() -> some View {
        if let ctx = selectedInstanceContext {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                // Phase 19a: component CATEGORY (curated ARIA roles as organizing
                // vocabulary). Friendly labels shown; token stored on the SOURCE,
                // so every instance and the Components panel update together.
                Text("Category").expSectionLabel()
                Picker("Component category", selection: componentCategoryBinding(ctx.source.id)) {
                    Text("Uncategorized").tag(AriaRole?.none)
                    ForEach(AriaRole.grouped(), id: \.category) { group in
                        Section(group.category.label) {
                            ForEach(group.roles, id: \.self) { role in
                                Text(role.friendlyLabel).tag(AriaRole?.some(role))
                            }
                        }
                    }
                }
                .labelsHidden()
                .help("Organize components by what they are — the same choice powers accessible export later")

                Divider()
                Text("Overrides").expSectionLabel()

                ForEach(overridableChildren(ctx.source.children)) { child in
                    switch child.content {
                    case .text(let tc):
                        InstanceTextRow(
                            name: child.name,
                            current: ctx.instance.textOverride(for: child.id) ?? tc.plainString,
                            hasOverride: ctx.instance.textOverride(for: child.id) != nil,
                            onCommit: { newValue in commitTextOverride(child.id, newValue) },
                            onReset: { resetOverride(child.id) })
                    case .rectangle(let s):
                        fillOverrideRow(child: child, sourceFill: s.fill, instance: ctx.instance)
                    case .ellipse(let s):
                        fillOverrideRow(child: child, sourceFill: s.fill, instance: ctx.instance)
                    case .path(let s):
                        fillOverrideRow(child: child, sourceFill: s.fill, instance: ctx.instance)
                    case .group:
                        // A frame's background fill (the button surface).
                        if let f = child.autoPadding?.fill {
                            fillOverrideRow(child: child, sourceFill: f, instance: ctx.instance)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// Overridable leaves of a component source, recursing INTO groups — so a
    /// component whose content is grouped still exposes its text/fill overrides.
    private func overridableChildren(_ nodes: [Node]) -> [Node] {
        var out: [Node] = []
        for n in nodes {
            switch n.content {
            case .text, .rectangle, .ellipse, .path: out.append(n)
            case .group(let kids):
                // A frame with a background fill (a button surface) exposes that fill
                // as an override; then recurse for nested text/shape overrides.
                if n.autoPadding?.fill != nil { out.append(n) }
                out.append(contentsOf: overridableChildren(kids))
            default: break
            }
        }
        return out
    }

    @ViewBuilder
    private func fillOverrideRow(child: Node, sourceFill: Paint, instance: ComponentInstance) -> some View {
        HStack {
            PaintWell(label: child.name, paint: fillBinding(child.id, sourceFill: sourceFill))
            if instance.fillOverride(for: child.id) != nil {
                resetButton(child.id)
            }
        }
    }

    private func resetButton(_ childID: UUID) -> some View {
        Button {
            updateSelectedInstance("Reset Override") { $0.overrides.removeAll { $0.targetNodeID == childID } }
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help("Reset to source")
    }

    /// Apply a text override once, on explicit commit (Enter / ✓), so the model
    /// (and the re-hug) updates once per edit instead of on every keystroke.
    private func commitTextOverride(_ childID: UUID, _ newValue: String) {
        updateSelectedInstance("Override Text") { inst in
            inst.overrides.removeAll { $0.targetNodeID == childID && $0.value.textValue != nil }
            inst.overrides.append(InstanceOverride(targetNodeID: childID, value: .text(newValue)))
        }
    }

    private func resetOverride(_ childID: UUID) {
        updateSelectedInstance("Reset Override") { $0.overrides.removeAll { $0.targetNodeID == childID } }
    }

    private func fillBinding(_ childID: UUID, sourceFill: Paint) -> Binding<Paint> {
        Binding(
            get: { selectedInstanceContext?.instance.fillOverride(for: childID) ?? sourceFill },
            set: { newValue in
                updateSelectedInstance("Override Fill") { inst in
                    inst.overrides.removeAll { $0.targetNodeID == childID && $0.value.fillValue != nil }
                    inst.overrides.append(InstanceOverride(targetNodeID: childID, value: .fill(newValue)))
                }
            }
        )
    }

    private func updateSelectedInstance(_ action: String, _ change: @escaping (inout ComponentInstance) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        let model = document.model
        mutateScopedNode(id, action: action) { node in
            guard case .instance(var inst) = node.content else { return }
            change(&inst)
            node.content = .instance(inst)
            // Keep the stored frame matching the re-hugged resolved size, so the
            // selection box / hit area / export bounds track the override.
            let size = model.resolvedSize(of: inst)
            if size.width > 0, size.height > 0 { node.frame.size = size }
        }
    }

    // MARK: Shape styling (rectangle / ellipse): fill, corner, stroke

    @ViewBuilder
    private func shapeControls(corner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            PaintWell(label: "Fill", paint: shapeFillBinding)
            if corner {
                HStack(spacing: 8) {
                    Text("Corner").foregroundStyle(EXPColor.textSecondary).font(.callout)
                    TextField("", value: cornerRadiusBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.exp).frame(width: 56).multilineTextAlignment(.trailing)
                        .numericStepping(cornerRadiusBinding, min: 0)
                        .expFieldTip("Corner radius",
                                     "Rounds all four corners at once — the everyday control. Open Advanced below to set each corner separately.")
                    Spacer()
                }
                // v1.3: per-corner radii behind an Advanced disclosure (default
                // stays the single all-corners field — no extra actions).
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(EXPMotion.fast) { cornersAdvancedOpen.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .rotationEffect(.degrees(cornersAdvancedOpen ? 90 : 0))
                            Text("Advanced")
                        }
                        .font(.caption)
                        .foregroundStyle(EXPColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cornersAdvancedOpen
                        ? "Hide per-corner radius settings" : "Show per-corner radius settings")
                    if cornersAdvancedOpen {
                        HStack(spacing: 4) {
                            cornerField("TL", \.topLeft, tip: "Top-left corner radius")
                            cornerField("TR", \.topRight, tip: "Top-right corner radius")
                        }
                        HStack(spacing: 4) {
                            cornerField("BL", \.bottomLeft, tip: "Bottom-left corner radius")
                            cornerField("BR", \.bottomRight, tip: "Bottom-right corner radius")
                        }
                        Text("Matching all four snaps back to the single Corner field.")
                            .font(.caption2).foregroundStyle(EXPColor.textTertiary)
                    }
                }
            }
            Divider()
            Text("Stroke").expSectionLabel()
            ColorWell(label: "Color", color: shapeStrokeBinding)
            HStack(spacing: 8) {
                Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: strokeWidthShapeBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 56).multilineTextAlignment(.trailing)
                    .numericStepping(strokeWidthShapeBinding, min: 0)
                Spacer()
            }
            // v1.3 stroke alignment (rect/ellipse/polygon are all closed).
            // EXPSegmented = the design-system accent segmented control.
            EXPSegmented(selection: shapeStrokeAlignmentBinding,
                         segments: StrokeAlignment.allCases.map { .init(value: $0, label: $0.label) })
            .expFieldTip("Stroke position",
                         "Where the stroke sits on the shape's edge. **Center** straddles it (half in, half out — the classic default). **Inside** keeps the whole stroke within the frame. **Outside** paints it entirely beyond the edge.")
            .accessibilityLabel("Stroke position: center, inside, or outside the shape edge")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// One per-corner radius field (v1.3 Advanced corners).
    @ViewBuilder
    private func cornerField(_ label: String, _ kp: WritableKeyPath<CornerRadii, CGFloat>, tip: String) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary).font(.caption2)
            TextField("", value: cornerRadiiBinding(kp), format: .number.precision(.fractionLength(0)))
                .labelsHidden().textFieldStyle(.exp)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .frame(width: 44).numericStepping(cornerRadiiBinding(kp), min: 0)
        }
        .help(tip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tip)
    }

    // Read helpers (fill/stroke/width exist on both rect + ellipse).
    private var shapeFill: Paint? {
        guard let content = selectedNode?.content else { return nil }
        switch content {
        case .rectangle(let s): return s.fill
        case .ellipse(let s):   return s.fill
        case .polygon(let s):   return s.fill
        default: return nil
        }
    }
    private var shapeStroke: RGBAColor? {
        guard let content = selectedNode?.content else { return nil }
        switch content {
        case .rectangle(let s): return s.stroke
        case .ellipse(let s):   return s.stroke
        case .polygon(let s):   return s.stroke
        default: return nil
        }
    }
    private var shapeStrokeWidth: CGFloat {
        guard let content = selectedNode?.content else { return 0 }
        switch content {
        case .rectangle(let s): return s.strokeWidth
        case .ellipse(let s):   return s.strokeWidth
        case .polygon(let s):   return s.strokeWidth
        default: return 0
        }
    }
    private var polygonSides: Int {
        if case .polygon(let s)? = selectedNode?.content { return s.sides }
        return 3
    }
    private var rectCornerRadius: CGFloat {
        if case .rectangle(let s)? = selectedNode?.content { return s.cornerRadius }
        return 0
    }

    private var shapeFillBinding: Binding<Paint> {
        Binding(get: { shapeFill ?? .white },
                set: { c in updateShape("Fill") { $0.fill = c } })
    }
    private var shapeStrokeBinding: Binding<RGBAColor> {
        Binding(get: { shapeStroke ?? .black },
                set: { c in updateShape("Stroke Color") { $0.stroke = c } })
    }
    private var strokeWidthShapeBinding: Binding<Double> {
        Binding(get: { Double(shapeStrokeWidth) },
                set: { v in updateShape("Stroke Width") { $0.strokeWidth = max(0, CGFloat(v)) } })
    }
    private var cornerRadiusBinding: Binding<Double> {
        Binding(get: { Double(rectCornerRadius) },
                set: { v in
                    guard let id = app.singleSelectedNodeID else { return }
                    mutateScopedNode(id, action: "Corner Radius") { node in
                        guard case .rectangle(var s) = node.content else { return }
                        s.cornerRadius = max(0, CGFloat(v))
                        // The simple field is the uniform control: setting it
                        // dissolves any per-corner overrides (v1.3 spec).
                        s.cornerRadii = nil
                        node.content = .rectangle(s)
                    }
                })
    }

    /// Effective per-corner radii of the selected rectangle (v1.3).
    private var rectRadii: CornerRadii {
        if case .rectangle(let s)? = selectedNode?.content { return s.effectiveRadii }
        return CornerRadii()
    }

    /// One corner's binding. Diverging any corner switches the shape to
    /// per-corner mode; making all four match again collapses back to the
    /// single uniform `cornerRadius` (so the simple field stays truthful).
    private func cornerRadiiBinding(_ kp: WritableKeyPath<CornerRadii, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(rectRadii[keyPath: kp]) },
                set: { v in
                    guard let id = app.singleSelectedNodeID else { return }
                    mutateScopedNode(id, action: "Corner Radius") { node in
                        guard case .rectangle(var s) = node.content else { return }
                        var r = s.effectiveRadii
                        r[keyPath: kp] = max(0, CGFloat(v))
                        if r.isUniform {
                            s.cornerRadius = r.topLeft
                            s.cornerRadii = nil
                        } else {
                            s.cornerRadii = r
                        }
                        node.content = .rectangle(s)
                    }
                })
    }

    /// Selected shape's stroke alignment (single selection; v1.3).
    private var shapeStrokeAlignment: StrokeAlignment {
        guard let content = selectedNode?.content else { return .center }
        switch content {
        case .rectangle(let s): return s.strokeAlignment
        case .ellipse(let s):   return s.strokeAlignment
        case .polygon(let s):   return s.strokeAlignment
        case .path(let s):      return s.strokeAlignment
        default: return .center
        }
    }

    private var shapeStrokeAlignmentBinding: Binding<StrokeAlignment> {
        Binding(get: { shapeStrokeAlignment },
                set: { a in
                    guard let id = app.singleSelectedNodeID else { return }
                    mutateScopedNode(id, action: "Stroke Position") { node in
                        switch node.content {
                        case .rectangle(var s): s.strokeAlignment = a; node.content = .rectangle(s)
                        case .ellipse(var s):   s.strokeAlignment = a; node.content = .ellipse(s)
                        case .polygon(var s):   s.strokeAlignment = a; node.content = .polygon(s)
                        case .path(var s):      s.strokeAlignment = a; node.content = .path(s)
                        default: break
                        }
                    }
                })
    }

    private var polygonSidesBinding: Binding<Double> {
        Binding(get: { Double(polygonSides) },
                set: { v in
                    let n = Swift.min(25, Swift.max(3, Int(v.rounded())))
                    guard let id = app.singleSelectedNodeID else { return }
                    app.polygonSides = n   // remember for the next polygon drawn
                    mutateScopedNode(id, action: "Polygon Sides") { node in
                        guard case .polygon(var s) = node.content else { return }
                        s.sides = n; node.content = .polygon(s)
                    }
                })
    }

    /// Sides control for a selected polygon (3–25).
    @ViewBuilder private func polygonControls() -> some View {
        HStack(spacing: 8) {
            Text("Sides").foregroundStyle(EXPColor.textSecondary)
            TextField("", value: polygonSidesBinding, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp).frame(width: 48).multilineTextAlignment(.trailing)
                .numericStepping(polygonSidesBinding, min: 3, max: 25)
            Stepper("", value: polygonSidesBinding, in: 3...25, step: 1).labelsHidden()
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    /// Mutate the common (fill/stroke/strokeWidth) fields of a rect OR ellipse OR polygon.
    private func updateShape(_ action: String, _ change: @escaping (inout ShapeStyle) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: action) { node in
            switch node.content {
            case .rectangle(var s):
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth
                node.content = .rectangle(s)
            case .ellipse(var s):
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth
                node.content = .ellipse(s)
            case .polygon(var s):
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth
                node.content = .polygon(s)
            default:
                return
            }
        }
    }
}

/// Common fill/stroke fields shared between rectangle and ellipse, so the
/// Inspector can edit them through one code path.
private struct ShapeStyle {
    var fill: Paint
    var stroke: RGBAColor
    var strokeWidth: CGFloat
}

// MARK: - Path styling controls

extension RightPanel {
    @ViewBuilder
    func pathControls() -> some View {
        if let ps = selectedPathShape {
            VStack(alignment: .leading, spacing: 8) {
                if app.tool == .node, app.selectedPointCount > 0 {
                    Divider()
                    HStack(spacing: 4) {
                        Text(app.selectedPointCount == 1 ? "1 point selected" : "\(app.selectedPointCount) points selected")
                            .expSectionLabel()
                        Spacer()
                        Text("R").foregroundStyle(EXPColor.textSecondary)
                        TextField("", value: pointRotationBinding, format: .number.precision(.fractionLength(0)))
                            .labelsHidden().textFieldStyle(.exp)
                            .multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(width: 56)
                            .numericStepping(pointRotationBinding)
                        Text("°").foregroundStyle(EXPColor.textSecondary)
                    }
                    .font(.callout)
                }
                Divider()
                Toggle("Closed", isOn: pathClosedBinding)
                    .font(.callout)
                if ps.closed {
                    PaintWell(label: "Fill", paint: pathFillBinding)
                }
                Divider()
                Text("Stroke").expSectionLabel()
                ColorWell(label: "Color", color: pathStrokeBinding)
                HStack(spacing: 8) {
                    Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                    TextField("", value: pathStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.exp).frame(width: 56).multilineTextAlignment(.trailing)
                        .numericStepping(pathStrokeWidthBinding, min: 0)
                    Spacer()
                }
                if ps.closed || ps.isMultiContour {
                    // v1.3 stroke alignment — closed outlines only (an open
                    // stroke has no interior, so it always renders centered).
                    EXPSegmented(selection: shapeStrokeAlignmentBinding,
                                 segments: StrokeAlignment.allCases.map { .init(value: $0, label: $0.label) })
                    .expFieldTip("Stroke position",
                                 "Where the stroke sits on the path's edge: centered on it, fully inside, or fully outside. Available because this path is closed.")
                    .accessibilityLabel("Stroke position: center, inside, or outside the path edge")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    var selectedPathShape: PathShape? {
        if case .path(let ps)? = selectedNode?.content { return ps }
        return nil
    }

    func updatePath(_ action: String, _ change: @escaping (inout PathShape) -> Void) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: action) { node in
            guard case .path(var ps) = node.content else { return }
            change(&ps)
            node.content = .path(ps)
        }
    }

    var pathClosedBinding: Binding<Bool> {
        Binding(get: { selectedPathShape?.closed ?? false },
                set: { v in updatePath("Close Path") { $0.closed = v } })
    }
    var pathFillBinding: Binding<Paint> {
        Binding(get: { selectedPathShape?.fill ?? .white },
                set: { c in updatePath("Path Fill") { $0.fill = c } })
    }
    var pathStrokeBinding: Binding<RGBAColor> {
        Binding(get: { selectedPathShape?.stroke ?? .black },
                set: { c in updatePath("Path Stroke") { $0.stroke = c } })
    }
    var pathStrokeWidthBinding: Binding<Double> {
        Binding(get: { Double(selectedPathShape?.strokeWidth ?? 2) },
                set: { v in updatePath("Stroke Width") { $0.strokeWidth = max(0, CGFloat(v)) } })
    }
}

/// A small labelled numeric field with accelerated arrow stepping.
/// A brand icon toggle/action button for the inspector (align, text-align, B/I/U,
/// distribute). Accent-subtle when active, a soft hover wash otherwise; tool radius.
private struct InspectorIconButton: View {
    let symbol: String
    var active: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .background(active ? EXPColor.accentSubtle : (hovering ? EXPColor.rowHover : Color.clear),
                            in: RoundedRectangle(cornerRadius: EXPMetric.radiusTool, style: .continuous))
                .foregroundStyle(active ? EXPColor.accent : EXPColor.textSecondary)
                .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusTool, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(EXPMotion.fast, value: hovering)
    }
}

private struct DimField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(EXPColor.textSecondary)
                .frame(width: 14, alignment: .leading)
            // Up to 2 decimals, shown only when the value actually has them — the
            // field tells the truth about sub-pixel positions instead of rounding
            // to a whole number (canvas drags snap to whole pixels by default, so
            // fractions are rare and deliberate). Typing "10.5" now sticks as 10.5.
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .textFieldStyle(.exp)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .numericStepping($value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// One instance text-override row with a LOCAL draft + explicit commit (Enter or
/// the ✓ button), so editing doesn't rewrite the model on every keystroke — the
/// re-hug fires once, on commit. Syncs the draft when the selection changes.
private struct InstanceTextRow: View {
    let name: String
    let current: String
    let hasOverride: Bool
    let onCommit: (String) -> Void
    let onReset: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var dirty: Bool { draft != current }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).expSectionLabel()
                Spacer()
                if hasOverride {
                    Button(action: onReset) { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help("Reset to source")
                }
            }
            HStack(spacing: 6) {
                TextField("Text", text: $draft, axis: .vertical)
                    .textFieldStyle(.exp)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { onCommit(draft) }
                Button { onCommit(draft) } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(dirty ? EXPColor.accent : Color.secondary)
                .disabled(!dirty)
                .help("Apply (also on Return)")
            }
        }
        .onAppear { draft = current }
        .onChange(of: current) { draft = $1 }   // selection changed → resync
    }
}

/// Arrow-key stepping for any numeric field: ↑/↓ = ±1, ⇧ = ±10, ⌥ = ±0.1, and
/// holding the key **accelerates** (key-repeat grows the step). Attach to a
/// focused `TextField` bound to the same value.
private struct NumericStepping: ViewModifier {
    @Binding var value: Double
    var min: Double? = nil
    var max: Double? = nil
    @State private var repeats = 0

    func body(content: Content) -> some View {
        content.onKeyPress(phases: [.down, .repeat]) { press in
            let dir: Double
            switch press.key {
            case .upArrow:   dir = 1
            case .downArrow: dir = -1
            default:         return .ignored
            }
            if press.phase.contains(.repeat) { repeats += 1 } else { repeats = 0 }
            let base: Double = press.modifiers.contains(.shift) ? 10
                             : press.modifiers.contains(.option) ? 0.1 : 1
            let accel = Double(1 + repeats / 5)        // grows every 5 repeats
            var next = value + dir * base * accel
            if let m = min { next = Swift.max(m, next) }
            if let m = max { next = Swift.min(m, next) }
            let stepped = (next * 1000).rounded() / 1000   // avoid float drift
            // BUG-002: this handler runs inside SwiftUI's key-event update pass,
            // and writing straight through the binding mutates the document's
            // @Published model mid-update — the "Publishing changes from within
            // view updates is not allowed" warning, flooding once per repeat
            // while a key is held. Deferring the write one runloop tick moves
            // the model mutation outside the update. Step sizes (±1, ⇧±10,
            // ⌥±0.1), key-repeat acceleration, and undo behavior are unchanged;
            // `value` is a Binding (a value type), so the copy captured here
            // still writes through to the live model.
            DispatchQueue.main.async { value = stepped }
            return .handled
        }
    }
}

private extension View {
    func numericStepping(_ value: Binding<Double>, min: Double? = nil, max: Double? = nil) -> some View {
        modifier(NumericStepping(value: value, min: min, max: max))
    }
}

// MARK: - Color bridging (UI layer; the model stays UI-free)

private extension RGBAColor {
    /// Build from a SwiftUI Color via its sRGB components.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

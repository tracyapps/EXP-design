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

                VStack(spacing: 0) {
                    CanvasPageTabs(document: document)
                        // Native canvas redraws are aggressive during fast pan.
                        // Keep the SwiftUI chrome in its own foreground stacking
                        // group so AppKit cannot transiently composite above it.
                        .compositingGroup()
                        .zIndex(1)
                    CanvasView(app: app, document: document, documentURL: fileURL)
                        .overlay(alignment: .topLeading) { ArtboardNotesOverlay(document: document) }
                        .clipped()
                        .zIndex(0)
                }
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
        .expInterfaceTypeSize()
        .environment(app)
        // Publish state for the Window menu (panels + dock visibility). Scene
        // value = active whenever this window is frontmost (no focused control
        // required), so the menu items enable correctly.
        .focusedSceneValue(\.windowMenu, makeWindowMenuModel(app))
        .focusedSceneValue(\.editorMenu, makeEditorMenuModel(document: document, app: app, scope: .document))
        // Multi-window mode: float panels into their own windows (and tear them
        // down when returning to single-window or closing this document window).
        // Shared floating panels point at the frontmost document. Claim them when
        // this window appears or becomes key, and reconcile windows on mode/tray
        // changes. (The tray set is global — PanelHub — so a 2nd document doesn't
        // open a 2nd set of panels.)
        .onAppear {
            app.activeCanvasPageID = document.model.pageID(resolving: app.activeCanvasPageID)
            activate()
        }
        .onDisappear { SourceEditorWindowManager.shared.closeAll(for: document) }
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
            Label("New Artboard", systemImage: "plus.viewfinder").labelStyle(.iconOnly)
        } primaryAction: {
            addArtboard(width: 375, height: 667, name: "Artboard")
        }
        .menuIndicator(.visible)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("New artboard (⇧⌘N for default; use the menu for sizes). Press F to draw one on the canvas instead.")
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
        PanelHub.shared.setActive(app: app, document: document, fileURL: fileURL,
                                  undoManager: undoManager)
        PanelWindowManager.shared.reconcile()
    }

    /// Add an artboard to the right of existing content, through the document's
    /// undo-aware funnel, then select it.
    private func addArtboard(width: CGFloat, height: CGFloat, name: String) {
        var model = document.model
        guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
        let page = model.pages[pageIndex]
        let originX = page.artboards.isEmpty
            ? 0
            : model.contentBounds(on: page.id).maxX + AppPreferences.artboardSpacingValue
        let artboard = Artboard(
            name: "\(name) \(page.artboards.count + 1)",
            frame: CGRect(x: originX, y: 0, width: width, height: height)
        )
        model.pages[pageIndex].artboards.append(artboard)
        document.setModel(model, undoManager: undoManager, actionName: "New Artboard")
        app.selectedArtboardID = artboard.id
    }
}

/// Document-level canvas navigation. Pages intentionally sit above the drawing
/// surface—not beside Layers—because switching one replaces the whole workspace.
private struct CanvasPageTabs: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @State private var deleteCandidate: CanvasPage?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(document.model.pages) { page in
                        CanvasPageTab(
                            page: page,
                            isActive: document.model.pageID(resolving: app.activeCanvasPageID) == page.id,
                            canDelete: document.model.pages.count > 1,
                            canMoveLeft: document.model.pages.first?.id != page.id,
                            canMoveRight: document.model.pages.last?.id != page.id,
                            select: { select(page.id) },
                            rename: { rename(page.id, to: $0) },
                            duplicate: { duplicate(page.id) },
                            delete: { deleteCandidate = page },
                            moveLeft: { reorder(page.id, delta: -1) },
                            moveRight: { reorder(page.id, delta: 1) })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            Divider().frame(height: 20)
            Button(action: addPage) {
                Image(systemName: "plus")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("New canvas page")
            .accessibilityLabel("New canvas page")
            .padding(.horizontal, 5)
        }
        .frame(height: 33)
        .background(EXPColor.surfacePanelSolid)
        .overlay(alignment: .bottom) { Divider() }
        .alert("Delete Canvas Page?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } })) {
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
                Button("Delete", role: .destructive) {
                    if let page = deleteCandidate { deletePage(page.id) }
                    deleteCandidate = nil
                }
            } message: {
                Text("This removes \(deleteCandidate?.name ?? "the page") and all of its artboards and layers. You can undo this action.")
            }
    }

    private func select(_ id: UUID) {
        guard app.activeCanvasPageID != id else { return }
        app.selectedNodeIDs = []
        app.selectedArtboardIDs = []
        app.selectionAnchorID = nil
        app.activeCanvasPageID = id
    }

    private func uniqueName(_ base: String, excluding id: UUID? = nil) -> String {
        let used = Set(document.model.pages.filter { $0.id != id }.map { $0.name.lowercased() })
        if !used.contains(base.lowercased()) { return base }
        var number = 2
        while used.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    private func addPage() {
        var model = document.model
        let page = CanvasPage(name: uniqueName("Page \(model.pages.count + 1)"))
        model.pages.append(page)
        document.setModel(model, undoManager: undoManager, actionName: "New Canvas Page")
        select(page.id)
    }

    private func rename(_ id: UUID, to proposed: String) {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var model = document.model
        guard let index = model.pages.firstIndex(where: { $0.id == id }) else { return }
        let name = uniqueName(trimmed, excluding: id)
        guard model.pages[index].name != name else { return }
        model.pages[index].name = name
        document.setModel(model, undoManager: undoManager, actionName: "Rename Canvas Page")
    }

    private func duplicate(_ id: UUID) {
        var model = document.model
        guard let index = model.pages.firstIndex(where: { $0.id == id }) else { return }
        let copy = Document.duplicatingPage(model.pages[index], named: uniqueName("\(model.pages[index].name) copy"))
        model.pages.insert(copy, at: index + 1)
        document.setModel(model, undoManager: undoManager, actionName: "Duplicate Canvas Page")
        select(copy.id)
    }

    private func deletePage(_ id: UUID) {
        var model = document.model
        guard model.pages.count > 1,
              let index = model.pages.firstIndex(where: { $0.id == id }) else { return }
        model.pages.remove(at: index)
        let fallback = model.pages[min(index, model.pages.count - 1)].id
        document.setModel(model, undoManager: undoManager, actionName: "Delete Canvas Page")
        if app.activeCanvasPageID == id { select(fallback) }
    }

    private func reorder(_ id: UUID, delta: Int) {
        var model = document.model
        guard let from = model.pages.firstIndex(where: { $0.id == id }) else { return }
        let to = from + delta
        guard model.pages.indices.contains(to) else { return }
        model.pages.swapAt(from, to)
        document.setModel(model, undoManager: undoManager, actionName: "Reorder Canvas Pages")
    }
}

private struct CanvasPageTab: View {
    let page: CanvasPage
    let isActive: Bool
    let canDelete: Bool
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let select: () -> Void
    let rename: (String) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let moveLeft: () -> Void
    let moveRight: () -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Page name", text: $draft)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 72, maxWidth: 180)
                    .focused($focused)
                    .onSubmit(commitRename)
                    .onExitCommand { editing = false }   // Esc cancels (discard)
                    .onChange(of: focused) { _, value in if !value, editing { commitRename() } }
            } else {
                Button(action: select) {
                    Text(page.name)
                        .font(.system(size: EXPType.small, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 25)
                }
                .buttonStyle(.plain)
                // Double-click renames, matching a Layers row. `simultaneousGesture`
                // rather than `onTapGesture`: the Button consumes taps, so a plain
                // tap gesture never fires here. Running alongside means a
                // double-click also switches to the page, which is what you want —
                // you can't sensibly rename a page you aren't looking at.
                .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename() })
            }
        }
        .foregroundStyle(isActive ? EXPColor.accent : EXPColor.textSecondary)
        .background(isActive ? EXPColor.rowSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl))
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? EXPColor.accent : Color.clear).frame(height: 2)
        }
        .contextMenu {
            Button("Rename…", action: beginRename)
            Button("Duplicate Page", action: duplicate)
            Divider()
            Button("Move Left", action: moveLeft).disabled(!canMoveLeft)
            Button("Move Right", action: moveRight).disabled(!canMoveRight)
            Divider()
            Button("Delete Page", role: .destructive, action: delete).disabled(!canDelete)
        }
        // While editing, the field must stay its own element — combining children
        // over a TextField hides the text from VoiceOver as you type.
        .accessibilityElement(children: editing ? .contain : .combine)
        .accessibilityLabel(editing ? "Page name" : "Canvas page \(page.name)")
        .accessibilityValue(editing ? "" : (isActive ? "Selected" : "Not selected"))
        // Double-click is a mouse-only affordance, so name the same action for
        // assistive technology instead of leaving the context menu as the only route.
        .accessibilityAction(named: "Rename", beginRename)
        .help(editing ? "Press Return to rename, Escape to cancel"
                      : (isActive ? "Current canvas page — double-click to rename"
                                  : "Switch to \(page.name) — double-click to rename"))
    }

    private func beginRename() {
        draft = page.name
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commitRename() {
        rename(draft)
        editing = false
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
                .accessibilityLabel("Zoom out")
            TextField("", value: zoomPercentBinding, format: .number.precision(.fractionLength(0)))
                .labelsHidden()
                .textFieldStyle(.exp)
                .frame(width: 46)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .numericStepping(zoomPercentBinding, min: 5)
                .accessibilityLabel("Zoom percentage")
                .help("Zoom %")
                .accessibilityLabel("Zoom percentage")
            Button { app.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in (⌘+)")
                .accessibilityLabel("Zoom in")
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
            .accessibilityLabel("Zoom presets")

            Divider().frame(height: 16)

            // Dock show/hide — disabled in Multi-Window mode (no docks; panels
            // live in their own windows).
            Button { app.showLeftPanel.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Show/hide the left panel")
                .accessibilityLabel(app.showLeftPanel ? "Hide left panel" : "Show left panel")
                .disabled(app.workspaceMode == .multiWindow)
            Button { app.showRightPanel.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("Show/hide the right panel")
                .accessibilityLabel(app.showRightPanel ? "Hide right panel" : "Show right panel")
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
                Divider()
                // FEAT-021 — the same commands the Window ▸ Workspace menu runs.
                WorkspacePresetMenuItems(app: app)
            } label: {
                Image(systemName: app.workspaceMode.icon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Workspace: \(app.workspaceMode.label)")
            .accessibilityLabel("Workspace mode")
            .accessibilityValue(app.workspaceMode.label)
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

// MARK: - Editor command menu state

struct ComponentPlacementChoice: Identifiable, Hashable {
    var id: UUID
    var name: String
}

struct CanvasPageChoice: Identifiable, Hashable {
    var id: UUID
    var name: String
}

/// Focused state used by SwiftUI command menus to grey out actions that do not
/// apply to the active selection. The canvas responder remains the source of
/// behavior; this is just the visible menu contract.
struct EditorMenuModel {
    var hasNodes: Bool
    var hasArtboards: Bool
    var hasAnySelection: Bool { hasNodes || hasArtboards }

    var canDuplicate: Bool
    var canDuplicateEffect: Bool
    var canCopyStyle: Bool
    var canPasteStyle: Bool
    var pageTransferChoices: [CanvasPageChoice]
    var selectedNodeIDs: Set<UUID>
    var selectedArtboardIDs: Set<UUID>

    var canGroup: Bool
    var canUngroup: Bool
    var canMask: Bool
    var canReleaseMask: Bool
    var canAutoLayout: Bool
    var canAutoPadding: Bool
    var autoLayoutTitle: String
    var autoPaddingTitle: String
    var canMoveAutoLayoutItem: Bool

    var canCreateComponent: Bool
    var canNewEmptyComponent: Bool
    var canEditComponent: Bool
    var canDuplicateComponent: Bool
    var canDetachComponent: Bool
    var canDeleteComponent: Bool
    var deleteComponentTitle: String
    var componentPlacementChoices: [ComponentPlacementChoice]
    var canSetComponentCategory: Bool
    var canEditRelationships: Bool
    var canAddComponentState: Bool
    var addComponentStateTitle: String
    var canCycleComponentState: Bool

    var canConvertToPath: Bool
    var canOutlineStroke: Bool
    var canPathfinder: Bool
    var canRoundToPixel: Bool
    var canEyedropper: Bool

    var canTypeActions: Bool
    var canConvertTextToOutlines: Bool
    /// Align/Distribute are ONE command for boards and nodes alike — CanvasNSView
    /// routes by what's selected — so these flags cover both cases.
    var canAlign: Bool
    var canDistribute: Bool
    var canCleanUpArtboards: Bool
    var canExportSelectedArtboards: Bool
    var canExportAllArtboards: Bool
    var canRevealSelectionInLayers: Bool
}

private struct EditorMenuKey: FocusedValueKey { typealias Value = EditorMenuModel }
extension FocusedValues {
    var editorMenu: EditorMenuModel? {
        get { self[EditorMenuKey.self] }
        set { self[EditorMenuKey.self] = newValue }
    }
}

@MainActor
func makeEditorMenuModel(document: ExpDocument, app: AppState, scope: CanvasScope) -> EditorMenuModel {
    let model = document.model
    let nodes: [Node]
    let source: ComponentSource?
    switch scope {
    case .document:
        nodes = model.page(for: app.activeCanvasPageID)?.nodes ?? []
        source = nil
    case .source(let sid):
        source = model.source(for: sid)
        nodes = source?.children ?? []
    }

    func find(_ id: UUID, in nodes: [Node]) -> Node? {
        for node in nodes {
            if node.id == id { return node }
            if case .group(let children) = node.content, let found = find(id, in: children) { return found }
        }
        return nil
    }
    func parentID(of id: UUID, in nodes: [Node], parent: UUID? = nil) -> UUID? {
        for node in nodes {
            if node.id == id { return parent }
            if case .group(let children) = node.content,
               let found = parentID(of: id, in: children, parent: node.id) { return found }
        }
        return nil
    }
    func flatten(_ nodes: [Node]) -> [Node] {
        nodes.flatMap { node -> [Node] in
            if case .group(let children) = node.content {
                return [node] + flatten(children)
            }
            return [node]
        }
    }
    let selectedIDs = app.selectedNodeIDs
    let selectedNodes = selectedIDs.compactMap { find($0, in: nodes) }
    let singleNode = selectedIDs.count == 1 ? selectedNodes.first : nil
    let hasNodes = !selectedIDs.isEmpty
    let hasArtboards = !app.selectedArtboardIDs.isEmpty
    let hasGroup = selectedNodes.contains { if case .group = $0.content { return true }; return false }
    let singleGroup = singleNode.flatMap { node -> Node? in
        if case .group = node.content { return node }
        return nil
    }
    let hasInstance = selectedNodes.contains { if case .instance = $0.content { return true }; return false }
    /// The source behind the first selected instance — Delete Component names it
    /// in the menu title so it can never read as "delete the selected layer."
    let instanceSource = selectedNodes.compactMap { node -> ComponentSource? in
        guard case .instance(let inst) = node.content else { return nil }
        return model.source(for: inst.sourceID)
    }.first
    let hasMask = selectedNodes.contains { $0.isMask }
    func selectedSubtreesContain(_ predicate: (Node) -> Bool) -> Bool {
        func scan(_ node: Node) -> Bool {
            if predicate(node) { return true }
            if case .group(let children) = node.content { return children.contains(where: scan) }
            return false
        }
        return selectedNodes.contains(where: scan)
    }
    let hasConvertible = selectedSubtreesContain {
        switch $0.content {
        case .rectangle, .ellipse, .polygon, .line: return true
        default: return false
        }
    }
    let hasOutlinedStroke = selectedSubtreesContain {
        VectorPathGeometry.stroke(from: $0.content) != nil
    }
    let hasTextToOutline = selectedSubtreesContain {
        if case .text = $0.content { return true }
        return false
    }
    let canPathfinder = selectedIDs.count >= 2 && selectedNodes.count == selectedIDs.count
        && selectedNodes.allSatisfy { VectorPathGeometry.isClosedVector($0.content) }
    let isSingleText: Bool = {
        guard let singleNode else { return false }
        if case .text = singleNode.content { return true }
        return false
    }()
    let selectedItemInAutoLayout: Bool = {
        guard selectedIDs.count == 1, let id = selectedIDs.first,
              let pid = parentID(of: id, in: nodes),
              let parent = find(pid, in: nodes) else { return false }
        return parent.autoLayout != nil
    }()
    let stateName: String = {
        guard let source else { return "Add Component State" }
        let lowered = Set(source.states.map { $0.name.lowercased() })
        guard let next = ComponentState.conventionalNames.first(where: { !lowered.contains($0.lowercased()) })
        else { return "Add Component State" }
        return "Add \(next.capitalized) State"
    }()
    /// Relationships are reachable when the COMPONENT ROOT can carry them, or when
    /// the selected layer has a role of its OWN. Roles do not inherit, so being
    /// inside a roled component is not enough — that was BUG-008, which offered
    /// naming on every decorative layer in a Tab Panel.
    /// Relationships are reachable when there is an ANCHOR holding both ends and
    /// something inside it that can carry one. Answers from
    /// `Document.hasRelationshipParticipant(in:)` so this and the canvas context
    /// menu and the inspector cannot drift apart.
    let canEditRelationships: Bool = {
        guard let node = singleNode else {
            // Source scope with nothing selected still offers the component ROOT.
            guard let source else { return false }
            return !(source.a11y.role?.authoredRelationshipKinds.isEmpty ?? true)
                || !source.anchoredRelationships.isEmpty
        }
        let carries = model.hasRelationshipParticipant(in: node)
        guard let source else {
            // Document scope: the anchor is the enclosing GROUP. Without one there
            // is nothing to point at, but the panel still explains the rule, so the
            // menu item stays enabled rather than going grey for an invisible reason.
            return carries
        }
        let rootCarries = !(source.a11y.role?.authoredRelationshipKinds.isEmpty ?? true)
            || !source.anchoredRelationships.isEmpty
        return carries || rootCarries
    }()
    let canAlign = selectedIDs.isEmpty
        ? app.selectedArtboardIDs.count >= 2
        : (selectedIDs.count >= 2 || app.alignTarget == .artboard)
    let componentPlacementChoices = model.sources
        .filter { candidate in
            switch scope {
            case .document:
                return true
            case .source(let parentSourceID):
                return model.canNestComponent(candidate.id, in: parentSourceID)
            }
        }
        .map { ComponentPlacementChoice(id: $0.id, name: $0.name) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let activePageID = model.pageID(resolving: app.activeCanvasPageID)
    let pageTransferChoices = scope == .document
        ? model.pages.filter { $0.id != activePageID }.map { CanvasPageChoice(id: $0.id, name: $0.name) }
        : []

    return EditorMenuModel(
        hasNodes: hasNodes,
        hasArtboards: hasArtboards,
        canDuplicate: hasNodes,
        canDuplicateEffect: singleNode?.effects.contains(where: { $0.id == app.selectedEffectID }) == true,
        canCopyStyle: hasNodes,
        canPasteStyle: hasNodes && app.copiedLayerStyle != nil,
        pageTransferChoices: pageTransferChoices,
        selectedNodeIDs: selectedIDs,
        selectedArtboardIDs: app.selectedArtboardIDs,
        canGroup: selectedIDs.count >= 2,
        canUngroup: hasGroup,
        canMask: selectedIDs.count >= 2,
        canReleaseMask: hasMask,
        canAutoLayout: hasNodes,
        canAutoPadding: hasNodes,
        autoLayoutTitle: (singleGroup?.autoLayout != nil) ? "Remove Auto Layout" : "Add Auto Layout",
        autoPaddingTitle: (singleGroup?.autoPadding != nil) ? "Remove Auto Padding" : "Add Auto Padding",
        canMoveAutoLayoutItem: selectedItemInAutoLayout,
        canCreateComponent: hasNodes,
        canNewEmptyComponent: true,
        canEditComponent: hasInstance,
        canDuplicateComponent: source != nil || hasInstance,
        canDetachComponent: hasInstance,
        canDeleteComponent: instanceSource != nil,
        deleteComponentTitle: instanceSource.map { "Delete Component \u{201C}\($0.name)\u{201D}" }
            ?? "Delete Component",
        componentPlacementChoices: componentPlacementChoices,
        canSetComponentCategory: source != nil || hasInstance,
        canEditRelationships: canEditRelationships,
        canAddComponentState: source != nil,
        addComponentStateTitle: stateName,
        canCycleComponentState: !(source?.states.isEmpty ?? true),
        canConvertToPath: hasConvertible,
        canOutlineStroke: hasOutlinedStroke,
        canPathfinder: canPathfinder,
        canRoundToPixel: hasNodes || hasArtboards,
        canEyedropper: hasNodes,
        canTypeActions: isSingleText,
        canConvertTextToOutlines: hasTextToOutline,
        canAlign: canAlign,
        canDistribute: selectedIDs.isEmpty
            ? app.selectedArtboardIDs.count >= 3
            : selectedIDs.count >= 3,
        canCleanUpArtboards: app.selectedArtboardIDs.count >= 2,
        canExportSelectedArtboards: !app.selectedArtboardIDs.isEmpty,
        canExportAllArtboards: !(model.page(for: app.activeCanvasPageID)?.artboards.isEmpty ?? true),
        canRevealSelectionInLayers: hasNodes
    )
}

/// Right panel — the Inspector. X/Y/W/H are two-way: editing a field writes
/// back through the document's undo-aware funnel, so the shape/artboard moves
/// or resizes and the change is a single undo step. The canvas, reading the
/// same document, redraws automatically.
/// Deliver a canvas action wherever the canvas actually is. This has now been the
/// cause of TWO rounds of "the command is enabled but does nothing," so the whole
/// problem is written down here.
///
/// Enablement and dispatch use different mechanisms and can disagree. Menu items
/// are SwiftUI `Button`s gated by `.focusedSceneValue(\.editorMenu)`, which is
/// SCENE-scoped — it stays live while focus moves between the canvas, Layers, and
/// the Inspector, so items keep looking enabled. Dispatch goes through
/// `NSApp.sendAction(to: nil)`, which only walks a responder chain. Two ways that
/// chain misses the canvas:
///
/// 1. ACROSS WINDOWS. Clicking a floating panel button makes the PANEL key, so the
///    key window's chain dead-ends there. Fixed earlier by also trying the main
///    window; tray windows override `canBecomeMain` to false, so `NSApp.mainWindow`
///    is reliably the document window.
/// 2. WITHIN ONE WINDOW. Click a Layers row or an Inspector control and the canvas
///    is a SIBLING subtree of whatever now holds focus — never on the chain, which
///    only runs UPWARD from the first responder. The old fallback walked upward
///    too, so it could not help. Whether a command worked came down to what you had
///    clicked last, which is why it looked random and would not reproduce.
///
/// So: responder chain first (cheapest, and correct whenever the canvas has focus),
/// then search DOWN the key and main windows' view trees. Only those two windows —
/// never every window — so a command can't leak into a different document.
/// `validateMenuItem` isn't consulted on the direct-target path, which is fine: the
/// SwiftUI `.disabled` gate already ran and every action guards its own
/// preconditions anyway.
// MARK: - Tool letter shortcuts (BUG-028)

/// Single-letter tool shortcuts (V, A, P, T, R, O, G, L, F, H, plus ⇧A) handled in
/// ONE place, so they work from any focus location — canvas, Layers, inspector, a
/// floating tray — instead of only when the canvas happens to hold focus.
///
/// **Why a local event monitor rather than menu key equivalents.** The main menu is
/// offered key equivalents BEFORE the event reaches the window's first responder, so
/// an unmodified letter equivalent fires while the user is typing and swallows the
/// character. That is not a hypothetical: BUG-038 was exactly this failure, already
/// shipped — BUG-020's opacity digits ate the numbers being typed into a layer name,
/// so layers could not be called "Button 2". A monitor can ask "is the user typing?"
/// FIRST and decline; a menu key equivalent has no such opportunity.
///
/// **Why not per-panel `.onKeyPress`.** That is the route BUG-020 took, and BUG-038
/// is what it produced: every panel has to repeat the guard, and eventually one of
/// them forgets. This is the single place that has to be right.
///
/// **Known minor behaviour:** with a non-document window key (Settings, the ARIA
/// guide) a tool letter still reaches the document via `sendCanvasAction`'s
/// main-window fallback and changes its active tool. Harmless, and the same fallback
/// is exactly what makes floating panel trays work — a key-window-must-host-a-canvas
/// guard would break the case this bug is about.
@MainActor
enum ToolShortcuts {
    private static var monitor: Any?

    /// Letter → the `@objc` action on `CanvasNSView`. Keep in sync with the Tools
    /// menu in `EXP__design_App.swift` and with `CanvasNSView.keyDown`'s own cases,
    /// which remain the path used when the canvas already has focus.
    private static let actions: [String: String] = [
        "v": "selectToolAction:",  "a": "nodeToolAction:",
        "p": "penToolAction:",     "t": "textToolAction:",
        "r": "rectangleToolAction:", "o": "ellipseToolAction:",
        "g": "polygonToolAction:", "l": "lineToolAction:",
        "f": "artboardToolAction:", "h": "panToolAction:",
    ]

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    /// Returns true when the event was consumed.
    private static func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌘/⌃/⌥ combinations belong to other commands.
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) { return false }
        // FEAT-008: the font popover uses unmodified letters for native
        // type-to-jump. It owns those keystrokes while open; otherwise A/F/T/etc.
        // would switch canvas tools before the picker could see the event.
        if FontPickerKeyboardSession.isActive { return false }
        // The user is typing. This check is the entire reason this is a monitor.
        if isTypingInTextField() { return false }
        // The canvas already handles these in its own keyDown when it has focus.
        // Declining here leaves the common path bit-for-bit unchanged, so this can
        // only ADD the missing routes, never alter existing behaviour.
        if NSApp.keyWindow?.firstResponder is CanvasNSView { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return false }
        // ⇧A is the Sketch/XD Artboard alias; every other tool letter is unshifted.
        if mods.contains(.shift) {
            guard key == "a" else { return false }
            return sendCanvasAction("artboardToolAction:")
        }
        guard let selector = actions[key] else { return false }
        // If nothing answered, let the event continue rather than silently eating a
        // keystroke — `sendCanvasAction` returns false and logs when it finds no target.
        return sendCanvasAction(selector)
    }
}

/// True when the user is typing into a text field RIGHT NOW, so an unmodified
/// character shortcut must not fire.
///
/// Why ask AppKit instead of tracking it in SwiftUI state: a panel that installs
/// `.onKeyPress` on its List has no idea whether some descendant row has opened a
/// rename field, because that `editing` flag is `@State` private to the row. That
/// is exactly how BUG-038 happened — BUG-020's opacity-digit fix returned
/// `.handled` for every digit, including the ones being typed into a layer name,
/// so layers could not be named "Button 2".
///
/// Checking the FIELD EDITOR matters and is easy to get wrong: AppKit does not
/// make the `NSTextField` itself first responder while editing — it installs a
/// shared `NSTextView` field editor whose delegate is the field. Testing only for
/// `NSTextField` therefore misses the case that actually matters. Both are checked
/// here, so this stays correct for SwiftUI `TextField`s, the component-name field,
/// the canvas's inline text editing, and any field added later — no plumbing
/// required at the call site.
@MainActor
func isTypingInTextField() -> Bool {
    guard let responder = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder else { return false }
    if let textView = responder as? NSTextView { return textView.isFieldEditor || textView.isEditable }
    return responder is NSTextField
}

@discardableResult
func sendCanvasAction(_ selectorName: String, from sender: Any? = nil) -> Bool {
    let sel = Selector(selectorName)
    if NSApp.sendAction(sel, to: nil, from: sender) { return true }

    var tried: [NSWindow] = []
    for window in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 })
    where !tried.contains(where: { $0 === window }) {
        tried.append(window)
        guard let root = window.contentView,
              let target = canvasDescendant(of: root, responding: sel) else { continue }
        if NSApp.sendAction(sel, to: target, from: sender) { return true }
    }

    // An action with nowhere to land is a wiring bug. It used to leave no trace at
    // all, which is exactly why these were unreproducible — now it is on the record.
    DiagnosticLog.shared.log("[EXP command] no target for \(selectorName) "
        + "— key=\(NSApp.keyWindow?.title ?? "nil") main=\(NSApp.mainWindow?.title ?? "nil")")
    return false
}

/// Breadth-first, so a direct child of the content view (the canvas) wins over some
/// deeply nested control that happens to answer the same selector.
private func canvasDescendant(of root: NSView, responding sel: Selector) -> NSView? {
    var queue = root.subviews
    while !queue.isEmpty {
        let view = queue.removeFirst()
        if view.responds(to: sel) { return view }
        queue.append(contentsOf: view.subviews)
    }
    return nil
}

private struct InspectorSectionTitle: View {
    let title: String
    let icon: String
    var helpTitle: String? = nil
    var helpBody: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: EXPType.small))
                .foregroundStyle(EXPColor.textTertiary)
                .accessibilityHidden(true)
            Text(title).expSectionLabel()
            if let helpBody {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: EXPType.small))
                    .foregroundStyle(EXPColor.textTertiary)
                    .expFieldTip(helpTitle ?? title, helpBody)
                    .accessibilityLabel("\(title) help")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RightPanel: View {
    @ObservedObject var document: ExpDocument
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    /// Noise/Dissolve "Advanced" accordion — remembered across effects, panel
    /// rebuilds, and app launches, so it stays the way the designer left it.
    @AppStorage("inspector.effects.advancedOpen") private var effectsAdvancedOpen = false
    /// Row disclosure is workspace UI state, not document data. Keep it while this
    /// Inspector lives; a newly added or duplicated effect starts expanded so its
    /// editable copy is never hidden unexpectedly.
    @State private var collapsedEffectIDs: Set<UUID> = []
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

    /// The component STATE being edited in this window's source scope, if any
    /// (v1.6 Chunk H). The inspector shows state-applied values and routes
    /// appearance edits into the state's diff while it's set.
    private var activeEditingState: ComponentState? {
        guard case .source(let sid) = scope,
              let stateID = app.activeComponentStateID else { return nil }
        return document.model.source(for: sid)?.states.first { $0.id == stateID }
    }

    /// The node list for the current scope — with the active component state's
    /// overrides applied, so the inspector reads what the canvas shows.
    private var scopedNodes: [Node] {
        switch scope {
        case .document: return document.model.page(for: app.activeCanvasPageID)?.nodes ?? []
        case .source(let sid):
            let children = document.model.source(for: sid)?.children ?? []
            if let state = activeEditingState {
                // Reflow through the document so component instances inside a
                // state contribute their resolved size, not a stale frame
                // (BUG-007).
                return document.model.reflowed(
                    ComponentStateEditing.applied(children, state: state))
            }
            return children
        }
    }

    /// Mutate the scoped node list in one undo step (the single write funnel so
    /// the inspector works identically in the document and source-editor windows).
    private func commitScoped(_ action: String, _ change: (inout [Node]) -> Void) {
        var model = document.model
        switch scope {
        case .document:
            guard let pageIndex = model.pageIndex(for: app.activeCanvasPageID) else { return }
            change(&model.pages[pageIndex].nodes)
            model.pages[pageIndex].nodes = model.reflowed(model.pages[pageIndex].nodes)
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            if let state = activeEditingState,
               let sti = model.sources[si].states.firstIndex(where: { $0.id == state.id }) {
                // Editing a STATE: run the change against the state-applied
                // tree (what the user sees), then split appearance differences
                // into the state's diff and keep the rest in the base
                // (see ComponentStateEditing).
                var resolved = ComponentStateEditing.applied(model.sources[si].children,
                                                             state: state)
                change(&resolved)
                let (newBase, newState) = ComponentStateEditing.capture(
                    base: model.sources[si].children, edited: resolved, state: state)
                let reflowed = model.reflowed(newBase)
                model.sources[si].children = reflowed
                model.sources[si].states[sti] = newState
                if fitSourceBounds,
                   let bounds = model.managedRootBounds(in: reflowed) {
                    model.sources[si].origin = bounds.origin
                    model.sources[si].size = bounds.size
                }
            } else {
                change(&model.sources[si].children)
                let reflowed = model.reflowed(model.sources[si].children)
                model.sources[si].children = reflowed
                if fitSourceBounds,
                   let bounds = model.managedRootBounds(in: reflowed) {
                    model.sources[si].origin = bounds.origin
                    model.sources[si].size = bounds.size
                }
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
        return document.model.page(for: app.activeCanvasPageID)?.artboards.first { $0.id == id }
    }

    /// The single selected shape, if exactly one is selected (within the scope).
    private var selectedNode: Node? {
        guard let id = app.singleSelectedNodeID else { return nil }
        return findScopedNode(id)   // resolves nested children too
    }

    /// One selection shared by the on-canvas gradient handles and whichever
    /// selected-object PaintWell is open in the Inspector.
    private var gradientStopSelection: Binding<UUID?> {
        Binding(get: { app.selectedGradientStopID },
                set: { app.selectedGradientStopID = $0 })
    }

    /// One pickable end of a relationship, addressed relative to the anchor.
    private struct RelationshipTarget: Identifiable {
        let endpoint: RelationshipEndpoint
        let title: String
        let icon: String
        /// The target's own role, shown beside its name. Picking "the panel" out of
        /// a list of layer names is guesswork; "Panel One — Tab Panel" is not.
        var roleLabel: String? = nil

        /// The PATH is the identity. A node id alone is not unique: the same source
        /// child appears once per placement of its component.
        var id: [UUID] { endpoint.path }

        var display: String {
            guard let roleLabel else { return title }
            return "\(title) \u{2014} \(roleLabel)"
        }
    }

    /// A thing that can CARRY a relationship, and where it sits relative to the
    /// anchor. The selection itself is one; so is each roled component nested
    /// inside it, which is how a single tab inside a placed Tab Bar becomes
    /// authorable without being selectable.
    private struct RelationshipParticipant: Identifiable {
        let subject: RelationshipEndpoint
        let title: String
        let subtitle: String
        let role: AriaRole?
        let kinds: [NodeRelationship.Kind]
        var id: [UUID] { subject.path }
    }

    /// Where a relationship is STORED: the nearest thing containing both ends.
    private enum RelationshipAnchor {
        case source(ComponentSource)
        case group(Node)

        var id: UUID {
            switch self {
            case .source(let s): return s.id
            case .group(let g):  return g.id
            }
        }
        var name: String {
            switch self {
            case .source(let s): return s.name
            case .group(let g):  return g.name.isEmpty ? "Group" : g.name
            }
        }
        var children: [Node] {
            switch self {
            case .source(let s): return s.children
            case .group(let g):
                if case .group(let kids) = g.content { return kids }
                return []
            }
        }
        var stored: [AnchoredRelationship] {
            switch self {
            case .source(let s): return s.anchoredRelationships
            case .group(let g):  return g.anchoredRelationships
            }
        }
    }

    private var editingSourceID: UUID? {
        if case .source(let sid) = scope { return sid }
        return nil
    }

    private var editingSource: ComponentSource? {
        editingSourceID.flatMap { document.model.source(for: $0) }
    }

    /// The role that will actually be emitted on the element hosting this node.
    ///
    /// ARIA roles do NOT inherit — each element has its own role, explicit or
    /// implicit, and nothing cascades to descendants. So this asks the NODE, never
    /// its container. A component instance hosts its source's role; every other
    /// layer exports as a plain `<div>`, whose implicit role is `generic`.
    /// Verified 2026-07-24; see BACKLOG BUG-008.
    private func effectiveExportRole(of node: Node) -> AriaRole? {
        if case .instance(let instance) = node.content {
            return document.model.source(for: instance.sourceID)?.a11y.role
        }
        return nil
    }

    /// The nearest enclosing GROUP of a node, or nil when it is not in one.
    private func enclosingGroup(of id: UUID, in nodes: [Node],
                                parent: Node? = nil) -> Node? {
        for node in nodes {
            if node.id == id { return parent }
            if case .group(let children) = node.content,
               let found = enclosingGroup(of: id, in: children, parent: node) {
                return found
            }
        }
        return nil
    }

    /// RELATIONSHIP SCOPE — the "neighborhood" rule, now expressed as the ANCHOR
    /// (owner calls 2026-07-24; BACKLOG FEAT-012).
    ///
    /// A relationship lives at the nearest thing containing BOTH ends, and the
    /// pickable ends are exactly that thing's subtree. So the neighborhood is not a
    /// separate constraint bolted onto the picker — it IS the anchor, which is why
    /// the two collapsed into one concept.
    ///
    /// - SOURCE scope: the component. A component is already a bounded thing, and
    ///   its root must be able to reach any layer in it.
    /// - DOCUMENT scope: the nearest enclosing GROUP, with NO fallback to the
    ///   artboard. Owner call: an artboard fallback quietly reintroduces the
    ///   long-list problem and makes the rule change with context, while "things you
    ///   connect live in a group together" always holds — and matches how the owner
    ///   already designs.
    private var relationshipAnchor: RelationshipAnchor? {
        switch scope {
        case .source:
            return editingSource.map { .source($0) }
        case .document:
            guard let id = app.singleSelectedNodeID,
                  let node = findScopedNode(id) else { return nil }
            // A selected GROUP is the anchor ITSELF, not its parent. Groups carry no
            // role, so a group is never a participant — it is only ever a container,
            // and the thing you want when you select one is to connect the parts
            // inside it. Asking for its ENCLOSING group instead meant selecting the
            // very group that holds a tab bar and its panel produced no anchor at
            // all, which is a dead end with nothing on screen to explain it.
            if case .group = node.content { return .group(node) }
            guard let group = enclosingGroup(
                of: id, in: document.model.page(for: app.activeCanvasPageID)?.nodes ?? []) else { return nil }
            return .group(group)
        }
    }

    // MARK: Endpoints available inside the anchor

    /// Everything in the anchor's subtree that may be an END of a relationship.
    ///
    /// Groups are transparent — they are structure, not identity, so a path never
    /// names one and a link survives regrouping. Component INSTANCES contribute
    /// themselves AND their roled descendants, but nothing else: an unroled layer
    /// inside a component is that component's private business, and linking to one
    /// from outside couples two components at a level that breaks the moment either
    /// is edited. A component's roled parts are its public semantic surface, and
    /// they are also the only things ARIA has any use for out here — a tabpanel is
    /// named by its TAB, not by some rectangle inside the tab bar.
    private func relationshipEndpoints(in nodes: [Node],
                                       chain: [UUID] = [],
                                       depth: Int = 0) -> [RelationshipTarget] {
        guard depth < 8 else { return [] }
        return nodes.flatMap { node -> [RelationshipTarget] in
            let indent = String(repeating: "  ", count: depth)
            let role = effectiveExportRole(of: node)
            let here = RelationshipTarget(
                endpoint: RelationshipEndpoint(instanceChain: chain, nodeID: node.id),
                title: "\(indent)\(node.name.isEmpty ? "Layer" : node.name)",
                icon: nodeTypeIcon(node),
                roleLabel: role?.friendlyLabel)
            switch node.content {
            case .group(let children):
                return [here] + relationshipEndpoints(in: children, chain: chain, depth: depth + 1)
            case .instance(let instance):
                guard let source = document.model.source(for: instance.sourceID) else { return [here] }
                let inner = relationshipEndpoints(in: source.children,
                                                  chain: chain + [node.id],
                                                  depth: depth + 1)
                    .filter { $0.roleLabel != nil }
                return [here] + inner
            default:
                return [here]
            }
        }
    }

    // MARK: Participants (what can carry a relationship)

    /// Roled things reachable from `node`, as subjects. `node` itself when it has a
    /// role, plus every roled component nested inside it — which is what makes one
    /// tab inside a placed Tab Bar authorable even though it cannot be selected.
    private func participants(from node: Node, chain: [UUID] = [],
                              depth: Int = 0) -> [RelationshipParticipant] {
        guard depth < 8 else { return [] }
        var result: [RelationshipParticipant] = []
        let endpoint = RelationshipEndpoint(instanceChain: chain, nodeID: node.id)
        if let role = effectiveExportRole(of: node) {
            result.append(RelationshipParticipant(
                subject: endpoint,
                title: node.name.isEmpty ? "Layer" : node.name,
                subtitle: role.friendlyLabel,
                role: role,
                kinds: kinds(for: role, authored: authoredKinds(for: endpoint))))
        }
        switch node.content {
        case .group(let children):
            for child in children {
                result += participants(from: child, chain: chain, depth: depth + 1)
            }
        case .instance(let instance):
            guard let source = document.model.source(for: instance.sourceID) else { break }
            for child in source.children {
                result += participants(from: child, chain: chain + [node.id], depth: depth + 1)
            }
        default:
            break
        }
        return result
    }

    /// Kinds offered for a role, plus anything already authored so a role change
    /// never hides data that still needs removing or retargeting.
    private func kinds(for role: AriaRole?,
                       authored: Set<NodeRelationship.Kind>) -> [NodeRelationship.Kind] {
        let roleKinds = role?.authoredRelationshipKinds ?? []
        return NodeRelationship.Kind.allCases.filter { roleKinds.contains($0) || authored.contains($0) }
    }

    private func authoredKinds(for subject: RelationshipEndpoint) -> Set<NodeRelationship.Kind> {
        guard let anchor = relationshipAnchor else { return [] }
        return Set(anchor.stored.filter { $0.subject == subject }.map(\.kind))
    }

    // MARK: Reading + writing anchored relationships

    private func currentTarget(_ subject: RelationshipEndpoint,
                               _ kind: NodeRelationship.Kind) -> RelationshipEndpoint? {
        relationshipAnchor?.stored
            .first { $0.subject == subject && $0.kind == kind }?.target
    }

    /// Write one relationship onto the ANCHOR, never onto the subject.
    ///
    /// Storing it on the subject is what FEAT-012 exists to undo: a subject inside a
    /// component source is shared by every placement of that source, so the link
    /// would apply to all of them. The anchor contains both ends, so placing the
    /// anchor twice yields two independent, correctly-resolved copies.
    private func anchoredBinding(_ subject: RelationshipEndpoint,
                                 _ kind: NodeRelationship.Kind) -> Binding<RelationshipEndpoint?> {
        Binding(
            get: { currentTarget(subject, kind) },
            set: { target in
                guard let anchor = relationshipAnchor else { return }
                let action = "Set \(kind.label) Relationship"
                switch anchor {
                case .source(let source):
                    var model = document.model
                    guard let si = model.sources.firstIndex(where: { $0.id == source.id }) else { return }
                    model.sources[si].anchoredRelationships.removeAll {
                        $0.subject == subject && $0.kind == kind
                    }
                    if let target {
                        model.sources[si].anchoredRelationships.append(
                            AnchoredRelationship(kind: kind, subject: subject, target: target))
                    }
                    document.setModel(model, undoManager: undoManager, actionName: action)
                case .group(let group):
                    mutateScopedNode(group.id, action: action) { node in
                        node.anchoredRelationships.removeAll {
                            $0.subject == subject && $0.kind == kind
                        }
                        if let target {
                            node.anchoredRelationships.append(
                                AnchoredRelationship(kind: kind, subject: subject, target: target))
                        }
                    }
                }
            }
        )
    }

    /// Document-space offset to subtract for display so a shape's X/Y read
    /// relative to its owning artboard (0 on the wall, and 0 in source scope).
    private func ownerOffset(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> CGFloat {
        guard case .document = scope,
              let node = selectedNode,
              let owner = document.model.owningArtboard(
                of: node.frame, on: app.activeCanvasPageID) else { return 0 }
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
                        InspectorSectionTitle(title: "Layer", icon: nodeTypeIcon(node))
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
                    // Read the same live descendant/outline bounds the designer sees,
                    // rather than a stale structural group frame.
                    dimensions(
                        title: "",
                        x: groupMoveBinding(node, horizontal: true),
                        y: groupMoveBinding(node, horizontal: false),
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
                        x: outlinedNodeBinding(\.origin.x, action: "Move Shape"),
                        y: outlinedNodeBinding(\.origin.y, action: "Move Shape"),
                        w: outlinedNodeBinding(\.size.width, action: "Resize Shape"),
                        h: outlinedNodeBinding(\.size.height, action: "Resize Shape")
                    )
                }
                HStack(spacing: 4) {
                    Text("R").foregroundStyle(EXPColor.textSecondary)
                        .frame(width: 14, alignment: .leading)
                        .accessibilityHidden(true)
                    TextField("", value: nodeRotationBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 64)
                        .numericStepping(nodeRotationBinding)
                        .expFieldTip("Rotation", "Layer rotation in degrees. Values wrap through 0–359.")
                        .accessibilityLabel("Rotation")
                    Text("°").foregroundStyle(EXPColor.textSecondary)
                        .accessibilityHidden(true)
                    Spacer()
                    Text("Opacity").foregroundStyle(EXPColor.textSecondary)
                        .accessibilityHidden(true)
                    TextField("", value: nodeOpacityBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 48)
                        .numericStepping(nodeOpacityBinding, min: 0, max: 100)
                        .expFieldTip("Opacity", "Layer opacity, from 0% transparent to 100% opaque.")
                        .accessibilityLabel("Layer opacity")
                    Text("%").foregroundStyle(EXPColor.textSecondary)
                        .accessibilityHidden(true)
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
                flipControls(multiple: false)
                if case .group = node.content {
                    Divider()
                    autoLayoutControls()
                    Divider()
                    autoPaddingControls()
                    // With Auto Padding on, the group's own background lives in
                    // the section directly above — a second Fill/Stroke pair here
                    // would not just repeat it, it would ALSO recolor every layer
                    // inside (these controls recurse), which is not what a control
                    // sitting under "Auto Padding" reads as.
                    //
                    // Type is dropped for a group entirely. The font menu's label
                    // is a fixed "Font" (it has no single value to show for a
                    // mixed selection), so on one group it looked like a control
                    // that never responded. Changing a typeface is an edit you
                    // make on the text layers themselves.
                    multiStyleControls(includeType: false,
                                       includeFillAndStroke: node.autoPadding == nil)
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
                if inspectorCanConvertToPath || inspectorCanOutlineStroke {
                    Divider()
                    vectorOperationsControls()
                }
                Divider()
                alignControls()
                Divider()
                effectsControls()
                relationshipControls()
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
                // FEAT-044: flipping several layers at once was only reachable from
                // the Object menu and the right-click menu, so the panel quietly
                // implied it was a single-layer action.
                flipControls(multiple: true)
                // Font / fill / stroke applied to EVERY selected layer at once.
                multiStyleControls()
                if inspectorCanConvertToPath || inspectorCanOutlineStroke || inspectorCanPathfinder {
                    Divider()
                    vectorOperationsControls()
                }
                Divider()
                alignControls()
            } else if app.selectedArtboardIDs.count > 1 {
                Text("\(app.selectedArtboardIDs.count) artboards selected")
                    .foregroundStyle(EXPColor.textSecondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Divider()
                alignControls(.artboards)
            } else if selectedArtboard != nil {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorSectionTitle(title: "Artboard", icon: "rectangle.dashed")
                    TextField("Name", text: artboardNameBinding)
                        .textFieldStyle(.exp)
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 8) {
                        DimField(label: "X", value: artboardBinding(\.origin.x, action: "Move Artboard"))
                        DimField(label: "Y", value: artboardBinding(\.origin.y, action: "Move Artboard"))
                    }
                    HStack(spacing: 8) {
                        DimField(label: "W", value: artboardBinding(\.size.width, action: "Resize Artboard"), min: 0)
                        DimField(label: "H", value: artboardBinding(\.size.height, action: "Resize Artboard"), min: 0)
                    }
                    Divider()
                    PaintWell(label: "Background", paint: artboardBackgroundBinding,
                              supportsOpacity: false,
                              gradientSize: selectedArtboard?.frame.size,
                              selectedGradientStopID: gradientStopSelection)
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
                .accessibilityLabel("Zoom presets")
            }
            HStack(spacing: 8) {
                Button { app.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless).help("Zoom out (⌘-)")
                    .accessibilityLabel("Zoom out")
                Slider(value: zoomSliderBinding, in: 0...1)
                    .accessibilityLabel("Zoom")
                Button { app.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless).help("Zoom in (⌘+)")
                    .accessibilityLabel("Zoom in")
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
                DimField(label: "W", value: w, min: 0)
                DimField(label: "H", value: h, min: 0)
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

    /// Inspector geometry for a single layer uses the painted OUTSIDE edge of
    /// its outline. Inside strokes leave the frame unchanged; centered/outside
    /// strokes expand X/Y/W/H by their actual reach. Shadows remain effects and
    /// are intentionally excluded from object dimensions.
    private func outlinedNodeBinding(_ keyPath: WritableKeyPath<CGRect, CGFloat>,
                                     action: String) -> Binding<Double> {
        Binding(
            get: {
                guard let node = selectedNode else { return 0 }
                let outset = SelectionTransform.strokeOutset(for: node.content)
                let outer = node.frame.insetBy(dx: -outset, dy: -outset)
                return Double(outer[keyPath: keyPath] - ownerOffset(keyPath))
            },
            set: { newValue in
                guard let id = app.singleSelectedNodeID else { return }
                let owner = ownerOffset(keyPath)
                mutateScopedNode(id, action: action) { node in
                    let outset = SelectionTransform.strokeOutset(for: node.content)
                    let value = CGFloat(newValue) + owner
                    switch keyPath {
                    case \CGRect.origin.x:    node.frame.origin.x = value + outset
                    case \CGRect.origin.y:    node.frame.origin.y = value + outset
                    case \CGRect.size.width:
                        let desired = max(1, CGFloat(newValue) - 2 * outset)
                        node = SelectionTransform.scaled(node, about: node.frame.origin,
                                                         sx: desired / max(1, node.frame.width), sy: 1)
                    case \CGRect.size.height:
                        let desired = max(1, CGFloat(newValue) - 2 * outset)
                        node = SelectionTransform.scaled(node, about: node.frame.origin,
                                                         sx: 1, sy: desired / max(1, node.frame.height))
                    default: break
                    }
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
                // Delta comes from the value BEFORE wrapping, so the turn actually
                // applied is exactly what was asked for; only the stored/displayed
                // value wraps. Matches `nodeRotationBinding` and the gradient angle:
                // type -45 and get 315, step down from 0 and get 359.
                let delta = newValue - app.pointSelectionRotation
                let wrapped = newValue.truncatingRemainder(dividingBy: 360)
                app.pointSelectionRotation = wrapped < 0 ? wrapped + 360 : wrapped
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

    /// Flip controls, shared by the single- and multi-selection inspectors.
    ///
    /// A single layer flips through the panel's own scoped mutation, which is what
    /// keeps it working inside a component-source editor. A MULTI-selection routes
    /// through the canvas action instead (per the project's command-dispatch rule),
    /// so every selected layer flips in ONE undo step using the same code the Object
    /// menu and the right-click menu already call.
    @ViewBuilder
    private func flipControls(multiple: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Flip").foregroundStyle(EXPColor.textSecondary)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
            Button {
                if multiple { _ = sendCanvasAction("flipHorizontalAction:") }
                else { flipSelectedLayer(horizontal: true) }
            } label: {
                Label("Horizontal", systemImage: "arrow.left.and.right")
            }
            .buttonStyle(.expCompact())
            .help(multiple ? "Flip every selected layer horizontally" : "Flip layer horizontally")
            .accessibilityLabel(multiple ? "Flip every selected layer horizontally"
                                         : "Flip layer horizontally")
            Button {
                if multiple { _ = sendCanvasAction("flipVerticalAction:") }
                else { flipSelectedLayer(horizontal: false) }
            } label: {
                Label("Vertical", systemImage: "arrow.up.and.down")
            }
            .buttonStyle(.expCompact())
            .help(multiple ? "Flip every selected layer vertically" : "Flip layer vertically")
            .accessibilityLabel(multiple ? "Flip every selected layer vertically"
                                         : "Flip layer vertically")
            Spacer(minLength: 0)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func flipSelectedLayer(horizontal: Bool) {
        guard let id = app.singleSelectedNodeID else { return }
        mutateScopedNode(id, action: horizontal ? "Flip Horizontal" : "Flip Vertical") { node in
            if horizontal { node.flipH.toggle() } else { node.flipV.toggle() }
        }
    }

    @ViewBuilder
    private func relationshipControls() -> some View {
        if let anchor = relationshipAnchor {
            let people = allParticipants(anchor)
            if !people.isEmpty {
                let targets = relationshipEndpoints(in: anchor.children)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    InspectorSectionTitle(
                        title: "Relationships",
                        icon: "point.3.connected.trianglepath.dotted",
                        helpBody: "Connect layers so assistive technology knows how they relate \u{2014} which layer gives another its name, which one explains it, and which one a control operates. Choices come from \u{201C}\(anchor.name)\u{201D}, and a connection is stored on it, so copying it copies the connections with it. Each one exports as an ARIA attribute; hover a field to see which.")

                    ForEach(people) { person in
                        relationshipGroup(person: person, targets: targets)
                    }

                    if case .document = scope, let node = selectedNode,
                       effectiveExportRole(of: node) == nil {
                        unroledSelectionNote()
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else if case .document = scope, selectedNode != nil {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    InspectorSectionTitle(title: "Relationships",
                                          icon: "point.3.connected.trianglepath.dotted")
                    unroledSelectionNote()
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        } else if case .document = scope, let node = selectedNode,
                  effectiveExportRole(of: node) != nil {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionTitle(title: "Relationships",
                                      icon: "point.3.connected.trianglepath.dotted")
                ungroupedNeighborhoodNote(node)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// Everything that can carry a relationship for the current selection.
    ///
    /// In SOURCE scope the component ROOT always comes first — the element carrying
    /// the role is the one hosting the instance, so it is the anchor itself, and it
    /// is not otherwise selectable from in here. Then the selection and any roled
    /// components nested inside it.
    private func allParticipants(_ anchor: RelationshipAnchor) -> [RelationshipParticipant] {
        var result: [RelationshipParticipant] = []
        if case .source(let source) = anchor {
            let subject = RelationshipEndpoint(nodeID: source.id)
            // NOT named `kinds` — that would shadow `kinds(for:authored:)` and the
            // compiler would try to call the local array as a function.
            let rootKinds = kinds(for: source.a11y.role,
                                  authored: authoredKinds(for: subject))
            if !rootKinds.isEmpty {
                result.append(RelationshipParticipant(
                    subject: subject,
                    title: "This component",
                    subtitle: componentRootSubtitle(source),
                    role: source.a11y.role,
                    kinds: rootKinds))
            }
        }
        if let node = selectedNode {
            result += participants(from: node)
        }
        return result
    }

    /// Caption for the component-root block, e.g. "Tab One — Tab Panel". Naming the
    /// component AND its role makes it clear these fields belong to the component
    /// itself, not to whatever layer happens to be selected — which is the
    /// confusion BUG-008 was really about.
    private func componentRootSubtitle(_ source: ComponentSource) -> String {
        if let role = source.a11y.role {
            return "\(source.name) \u{2014} \(role.friendlyLabel)"
        }
        return source.name
    }

    /// One labelled block of relationship rows for a single participant.
    @ViewBuilder
    private func relationshipGroup(person: RelationshipParticipant,
                                   targets: [RelationshipTarget]) -> some View {
        // A subject nested inside a placed component cannot be selected on the
        // canvas, so it can never point at ITSELF by accident — but it can still
        // appear in its own target list, which would be nonsense. Filter it here
        // rather than at the source, so the same list serves every participant.
        let choices = targets.filter { $0.endpoint != person.subject }
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(person.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EXPColor.textSecondary)
                Text(person.subtitle)
                    .font(.caption)
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)

            ForEach(person.kinds, id: \.self) { kind in
                let label = kind.friendlyLabel(for: person.role)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(label)
                        .foregroundStyle(EXPColor.textSecondary)
                        .frame(width: 110, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker(label, selection: anchoredBinding(person.subject, kind)) {
                        Text("None").tag(RelationshipEndpoint?.none)
                        // An end that no longer resolves stays SELECTABLE rather than
                        // vanishing, so a broken link can be seen and fixed instead of
                        // being silently swapped to None the next time this renders.
                        if let missing = currentTarget(person.subject, kind),
                           !choices.contains(where: { $0.endpoint == missing }) {
                            Text("Missing layer").tag(RelationshipEndpoint?.some(missing))
                        }
                        ForEach(choices) { target in
                            Label(target.display, systemImage: target.icon)
                                .tag(RelationshipEndpoint?.some(target.endpoint))
                        }
                    }
                    .labelsHidden()
                    .expFieldTip(label, kind.friendlyHelp(for: person.role))
                    // VoiceOver gets the plain-language name AND the attribute, so
                    // the mapping is available without reading it off the screen.
                    .accessibilityLabel("\(person.title): \(label)")
                    .accessibilityHint(kind.friendlyHelp(for: person.role))

                    // Two copies of the same component read IDENTICALLY in the
                    // picker, so a name cannot tell you WHICH one a link points at.
                    // This selects it, which can.
                    if let target = currentTarget(person.subject, kind) {
                        Button { revealEndpoint(target) } label: {
                            Image(systemName: "scope")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(EXPColor.textTertiary)
                        .help("Select what this points at")
                        .accessibilityLabel("Select the target of \(label)")
                    }
                }
            }
        }
    }

    /// Select whatever an endpoint points at, so a link can be VERIFIED rather than
    /// taken on trust. Two placements of the same component are indistinguishable by
    /// name, which makes this the only way to tell them apart.
    ///
    /// A layer nested inside a component is not selectable — it exists once per
    /// placement — so this selects the outermost PLACED thing on the path, which is
    /// the closest the canvas can get to "show me what this points at."
    private func revealEndpoint(_ endpoint: RelationshipEndpoint) {
        let id = endpoint.instanceChain.first ?? endpoint.nodeID
        app.selectedNodeIDs = [id]
    }

    /// Shown when a layer COULD carry relationships but is not inside a group, so
    /// there is nothing in scope to point at.
    ///
    /// Deliberately an INSTRUCTION rather than an empty dropdown or a disabled
    /// control. The rule is "connect things that live in a group together," and
    /// saying it once, here, teaches it better than a blank picker does. Grouping
    /// is also what the designer wants regardless — a tab that can drift away from
    /// its panel on the canvas is a bug waiting to happen — and it is what keeps
    /// the target list short enough to be usable by keyboard and screen reader,
    /// which a whole-artboard list would not be.
    @ViewBuilder
    private func ungroupedNeighborhoodNote(_ node: Node) -> some View {
        Label("Group this with the layers it connects to (\u{2318}G), then choose a target here. Connections are stored on the group, so the pieces travel together and the list stays short.",
              systemImage: "square.on.square.dashed")
            .font(.caption)
            .foregroundStyle(EXPColor.textSecondary)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shown when the selected layer itself has no role. Says the honest thing:
    /// roles live on components, so this layer has nothing to carry a connection —
    /// while anything roled INSIDE it is still offered above.
    @ViewBuilder
    private func unroledSelectionNote() -> some View {
        Label("This layer has no role of its own, so it exports as a plain container and carries no connections. Give it a role by making it a component \u{2014} anything roled inside it can still be connected above.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(EXPColor.textTertiary)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: false, vertical: true)
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
                InspectorSectionTitle(title: "Auto Layout", icon: "lines.measurement.horizontal")
                Spacer()
                Toggle("", isOn: alEnabledBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .help("Stack the children in a row or column with spacing")
                    .accessibilityLabel("Auto Layout")
            }
            if let al = selectedAutoLayout {
                EXPSegmented(selection: alDirectionBinding, segments: [
                    .init(value: .horizontal, icon: "arrow.right",
                          accessibilityLabel: "Horizontal layout", help: "Horizontal layout"),
                    .init(value: .vertical, icon: "arrow.down",
                          accessibilityLabel: "Vertical layout", help: "Vertical layout"),
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
                            .accessibilityLabel("Gap between items")
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
    private var apStrokeAlignmentBinding: Binding<StrokeAlignment> {
        Binding(get: { selectedAutoPadding?.strokeAlignment ?? .center },
                set: { v in mutateAP("Frame Stroke Position") { $0.strokeAlignment = v } })
    }
    private var apStrokePatternBinding: Binding<StrokePattern> {
        Binding(get: { selectedAutoPadding?.strokePattern ?? .solid },
                set: { v in mutateAP("Frame Stroke Pattern") { $0.strokePattern = v } })
    }

    @ViewBuilder
    private func autoPaddingControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorSectionTitle(title: "Auto Padding", icon: "rectangle.inset.filled")
                Spacer()
                Toggle("", isOn: apEnabledBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .help("Hug the children with padding and a background (button / tag / card)")
                    .accessibilityLabel("Auto Padding")
            }
            if selectedAutoPadding != nil {
                Text("Padding (content → background)").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                HStack(spacing: 4) {
                    apPadField("T", "Top padding", \.paddingTop)
                    apPadField("R", "Right padding", \.paddingRight)
                    apPadField("B", "Bottom padding", \.paddingBottom)
                    apPadField("L", "Left padding", \.paddingLeft)
                }
                Text("Margin (outside background)").font(.caption2).foregroundStyle(EXPColor.textSecondary)
                HStack(spacing: 4) {
                    apPadField("T", "Top margin", \.marginTop)
                    apPadField("R", "Right margin", \.marginRight)
                    apPadField("B", "Bottom margin", \.marginBottom)
                    apPadField("L", "Left margin", \.marginLeft)
                }
                PaintWell(label: "Fill", paint: apFillBinding,
                          gradientSize: selectedNode?.frame.size,
                          selectedGradientStopID: gradientStopSelection)
                HStack(spacing: 8) {
                    Text("Corner").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: apCornerBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 52).numericStepping(apCornerBinding, min: 0)
                        .accessibilityLabel("Background corner radius")
                    Spacer()
                    Text("Stroke").foregroundStyle(EXPColor.textSecondary)
                    ColorWell(label: "", color: apStrokeBinding)
                    TextField("", value: apStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 40).numericStepping(apStrokeWidthBinding, min: 0)
                        .accessibilityLabel("Background stroke width")
                }
                if (selectedAutoPadding?.strokeWidth ?? 0) > 0 {
                    EXPSegmented(selection: apStrokePatternBinding,
                                 segments: StrokePattern.allCases.map { .init(value: $0, label: $0.label) })
                        .help("Use a solid, dashed, or dotted group background border")
                        .accessibilityLabel("Border pattern: solid, dash, or dot")
                    HStack(spacing: 6) {
                        Text("Position").foregroundStyle(EXPColor.textSecondary)
                        EXPSegmented(selection: apStrokeAlignmentBinding, segments: [
                            .init(value: .inside, label: "Inside"),
                            .init(value: .center, label: "Middle"),
                            .init(value: .outside, label: "Outside"),
                        ])
                    }
                    .help("Place the group background outline inside, centered on, or outside its edge")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func apPadField(_ label: String, _ accessibilityLabel: String,
                            _ kp: WritableKeyPath<AutoPadding, CGFloat>) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(EXPColor.textSecondary).font(.caption2)
                .accessibilityHidden(true)
            TextField("", value: apPadBinding(kp), format: .number.precision(.fractionLength(0)))
                .labelsHidden().textFieldStyle(.exp)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .frame(width: 40).numericStepping(apPadBinding(kp), min: 0)
                .expFieldTip(accessibilityLabel)
                .accessibilityLabel(accessibilityLabel)
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

    /// X/Y for a group follows its live painted descendant union, matching the
    /// selection bounds even when an imported SVG's declared viewBox differs
    /// slightly from its actual paths.
    private func groupMoveBinding(_ node: Node, horizontal: Bool) -> Binding<Double> {
        Binding(
            get: {
                let bounds = SelectionTransform.paintedBounds(node)
                let keyPath: WritableKeyPath<CGRect, CGFloat> = horizontal ? \.origin.x : \.origin.y
                return Double(bounds[keyPath: keyPath] - ownerOffset(keyPath))
            },
            set: { value in
                let keyPath: WritableKeyPath<CGRect, CGFloat> = horizontal ? \.origin.x : \.origin.y
                let target = CGFloat(value) + ownerOffset(keyPath)
                mutateScopedNode(node.id, action: "Move Group") { current in
                    let bounds = SelectionTransform.paintedBounds(current)
                    if horizontal { current.frame.origin.x += target - bounds.minX }
                    else { current.frame.origin.y += target - bounds.minY }
                }
            }
        )
    }

    /// W/H for a single GROUP scales the group AND descendants while measuring
    /// against the painted outer bounds. A small binary solve accounts for fixed-
    /// width outlines, which do not themselves scale with the object geometry.
    private func groupSizeBinding(_ node: Node, width: Bool) -> Binding<Double> {
        Binding(
            get: {
                let bounds = SelectionTransform.paintedBounds(node)
                return Double(width ? bounds.width : bounds.height)
            },
            set: { v in
                mutateScopedNode(node.id, action: "Resize Group") { n in
                    let desired = max(1, CGFloat(v))
                    let original = n
                    let bounds = SelectionTransform.paintedBounds(original)
                    let anchor = bounds.origin
                    func scaled(_ factor: CGFloat) -> Node {
                        SelectionTransform.scaled(original, about: anchor,
                                                  sx: width ? factor : 1,
                                                  sy: width ? 1 : factor)
                    }
                    func measured(_ factor: CGFloat) -> CGFloat {
                        let b = SelectionTransform.paintedBounds(scaled(factor))
                        return width ? b.width : b.height
                    }
                    var low: CGFloat = 0.0001
                    var high = max(1, desired / max(1, width ? bounds.width : bounds.height) * 2)
                    while measured(high) < desired, high < 10_000 { high *= 2 }
                    for _ in 0..<32 {
                        let mid = (low + high) / 2
                        if measured(mid) < desired { low = mid } else { high = mid }
                    }
                    n = scaled((low + high) / 2)
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

    private var selectedResolvedNodes: [Node] {
        let roots = app.selectedNodeIDs
            .filter { !hasSelectedAncestorScoped($0) }
            .compactMap { findScopedNode($0) }
        return roots.flatMap(Self.flattenStyleTargets)
    }

    nonisolated private static func flattenStyleTargets(_ node: Node) -> [Node] {
        var result = [node]
        if case .group(let children) = node.content {
            result.append(contentsOf: children.flatMap(flattenStyleTargets))
        }
        return result
    }

    nonisolated private static func mutateStyleTargets(_ node: inout Node, _ change: (inout Node) -> Void) {
        change(&node)
        if case .group(var children) = node.content {
            for i in children.indices {
                mutateStyleTargets(&children[i], change)
            }
            node.content = .group(children: children)
        }
    }

    /// Apply a change to EVERY selected node (recursing into groups), one undo step.
    private func mutateAllSelected(_ action: String, _ change: @escaping (inout Node) -> Void) {
        let ids = app.selectedNodeIDs.filter { !hasSelectedAncestorScoped($0) }
        commitScoped(action) { nodes in
            for id in ids {
                _ = Self.mutateNestedNode(id, in: &nodes) { node in
                    Self.mutateStyleTargets(&node, change)
                }
            }
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
    private var multiStrokePattern: StrokePattern {
        for n in selectedResolvedNodes {
            switch n.content {
            case .rectangle(let s): return s.strokePattern
            case .ellipse(let s): return s.strokePattern
            case .polygon(let s): return s.strokePattern
            case .path(let s): return s.strokePattern
            case .line(let s): return s.strokePattern
            // A plain group has no stroke of its own. Keep walking to the first
            // stroked descendant; returning `.solid` here made the control lie
            // after its recursive setter had changed every child to Dash/Dot.
            case .group:
                if let pattern = n.autoPadding?.strokePattern { return pattern }
                continue
            default: continue
            }
        }
        return .solid
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
            case .group: return n.autoPadding != nil
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
            // Plain groups are containers, not stroked shapes. Their descendants
            // supply the representative value used by the segmented control.
            case .group:
                if let alignment = n.autoPadding?.strokeAlignment { return alignment }
                continue
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
                case .group:            if node.autoPadding != nil { node.autoPadding?.strokeAlignment = a }
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
    private var multiStrokePatternBinding: Binding<StrokePattern> {
        Binding(get: { multiStrokePattern }, set: { pattern in
            mutateAllSelected("Stroke Pattern") { node in
                switch node.content {
                case .rectangle(var s): s.strokePattern = pattern; node.content = .rectangle(s)
                case .ellipse(var s): s.strokePattern = pattern; node.content = .ellipse(s)
                case .polygon(var s): s.strokePattern = pattern; node.content = .polygon(s)
                case .path(var s): s.strokePattern = pattern; node.content = .path(s)
                case .line(var s): s.strokePattern = pattern; node.content = .line(s)
                case .group: if node.autoPadding != nil { node.autoPadding?.strokePattern = pattern }
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

    /// Font / fill / stroke applied to every selected layer AND everything inside
    /// it. `includeFillAndStroke: false` drops the paint sections for a single
    /// auto-padding group, whose background is already edited in its own section.
    /// `includeType: false` drops the font menu, which cannot display a value and
    /// so reads as broken when only one group is selected.
    @ViewBuilder
    private func multiStyleControls(includeType: Bool = true,
                                    includeFillAndStroke: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if includeType, multiAnyText {
                Divider()
                InspectorSectionTitle(title: "Type", icon: "textformat").padding(.top, 4)
                // A multi-selection has no single family, so the label stays fixed
                // and nothing is ticked — honest about there being no one answer.
                FontFamilyPicker(currentFamily: "Mixed", label: "Font",
                                 fontsUsed: { document.model.usedFontFamilies },
                                 onPick: { applyFontFamilyAll($0) },
                                 onPickSystem: { applyFontFamilyAll("") })
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
            if includeFillAndStroke, multiAnyFill {
                Divider()
                InspectorSectionTitle(title: "Fill", icon: "paintpalette").padding(.top, 4)
                PaintWell(label: "Fill", paint: multiFillBinding)
            }
            if includeFillAndStroke, multiAnyStroke {
                Divider()
                InspectorSectionTitle(title: "Stroke", icon: "pencil.line").padding(.top, 4)
                ColorWell(label: "Color", color: multiStrokeBinding)
                HStack(spacing: 8) {
                    Text("Width").foregroundStyle(EXPColor.textSecondary)
                    TextField("", value: multiStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().textFieldStyle(.exp).frame(width: 56)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .numericStepping(multiStrokeWidthBinding, min: 0)
                    Spacer()
                }
                EXPSegmented(selection: multiStrokePatternBinding,
                             segments: StrokePattern.allCases.map { .init(value: $0, label: $0.label) })
                    .help("Apply a solid, dashed, or dotted stroke to the selected layers")
                    .accessibilityLabel("Stroke pattern: solid, dash, or dot")
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

    /// The exact selected nodes, without recursively treating a selected group's
    /// children as separately selected. That distinction matters to Pathfinder:
    /// operating on one child must never silently consume its whole group.
    private var inspectorSelectedNodes: [Node] {
        app.selectedNodeIDs.compactMap(findScopedNode)
    }

    private var inspectorCanConvertToPath: Bool {
        inspectorSelectedSubtreesContain { node in
            switch node.content {
            case .rectangle, .ellipse, .polygon, .line: return true
            default: return false
            }
        }
    }

    private var inspectorCanOutlineStroke: Bool {
        inspectorSelectedSubtreesContain { VectorPathGeometry.stroke(from: $0.content) != nil }
    }

    private func inspectorSelectedSubtreesContain(_ predicate: (Node) -> Bool) -> Bool {
        func scan(_ node: Node) -> Bool {
            if predicate(node) { return true }
            if case .group(let children) = node.content { return children.contains(where: scan) }
            return false
        }
        return inspectorSelectedNodes.contains(where: scan)
    }

    private var inspectorCanPathfinder: Bool {
        inspectorSelectedNodes.count >= 2
            && inspectorSelectedNodes.count == app.selectedNodeIDs.count
            && inspectorSelectedNodes.allSatisfy { VectorPathGeometry.isClosedVector($0.content) }
    }

    @ViewBuilder private func vectorOperationsControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionTitle(title: "Vector", icon: "point.3.connected.trianglepath.dotted")
                .padding(.top, 4)

            if inspectorCanConvertToPath || inspectorCanOutlineStroke {
                HStack(spacing: 6) {
                    if inspectorCanConvertToPath {
                        vectorTextButton("Convert to Path", selector: "convertToPathAction:")
                    }
                    if inspectorCanOutlineStroke {
                        vectorTextButton("Outline Stroke", selector: "outlineStrokeAction:")
                    }
                }
            }

            if inspectorCanPathfinder {
                Text("Pathfinder")
                    .font(.callout)
                    .foregroundStyle(EXPColor.textSecondary)
                HStack(spacing: 6) {
                    vectorTextButton("Unite", selector: "pathfinderUniteAction:")
                    vectorTextButton("Subtract", selector: "pathfinderSubtractAction:")
                }
                HStack(spacing: 6) {
                    vectorTextButton("Intersect", selector: "pathfinderIntersectAction:")
                    vectorTextButton("Exclude", selector: "pathfinderExcludeAction:")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vectorTextButton(_ title: String, selector: String) -> some View {
        Button(title) { sendCanvasAction(selector) }
            .buttonStyle(.exp(.secondary))
            .frame(maxWidth: .infinity)
            .accessibilityHint("Applies \(title.lowercased()) to the current selection")
    }

    /// What the Align section is pointed at. The BUTTONS and the selectors behind
    /// them are identical either way — CanvasNSView routes one align command by
    /// selection — this only changes which count gates them and whether the
    /// node-only "To" scope row appears.
    enum AlignSubject { case nodes, artboards }

    @ViewBuilder private func alignControls(_ subject: AlignSubject = .nodes) -> some View {
        let count = subject == .artboards ? app.selectedArtboardIDs.count : app.selectedNodeIDs.count
        let alignOK = subject == .artboards ? count >= 2 : (count >= 2 || app.alignTarget == .artboard)
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionTitle(title: "Align", icon: "align.horizontal.left").padding(.top, 4)

            // "Relative to" scope on its own labeled row — a segmented control, so
            // it reads as a mode toggle and can't be confused with the icon buttons.
            // Omitted for boards: a board has no enclosing board to align to, and a
            // dead mode toggle is worse than no toggle.
            if subject == .nodes {
                HStack(spacing: 8) {
                    Text("To").foregroundStyle(EXPColor.textSecondary)
                    EXPSegmented(selection: alignTargetBinding, segments: [
                        .init(value: .selection, label: "Selection"),
                        .init(value: .artboard, label: "Artboard"),
                    ])
                    .help("Align relative to the selection's bounds or the artboard")
                }
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

            // Clean Up is a different idea from aligning things to each other, so it
            // sits apart — and it only exists for boards.
            if subject == .artboards {
                Divider()
                HStack(spacing: 6) {
                    Button("Clean Up") { sendCanvasAction("cleanUpArtboardsAction:") }
                        .buttonStyle(.exp(.secondary))
                        .disabled(count < 2)
                        .help("Tidy the selected artboards into even rows, keeping their rough placement and order")
                    Spacer()
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alignOpButton(_ symbol: String, _ help: String, _ selector: String, enabled: Bool = true) -> some View {
        InspectorIconButton(symbol: symbol, accessibilityLabel: help, enabled: enabled) {
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
            InspectorSectionTitle(title: "Grid", icon: "grid")
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
            Toggle("Snap to whole pixels",
                   isOn: Binding(get: { app.pixelSnap }, set: { app.pixelSnap = $0 }))
                .help("Off lets moves and resizes land on fractional values. Hold \u{2318} during a drag to bypass snapping either way.")
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
                InspectorSectionTitle(title: "Layout Grids", icon: "square.grid.3x3").padding(.top, 4)

                Spacer()
                Menu {
                    Button("Columns") { addLayoutGrid(.columns) }
                    Button("Rows") { addLayoutGrid(.rows) }
                    Button("Baseline") { addLayoutGrid(.baseline) }
                } label: { Image(systemName: "plus.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("Add a layout grid")
                    .accessibilityLabel("Add layout grid")
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
                    .accessibilityLabel("Show layout grid")
                Picker("", selection: lgKind(idx)) {
                    Text("Columns").tag(LayoutGrid.Kind.columns)
                    Text("Rows").tag(LayoutGrid.Kind.rows)
                    Text("Baseline").tag(LayoutGrid.Kind.baseline)
                }.labelsHidden().frame(width: 96)
                    .accessibilityLabel("Layout grid type")
                ColorWell(label: "", color: lgColor(idx))
                Spacer()
                Button { removeLayoutGrid(grid.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Remove layout grid")
                    .accessibilityLabel("Remove layout grid")
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
              let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
              let ai = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }),
              document.model.pages[pageIndex].artboards[ai].layoutGrids.indices.contains(idx) else { return }
        var model = document.model
        change(&model.pages[pageIndex].artboards[ai].layoutGrids[idx])
        document.setModel(model, undoManager: undoManager, actionName: action)
    }
    private func addLayoutGrid(_ kind: LayoutGrid.Kind) {
        guard let id = app.selectedArtboardID,
              let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
              let ai = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }) else { return }
        var model = document.model
        model.pages[pageIndex].artboards[ai].layoutGrids.append(LayoutGrid(kind: kind))
        document.setModel(model, undoManager: undoManager, actionName: "Add Layout Grid")
    }
    private func removeLayoutGrid(_ gid: UUID) {
        guard let id = app.selectedArtboardID,
              let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
              let ai = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }) else { return }
        var model = document.model
        model.pages[pageIndex].artboards[ai].layoutGrids.removeAll { $0.id == gid }
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
                .accessibilityLabel("Layout grid \(label.lowercased())")
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
                .accessibilityLabel("Layout grid \(label.lowercased())")
        }
    }

    // MARK: Effects (drop / inner shadow) — applies to any node type

    /// BUG-034. Stage 2 closed the DROP SHADOW gap — every node type now previews
    /// spread — so this row is left carrying one case: INNER shadow spread on a
    /// shape with no analytic outline (polygon, path, text, group, line, instance).
    /// Where the canvas and the exported file disagree, say so — a preview that
    /// quietly differs from the export is the thing this tool exists to prevent.
    /// Text, not colour, carries the message (WCAG 2.1 AA §1.4.1), and it reuses
    /// the established tertiary caption token rather than introducing a new colour;
    /// that token's contrast was NOT re-measured for this change.
    @ViewBuilder
    private func spreadNotPreviewedNote() -> some View {
        Label("Inner shadow spread isn\u{2019}t previewed on this shape \u{2014} it needs a rectangle, ellipse or image outline. The value is kept and is applied in PNG export; SVG export drops inner-shadow spread on every shape.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(EXPColor.textTertiary)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func effectsControls() -> some View {
        let effects = selectedNode?.effects ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorSectionTitle(title: "Effects", icon: "sparkles")
                Spacer()
                Menu {
                    Button("Drop Shadow") { addEffect(.dropShadow) }
                    Button("Inner Shadow") { addEffect(.innerShadow) }
                    Button("Layer Blur") { addEffect(.layerBlur) }
                    Button("Noise") { addEffect(.noise) }
                    Button("Dissolve") { addEffect(.dissolve) }
                    // Background Blur intentionally omitted — disabled for performance
                    // (see CanvasNSView.backgroundBlurEnabled). Re-add when reworked.
                } label: { Image(systemName: "plus.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Add an effect")
                    .accessibilityLabel("Add effect")
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
        .onAppear { selectFirstEffectIfNeeded(effects) }
        .onChange(of: selectedNode?.id) { _, _ in selectFirstEffectIfNeeded(effects) }
    }

    @ViewBuilder private func effectRow(idx: Int, effect: Effect) -> some View {
        let isCollapsed = collapsedEffectIDs.contains(effect.id)
        let kindName = effectKindName(effect.kind)
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    setEffectCollapsed(effect.id, !isCollapsed)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .expFieldTip(isCollapsed ? "Expand effect" : "Collapse effect")
                .accessibilityLabel(isCollapsed ? "Expand \(kindName)" : "Collapse \(kindName)")
                .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
                Toggle("", isOn: effectEnabledBinding(idx)).labelsHidden().toggleStyle(.checkbox)
                    .expFieldTip("Enable effect",
                                 "Temporarily turn the effect off without losing its settings.")
                    .accessibilityLabel("Enable \(kindName) effect")
                Picker("", selection: effectKindBinding(idx)) {
                    Text("Drop").tag(Effect.Kind.dropShadow)
                    Text("Inner").tag(Effect.Kind.innerShadow)
                    Text("Blur").tag(Effect.Kind.layerBlur)
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
                    .accessibilityLabel("Effect type")
                // Only the shadows have a color; blur samples the backdrop and
                // noise/dissolve are procedural grain.
                if isCollapsed {
                    Button {
                        setEffectCollapsed(effect.id, false)
                    } label: {
                        Text(effectSummary(effect))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(EXPColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .expFieldTip("Expand effect settings",
                                 "\(kindName): \(effectSummary(effect)). Click to edit all settings.")
                    .accessibilityLabel("\(kindName) settings: \(effectSummary(effect)). Expand effect")
                } else if effect.kind == .dropShadow || effect.kind == .innerShadow {
                    ColorWell(label: "", color: effectColorBinding(idx))
                    Spacer()
                } else {
                    Spacer()
                }
                Menu {
                    Button("Duplicate Effect") { duplicateEffect(effect.id) }
                    Divider()
                    Button("Remove Effect", role: .destructive) { removeEffect(effect.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .expFieldTip("Effect actions",
                             "Duplicate makes an editable copy directly above this effect. Remove deletes this effect and its settings.",
                             align: .trailing)
                .accessibilityLabel("Actions for \(kindName) effect")
            }
            if !isCollapsed {
            if effect.kind == .dropShadow || effect.kind == .innerShadow {
                // Full labels above flexible fields: four fixed 40pt fields in one
                // line were the panel's worst label-crushing case.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible())], spacing: 6) {
                    effectAdvancedNum("Horizontal offset", idx, \.dx,
                                      tip: "Horizontal offset",
                                      tipDetail: "How far the shadow shifts horizontally, in pixels. Positive moves it right; negative moves it left.")
                    effectAdvancedNum("Vertical offset", idx, \.dy,
                                      tip: "Vertical offset",
                                      tipDetail: "How far the shadow shifts vertically, in pixels. Positive moves it down; negative moves it up.")
                    effectAdvancedNum("Blur radius", idx, \.blur, min: 0,
                                      tip: "Blur radius",
                                      tipDetail: "How soft the shadow's edge is, in pixels. 0 is a hard edge; larger values spread and fade it.")
                    effectAdvancedNum("Spread", idx, \.spread,
                                      tip: "Spread",
                                      tipDetail: "Grows (positive) or shrinks (negative) the shadow before blurring, in pixels. Previewed on canvas for rectangles, ellipses and images; on text, groups, lines and custom paths the canvas cannot draw it yet, but the value is kept and IS applied in SVG export.")
                }
                .font(.caption)
            } else {
                HStack(spacing: 4) {
                if effect.kind == .backgroundBlur {
                    effectNum("Amount", idx, \.blur, min: 0,
                              tip: "Blur amount",
                              tipDetail: "How strongly the backdrop behind the layer is blurred, in pixels.")
                } else if effect.kind == .layerBlur {
                    effectNum("Amount", idx, \.blur, min: 0,
                              tip: "Layer blur amount",
                              tipDetail: "How strongly this layer's own pixels are blurred. Maps directly to SVG feGaussianBlur standard deviation.")
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
                }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // BUG-034 Stage 1 — DISCLOSURE ONLY. Nothing stored changes and nothing
            // is suppressed in export; this row exists so the canvas never quietly
            // contradicts the exported SVG.
            if effect.kind == .dropShadow || effect.kind == .innerShadow,
               effect.spread != 0,
               let node = selectedNode,
               !EffectsRender.previewsSpread(node, kind: effect.kind) {
                spreadNotPreviewedNote()
            }
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
                        let freq = effectAdvancedNum(
                            "Frequency", idx, \.frequency,
                            min: 0.001, digits: 3, step: 0.01,
                            tip: "Frequency",
                            tipDetail: "How tightly the noise pattern repeats. **Higher** values make finer, denser grain; **lower** values make larger, softer blobs.\nMaps directly to SVG's baseFrequency. Use Option–Up/Down for 0.001 adjustments."
                        )
                        let oct = effectAdvancedIntNum(
                            "Octaves", idx, \.octaves, min: 1, max: 8,
                            tip: "Octaves",
                            tipDetail: "Layers of detail stacked onto the base noise, **1–8**. Each octave adds finer detail; more octaves look richer but render slower.\n1–3 covers most uses."
                        )
                        let seed = effectAdvancedIntNum(
                            "Seed", idx, \.seed, min: 0, max: 9999,
                            tip: "Random seed",
                            tipDetail: "The starting number for the random pattern, **0–9999**. The same seed always reproduces the exact same grain — change it for a different pattern with the same settings."
                        )
                        let dice = Button {
                            updateEffect(idx, action: "Shuffle Seed") { $0.seed = Int.random(in: 1...9999) }
                        } label: { Image(systemName: "die.face.5") }
                            .buttonStyle(.borderless)
                            .expFieldTip("New random seed",
                                         "Rolls a different random pattern without changing any other setting.")
                            .accessibilityLabel("Shuffle noise seed")
                        let mono = VStack(alignment: .leading, spacing: 3) {
                            Text("Color")
                                .foregroundStyle(EXPColor.textSecondary)
                                .accessibilityHidden(true)
                            Toggle("Monochrome", isOn: effectMonoBinding(idx))
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Monochrome noise")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .expFieldTip("Monochrome",
                                     "Grayscale grain. Turn off for independent red, green, and blue noise — a colorful, RGB-static look.")

                        // Two flexible columns give the values the room the panel
                        // already has. Labels sit above their controls, so widening
                        // the inspector widens the fields instead of only adding
                        // empty trailing space; narrow panels keep full labels too.
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                freq
                                oct
                            }
                            HStack(alignment: .bottom, spacing: 8) {
                                HStack(alignment: .bottom, spacing: 4) {
                                    seed
                                    dice
                                        .frame(height: EXPMetric.controlH)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if effect.kind == .noise { mono }
                            }
                        }
                        .font(.caption)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
        .padding(6)
        .background(app.selectedEffectID == effect.id ? EXPColor.rowActive
                    : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(app.selectedEffectID == effect.id ? EXPColor.accent : Color.clear,
                    lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .simultaneousGesture(TapGesture().onEnded { app.selectedEffectID = effect.id })
        .contextMenu {
            Button("Duplicate Effect") { duplicateEffect(effect.id) }
            Divider()
            Button("Remove Effect", role: .destructive) { removeEffect(effect.id) }
        }
        .animation(EXPMotion.fast, value: isCollapsed)
    }

    private func setEffectCollapsed(_ id: UUID, _ collapsed: Bool) {
        if collapsed { collapsedEffectIDs.insert(id) }
        else { collapsedEffectIDs.remove(id) }
    }

    private func effectKindName(_ kind: Effect.Kind) -> String {
        switch kind {
        case .dropShadow: return "Drop Shadow"
        case .innerShadow: return "Inner Shadow"
        case .layerBlur: return "Layer Blur"
        case .backgroundBlur: return "Background Blur"
        case .noise: return "Noise"
        case .dissolve: return "Dissolve"
        }
    }

    private func effectSummary(_ effect: Effect) -> String {
        switch effect.kind {
        case .dropShadow, .innerShadow:
            return "X \(compactEffectNumber(effect.dx)) · Y \(compactEffectNumber(effect.dy)) · Blur \(compactEffectNumber(effect.blur)) · Spread \(compactEffectNumber(effect.spread))"
        case .layerBlur, .backgroundBlur:
            return "\(compactEffectNumber(effect.blur)) px"
        case .noise:
            let texture = effect.turbulenceType == .fractalNoise ? "Fractal" : "Turbulent"
            let color = effect.monochrome ? "Mono" : "RGB"
            return "\(texture) · \(Int((effect.amount * 100).rounded()))% · \(effect.blend.label) · \(color)"
        case .dissolve:
            let texture = effect.turbulenceType == .fractalNoise ? "Fractal" : "Turbulent"
            return "\(texture) · \(Int((effect.amount * 100).rounded()))% gone · F \(compactEffectNumber(effect.frequency))"
        }
    }

    private func compactEffectNumber(_ value: CGFloat) -> String {
        let number = Double(value)
        if abs(number.rounded() - number) < 0.001 { return String(Int(number.rounded())) }
        return String(format: "%.2f", number)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
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

    /// Precision controls in the Noise/Dissolve accordion use the inspector's
    /// available width instead of inheriting the compact 40pt shadow-field layout.
    /// The visible label is hidden from accessibility because the field already has
    /// the full programmatic label; that keeps VoiceOver order concise after moving
    /// the label above the control.
    private func effectAdvancedNum(
        _ label: String, _ idx: Int, _ kp: WritableKeyPath<Effect, CGFloat>,
        min: Double? = nil, max: Double? = nil, digits: Int = 0, step: Double = 1,
        tip: String = "", tipDetail: String = ""
    ) -> some View {
        let b = effectNumBinding(idx, kp)
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .foregroundStyle(EXPColor.textSecondary)
                .accessibilityHidden(true)
            TextField("", value: b, format: .number.precision(.fractionLength(0...digits)))
                .textFieldStyle(.exp)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .numericStepping(b, min: min, max: max, step: step)
                .accessibilityLabel(tip.isEmpty ? label : tip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .expFieldTip(tip.isEmpty ? label : tip, tipDetail)
    }

    private func effectAdvancedIntNum(
        _ label: String, _ idx: Int, _ kp: WritableKeyPath<Effect, Int>,
        min: Double, max: Double,
        tip: String = "", tipDetail: String = ""
    ) -> some View {
        let b = Binding<Double>(
            get: { Double(effectAt(idx)?[keyPath: kp] ?? 0) },
            set: { v in updateEffect(idx, action: "Effect") {
                $0[keyPath: kp] = Int(Swift.min(max, Swift.max(min, v)))
            } }
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .foregroundStyle(EXPColor.textSecondary)
                .accessibilityHidden(true)
            TextField("", value: b, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.exp)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .numericStepping(b, min: min, max: max)
                .accessibilityLabel(tip.isEmpty ? label : tip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        var addedID: UUID?
        mutateScopedNode(id, action: "Add Effect") { node in
            var e = Effect(kind: kind)
            if kind == .innerShadow { e.color = RGBAColor(r: 0, g: 0, b: 0, a: 0.5) }
            if kind == .backgroundBlur { e.blur = 8 }   // visible by default; 0 = no-op
            if kind == .layerBlur { e.blur = 8 }
            if kind == .noise { e.blend = .overlay }    // classic grain-over-fill look
            if kind == .noise || kind == .dissolve { e.seed = Int.random(in: 1...9999) }
            node.effects.append(e)
            addedID = e.id
        }
        app.selectedEffectID = addedID
    }
    private func duplicateEffect(_ effectID: UUID) {
        guard let nodeID = app.singleSelectedNodeID else { return }
        var duplicateID: UUID?
        mutateScopedNode(nodeID, action: "Duplicate Effect") { node in
            guard let index = node.effects.firstIndex(where: { $0.id == effectID }) else { return }
            var copy = node.effects[index]
            copy.id = UUID()
            node.effects.insert(copy, at: index)
            duplicateID = copy.id
        }
        app.selectedEffectID = duplicateID
    }
    private func removeEffect(_ effectID: UUID) {
        guard let id = app.singleSelectedNodeID else { return }
        let nextID = selectedNode?.effects.first(where: { $0.id != effectID })?.id
        mutateScopedNode(id, action: "Remove Effect") { node in
            node.effects.removeAll { $0.id == effectID }
        }
        collapsedEffectIDs.remove(effectID)
        if app.selectedEffectID == effectID { app.selectedEffectID = nextID }
    }
    private func selectFirstEffectIfNeeded(_ effects: [Effect]) {
        if !effects.contains(where: { $0.id == app.selectedEffectID }) {
            app.selectedEffectID = effects.first?.id
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
                      let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
                      let i = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.pages[pageIndex].artboards[i].background = c
                document.setModel(model, undoManager: undoManager, actionName: "Artboard Background")
            }
        )
    }

    private var artboardNameBinding: Binding<String> {
        Binding(
            get: { selectedArtboard?.name ?? "" },
            set: { newValue in
                guard let id = app.selectedArtboardID,
                      let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
                      let i = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.pages[pageIndex].artboards[i].name = newValue
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
                      let pageIndex = document.model.pageIndex(for: app.activeCanvasPageID),
                      let i = document.model.pages[pageIndex].artboards.firstIndex(where: { $0.id == id }) else { return }
                var model = document.model
                model.pages[pageIndex].artboards[i].frame[keyPath: keyPath] = clamp(keyPath, CGFloat(newValue))
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
            InspectorSectionTitle(title: "Type", icon: "textformat").padding(.top, 2)

            // Typeface — families rendered in their own face. Labeled "Font" so it
            // isn't mistaken for the semantic Content role (now its own sub-section
            // below, near Case).
            HStack(spacing: 8) {
                Text("Font").foregroundStyle(EXPColor.textSecondary).font(.callout)
                FontFamilyPicker(currentFamily: currentFamilyForPicker,
                                 label: currentFamilyDisplay,
                                 fontsUsed: { document.model.usedFontFamilies },
                                 onPick: { setTextFamily($0) },
                                 onPickSystem: { setTextFontName("") })
                .help("Typeface (applies to the whole text, or the selection while editing)")
            }

            // Weight / style within the family — a Menu (not a Picker) so a
            // selection that isn't in the list never logs warnings / writes back.
            let faces = currentFaces
            if faces.count > 1 {
                HStack(spacing: 8) {
                    Text("Weight").foregroundStyle(EXPColor.textSecondary).font(.callout)
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
                        .expDropdownChrome()
                    }
                    .help("Weight / style")
                }
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
                        .numericStepping(lineHeightBinding, min: 0, step: lineHeightStep)
                }
                Spacer()
            }
            .help("Auto uses the selected font’s native line height. × is a font-size multiplier; px and em preserve fixed authored line boxes. Changing the unit converts the value so the text keeps the same line height — switching to Auto is the exception, since Auto is the font’s own value. Arrows step by 0.1 for × and em, 1 for px (Shift 10×, Option 0.1×).")
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
                EXPSegmented(selection: textCaseBinding, segments: [
                    .init(value: .none, label: "—", accessibilityLabel: "As typed", help: "As typed"),
                    .init(value: .upper, label: "AA", accessibilityLabel: "Uppercase", help: "Uppercase"),
                    .init(value: .lower, label: "aa", accessibilityLabel: "Lowercase", help: "Lowercase"),
                    .init(value: .title, label: "Aa", accessibilityLabel: "Capitalize each word", help: "Capitalize each word"),
                    .init(value: .sentence, label: "Ab.", accessibilityLabel: "Sentence case", help: "Sentence case"),
                ])
                .accessibilityHint("Changes display without changing the stored characters.")
                Spacer()
            }

            // FEAT-028 — stroke on LIVE text. Zero width means no stroke, so the
            // rest of the controls stay out of the way until the designer asks for
            // one. Inside alignment is deliberately absent: it cannot survive the
            // HTML round trip, and Convert to Outlines is the honest route when
            // exact stroke geometry matters.
            HStack(spacing: 6) {
                Text("Stroke").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: textStrokeWidthBinding,
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.exp)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .numericStepping(textStrokeWidthBinding, min: 0)
                    .accessibilityLabel("Text stroke width")
                    .accessibilityHint("Zero removes the stroke.")
                Text("px").foregroundStyle(EXPColor.textSecondary).font(.caption2)
                Spacer()
            }
            if (selectedTextContent?.strokeWidth ?? 0) > 0 {
                ColorWell(label: "Stroke color", color: textStrokeColorBinding)
                HStack(spacing: 6) {
                    Text("Align").foregroundStyle(EXPColor.textSecondary).font(.callout)
                    EXPSegmented(selection: textStrokeAlignmentBinding, segments: [
                        .init(value: TextStrokeAlignment.outside, label: "Outside",
                              accessibilityLabel: "Stroke outside the letterforms",
                              help: "Stroke sits behind the fill, so thick strokes do not eat the letterforms"),
                        .init(value: TextStrokeAlignment.center, label: "Center",
                              accessibilityLabel: "Stroke centred on the letterforms",
                              help: "Stroke straddles the outline, half inside and half outside"),
                    ])
                    Spacer()
                }
                Text("Stays editable text. In HTML handoff this exports as -webkit-text-stroke with paint-order; browsers before Chrome/Edge 123 draw it centred instead of behind the fill. Convert to Outlines for exact control.")
                    .font(.caption2)
                    .foregroundStyle(EXPColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Semantic page role for HTML handoff — its own sub-section, separated
            // from the visual type controls it used to sit atop. Kept away from the
            // Font menu because the two dropdowns were easy to confuse.
            Divider()
            HStack(spacing: 6) {
                Text("Content")
                    .foregroundStyle(EXPColor.textSecondary)
                    .font(.callout)
                Picker("", selection: contentRoleBinding) {
                    ForEach(TextContentRole.allCases, id: \.self) { role in
                        Text(role.friendlyLabel).tag(role)
                    }
                }
                .labelsHidden()
                .help("Semantic page role for HTML handoff; independent of the visual Type Style")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func alignButton(_ a: TextAlign, _ symbol: String) -> some View {
        let active = (selectedTextContent?.align ?? .left) == a
        let label: String = switch a {
        case .left: "Align text left"
        case .center: "Align text center"
        case .right: "Align text right"
        }
        return InspectorIconButton(symbol: symbol, accessibilityLabel: label, active: active) {
            updateTextContent(action: "Align", remeasure: false) { $0.align = a }
        }
        .help(label)
    }

    private var boxBinding: Binding<TextBox> {
        Binding(get: { selectedTextContent?.box ?? .auto },
                set: { b in updateTextContent(action: "Text Box", remeasure: b == .auto) { $0.box = b } })
    }
    private var lineHeightBinding: Binding<Double> {
        Binding(get: { Double(selectedTextContent?.lineHeight ?? 1.3) },
                set: { v in updateTextContent(action: "Line Height", remeasure: true) {
                    $0.lineHeight = max(0, CGFloat(v))
                    if $0.lineHeightUnit == .px || $0.lineHeightUnit == .em {
                        $0.centersFixedLineHeightLeading = true
                    }
                } })
    }
    private var lineHeightUnitBinding: Binding<LineHeightUnit> {
        Binding(get: { selectedTextContent?.lineHeightUnit ?? .auto },
                set: { u in updateTextContent(action: "Line Height Unit", remeasure: true) {
                    // Changing the UNIT must not change how the text looks. Convert
                    // the number into the new unit rather than reinterpreting it:
                    // 64px on large type is roughly 1.4×, and reading that "64" as a
                    // multiplier is a several-thousand-point line box.
                    //
                    // Switching TO Auto is the one case that can change the
                    // rendering, because Auto IS a value — the font's natural line
                    // height. The authored number is kept untouched there, so
                    // switching back off Auto lands on exactly what Auto was drawing.
                    let points = $0.renderedLineHeightPoints
                    $0.lineHeightUnit = u
                    let converted = $0.lineHeightValue(for: points, in: u)
                    // Round to the precision the stepper and the field work in, so
                    // the displayed 1.40 is not secretly 1.3999 when an arrow key
                    // steps from it.
                    $0.lineHeight = max(0, (converted * 1000).rounded() / 1000)
                    if u == .px || u == .em {
                        $0.centersFixedLineHeightLeading = true
                    }
                } })
    }

    /// Arrow-key step for the line-height field, matched to what the unit means.
    /// A multiplier lives between about 0.8 and 2, so whole-number steps are
    /// useless there; points are whole numbers in practice. The modifier
    /// relationship is the app-wide one — Shift is 10×, Option is 0.1× — so ×/em
    /// give 0.1 / 1.0 / 0.01 and px keeps 1 / 10 / 0.1.
    private var lineHeightStep: Double {
        switch selectedTextContent?.lineHeightUnit ?? .auto {
        case .multiple, .em: return 0.1
        case .px, .auto:     return 1
        }
    }
    private var trackingBinding: Binding<Double> {
        Binding(get: { Double(selectedTextContent?.tracking ?? 0) },
                set: { v in updateTextContent(action: "Letter Spacing", remeasure: true) { $0.tracking = CGFloat(v) } })
    }
    private var textStrokeWidthBinding: Binding<Double> {
        Binding(get: { Double(selectedTextContent?.strokeWidth ?? 0) },
                set: { w in updateTextContent(action: "Text Stroke", remeasure: false) {
                    $0.strokeWidth = max(0, CGFloat(w))
                } })
    }
    private var textStrokeColorBinding: Binding<RGBAColor> {
        Binding(get: { selectedTextContent?.strokeColor ?? .black },
                set: { c in updateTextContent(action: "Text Stroke Color", remeasure: false) {
                    $0.strokeColor = c
                } })
    }
    private var textStrokeAlignmentBinding: Binding<TextStrokeAlignment> {
        Binding(get: { selectedTextContent?.strokeAlignment ?? .outside },
                set: { a in updateTextContent(action: "Text Stroke Alignment", remeasure: false) {
                    $0.strokeAlignment = a
                } })
    }
    private var textCaseBinding: Binding<TextCase> {
        Binding(get: { selectedTextContent?.textCase ?? .none },
                set: { c in updateTextContent(action: "Text Case", remeasure: true) { $0.textCase = c } })
    }
    private var contentRoleBinding: Binding<TextContentRole> {
        Binding(get: { selectedTextContent?.contentRole ?? .plain },
                set: { role in
                    updateTextContent(action: "Text Content Role", remeasure: false) {
                        $0.contentRole = role
                    }
                })
    }

    private var selectedTextContent: TextContent? {
        if let node = selectedNode, case .text(let tc) = node.content { return tc }
        return nil
    }

    // While editing, the canvas publishes the SELECTION's style to `app.textSelection`
    // and these controls drive it; otherwise they act on the whole text node.
    private var isEditingText: Bool { app.applyTextStyle != nil || app.textSelection != nil }

    /// What the picker should TICK. `currentFamilyDisplay` says "System" for the
    /// default face, but the picker's system row is keyed on an EMPTY family — the
    /// same distinction the model makes, where `fontName == ""` means "no face
    /// chosen" rather than a family literally named System.
    private var currentFamilyForPicker: String {
        let shown = currentFamilyDisplay
        return shown == "System" ? "" : shown
    }

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
        app.rememberTextStyle(fontName: ps)
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
                    let size = max(1, CGFloat(v))
                    app.rememberTextStyle(fontSize: size)
                    if let applyTextStyle = app.applyTextStyle { applyTextStyle(.fontSize(size)) }
                    else { updateTextContent(action: "Font Size", remeasure: true) { $0.applyToAllRuns { $0.fontSize = size } } }
                })
    }
    private var colorBinding: Binding<RGBAColor> {
        Binding(get: { currentTextColor },
                set: { c in
                    app.rememberTextStyle(color: c)
                    if let applyTextStyle = app.applyTextStyle { applyTextStyle(.color(c)) }
                    else { updateTextContent(action: "Text Color", remeasure: false) { $0.applyToAllRuns { $0.color = c } } }
                })
    }
    private func setTextFontName(_ ps: String) { applyFontName(ps) }

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
            InspectorSectionTitle(title: "Stroke", icon: "pencil.line")
            HStack(spacing: 8) {
                Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: strokeWidthBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .numericStepping(strokeWidthBinding, min: 0)
                Spacer()
            }
            ColorWell(label: "Color", color: strokeColorBinding)
            EXPSegmented(selection: lineStrokePatternBinding,
                         segments: StrokePattern.allCases.map { .init(value: $0, label: $0.label) })
                .help("Use a solid, dashed, or dotted line")
                .accessibilityLabel("Line pattern: solid, dash, or dot")
            EXPSegmented(selection: lineStrokeCapBinding,
                         segments: StrokeLineCap.allCases.map { .init(value: $0, label: $0.label) })
                .help("Choose the cap used at exposed line ends")
                .accessibilityLabel("Line cap: flat, round, or square")
            if app.tool == .node, let endpoint = app.selectedStrokeEndpoint {
                strokeMarkerRow("\(endpoint.label) (selected)",
                                accessibilityLabel: "\(endpoint.label) marker",
                                selection: endpoint == .start
                                    ? lineStartMarkerBinding : lineEndMarkerBinding)
            } else {
                strokeMarkerRow("Start", accessibilityLabel: "Start marker",
                                selection: lineStartMarkerBinding)
                strokeMarkerRow("End", accessibilityLabel: "End marker",
                                selection: lineEndMarkerBinding)
            }
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
    private var lineStrokePatternBinding: Binding<StrokePattern> {
        Binding(get: { selectedLineShape?.strokePattern ?? .solid },
                set: { pattern in updateLineContent { $0.strokePattern = pattern } })
    }
    private var lineStrokeCapBinding: Binding<StrokeLineCap> {
        Binding(get: { selectedLineShape?.strokeCap ?? .round },
                set: { cap in updateLineContent { $0.strokeCap = cap } })
    }
    private var lineStartMarkerBinding: Binding<StrokeMarker> {
        Binding(get: { selectedLineShape?.startMarker ?? .none },
                set: { marker in updateLineContent { $0.startMarker = marker } })
    }
    private var lineEndMarkerBinding: Binding<StrokeMarker> {
        Binding(get: { selectedLineShape?.endMarker ?? .none },
                set: { marker in updateLineContent { $0.endMarker = marker } })
    }

    private func strokeMarkerRow(_ label: String, accessibilityLabel: String,
                                 selection: Binding<StrokeMarker>) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(EXPColor.textSecondary).font(.callout)
            Spacer()
            Picker(accessibilityLabel, selection: selection) {
                ForEach(StrokeMarker.allCases, id: \.self) { marker in
                    Text(marker.label).tag(marker)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(accessibilityLabel)
        }
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

    /// Two-way binding to the SELECTED instance's active state (nil = base). The
    /// setter routes through `updateSelectedInstance`, so the change is undoable
    /// and the stored frame re-hugs to the new state's resolved size.
    private func instanceStateBinding() -> Binding<UUID?> {
        Binding(
            get: { selectedInstanceContext?.instance.activeStateID },
            set: { newID in
                updateSelectedInstance("Change Component State") { $0.activeStateID = newID }
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
                InspectorSectionTitle(title: "Category", icon: "tag")
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

                // State picker (v1.6): which of the source's states THIS instance
                // shows on the canvas. Same undoable write as the canvas label-bar
                // chevron + right-click ▸ State (command-coverage: inspector path).
                // Only shown when the source actually defines states.
                if !ctx.source.states.isEmpty {
                    Divider()
                    InspectorSectionTitle(title: "State", icon: "square.filled.and.line.vertical.and.square")
                    Picker("Component state", selection: instanceStateBinding()) {
                        Text("default").tag(UUID?.none)
                        ForEach(ctx.source.states) { st in
                            Text(st.name).tag(UUID?.some(st.id))
                        }
                    }
                    .labelsHidden()
                    .help("Which of this component's states this instance shows on the canvas")
                }

                let targets = overridableTargets(ctx.source.children)
                // Hoisted out of the rows on purpose — see `resolvedTargetNodes`.
                let resolvedNodes = resolvedTargetNodes(targets, instance: ctx.instance)
                if !targets.isEmpty {
                    Divider()
                    InspectorSectionTitle(
                        title: "Overrides", icon: "arrow.left.arrow.right",
                        helpBody: "Change this placement's content without touching the component. Layers from a component nested inside this one are grouped under its name; editing one here affects only THIS placement.")

                    // Direct children first, then a block per nested component, so a
                    // list of same-named layers ("label", "label", "label") is
                    // readable instead of ambiguous.
                    ForEach(targets.filter { $0.componentName == nil }) { target in
                        overrideRow(target, instance: ctx.instance,
                                    resolved: resolvedNodes[target.id])
                    }
                    ForEach(nestedGroupNames(targets), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(EXPColor.textSecondary)
                            ForEach(targets.filter { $0.componentName == name }) { target in
                                overrideRow(target, instance: ctx.instance,
                                            resolved: resolvedNodes[target.id])
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    // Say WHY rather than showing a heading over nothing, which reads
                    // as broken. Owner hit exactly that on a component whose children
                    // are all components.
                    Divider()
                    InspectorSectionTitle(title: "Overrides", icon: "arrow.left.arrow.right")
                    Text("This component has no text or fills to override.")
                        .font(.caption)
                        .foregroundStyle(EXPColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// One overridable layer, and the nested-instance path that reaches it.
    private struct OverridableTarget: Identifiable {
        /// Nested instance node ids, outermost first. EMPTY means a direct child of
        /// the selected instance's own source — the flat case that already worked.
        let instancePath: [UUID]
        let node: Node
        /// Name of the nested component this came from, for grouping the rows.
        /// nil for the flat case, which needs no heading.
        let componentName: String?
        var id: [UUID] { instancePath + [node.id] }
    }

    /// Overridable leaves of a component source, recursing into groups AND into
    /// nested components (FEAT-017 chunk J-c).
    ///
    /// This used to stop dead at `.instance`, which is why a component built out of
    /// other components — a tab bar whose children are all tab components — showed
    /// an "Overrides" header with nothing under it. Nothing was broken; there was
    /// simply no way to address a layer one level further down. `instancePath` is
    /// that address, and it is the same path `NestedInstanceOverride` stores.
    ///
    /// Depth is capped for the same reason every other walk here is: a damaged or
    /// legacy document may already contain a cycle, and this must terminate.
    private func overridableTargets(_ nodes: [Node], path: [UUID] = [],
                                    componentName: String? = nil,
                                    depth: Int = 0) -> [OverridableTarget] {
        guard depth < 8 else { return [] }
        var out: [OverridableTarget] = []
        for n in nodes {
            switch n.content {
            case .text, .rectangle, .ellipse, .path:
                out.append(OverridableTarget(instancePath: path, node: n,
                                             componentName: componentName))
            case .group(let kids):
                // A frame with a background fill (a button surface) exposes that fill
                // as an override; then recurse for nested text/shape overrides.
                if n.autoPadding?.fill != nil {
                    out.append(OverridableTarget(instancePath: path, node: n,
                                                 componentName: componentName))
                }
                out.append(contentsOf: overridableTargets(kids, path: path,
                                                          componentName: componentName,
                                                          depth: depth + 1))
            case .instance(let nested):
                guard let source = document.model.source(for: nested.sourceID) else { break }
                // The nested component's own layers, addressed THROUGH this node.
                // Named by the layer rather than the source, because two tabs from
                // one component are told apart by their layer names, not by the
                // component they share.
                let label = n.name.isEmpty ? source.name : n.name
                out.append(contentsOf: overridableTargets(source.children,
                                                          path: path + [n.id],
                                                          componentName: label,
                                                          depth: depth + 1))
            default: break
            }
        }
        return out
    }

    /// The RESOLVED node behind each overridable target — what the canvas actually
    /// draws — keyed by the target's id.
    ///
    /// Without this the panel showed the RAW source value, which is wrong twice
    /// over: a nested instance usually carries its own overrides inside the parent
    /// source (the tab bar sets its three tabs to "one", "two", "three"), and an
    /// active state can change a value too. Both meant the field said one thing
    /// while the canvas said another. Owner's phrasing, and it is the right
    /// instinct: "the default text in there [should] match what is shown in the
    /// canvas."
    ///
    /// Resolved ONCE per body evaluation, by distinct PATH rather than per row.
    /// Resolving inside each row would be a computed property in a `ForEach`, which
    /// is exactly the shape that caused the ~6.2s inspector hangs in PERF rounds 8
    /// and 10 — see docs/PERF-LOG.md. Do not move this into `overrideRow`.
    private func resolvedTargetNodes(_ targets: [OverridableTarget],
                                     instance: ComponentInstance) -> [[UUID]: Node] {
        var result: [[UUID]: Node] = [:]
        func find(_ id: UUID, in nodes: [Node]) -> Node? {
            for node in nodes {
                if node.id == id { return node }
                if case .group(let children) = node.content,
                   let found = find(id, in: children) { return found }
            }
            return nil
        }
        // Group by path so each nested component is resolved once, not once per leaf.
        var byPath: [[UUID]: [OverridableTarget]] = [:]
        for target in targets { byPath[target.instancePath, default: []].append(target) }

        for (path, group) in byPath {
            var level = document.model.resolvedChildren(of: instance)
            var reachable = true
            for step in path {
                guard let host = find(step, in: level),
                      case .instance(let nested) = host.content else { reachable = false; break }
                level = document.model.resolvedChildren(of: nested)
            }
            guard reachable else { continue }
            for target in group {
                if let node = find(target.node.id, in: level) { result[target.id] = node }
            }
        }
        return result
    }

    // MARK: Nested override read / write (FEAT-017)

    private func nestedOverrideValue(_ target: OverridableTarget) -> InstanceOverride.Value? {
        selectedInstanceContext?.instance.nestedOverrides.last {
            $0.instancePath == target.instancePath && $0.targetNodeID == target.node.id
        }?.value
    }

    private func commitNestedText(_ target: OverridableTarget, _ newValue: String) {
        updateSelectedInstance("Override Text") { inst in
            inst.nestedOverrides.removeAll {
                $0.instancePath == target.instancePath
                    && $0.targetNodeID == target.node.id
                    && $0.value.textValue != nil
            }
            inst.nestedOverrides.append(
                NestedInstanceOverride(instancePath: target.instancePath,
                                       targetNodeID: target.node.id,
                                       value: .text(newValue)))
        }
    }

    private func nestedFillBinding(_ target: OverridableTarget,
                                   sourceFill: Paint) -> Binding<Paint> {
        Binding(
            get: { nestedOverrideValue(target)?.fillValue ?? sourceFill },
            set: { newValue in
                updateSelectedInstance("Override Fill") { inst in
                    inst.nestedOverrides.removeAll {
                        $0.instancePath == target.instancePath
                            && $0.targetNodeID == target.node.id
                            && $0.value.fillValue != nil
                    }
                    inst.nestedOverrides.append(
                        NestedInstanceOverride(instancePath: target.instancePath,
                                               targetNodeID: target.node.id,
                                               value: .fill(newValue)))
                }
            }
        )
    }

    /// Reset is the ABSENCE of an override — drop the entry and resolution falls
    /// back to the nearest source value on its own. No separate restore path to
    /// keep in step with the setters.
    private func resetNestedOverride(_ target: OverridableTarget) {
        updateSelectedInstance("Reset Override") { inst in
            inst.nestedOverrides.removeAll {
                $0.instancePath == target.instancePath && $0.targetNodeID == target.node.id
            }
        }
    }

    /// Nested component names in first-seen order, so the blocks follow the
    /// component's own layer order rather than an alphabetical shuffle.
    private func nestedGroupNames(_ targets: [OverridableTarget]) -> [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for target in targets {
            guard let name = target.componentName else { continue }
            if seen.insert(name).inserted { order.append(name) }
        }
        return order
    }

    /// One override row. The FLAT case keeps its existing bindings untouched; only
    /// a nested target routes through `nestedOverrides`, so nothing that already
    /// worked changes shape.
    /// One override row.
    ///
    /// `resolved` is the node as the CANVAS draws it — already carrying any
    /// override baked into the parent source, any active state, and this
    /// placement's own override. Showing that instead of the raw source value is
    /// what makes the field agree with the canvas. The stored entry is still what
    /// decides `hasOverride`, so the reset affordance stays exact: the displayed
    /// value and the question "has this been changed HERE" are genuinely different
    /// questions and must not be answered from the same place.
    @ViewBuilder
    private func overrideRow(_ target: OverridableTarget,
                             instance: ComponentInstance,
                             resolved: Node?) -> some View {
        let nested = !target.instancePath.isEmpty
        let shown = resolved ?? target.node
        switch target.node.content {
        case .text:
            let fallback: String = {
                if case .text(let tc) = shown.content { return tc.plainString }
                if case .text(let tc) = target.node.content { return tc.plainString }
                return ""
            }()
            let hasOverride = nested
                ? nestedOverrideValue(target)?.textValue != nil
                : instance.textOverride(for: target.node.id) != nil
            InstanceTextRow(
                name: target.node.name,
                current: fallback,
                hasOverride: hasOverride,
                onCommit: { newValue in
                    nested ? commitNestedText(target, newValue)
                           : commitTextOverride(target.node.id, newValue)
                },
                onReset: {
                    nested ? resetNestedOverride(target)
                           : resetOverride(target.node.id)
                })
        case .rectangle:
            if case .rectangle(let shape) = shown.content {
                overrideFillRow(target, sourceFill: shape.fill, instance: instance)
            }
        case .ellipse:
            if case .ellipse(let shape) = shown.content {
                overrideFillRow(target, sourceFill: shape.fill, instance: instance)
            }
        case .path:
            if case .path(let shape) = shown.content {
                overrideFillRow(target, sourceFill: shape.fill, instance: instance)
            }
        case .group:
            if let fill = shown.autoPadding?.fill ?? target.node.autoPadding?.fill {
                overrideFillRow(target, sourceFill: fill, instance: instance)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func overrideFillRow(_ target: OverridableTarget, sourceFill: Paint,
                                 instance: ComponentInstance) -> some View {
        if target.instancePath.isEmpty {
            fillOverrideRow(child: target.node, sourceFill: sourceFill, instance: instance)
        } else {
            HStack {
                PaintWell(label: target.node.name,
                          paint: nestedFillBinding(target, sourceFill: sourceFill))
                if nestedOverrideValue(target)?.fillValue != nil {
                    Button { resetNestedOverride(target) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to source")
                }
            }
        }
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
            PaintWell(label: "Fill", paint: shapeFillBinding,
                      gradientSize: selectedNode?.frame.size,
                      selectedGradientStopID: gradientStopSelection)
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
            InspectorSectionTitle(title: "Stroke", icon: "pencil.line")
            ColorWell(label: "Color", color: shapeStrokeBinding)
            HStack(spacing: 8) {
                Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                TextField("", value: strokeWidthShapeBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.exp).frame(width: 56).multilineTextAlignment(.trailing)
                    .numericStepping(strokeWidthShapeBinding, min: 0)
                Spacer()
            }
            EXPSegmented(selection: shapeStrokePatternBinding,
                         segments: StrokePattern.allCases.map { .init(value: $0, label: $0.label) })
                .help("Use a solid, dashed, or dotted shape border")
                .accessibilityLabel("Border pattern: solid, dash, or dot")
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
    private var shapeStrokePattern: StrokePattern {
        guard let content = selectedNode?.content else { return .solid }
        switch content {
        case .rectangle(let s): return s.strokePattern
        case .ellipse(let s): return s.strokePattern
        case .polygon(let s): return s.strokePattern
        default: return .solid
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
    private var shapeStrokePatternBinding: Binding<StrokePattern> {
        Binding(get: { shapeStrokePattern },
                set: { value in updateShape("Stroke Pattern") { $0.strokePattern = value } })
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
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth,
                                       strokePattern: s.strokePattern)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth; s.strokePattern = style.strokePattern
                node.content = .rectangle(s)
            case .ellipse(var s):
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth,
                                       strokePattern: s.strokePattern)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth; s.strokePattern = style.strokePattern
                node.content = .ellipse(s)
            case .polygon(var s):
                var style = ShapeStyle(fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth,
                                       strokePattern: s.strokePattern)
                change(&style)
                s.fill = style.fill; s.stroke = style.stroke; s.strokeWidth = style.strokeWidth; s.strokePattern = style.strokePattern
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
    var strokePattern: StrokePattern
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
                        InspectorSectionTitle(
                            title: app.selectedPointCount == 1 ? "1 point selected" : "\(app.selectedPointCount) points selected",
                            icon: "point.3.connected.trianglepath.dotted")
                        Spacer()
                        Text("R").foregroundStyle(EXPColor.textSecondary)
                            .accessibilityHidden(true)
                        TextField("", value: pointRotationBinding, format: .number.precision(.fractionLength(0)))
                            .labelsHidden().textFieldStyle(.exp)
                            .multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(width: 56)
                            .numericStepping(pointRotationBinding)
                            .expFieldTip("Point selection rotation",
                                         "Rotates the selected path points together, in degrees.")
                            .accessibilityLabel("Point selection rotation")
                        Text("°").foregroundStyle(EXPColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .font(.callout)
                }
                Divider()
                Toggle("Closed", isOn: pathClosedBinding)
                    .font(.callout)
                if ps.closed {
                    PaintWell(label: "Fill", paint: pathFillBinding,
                              gradientSize: selectedNode?.frame.size,
                              selectedGradientStopID: gradientStopSelection)
                }
                Divider()
                InspectorSectionTitle(title: "Stroke", icon: "pencil.line")
                ColorWell(label: "Color", color: pathStrokeBinding)
                HStack(spacing: 8) {
                    Text("Width").foregroundStyle(EXPColor.textSecondary).font(.callout)
                    TextField("", value: pathStrokeWidthBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.exp).frame(width: 56).multilineTextAlignment(.trailing)
                        .numericStepping(pathStrokeWidthBinding, min: 0)
                    Spacer()
                }
                EXPSegmented(selection: pathStrokePatternBinding,
                             segments: StrokePattern.allCases.map { .init(value: $0, label: $0.label) })
                    .help("Use a solid, dashed, or dotted path stroke")
                    .accessibilityLabel("Path stroke pattern: solid, dash, or dot")
                if !ps.closed && !ps.isMultiContour {
                    EXPSegmented(selection: pathStrokeCapBinding,
                                 segments: StrokeLineCap.allCases.map { .init(value: $0, label: $0.label) })
                        .help("Choose the cap used at exposed path ends")
                        .accessibilityLabel("Path cap: flat, round, or square")
                    if app.tool == .node, let endpoint = app.selectedStrokeEndpoint {
                        strokeMarkerRow("\(endpoint.label) (selected)",
                                        accessibilityLabel: "\(endpoint.label) marker",
                                        selection: endpoint == .start
                                            ? pathStartMarkerBinding : pathEndMarkerBinding)
                    } else {
                        strokeMarkerRow("Start", accessibilityLabel: "Start marker",
                                        selection: pathStartMarkerBinding)
                        strokeMarkerRow("End", accessibilityLabel: "End marker",
                                        selection: pathEndMarkerBinding)
                    }
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
    var pathStrokePatternBinding: Binding<StrokePattern> {
        Binding(get: { selectedPathShape?.strokePattern ?? .solid },
                set: { value in updatePath("Stroke Pattern") { $0.strokePattern = value } })
    }
    var pathStrokeCapBinding: Binding<StrokeLineCap> {
        Binding(get: { selectedPathShape?.strokeCap ?? .round },
                set: { value in updatePath("Stroke Cap") { $0.strokeCap = value } })
    }
    var pathStartMarkerBinding: Binding<StrokeMarker> {
        Binding(get: { selectedPathShape?.startMarker ?? .none },
                set: { value in updatePath("Start Marker") { $0.startMarker = value } })
    }
    var pathEndMarkerBinding: Binding<StrokeMarker> {
        Binding(get: { selectedPathShape?.endMarker ?? .none },
                set: { value in updatePath("End Marker") { $0.endMarker = value } })
    }
}

/// A small labelled numeric field with accelerated arrow stepping.
/// A brand icon toggle/action button for the inspector (align, text-align, B/I/U,
/// distribute). Accent-subtle when active, a soft hover wash otherwise; tool radius.
private struct InspectorIconButton: View {
    let symbol: String
    let accessibilityLabel: String
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
        .accessibilityLabel(accessibilityLabel)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(EXPMotion.fast, value: hovering)
    }
}

private struct DimField: View {
    let label: String
    @Binding var value: Double
    /// Lower bound for arrow stepping. X/Y are deliberately unbounded — a negative
    /// coordinate is valid — but W/H pass 0, because a negative size is not.
    var min: Double? = nil

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
                .numericStepping($value, min: min)
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
                InspectorSectionTitle(title: name, icon: "textformat")
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

/// Arrow-key stepping for any numeric field. The default is ↑/↓ = ±1,
/// ⇧ = ±10, ⌥ = ±0.1; callers with precision values can provide a smaller
/// base `step` while keeping the same modifier relationship. Holding the key
/// accelerates. Internal, NOT private — see the `View` extension below.
struct NumericStepping: ViewModifier {
    @Binding var value: Double
    var min: Double? = nil
    var max: Double? = nil
    /// Default increment. Modifier keys retain the universal relationship:
    /// Shift = 10× and Option = 0.1×.
    var step: Double = 1
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
            let multiplier: Double = press.modifiers.contains(.shift) ? 10
                                   : press.modifiers.contains(.option) ? 0.1 : 1
            let accel = Double(1 + repeats / 5)        // grows every 5 repeats
            var next = value + dir * step * multiplier * accel
            if let m = min { next = Swift.max(m, next) }
            if let m = max { next = Swift.min(m, next) }
            let stepped = (next * 1000).rounded() / 1000   // avoid float drift
            // BUG-002: this handler runs inside SwiftUI's key-event update pass,
            // and writing straight through the binding mutates the document's
            // @Published model mid-update — the "Publishing changes from within
            // view updates is not allowed" warning, flooding once per repeat
            // while a key is held. Deferring the write one runloop tick moves
            // the model mutation outside the update. Existing callers retain the
            // default steps (±1, ⇧±10, ⌥±0.1); custom-step callers keep the same
            // modifier ratios. Key-repeat acceleration and undo are unchanged;
            // `value` is a Binding (a value type), so the copy captured here
            // still writes through to the live model.
            DispatchQueue.main.async { value = stepped }
            return .handled
        }
    }
}

// Internal, not `private`. This was file-private, which quietly meant every
// numeric field OUTSIDE MainWindow.swift had no arrow-key stepping at all — not an
// oversight at each call site but a visibility wall. The gradient Angle and stop
// Position fields in PaintEditor.swift were the visible symptom.
extension View {
    func numericStepping(_ value: Binding<Double>, min: Double? = nil,
                         max: Double? = nil, step: Double = 1) -> some View {
        modifier(NumericStepping(value: value, min: min, max: max, step: step))
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

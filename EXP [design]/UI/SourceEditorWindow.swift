//
//  SourceEditorWindow.swift
//  EXP [design]
//
//  The component "source editor" — a SEPARATE, independently movable + resizable
//  window for editing a component's source, with room for its own tool panes.
//  Double-clicking an instance on the canvas opens it.
//
//  It hosts a SwiftUI view inside a plain AppKit NSWindow, handed the SAME
//  ExpDocument reference as the main window — so edits to the source (round 2)
//  flow through the one document and every instance updates live, and undo is
//  shared. (We use AppKit windowing rather than a SwiftUI Window scene precisely
//  so we can share that object reference.)
//
//  ROUND 1 SCOPE: the window opens, lives on its own, and shows a live read-only
//  preview of the source plus a placeholder tools column. Actual in-window
//  editing (its own canvas + working tools) is the next round — it needs the
//  main canvas generalized to operate on an arbitrary node list (a source's
//  children) rather than only the document's top-level nodes.
//

import SwiftUI
import AppKit

@MainActor
final class SourceEditorWindowManager {
    static let shared = SourceEditorWindowManager()

    // One window per source id; reused if already open. Delegates retained here
    // (NSWindow.delegate is weak).
    private var controllers: [UUID: NSWindowController] = [:]
    private var delegates: [UUID: SourceEditorWindowDelegate] = [:]

    func open(sourceID: UUID, document: ExpDocument, undoManager: UndoManager?) {
        if let existing = controllers[sourceID] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        // Share the document's undo manager so ⌘Z works in this window AND edits
        // mark the document dirty for Save. The delegate vends it to SwiftUI
        // through the responder chain automatically.
        let app = AppState()
        let rootView = SourceEditorView(app: app, document: document, sourceID: sourceID)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [NSWindow.StyleMask.titled, .closable, .miniaturizable, .resizable]
        window.title = "Edit Component"
        window.isReleasedWhenClosed = false
        if let frame = SourceEditorWindowPreferences.windowFrame {
            window.setFrame(frame, display: false)
        } else {
            window.setContentSize(SourceEditorWindowPreferences.defaultContentSize)
            window.center()
        }

        // The View-only backdrop picker rides in the titlebar (trailing), on one
        // row with the traffic lights + title — sharing this window's AppState.
        let backdropAccessory = NSTitlebarAccessoryViewController()
        backdropAccessory.layoutAttribute = .trailing
        let backdropHost = NSHostingView(rootView: SourceBackdropPicker(app: app))
        backdropHost.setFrameSize(backdropHost.fittingSize)
        backdropAccessory.view = backdropHost
        window.addTitlebarAccessoryViewController(backdropAccessory)

        let delegate = SourceEditorWindowDelegate(
            sourceID: sourceID,
            document: document,
            undoManager: undoManager,
            onClose: { [weak self] id in
                self?.controllers[id] = nil
                self?.delegates[id] = nil
            })
        window.delegate = delegate
        delegates[sourceID] = delegate

        let controller = NSWindowController(window: window)
        controllers[sourceID] = controller
        controller.showWindow(nil as Any?)
        window.makeKeyAndOrderFront(nil as Any?)
    }

    /// Close the editor for one source — used when that source is deleted, so
    /// no window is left editing a component the document no longer contains.
    func close(sourceID: UUID) {
        controllers[sourceID]?.close()
    }

    func closeAll(for document: ExpDocument) {
        let ids = delegates.compactMap { sourceID, delegate in
            delegate.document === document ? sourceID : nil
        }
        for id in ids {
            controllers[id]?.close()
        }
    }
}

private enum SourceEditorWindowPreferences {
    static let defaultContentSize = NSSize(width: 1120, height: 680)
    static let defaultLeftPanelWidth: CGFloat = 220
    static let defaultRightPanelWidth: CGFloat = 340

    private static let windowFrameKey = "exp.sourceEditor.windowFrame.v1"
    private static let leftPanelWidthKey = "exp.sourceEditor.leftPanelWidth.v1"
    private static let rightPanelWidthKey = "exp.sourceEditor.rightPanelWidth.v1"

    static var windowFrame: NSRect? {
        get {
            guard let string = UserDefaults.standard.string(forKey: windowFrameKey) else { return nil }
            let rect = NSRectFromString(string)
            return rect.width >= 760 && rect.height >= 340 ? rect : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromRect(newValue), forKey: windowFrameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: windowFrameKey)
            }
        }
    }

    static var leftPanelWidth: CGFloat {
        get { storedWidth(leftPanelWidthKey, defaultValue: defaultLeftPanelWidth, range: 180...320) }
        set { storeWidth(newValue, key: leftPanelWidthKey, range: 180...320) }
    }

    static var rightPanelWidth: CGFloat {
        get { storedWidth(rightPanelWidthKey, defaultValue: defaultRightPanelWidth, range: 300...460) }
        set { storeWidth(newValue, key: rightPanelWidthKey, range: 300...460) }
    }

    private static func storedWidth(_ key: String, defaultValue: CGFloat,
                                    range: ClosedRange<CGFloat>) -> CGFloat {
        let value = UserDefaults.standard.double(forKey: key)
        guard value > 0 else { return defaultValue }
        return min(max(CGFloat(value), range.lowerBound), range.upperBound)
    }

    private static func storeWidth(_ value: CGFloat, key: String,
                                   range: ClosedRange<CGFloat>) {
        guard value.isFinite, value > 0 else { return }
        UserDefaults.standard.set(Double(min(max(value, range.lowerBound), range.upperBound)),
                                  forKey: key)
    }
}

/// Makes the source-editor window vend the document's undo manager, persists
/// the last editor frame, and tells the manager when a user closes the window.
private final class SourceEditorWindowDelegate: NSObject, NSWindowDelegate {
    let sourceID: UUID
    weak var document: ExpDocument?
    let undoManager: UndoManager?
    let onClose: (UUID) -> Void

    init(sourceID: UUID, document: ExpDocument, undoManager: UndoManager?,
         onClose: @escaping (UUID) -> Void) {
        self.sourceID = sourceID
        self.document = document
        self.undoManager = undoManager
        self.onClose = onClose
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }
    func windowDidMove(_ notification: Notification) { saveFrame(notification) }
    func windowDidResize(_ notification: Notification) { saveFrame(notification) }
    func windowWillClose(_ notification: Notification) {
        saveFrame(notification)
        onClose(sourceID)
    }

    private func saveFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        SourceEditorWindowPreferences.windowFrame = window.frame
    }
}

struct SourceEditorView: View {
    @ObservedObject var document: ExpDocument
    let sourceID: UUID
    @Environment(\.undoManager) private var undoManager

    // This window's OWN view state (tool, selection, camera) — independent of
    // the main editor window. Created by the window manager and passed in so the
    // titlebar accessory (the "View" backdrop picker) can share this instance.
    @State private var app: AppState

    init(app: AppState, document: ExpDocument, sourceID: UUID) {
        _document = ObservedObject(wrappedValue: document)
        self.sourceID = sourceID
        _app = State(initialValue: app)
    }

    // Editable component name (owner request, v1.6): drafts locally, commits
    // one undoable rename on submit or focus loss — not per keystroke.
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var source: ComponentSource? { document.model.source(for: sourceID) }

    /// The View-only backdrop picker now lives in the window TITLEBAR (trailing,
    /// beside the traffic lights) — see `SourceBackdropPicker` and the titlebar
    /// accessory wired up in `SourceEditorWindowManager.open`.

    /// The source's category, written through the document funnel (undoable,
    /// updates the Components panel + every instance immediately).
    private var categoryBinding: Binding<AriaRole?> {
        Binding(
            get: { source?.a11y.role },
            set: { newRole in
                guard let si = document.model.sources.firstIndex(where: { $0.id == sourceID }),
                      document.model.sources[si].a11y.role != newRole else { return }
                var model = document.model
                model.sources[si].a11y.role = newRole
                document.setModel(model, undoManager: undoManager, actionName: "Set Component Category")
            }
        )
    }

    /// What the current choice MEANS, in plain language — plus, when this
    /// component's role expects particular children and none of the components
    /// inside it carry that role yet, the semantic-containment nudge. Surfaced
    /// here because it is far cheaper to fix while authoring than to discover in
    /// the handoff package's fidelity report.
    private var categoryBlurb: String {
        guard let role = source?.a11y.role else {
            return "Optional — tag what this component IS. It organizes the Components panel today, and the same tag powers accessible code export later."
        }
        if let advice = document.model.containmentAdvice(forSource: sourceID) {
            return role.blurb + "\n\n" + advice.message
        }
        if let guidance = role.containmentGuidance {
            return role.blurb + "\n\n" + guidance
        }
        return role.blurb
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let si = document.model.sources.firstIndex(where: { $0.id == sourceID }),
              document.model.sources[si].name != trimmed else {
            draftName = source?.name ?? ""   // revert empty / no-op edits
            return
        }
        var model = document.model
        model.sources[si].name = trimmed
        document.setModel(model, undoManager: undoManager, actionName: "Rename Component")
    }

    /// Full name of the state being viewed, shown beside the component name
    /// (the extended chips abbreviate to ":h"-style labels). nil when the
    /// component has no states yet, so the header stays quiet.
    private var activeStateLabel: String? {
        guard let source, !source.states.isEmpty else { return nil }
        return source.states.first { $0.id == app.activeComponentStateID }?.name ?? "default"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header (v1.6 cleanup, owner mock): identity on the left —
            // editable name + the full name of the state being viewed. The
            // category picker moved to the right with its description below,
            // and the old "changes apply to every instance" banner is gone
            // (the window title already says what this is).
            HStack(alignment: .top, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square")
                    TextField("Component name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.expDocName)
                        .foregroundStyle(EXPColor.textPrimary)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                        .onAppear { draftName = source?.name ?? "" }
                        .onChange(of: source?.name) { _, newName in
                            if !nameFocused { draftName = newName ?? "" }
                        }
                        .frame(minWidth: 90, maxWidth: 260)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Component name")
                    if let stateLabel = activeStateLabel {
                        Text(stateLabel)
                            .font(.system(size: EXPType.mini, weight: .semibold))
                            .foregroundStyle(EXPColor.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(EXPColor.accentSubtle))
                            .accessibilityLabel("Viewing state \(stateLabel)")
                    }
                }
                Spacer()
                // Category picker + a compact "?" that reveals the description on
                // hover (our field-tip pattern), replacing the old always-on blurb
                // whose changing height made the row below jump around. The "View"
                // backdrop control moved OUT of here into the window titlebar.
                HStack(spacing: 8) {
                    Text("Category")
                        .font(.system(size: EXPType.mini, weight: .medium))
                        .foregroundStyle(EXPColor.textSecondary)
                    Picker("Component category", selection: categoryBinding) {
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
                    .fixedSize()
                    .accessibilityLabel("Component category")
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: EXPType.base))
                        .foregroundStyle(EXPColor.textTertiary)
                        .expFieldTip("Category", categoryBlurb, align: .trailing)
                        .accessibilityLabel("What does this category mean?")
                }
            }
            .padding(10)

            // ── States bar (v1.6 Chunk H): full width, below the name row.
            // Set into its own slightly-recessed strip (toolbar surface, with a
            // hairline above and below) so it reads as separate from the category
            // area above — echoing the layers / components panels.
            Divider()
            ComponentStatesBar(document: document, sourceID: sourceID)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(EXPColor.surfaceToolbar)
            Divider()

            // Mirror the main window: the tools strip is pinned OUTSIDE the split,
            // and the three panes live in an HSplitView. Split panes clip their
            // contents, so the AppKit-backed canvas stays inside its pane instead of
            // overdrawing the header and left panel (a plain HStack left the
            // unclipped canvas painting over its neighbours).
            HStack(spacing: 0) {
                ToolsStrip()
                Divider()
                HSplitView {
                    LayersPanel(document: document, scope: .source(sourceID))
                        .frame(minWidth: 180,
                               idealWidth: SourceEditorWindowPreferences.leftPanelWidth,
                               maxWidth: 320)
                        .background(SourceEditorWidthReporter { width in
                            SourceEditorWindowPreferences.leftPanelWidth = width
                        })
                    CanvasView(app: app, document: document, scope: .source(sourceID))
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    RightPanel(document: document, scope: .source(sourceID))
                        .frame(minWidth: 300,
                               idealWidth: SourceEditorWindowPreferences.rightPanelWidth,
                               maxWidth: 460)
                        .background(SourceEditorWidthReporter { width in
                            SourceEditorWindowPreferences.rightPanelWidth = width
                        })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(app)
        .focusedSceneValue(\.editorMenu, makeEditorMenuModel(document: document, app: app, scope: .source(sourceID)))
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
    }
}

private struct SourceEditorWidthReporter: View {
    var onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.size.width) }
                .onChange(of: proxy.size.width) { _, width in report(width) }
        }
    }

    private func report(_ width: CGFloat) {
        guard width.isFinite, width > 40 else { return }
        onChange(width)
    }
}


// MARK: - Backdrop picker (titlebar accessory)

/// The View-only canvas backdrop picker (light / grey / dark) drawn behind the
/// component. It gives contrast for white or black artwork and never changes the
/// element's own background — hence the explicit "View" label. Hosted in the
/// window titlebar (trailing) so it sits on one row with the traffic lights and
/// the "Edit Component" title, out of the content area.
struct SourceBackdropPicker: View {
    var app: AppState

    var body: some View {
        HStack(spacing: 6) {
            Text("View").font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textSecondary)
            ForEach(AppState.CanvasBackdrop.allCases) { bd in
                let selected = app.sourceBackdrop == bd
                Button { app.sourceBackdrop = bd } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bd.color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(selected ? EXPColor.accent
                                                       : EXPColor.borderStrong,
                                              lineWidth: selected ? EXPMetric.strokeSelection : EXPMetric.strokeHairline)
                        )
                }
                .buttonStyle(.plain)
                .help("\(bd.label) backdrop (view only — doesn't change the component)")
                .accessibilityLabel("\(bd.label) canvas backdrop, view setting")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.trailing, 12)
    }
}

// MARK: - States bar (v1.6 Chunk H)

/// The component-states bar: shows the source's named states across the top of
/// the editor, switches which state the window views/edits, and manages them.
/// Two layouts (owner mock): the EXTENDED chip row — "default" spelled out,
/// other states as ":h"-style two-character chips — and a COMPACT dropdown.
/// The layout choice persists app-wide; a manage mode adds rename / reorder /
/// delete without cluttering the everyday row.
struct ComponentStatesBar: View {
    @ObservedObject var document: ExpDocument
    let sourceID: UUID
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager

    @State private var manageMode = false
    @State private var showingCustomName = false
    @State private var customName = ""

    private var source: ComponentSource? { document.model.source(for: sourceID) }
    private var states: [ComponentState] { source?.states ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
            // Component-scope marker + label. The marker glyph (a source/instance
            // split) tags this as a component section, echoed on the Layers header.
            HStack(spacing: 5) {
                Image(systemName: "square.filled.and.line.vertical.and.square")
                    .font(.system(size: EXPType.small))
                    .foregroundStyle(EXPColor.textTertiary)
                    .accessibilityHidden(true)
                Text("States")
                    .font(.system(size: EXPType.mini, weight: .medium))
                    .foregroundStyle(EXPColor.textSecondary)
            }
            if manageMode {
                manageRow
            } else if app.statesBarCompact {
                compactPicker
            } else {
                chipRow
            }
            addButton
            Spacer()
            if !states.isEmpty { manageToggle }
            layoutToggle
        }
            contrastStrip
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Component states")
    }

    // MARK: Per-state contrast (advisory)

    /// WCAG-AA contrast results for the text in the state currently being viewed.
    private var activeContrast: [StateContrastResult] {
        guard let source else { return [] }
        let state = states.first { $0.id == app.activeComponentStateID }
        return ComponentContrastAudit.results(source: source, state: state, model: document.model)
    }

    /// A compact contrast readout under the states row. It reflects the ACTIVE
    /// state, so switching states re-checks — contrast is evaluated per state,
    /// not just the default. Hidden when the component has no text to check.
    @ViewBuilder private var contrastStrip: some View {
        let results = activeContrast
        if let worst = results.min(by: { $0.report.ratio < $1.report.ratio }) {
            let failing = results.filter { !$0.passesAA }
            let ok = failing.isEmpty
            HStack(spacing: 5) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(ok ? EXPColor.green : EXPColor.orange)
                Text("Contrast \(worst.report.ratioLabel)")
                    .font(.system(size: EXPType.mini, weight: .medium))
                    .foregroundStyle(EXPColor.textSecondary)
                Text(ok ? "· AA"
                        : (failing.count > 1
                           ? "· below AA on \(failing.count) layers"
                           : "· below AA on \(failing.first?.layerName ?? worst.layerName)"))
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(ok ? EXPColor.textTertiary : EXPColor.orange)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ok
                ? "Contrast passes AA, lowest ratio \(worst.report.ratioLabel)"
                : "Contrast below AA on \(failing.count) text layer\(failing.count == 1 ? "" : "s"), lowest ratio \(worst.report.ratioLabel)")
            .help("WCAG AA contrast of this state's text against its background (advisory)")
        }
    }

    // MARK: Extended chips

    /// ":h"-style chip: colon + first letter (two characters, per the mock),
    /// widened to two letters only when states share a first letter (":pr" vs
    /// ":pi"). "default" always shows its full name. Hover/VoiceOver give the
    /// full name; the header pill shows it too.
    private func chipLabel(for state: ComponentState) -> String {
        // Every chip is two characters. Conventional pseudo-class states
        // (hover / pressed / focus / disabled) — and names that literally begin
        // with a colon — read as ":" + their first letter (":h"). Custom names
        // read as their first two characters ("op" for "open").
        let isConventional = ComponentState.conventionalNames.contains {
            $0.caseInsensitiveCompare(state.name) == .orderedSame
        }
        if isConventional || state.name.hasPrefix(":") {
            let letter = state.name.drop { $0 == ":" }.prefix(1)
            return ":" + letter
        }
        return String(state.name.prefix(2))
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            chip(label: "default", name: "default",
                 isActive: app.activeComponentStateID == nil) {
                app.activeComponentStateID = nil
            }
            ForEach(states) { state in
                chip(label: chipLabel(for: state), name: state.name,
                     isActive: app.activeComponentStateID == state.id) {
                    app.activeComponentStateID = state.id
                }
            }
        }
    }

    private func chip(label: String, name: String, isActive: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: EXPType.small, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? EXPColor.accent : EXPColor.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? EXPColor.accentSubtle : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? EXPColor.accent : EXPColor.borderStrong,
                                      lineWidth: isActive ? EXPMetric.strokeSelection
                                                          : EXPMetric.strokeHairline)
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("State \(name)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: Compact dropdown

    private var compactPicker: some View {
        Picker("Active state", selection: Binding(
            get: { app.activeComponentStateID },
            set: { app.activeComponentStateID = $0 })) {
            Text("default").tag(UUID?.none)
            ForEach(states) { state in
                Text(state.name).tag(UUID?.some(state.id))
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Active state")
    }

    // MARK: Add

    private var addButton: some View {
        Menu {
            ForEach(ComponentState.conventionalNames.filter { name in
                !states.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }, id: \.self) { name in
                Button(name) { addState(named: name) }
            }
            Divider()
            Button("Custom…") { customName = ""; showingCustomName = true }
        } label: {
            Image(systemName: "plus")
        }
        .fixedSize()
        .help("Add a state")
        .accessibilityLabel("Add state")
        .popover(isPresented: $showingCustomName, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                TextField("State name", text: $customName)
                    .frame(width: 150)
                    .onSubmit { addCustomState() }
                    .accessibilityLabel("New state name")
                Button("Add") { addCustomState() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
    }

    private func addCustomState() {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showingCustomName = false
        addState(named: trimmed)
    }

    private func addState(named name: String) {
        let state = ComponentState(name: name)
        mutateStates("Add Component State") { $0.append(state) }
        app.activeComponentStateID = state.id
    }

    // MARK: Manage (rename / reorder / delete)

    private var manageToggle: some View {
        Button { manageMode.toggle() } label: {
            Image(systemName: manageMode ? "checkmark.circle" : "pencil")
        }
        .buttonStyle(.plain)
        .foregroundStyle(manageMode ? EXPColor.accent : EXPColor.textSecondary)
        .help(manageMode ? "Done managing states"
                         : "Edit, reorder, or delete states")
        .accessibilityLabel(manageMode ? "Done managing states" : "Manage states")
    }

    private var layoutToggle: some View {
        Button { app.statesBarCompact.toggle() } label: {
            Image(systemName: app.statesBarCompact
                  ? "rectangle.split.3x1" : "chevron.down.square")
        }
        .buttonStyle(.plain)
        .foregroundStyle(EXPColor.textSecondary)
        .help(app.statesBarCompact ? "Switch to the extended state buttons"
                                   : "Switch to the compact dropdown")
        .accessibilityLabel(app.statesBarCompact
                            ? "Use extended states bar" : "Use compact states dropdown")
    }

    private var manageRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(states.enumerated()), id: \.element.id) { index, state in
                HStack(spacing: 3) {
                    StateRenameField(name: state.name) { newName in
                        rename(state, to: newName)
                    }
                    Button { move(state, by: -1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .help("Move \(state.name) left")
                    .accessibilityLabel("Move state \(state.name) earlier")
                    Button { move(state, by: 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == states.count - 1)
                    .help("Move \(state.name) right")
                    .accessibilityLabel("Move state \(state.name) later")
                    Button { delete(state) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(EXPColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete \(state.name)")
                    .accessibilityLabel("Delete state \(state.name)")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(EXPColor.borderStrong,
                                      lineWidth: EXPMetric.strokeHairline)
                )
            }
        }
    }

    private func rename(_ state: ComponentState, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != state.name else { return }
        mutateStates("Rename Component State") { arr in
            guard let i = arr.firstIndex(where: { $0.id == state.id }) else { return }
            arr[i].name = trimmed
        }
    }

    private func move(_ state: ComponentState, by delta: Int) {
        mutateStates("Reorder Component States") { arr in
            guard let i = arr.firstIndex(where: { $0.id == state.id }) else { return }
            let j = i + delta
            guard arr.indices.contains(j) else { return }
            arr.swapAt(i, j)
        }
    }

    private func delete(_ state: ComponentState) {
        if app.activeComponentStateID == state.id { app.activeComponentStateID = nil }
        mutateStates("Delete Component State") { arr in
            arr.removeAll { $0.id == state.id }
        }
    }

    /// All state mutations funnel through setModel — undoable, and every
    /// window observing the document updates.
    private func mutateStates(_ action: String,
                              _ change: (inout [ComponentState]) -> Void) {
        guard let si = document.model.sources.firstIndex(where: { $0.id == sourceID })
        else { return }
        var model = document.model
        change(&model.sources[si].states)
        document.setModel(model, undoManager: undoManager, actionName: action)
    }
}

/// A rename field that drafts locally and commits ONE undoable change on
/// submit or focus loss — not an undo step per keystroke.
private struct StateRenameField: View {
    let name: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("State name", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: EXPType.small))
            .frame(minWidth: 52, maxWidth: 110)
            .fixedSize(horizontal: true, vertical: false)
            .focused($focused)
            .onSubmit { commit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(draft) }
            }
            .onAppear { draft = name }
            .onChange(of: name) { _, newName in
                if !focused { draft = newName }
            }
            .accessibilityLabel("Rename state \(name)")
    }
}


// MARK: - Per-state component contrast audit

/// One text layer's contrast result within a resolved component state.
struct StateContrastResult: Identifiable {
    let id = UUID()
    let layerName: String
    let report: ContrastReport
    let use: ContrastUse
    var passesAA: Bool { report.passes(use, atLeast: .aa) }
}

/// Evaluates every text layer in a component SOURCE, resolved in a given state
/// (nil = base), against the background it actually sits on. Reuses the exact
/// instance-resolution machinery states already use, so overrides + re-hug match
/// what's drawn. Advisory only — it flags, it never edits.
///
/// Background heuristic (covers buttons, chips, cards): text inside a frame reads
/// against that frame's fill; text over a sibling shape reads against the topmost
/// enclosing shape drawn behind it; otherwise white (the honest design default).
enum ComponentContrastAudit {
    static func results(source: ComponentSource, state: ComponentState?, model: Document) -> [StateContrastResult] {
        var out: [StateContrastResult] = []
        walk(model.resolvedChildren(of: source, in: state), background: .white, into: &out)
        return out
    }

    private static func walk(_ nodes: [Node], background: RGBAColor, into out: inout [StateContrastResult]) {
        for (i, n) in nodes.enumerated() {
            switch n.content {
            case .text(let tc):
                let bg = enclosingFill(before: i, in: nodes, target: n.frame) ?? background
                if let run = tc.runs.first {
                    let use: ContrastUse = run.fontSize >= 24 ? .largeText : .normalText
                    let report = ContrastMath.report(foreground: run.color, background: bg)
                    out.append(StateContrastResult(layerName: n.name, report: report, use: use))
                }
            case .group(let kids):
                let groupBG = n.autoPadding?.fill?.representativeColor
                    ?? enclosingFill(before: i, in: nodes, target: n.frame)
                    ?? background
                walk(kids, background: groupBG, into: &out)
            default:
                break
            }
        }
    }

    /// Fill of the topmost shape/frame sibling drawn BEHIND `target` (earlier in
    /// the array = lower z) that encloses it — the surface a text layer reads on.
    private static func enclosingFill(before index: Int, in nodes: [Node], target: CGRect) -> RGBAColor? {
        for j in stride(from: index - 1, through: 0, by: -1) {
            let s = nodes[j]
            guard s.frame.contains(target) || significantOverlap(s.frame, target) else { continue }
            if let paint = fill(of: s) { return paint.representativeColor }
        }
        return nil
    }

    private static func significantOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let o = a.intersection(b)
        guard !o.isNull, b.width > 0, b.height > 0 else { return false }
        return (o.width * o.height) >= 0.6 * (b.width * b.height)
    }

    private static func fill(of n: Node) -> Paint? {
        switch n.content {
        case .rectangle(let s): return s.fill
        case .ellipse(let s):   return s.fill
        case .polygon(let s):   return s.fill
        case .path(let s):      return s.fill
        case .group:            return n.autoPadding?.fill
        default:                return nil
        }
    }
}

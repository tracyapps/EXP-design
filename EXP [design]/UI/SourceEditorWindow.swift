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
    private var delegates: [UUID: SharedUndoWindowDelegate] = [:]

    func open(sourceID: UUID, document: ExpDocument, undoManager: UndoManager?) {
        if let existing = controllers[sourceID] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        // Share the document's undo manager so ⌘Z works in this window AND edits
        // mark the document dirty for Save. The delegate vends it to SwiftUI
        // through the responder chain automatically.
        let rootView = SourceEditorView(document: document, sourceID: sourceID)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 880, height: 520))
        window.styleMask = [NSWindow.StyleMask.titled, .closable, .miniaturizable, .resizable]
        window.title = "Edit Component"
        window.isReleasedWhenClosed = false
        window.center()

        let delegate = SharedUndoWindowDelegate(undoManager: undoManager)
        window.delegate = delegate
        delegates[sourceID] = delegate

        let controller = NSWindowController(window: window)
        controllers[sourceID] = controller
        controller.showWindow(nil as Any?)
        window.makeKeyAndOrderFront(nil as Any?)
    }
}

/// Makes the source-editor window vend the document's undo manager, so the
/// Edit menu's Undo/Redo (and ⌘Z) act on the same stack the canvas edits use.
private final class SharedUndoWindowDelegate: NSObject, NSWindowDelegate {
    let undoManager: UndoManager?
    init(undoManager: UndoManager?) { self.undoManager = undoManager }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }
}

struct SourceEditorView: View {
    @ObservedObject var document: ExpDocument
    let sourceID: UUID
    @Environment(\.undoManager) private var undoManager

    // This window's OWN view state (tool, selection, camera) — independent of
    // the main editor window.
    @State private var app = AppState()

    private var source: ComponentSource? { document.model.source(for: sourceID) }

    /// View-ONLY backdrop control (light / grey / dark) drawn behind the component
    /// in the canvas — Photoshop-style canvas colour. It gives contrast for white or
    /// black artwork and never changes the element's own background. Labelled "View"
    /// so that's unmistakable.
    private var backdropPicker: some View {
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
    }

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

    /// What the current choice MEANS, in plain language.
    private var categoryBlurb: String {
        if let role = source?.a11y.role { return role.blurb }
        return "Optional — tag what this component IS. It organizes the Components panel today, and the same tag powers accessible code export later."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.on.square")
                Text(source?.name ?? "Component")
                    .font(.expDocName)
                    .foregroundStyle(EXPColor.textPrimary)
                Spacer()
                Text("Editing component — changes apply to every instance")
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(EXPColor.textSecondary)
                Divider().frame(height: 16)
                backdropPicker
            }
            .padding(10)

            // Phase 19a follow-up (owner request): categorize the component right
            // where it's edited, with a plain-language line describing the chosen
            // role — similar options (Checkbox vs Switch, Menu vs Navigation…)
            // are confusing without it. The blurb earns its vertical space.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                Text(categoryBlurb)
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Category description: \(categoryBlurb)")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
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
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
                    CanvasView(app: app, document: document, scope: .source(sourceID))
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    RightPanel(document: document, scope: .source(sourceID))
                        .frame(minWidth: 240, idealWidth: 260, maxWidth: 340)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(app)
		.frame(minWidth: 760, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
    }
}

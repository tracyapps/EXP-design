//
//  EXP__design_App.swift
//  EXP [design]
//
//  Created by tapps on 6/3/26.
//

import SwiftUI
import AppKit

@main
struct EXP__design_App: App {
    // Register the bundled SF Compact Display weights at launch (before any view
    // renders) so the condensed chrome voice is consistent on every Mac.
    // See UI/FontRegistration.swift for the licensing note.
    init() { EXPFonts.registerBundledFonts() }

    // Sparkle auto-updates (Phase 20): one UpdaterModel for the app's
    // lifetime drives the "Check for Updates…" item below. See
    // UI/UpdaterController.swift for the canImport guard + consent notes.
    @StateObject private var updaterModel = UpdaterModel()

    var body: some Scene {
        // DocumentGroup gives us New / Open / Save / Duplicate / Rename / Revert
        // and multi-window for free — each window hosts one ExpDocument.
        DocumentGroup(newDocument: { ExpDocument() }) { configuration in
            MainWindow(document: configuration.document, fileURL: configuration.fileURL)
        }
        // A roomier default window so the canvas + both panels have breathing room
        // on first launch (users can resize; this only sets the initial size).
        .defaultSize(width: 1500, height: 950)
        .commands {
            // ⌘G is the system "Find Next" by default, which would eat our Group
            // shortcut before the canvas sees it. Remove the text-find menu (this
            // is a graphics app, not a text editor) so ⌘G / ⇧⌘G dispatch through the
            // responder chain to the focused canvas.
            CommandGroup(replacing: .textEditing) { }

            // APP MENU ▸ Check for Updates… (right under "About EXP [design]").
            // App-chrome action, not a canvas action, so the command-coverage
            // rule's canvas/@objc/context-menu legs don't apply; enablement
            // comes from Sparkle via canCheckForUpdates.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { updaterModel.checkForUpdates() }
                    .disabled(!updaterModel.canCheckForUpdates)
            }

            // HELP ▸ Send Feedback (in-app bug / idea reporter).
            CommandGroup(replacing: .help) {
                ARIARolesGuideCommand()
                Divider()
                Button("Send Feedback\u{2026}") { send("sendFeedbackAction:") }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                Divider()
                // Tester diagnostics (v1.3): the report bundles machine info,
                // document stats, and a geometry audit into one attachable file.
                Button("Save Diagnostic Report\u{2026}") { send("saveDiagnosticReportAction:") }
            }

            // FILE ▸ Export (alongside the DocumentGroup's New/Open/Save/Close).
            CommandGroup(replacing: .importExport) {
                FileCommandItems()
            }

            // EDIT ▸ selection + duplicate (after the standard Cut/Copy/Paste).
            // Cut/Copy/Paste/Delete + Undo/Redo come from the system Edit menu and
            // route to the canvas's standard action methods.
            CommandGroup(after: .pasteboard) {
                EditCommandItems()
            }

            // OBJECT ▸ structure + components + conversion.
            CommandMenu("Object") {
                ObjectCommandItems()
            }

            // TYPE ▸ text styling + outlines.
            CommandMenu("Type") {
                TypeCommandItems()
            }

            // ARRANGE ▸ z-order + align + distribute.
            CommandMenu("Arrange") {
                ArrangeCommandItems()
            }

            // VIEW ▸ zoom + overlays (added to the system View menu via .toolbar slot).
            CommandGroup(after: .toolbar) {
                ViewCommandItems()
            }

            // WINDOW ▸ appended after the system window list (which shows the
            // document window). Panels section reveals/focuses floating panels
            // (multi-window); dock section toggles the side panels (single-window).
            CommandGroup(after: .windowList) {
                WindowMenuItems()
            }
        }

        // App-wide Settings (⌘,). The standard SwiftUI `Settings` scene also adds
        // the "Settings…" item to the app menu for us — one canonical entry point,
        // app-chrome rather than a canvas action. Built as a full window (sidebar
        // + detail) so it scales as more user options arrive (see SettingsWindow).
        Settings {
            SettingsWindow()
        }

        // A single-purpose learning surface rather than a general browser. The
        // guide owns its search/history UI; EXP supplies only a resizable native
        // window and keeps off-site navigation in the user's default browser.
        Window("ARIA Roles Guide", id: ARIARolesGuideWindow.sceneID) {
            ARIARolesGuideWindow()
        }
        .defaultSize(width: 1100, height: 820)
        .windowResizability(.contentMinSize)
    }

    /// Send an action up the responder chain to whichever canvas is focused.
    private func send(_ selectorName: String) {
        NSApp.sendAction(NSSelectorFromString(selectorName), to: nil, from: nil)
    }

}

private struct ARIARolesGuideCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("ARIA Roles Guide") {
            openWindow(id: ARIARolesGuideWindow.sceneID)
        }
    }
}

private func sendEditorAction(_ selectorName: String) {
    NSApp.sendAction(NSSelectorFromString(selectorName), to: nil, from: nil)
}

private func sendEditorComponentCategory(_ role: AriaRole?) {
    let item = NSMenuItem(title: role?.friendlyLabel ?? "Uncategorized",
                          action: nil, keyEquivalent: "")
    item.representedObject = role?.rawValue
    NSApp.sendAction(NSSelectorFromString("setComponentCategoryAction:"), to: nil, from: item)
}

private func sendEditorTextContentRole(_ role: TextContentRole) {
    let item = NSMenuItem(title: role.friendlyLabel, action: nil, keyEquivalent: "")
    item.representedObject = role.rawValue
    NSApp.sendAction(NSSelectorFromString("setTextContentRoleAction:"), to: nil, from: item)
}

private struct FileCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Button("Place Image…") { sendEditorAction("placeImageAction:") }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(menu == nil)
        Button("Import PDF…") { sendEditorAction("importPDFAction:") }
            .disabled(menu == nil)
        Divider()
        Button("Export Selected Artboard(s)…") { sendEditorAction("exportSelectedArtboard:") }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(menu?.canExportSelectedArtboards != true)
        Button("Export All Artboards…") { sendEditorAction("exportAllArtboards:") }
            .disabled(menu?.canExportAllArtboards != true)
        Button("Export Handoff Package…") { sendEditorAction("exportHandoffPackage:") }
            .disabled(menu == nil)
    }
}

private struct EditCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Button("Duplicate") { sendEditorAction("duplicateSelection:") }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(menu?.canDuplicate != true)
        Button("Deselect All") { sendEditorAction("deselectAllAction:") }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(menu?.hasAnySelection != true)
        Divider()
        Button("Copy Style") { sendEditorAction("copyLayerStyle:") }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(menu?.canCopyStyle != true)
        Button("Paste Style") { sendEditorAction("pasteLayerStyle:") }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(menu?.canPasteStyle != true)
    }
}

private struct ObjectCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Button("Group") { sendEditorAction("groupSelection:") }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(menu?.canGroup != true)
        Button("Ungroup") { sendEditorAction("ungroupSelection:") }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(menu?.canUngroup != true)
        Divider()
        Button("Lock") { sendEditorAction("lockSelection:") }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(menu?.hasNodes != true)
        Button("Unlock") { sendEditorAction("unlockSelection:") }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(menu?.hasNodes != true)
        Divider()
        Menu("Mask") {
            Button("Mask with Top Shape") { sendEditorAction("maskWithTopShapeAction:") }
                .keyboardShortcut("m", modifiers: [.command, .control])
                .disabled(menu?.canMask != true)
            Button("Release Mask") { sendEditorAction("releaseMaskAction:") }
                .disabled(menu?.canReleaseMask != true)
        }
        Menu("Frame") {
            Button(menu?.autoLayoutTitle ?? "Add Auto Layout") { sendEditorAction("toggleAutoLayoutAction:") }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(menu?.canAutoLayout != true)
            Button(menu?.autoPaddingTitle ?? "Add Auto Padding") { sendEditorAction("toggleAutoPaddingAction:") }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(menu?.canAutoPadding != true)
            Divider()
            Button("Move Item Forward") { sendEditorAction("nudgeItemForwardAction:") }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(menu?.canMoveAutoLayoutItem != true)
            Button("Move Item Backward") { sendEditorAction("nudgeItemBackwardAction:") }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(menu?.canMoveAutoLayoutItem != true)
        }
        Divider()
        Menu("Component") {
            Button("Create Component") { sendEditorAction("createComponentAction:") }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(menu?.canCreateComponent != true)
            Button("New Empty Component") { sendEditorAction("newEmptyComponentAction:") }
                .disabled(menu?.canNewEmptyComponent != true)
            Button("Edit Component") { sendEditorAction("editComponentAction:") }
                .disabled(menu?.canEditComponent != true)
            Button("Detach Component") { sendEditorAction("detachComponentAction:") }
                .disabled(menu?.canDetachComponent != true)
            Divider()
            Button(menu?.addComponentStateTitle ?? "Add Component State") {
                sendEditorAction("addComponentStateAction:")
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(menu?.canAddComponentState != true)
            Button("Previous Component State") { sendEditorAction("previousComponentStateAction:") }
                .keyboardShortcut("[", modifiers: [.command, .control])
                .disabled(menu?.canCycleComponentState != true)
            Button("Next Component State") { sendEditorAction("nextComponentStateAction:") }
                .keyboardShortcut("]", modifiers: [.command, .control])
                .disabled(menu?.canCycleComponentState != true)
            Divider()
            Menu("Set Category") {
                Button("Uncategorized") { sendEditorComponentCategory(nil) }
                ForEach(AriaRole.grouped(), id: \.category) { group in
                    Section(group.category.label) {
                        ForEach(group.roles, id: \.self) { role in
                            Button(role.friendlyLabel) { sendEditorComponentCategory(role) }
                        }
                    }
                }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(menu?.canSetComponentCategory != true)
            Button("Relationships…") { sendEditorAction("showRelationshipsAction:") }
                .disabled(menu?.canEditRelationships != true)
        }
        Divider()
        Menu("Path") {
            Button("Convert to Path") { sendEditorAction("convertToPathAction:") }
                .disabled(menu?.canConvertToPath != true)
            Button("Outline Stroke") { sendEditorAction("outlineStrokeAction:") }
                .disabled(menu?.canOutlineStroke != true)
        }
        Menu("Pathfinder") {
            Button("Unite") { sendEditorAction("pathfinderUniteAction:") }
            Button("Subtract Front") { sendEditorAction("pathfinderSubtractAction:") }
            Button("Intersect") { sendEditorAction("pathfinderIntersectAction:") }
            Button("Exclude Overlap") { sendEditorAction("pathfinderExcludeAction:") }
        }
        .disabled(menu?.canPathfinder != true)
        Button("Round to Pixel") { sendEditorAction("roundToPixelAction:") }
            .disabled(menu?.canRoundToPixel != true)
        Divider()
        Button("Eyedropper (Pick Fill) — i") { sendEditorAction("eyedropperAction:") }
            .disabled(menu?.canEyedropper != true)
    }
}

private struct TypeCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Menu("Content Role") {
            ForEach(TextContentRole.allCases, id: \.self) { role in
                Button(role.friendlyLabel) { sendEditorTextContentRole(role) }
            }
        }
        .disabled(menu?.canTypeActions != true)
        Divider()
        Button("Bold") { sendEditorAction("toggleBoldText:") }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(menu?.canTypeActions != true)
        Button("Italic") { sendEditorAction("toggleItalicText:") }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(menu?.canTypeActions != true)
        Button("Underline") { sendEditorAction("toggleUnderlineText:") }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(menu?.canTypeActions != true)
        Divider()
        Button("Convert to Outlines") { sendEditorAction("convertTextToShapesAction:") }
            .disabled(menu?.canTypeActions != true)
        Divider()
        Button("Save as Type Style") { sendEditorAction("saveTypeStyleAction:") }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(menu?.canTypeActions != true)
    }
}

private struct ArrangeCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Menu("Order") {
            Button("Bring to Front") { sendEditorAction("bringToFront:") }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(menu?.hasNodes != true)
            Button("Bring Forward") { sendEditorAction("bringForward:") }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(menu?.hasNodes != true)
            Button("Send Backward") { sendEditorAction("sendBackward:") }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(menu?.hasNodes != true)
            Button("Send to Back") { sendEditorAction("sendToBack:") }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(menu?.hasNodes != true)
        }
        Menu("Flip") {
            Button("Flip Horizontal") { sendEditorAction("flipHorizontalAction:") }
                .disabled(menu?.hasNodes != true)
            Button("Flip Vertical") { sendEditorAction("flipVerticalAction:") }
                .disabled(menu?.hasNodes != true)
        }
        Divider()
        Menu("Align") {
            Button("Left") { sendEditorAction("alignLeftAction:") }
            Button("Horizontal Centers") { sendEditorAction("alignHCenterAction:") }
            Button("Right") { sendEditorAction("alignRightAction:") }
            Button("Top") { sendEditorAction("alignTopAction:") }
            Button("Vertical Centers") { sendEditorAction("alignVCenterAction:") }
            Button("Bottom") { sendEditorAction("alignBottomAction:") }
        }
        .disabled(menu?.canAlign != true)
        Menu("Distribute") {
            Button("Horizontally") { sendEditorAction("distributeHorizontallyAction:") }
            Button("Vertically") { sendEditorAction("distributeVerticallyAction:") }
        }
        .disabled(menu?.canDistribute != true)
    }
}

private struct ViewCommandItems: View {
    @FocusedValue(\.editorMenu) private var menu

    var body: some View {
        Button("Zoom In") { sendEditorAction("zoomInAction:") }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(menu == nil)
        Button("Zoom Out") { sendEditorAction("zoomOutAction:") }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(menu == nil)
        Button("Actual Size (100%)") { sendEditorAction("zoomActualAction:") }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(menu == nil)
        Button("Zoom to Fit") { sendEditorAction("fitToScreen:") }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(menu == nil)
        Divider()
        Button("Toggle Selection Bounds") { sendEditorAction("toggleSelectionBounds:") }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(menu == nil)
        Divider()
        Button("Expand All Layers") { sendEditorAction("expandAllLayersAction:") }
            .disabled(menu == nil)
        Button("Collapse All Layers") { sendEditorAction("collapseAllLayersAction:") }
            .disabled(menu == nil)
        Button("Reveal Selection in Layers") { sendEditorAction("revealSelectionInLayersAction:") }
            .disabled(menu?.canRevealSelectionInLayers != true)
        Divider()
        Button("Show / Hide Rulers") { sendEditorAction("toggleRulersAction:") }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(menu == nil)
        Button("Show / Hide Guides") { sendEditorAction("toggleGuidesAction:") }
            .keyboardShortcut(";", modifiers: .command)
            .disabled(menu == nil)
        Button("Lock Guides") { sendEditorAction("toggleLockGuidesAction:") }
            .keyboardShortcut(";", modifiers: [.command, .option])
            .disabled(menu == nil)
        Button("Clear Guides") { sendEditorAction("clearGuidesAction:") }
            .disabled(menu == nil)
        Divider()
        Button("Show / Hide Grid") { sendEditorAction("toggleGridAction:") }
            .keyboardShortcut("'", modifiers: .command)
            .disabled(menu == nil)
        Button("Snap to Grid") { sendEditorAction("toggleSnapToGridAction:") }
            .keyboardShortcut("'", modifiers: [.command, .shift])
            .disabled(menu == nil)
    }
}

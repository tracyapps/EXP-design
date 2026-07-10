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
            MainWindow(document: configuration.document)
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
                Button("Send Feedback\u{2026}") { send("sendFeedbackAction:") }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                Divider()
                // Tester diagnostics (v1.3): the report bundles machine info +
                // geometry audit + the perf stream tail into one attachable file;
                // the reveal item opens the always-on daily stream log. Reveal is
                // app-chrome (no canvas needed), so it calls DiagnosticLog directly.
                Button("Save Diagnostic Report\u{2026}") { send("saveDiagnosticReportAction:") }
                Button("Reveal Diagnostic Log in Finder") { DiagnosticLog.revealInFinder() }
            }

            // FILE ▸ Export (alongside the DocumentGroup's New/Open/Save/Close).
            CommandGroup(replacing: .importExport) {
                Button("Place Image…") { send("placeImageAction:") }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Export Selected Artboard(s)…") { send("exportSelectedArtboard:") }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export All Artboards…") { send("exportAllArtboards:") }
            }

            // EDIT ▸ selection + duplicate (after the standard Cut/Copy/Paste).
            // Cut/Copy/Paste/Delete + Undo/Redo come from the system Edit menu and
            // route to the canvas's standard action methods.
            CommandGroup(after: .pasteboard) {
                Button("Duplicate") { send("duplicateSelection:") }
                    .keyboardShortcut("d", modifiers: .command)
                // (Select All ⌘A comes from the system Edit menu → canvas selectAll:.)
                Button("Deselect All") { send("deselectAllAction:") }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                // Copy/paste a layer's appearance (effects + blend mode + opacity)
                // onto other layers. ⇧⌘C / ⇧⌘V are free (⌘C/⌘V are the system
                // Cut/Copy/Paste that route to the canvas's copy:/paste:).
                Button("Copy Style") { send("copyLayerStyle:") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Style") { send("pasteLayerStyle:") }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            // OBJECT ▸ structure + components + conversion.
            CommandMenu("Object") {
                Button("Group") { send("groupSelection:") }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Ungroup") { send("ungroupSelection:") }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                // Lock / Unlock the selection (also on the layer rows + right-click).
                Button("Lock") { send("lockSelection:") }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Unlock") { send("unlockSelection:") }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                // Mask: top selected shape clips the rest (non-destructive). ⌃⌘M
                // avoids ⌘M (minimize) and ⇧⌘M.
                Button("Mask with Top Shape") { send("maskWithTopShapeAction:") }
                    .keyboardShortcut("m", modifiers: [.command, .control])
                Button("Release Mask") { send("releaseMaskAction:") }
                // Frame traits. ⌥⌘A / ⌥⌘P avoid stealing capital letters while typing
                // (a bare ⇧-letter equivalent would). Titles are fixed here; the
                // canvas's validateMenuItem swaps them to Add/Remove contextually.
                Button("Auto Layout") { send("toggleAutoLayoutAction:") }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button("Auto Padding") { send("toggleAutoPaddingAction:") }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Move Item Forward") { send("nudgeItemForwardAction:") }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Move Item Backward") { send("nudgeItemBackwardAction:") }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Divider()
                Button("Create Component") { send("createComponentAction:") }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New Empty Component") { send("newEmptyComponentAction:") }
                Button("Edit Component") { send("editComponentAction:") }
                Button("Detach Component") { send("detachComponentAction:") }
                // Phase 19a: component categories, vocabulary = curated ARIA roles.
                // Friendly labels shown; the ARIA token rides in representedObject
                // (send() is parameterless, so each choice ships its token on a
                // stand-in NSMenuItem sender the canvas action reads back).
                Menu("Set Component Category") {
                    Button("Uncategorized") { sendComponentCategory(nil) }
                    ForEach(AriaRole.grouped(), id: \.category) { group in
                        Section(group.category.label) {
                            ForEach(group.roles, id: \.self) { role in
                                Button(role.friendlyLabel) { sendComponentCategory(role) }
                            }
                        }
                    }
                }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Convert to Path") { send("convertToPathAction:") }
                Button("Round to Pixel") { send("roundToPixelAction:") }
                Divider()
                // No key-equivalent: `i` is a canvas key (like the V/A/R/… tool
                // letters), handled in the canvas's keyDown so it never hijacks a
                // focused text field. The menu item is for discoverability.
                Button("Eyedropper (Pick Fill) — i") { send("eyedropperAction:") }
            }

            // TYPE ▸ text styling + outlines.
            CommandMenu("Type") {
                Button("Bold") { send("toggleBoldText:") }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { send("toggleItalicText:") }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Underline") { send("toggleUnderlineText:") }
                    .keyboardShortcut("u", modifiers: .command)
                Divider()
                Button("Convert to Outlines") { send("convertTextToShapesAction:") }
                Divider()
                Button("Save as Type Style") { send("saveTypeStyleAction:") }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            // ARRANGE ▸ z-order + align + distribute.
            CommandMenu("Arrange") {
                Button("Bring to Front") { send("bringToFront:") }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Bring Forward") { send("bringForward:") }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Send Backward") { send("sendBackward:") }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Send to Back") { send("sendToBack:") }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Flip Horizontal") { send("flipHorizontalAction:") }
                Button("Flip Vertical") { send("flipVerticalAction:") }
                Divider()
                Button("Align Left") { send("alignLeftAction:") }
                Button("Align Horizontal Centers") { send("alignHCenterAction:") }
                Button("Align Right") { send("alignRightAction:") }
                Button("Align Top") { send("alignTopAction:") }
                Button("Align Vertical Centers") { send("alignVCenterAction:") }
                Button("Align Bottom") { send("alignBottomAction:") }
                Divider()
                Button("Distribute Horizontally") { send("distributeHorizontallyAction:") }
                Button("Distribute Vertically") { send("distributeVerticallyAction:") }
            }

            // VIEW ▸ zoom + overlays (added to the system View menu via .toolbar slot).
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { send("zoomInAction:") }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { send("zoomOutAction:") }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size (100%)") { send("zoomActualAction:") }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom to Fit") { send("fitToScreen:") }
                    .keyboardShortcut("1", modifiers: .command)
                Divider()
                Button("Toggle Selection Bounds") { send("toggleSelectionBounds:") }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("Expand All Layers") { send("expandAllLayersAction:") }
                Button("Collapse All Layers") { send("collapseAllLayersAction:") }
                Divider()
                Button("Show / Hide Rulers") { send("toggleRulersAction:") }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Show / Hide Guides") { send("toggleGuidesAction:") }
                    .keyboardShortcut(";", modifiers: .command)
                Button("Lock Guides") { send("toggleLockGuidesAction:") }
                    .keyboardShortcut(";", modifiers: [.command, .option])
                Button("Clear Guides") { send("clearGuidesAction:") }
                Divider()
                Button("Show / Hide Grid") { send("toggleGridAction:") }
                    .keyboardShortcut("'", modifiers: .command)
                Button("Snap to Grid") { send("toggleSnapToGridAction:") }
                    .keyboardShortcut("'", modifiers: [.command, .shift])
                Divider()
                Button("Testing Mode (Perf Logging)") { send("toggleTestingModeAction:") }
                    .keyboardShortcut("t", modifiers: [.command, .control])
                Button("Log Geometry Audit") { send("runGeometryAuditAction:") }
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
    }

    /// Send an action up the responder chain to whichever canvas is focused.
    private func send(_ selectorName: String) {
        NSApp.sendAction(NSSelectorFromString(selectorName), to: nil, from: nil)
    }

    /// Phase 19a helper: category choices need a payload, and `send` can't carry
    /// one — so wrap the ARIA token in a stand-in NSMenuItem and pass it as the
    /// action's sender (nil token = uncategorized).
    private func sendComponentCategory(_ role: AriaRole?) {
        let item = NSMenuItem(title: role?.friendlyLabel ?? "Uncategorized",
                              action: nil, keyEquivalent: "")
        item.representedObject = role?.rawValue
        NSApp.sendAction(NSSelectorFromString("setComponentCategoryAction:"), to: nil, from: item)
    }
}

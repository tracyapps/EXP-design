//
//  CanvasTokenActions.swift
//  EXP [design]
//
//  FEAT-089a (v2.9): create, edit and delete Design Language dimension tokens.
//  Plan: docs/DESIGN-LANGUAGE-PLAN.md. App target only.
//
//  These live on the canvas view because every user-facing action has ONE
//  implementation there (CLAUDE.md → Command-coverage rule); the menu bar and
//  the Design Language panel both dispatch here through `sendCanvasAction`.
//

import AppKit
import SwiftUI

struct DLApplyDimensionToken {
    let id: UUID
    let linked: Bool
}

extension CanvasNSView {

    @objc func applyDimensionTokenAction(_ sender: Any?) {
        guard let request = (sender as? NSMenuItem)?.representedObject as? DLApplyDimensionToken,
              scope == .document, let document, let app else { return }
        app.finishInlineTextEditing?()
        var model = document.model
        guard model.applyNumericToken(request.id, on: app.activeCanvasPageID,
                                      selection: app.selectedNodeIDs, linked: request.linked) else { return }
        let title = model.designLanguage.token(request.id)?.name ?? "Dimension Token"
        document.setModel(model, undoManager: undoManager,
                          actionName: request.linked ? "Link \(title)" : "Apply \(title)")
    }

    /// Object ▸ New \(kind.rawValue) Token… and the panel's + button. An NSMenuItem can
    /// carry the dimension kind and a starting value.
    @objc func newDimensionTokenAction(_ sender: Any?) {
        guard let document else { return }
        let request = (sender as? NSMenuItem)?.representedObject as? DLNewDimensionToken
        let kind = request?.kind ?? .spacing
        let existing = document.model.designLanguage.tokens(role: kind.role).count
        let startValue = request?.value ?? kind.defaultValue
        promptForDimensionToken(title: "New \(kind.rawValue) Token", confirm: "Create",
                              name: "\(kind.namePrefix) \(existing + 1)", value: startValue) { [weak self, weak document] name, value in
            guard let self, let document else { return }
            var model = document.model
            model.designLanguage.addToken(DLToken(name: name, type: .dimension, role: kind.role, value: value))
            document.setModel(model, undoManager: self.undoManager, actionName: "New \(kind.rawValue) Token")
        }
    }

    /// Edit a saved token in one sheet. The menu item carries its stable ID.
    @objc func editDimensionTokenAction(_ sender: Any?) {
        guard let document, let window, window.attachedSheet == nil,
              let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let token = document.model.designLanguage.token(id),
              let kind = DLDimensionKind.allCases.first(where: { $0.role == token.role }) else { return }
        window.beginSheet {
            DLDimensionTokenEditor(document: document, token: token, kind: kind, undoManager: undoManager)
        }
    }

    /// Delete a token. Linked properties keep their current numbers and become
    /// unlinked; when anything is linked, say so and ask first.
    @objc func deleteDimensionTokenAction(_ sender: Any?) {
        guard let document, let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let token = document.model.designLanguage.token(id),
              let kind = DLDimensionKind.allCases.first(where: { $0.role == token.role }) else { return }
        let uses = document.model.tokenUseCount(id)
        let delete = { [weak self, weak document] in
            guard let self, let document else { return }
            var model = document.model
            model.removeToken(id)
            document.setModel(model, undoManager: self.undoManager, actionName: "Delete \(kind.rawValue) Token")
        }
        guard uses > 0, let window else { delete(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(token.name)”?"
        alert.informativeText = uses == 1
            ? "1 property is linked to this token. It keeps its current value and becomes unlinked."
            : "\(uses) properties are linked to this token. They keep their current values and become unlinked."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { delete() }
        }
    }

    /// The quick-add sheet takes a name and a value. The value accepts a plain
    /// number or any CSS length; what is typed is what is stored.
    private func promptForDimensionToken(title: String, confirm: String, name: String, value: String,
                                       onSave: @escaping (String, DLTokenValue) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Value: a number, or any CSS length such as 16, 1rem, 1.5em or clamp(1rem, 2vw, 2rem)."
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")

        // Plain frames, no Auto Layout: an accessory view that throws while
        // being built is swallowed by AppKit and the command silently does nothing.
        let width: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 0, y: 82, width: width, height: 16)
        let nameField = NSTextField(frame: NSRect(x: 0, y: 56, width: width, height: 24))
        nameField.stringValue = name
        nameField.setAccessibilityLabel("Token name")
        let valueLabel = NSTextField(labelWithString: "Value")
        valueLabel.frame = NSRect(x: 0, y: 30, width: width, height: 16)
        let valueField = NSTextField(frame: NSRect(x: 0, y: 4, width: width, height: 24))
        valueField.stringValue = value
        valueField.setAccessibilityLabel("Token value")
        for label in [nameLabel, valueLabel] { label.font = .systemFont(ofSize: NSFont.smallSystemFontSize) }
        for view in [nameLabel, nameField, valueLabel, valueField] { container.addSubview(view) }
        nameField.nextKeyView = valueField
        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = DLTokenValue.parsingLength(valueField.stringValue) else {
                NSSound.beep()
                return
            }
            onSave(trimmedName.isEmpty ? name : trimmedName, parsed)
        }
    }
}

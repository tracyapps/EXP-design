//
//  CanvasTokenActions.swift
//  EXP [design]
//
//  FEAT-089a (v2.9): create, edit and delete Design Language spacing tokens.
//  Plan: docs/DESIGN-LANGUAGE-PLAN.md. App target only.
//
//  These live on the canvas view because every user-facing action has ONE
//  implementation there (CLAUDE.md → Command-coverage rule); the menu bar and
//  the Design Language panel both dispatch here through `sendCanvasAction`.
//

import AppKit

extension CanvasNSView {

    /// Object ▸ New Spacing Token… and the panel's + button. An NSMenuItem
    /// sender may carry a starting value string in `representedObject`.
    @objc func newSpacingTokenAction(_ sender: Any?) {
        guard let document else { return }
        let existing = document.model.designLanguage.tokens(role: .spacing).count
        let startValue = ((sender as? NSMenuItem)?.representedObject as? String) ?? "16"
        promptForSpacingToken(title: "New Spacing Token", confirm: "Create",
                              name: "Space \(existing + 1)", value: startValue) { [weak self, weak document] name, value in
            guard let self, let document else { return }
            var model = document.model
            model.designLanguage.addToken(DLToken(name: name, type: .dimension, role: .spacing, value: value))
            document.setModel(model, undoManager: self.undoManager, actionName: "New Spacing Token")
        }
    }

    /// Edit a token's name and value. The sender is an NSMenuItem whose
    /// `representedObject` is the token's UUID. Everything linked to the token
    /// updates and reflows in the same undo step.
    @objc func editSpacingTokenAction(_ sender: Any?) {
        guard let document, let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let token = document.model.designLanguage.token(id) else { return }
        promptForSpacingToken(title: "Edit Spacing Token", confirm: "Save",
                              name: token.name, value: token.value.authoredText) { [weak self, weak document] name, value in
            guard let self, let document else { return }
            var model = document.model
            guard model.designLanguage.token(id) != nil else { return }
            model.designLanguage.renameToken(id, to: name)
            model.setTokenValue(id, to: value)
            document.setModel(model, undoManager: self.undoManager, actionName: "Edit Spacing Token")
        }
    }

    /// Delete a token. Linked properties keep their current numbers and become
    /// unlinked; when anything is linked, say so and ask first.
    @objc func deleteSpacingTokenAction(_ sender: Any?) {
        guard let document, let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let token = document.model.designLanguage.token(id) else { return }
        let uses = document.model.tokenUseCount(id)
        let delete = { [weak self, weak document] in
            guard let self, let document else { return }
            var model = document.model
            model.removeToken(id)
            document.setModel(model, undoManager: self.undoManager, actionName: "Delete Spacing Token")
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

    /// One sheet for New and Edit: a name and a value. The value accepts a plain
    /// number or any CSS length; what is typed is what is stored.
    private func promptForSpacingToken(title: String, confirm: String, name: String, value: String,
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

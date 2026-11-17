//
//  DesignLanguageSpacing.swift
//  EXP [design]
//
//  FEAT-089a (v2.9): the Spacing section of the Design Language panel.
//  Plan: docs/DESIGN-LANGUAGE-PLAN.md §5. App target only.
//
//  Every action dispatches to the canvas (`CanvasTokenActions.swift`), so the
//  panel, the menu bar and any later surface share one implementation.
//

import SwiftUI
import AppKit

/// Remembers the last use counts so a drag on the canvas (which republishes the
/// model on every mouse event) never pays for a document walk per event.
private final class DLTokenUseCache {
    var counts: [UUID: Int] = [:]
}

struct DLSpacingSection: View {
    @ObservedObject var document: ExpDocument
    @State private var cache = DLTokenUseCache()

    /// The widest bar, in points. Larger values are drawn at this width.
    private static let barColumn: CGFloat = 64

    var body: some View {
        // Read the model ONCE per render; rows get plain values (see the panel
        // lag postmortem: per-row computed properties re-walk the model).
        let language = document.model.designLanguage
        let tokens = language.tokens(role: .spacing)
        let context = DLResolveContext(modeIDs: language.activeModeIDs)
        let uses = useCounts(hasTokens: !tokens.isEmpty)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SPACING")
                    .font(.system(size: EXPType.micro, weight: .semibold))
                    .tracking(EXPType.tracking(EXPType.trCaps, EXPType.micro))
                    .foregroundStyle(EXPColor.textSecondary)
                Text("\(tokens.count)")
                    .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textTertiary)
                Spacer(minLength: 0)
                Button { _ = sendCanvasAction("newSpacingTokenAction:") } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(EXPColor.textSecondary)
                .help("New spacing token")
                .accessibilityLabel("New spacing token")
            }
            if tokens.isEmpty {
                Text("Named spacing values for gap, padding and margin. Press + to add one.")
                    .font(.system(size: EXPType.micro)).foregroundStyle(EXPColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 3) {
                    ForEach(tokens) { token in
                        DLSpacingRow(token: token,
                                     resolved: language.resolvedNumber(token.id, context: context),
                                     uses: uses[token.id] ?? 0,
                                     barColumn: Self.barColumn)
                    }
                }
            }
        }
    }

    private func useCounts(hasTokens: Bool) -> [UUID: Int] {
        guard hasTokens else { return [:] }
        if NSEvent.pressedMouseButtons == 0 { cache.counts = document.model.tokenUseCounts() }
        return cache.counts
    }
}

private struct DLSpacingRow: View {
    let token: DLToken
    let resolved: CGFloat?
    let uses: Int
    let barColumn: CGFloat

    private var title: String { token.name.isEmpty ? "Unnamed" : token.name }
    private var authored: String {
        if token.value.aliasTarget != nil { return "alias" }
        let text = token.value.authoredText
        return text.isEmpty ? "preserved value" : text
    }
    /// "1rem · 16" when the authored text isn't already the plain number.
    private var valueText: String {
        guard let resolved else { return authored }
        let number = Self.format(resolved)
        return (authored == number || authored == number + "px") ? authored : "\(authored) · \(number)"
    }
    private var usesText: String { uses == 0 ? "unused" : (uses == 1 ? "1 use" : "\(uses) uses") }
    private var spoken: String {
        let value = resolved.map { "\(authored), resolves to \(Self.format($0))" }
            ?? "\(authored), cannot be measured without an artboard"
        return "\(title), spacing token, \(value), \(usesText)"
    }

    private static func format(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", Double(value))
    }
    private func item() -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = token.id
        return item
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        Button { _ = sendCanvasAction("editSpacingTokenAction:", from: item()) } label: {
            HStack(spacing: 8) {
                // The bar shows the value at true size up to the column width.
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(resolved == nil ? EXPColor.textTertiary : EXPColor.accent)
                        .frame(width: Swift.max(2, Swift.min(resolved ?? 2, barColumn)), height: 10)
                    Spacer(minLength: 0)
                }
                .frame(width: barColumn)
                .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(EXPColor.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(valueText)
                    .font(.system(size: EXPType.micro, design: .monospaced))
                    .foregroundStyle(EXPColor.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(usesText)
                    .font(.system(size: EXPType.micro))
                    .foregroundStyle(EXPColor.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 26)
            .background(RoundedRectangle(cornerRadius: EXPMetric.radiusRow).fill(EXPColor.rowHover.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
        }
        .buttonStyle(.plain)
        .help("\(title) — \(valueText) · \(usesText). Click to edit.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Edits this token")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("Edit…") { _ = sendCanvasAction("editSpacingTokenAction:", from: item()) }
            Divider()
            Button("Copy Name") { copy(title) }
            Button("Copy Value") { copy(authored) }
            Divider()
            Button("Delete", role: .destructive) { _ = sendCanvasAction("deleteSpacingTokenAction:", from: item()) }
        }
    }
}

// MARK: - Settings ▸ Design Language ▸ Spacing

/// The bulk editor's Spacing group: every token as an editable row, plus an add
/// row. Rows keep a local draft and commit on Return or when focus leaves, so
/// typing never writes the document per keystroke.
struct DLSpacingSettingsGroup: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?

    @State private var draftName = ""
    @State private var draftValue = ""

    private var draftParsed: DLTokenValue? { DLTokenValue.parsingLength(draftValue) }

    var body: some View {
        let model = document.model
        let language = model.designLanguage
        let tokens = language.tokens(role: .spacing)
        let context = DLResolveContext(modeIDs: language.activeModeIDs)
        let uses = tokens.isEmpty ? [:] : model.tokenUseCounts()

        SettingsGroup(
            "Spacing (\(tokens.count))",
            footnote: "Named spacing values for gap, padding and margin. A value is a number or any CSS length: 16, 1rem, 1.5em, clamp(1rem, 2vw, 2rem). Changing a value updates everything linked to it."
        ) {
            if tokens.isEmpty {
                Text("No spacing tokens yet.").foregroundStyle(.secondary)
            } else {
                ForEach(tokens) { token in
                    DLSpacingSettingsRow(
                        token: token,
                        resolved: language.resolvedNumber(token.id, context: context),
                        uses: uses[token.id] ?? 0,
                        onRename: { name in
                            commit("Rename Spacing Token") { $0.designLanguage.renameToken(token.id, to: name) }
                        },
                        onSetValue: { value in
                            commit("Edit Spacing Token") { $0.setTokenValue(token.id, to: value) }
                        },
                        onDelete: {
                            commit("Delete Spacing Token") { $0.removeToken(token.id) }
                        })
                    Divider().opacity(0.4)
                }
            }
            HStack(spacing: 8) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("New spacing token name")
                TextField("Value, e.g. 16 or 1rem", text: $draftValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("New spacing token value")
                    .onSubmit(add)
                Spacer()
                Button("Add", action: add)
                    .buttonStyle(.exp(.primary))
                    .disabled(draftParsed == nil)
            }
        }
    }

    private func add() {
        guard let value = draftParsed else { return }
        let existing = document.model.designLanguage.tokens(role: .spacing).count
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Space \(existing + 1)" : trimmed
        commit("New Spacing Token") {
            $0.designLanguage.addToken(DLToken(name: name, type: .dimension, role: .spacing, value: value))
        }
        draftName = ""
        draftValue = ""
    }

    private func commit(_ action: String, _ change: (inout Document) -> Void) {
        var model = document.model
        change(&model)
        document.setModel(model, undoManager: undoManager, actionName: action)
    }
}

private struct DLSpacingSettingsRow: View {
    let token: DLToken
    let resolved: CGFloat?
    let uses: Int
    let onRename: (String) -> Void
    let onSetValue: (DLTokenValue) -> Void
    let onDelete: () -> Void

    @State private var name = ""
    @State private var value = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool
    @FocusState private var valueFocused: Bool

    private var title: String { token.name.isEmpty ? "Unnamed" : token.name }
    /// Aliases and preserved values aren't plain text; they stay read-only here.
    private var isEditableValue: Bool {
        switch token.value {
        case .dimension, .number, .raw: return true
        case .alias, .preserved: return false
        }
    }
    private var detail: String {
        let measured: String
        if let resolved {
            let number = resolved == resolved.rounded() ? String(Int(resolved)) : String(format: "%.2f", Double(resolved))
            measured = "resolves to \(number)"
        } else {
            measured = "measured on an artboard"
        }
        return "\(measured) · \(uses == 0 ? "unused" : (uses == 1 ? "1 use" : "\(uses) uses"))"
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .focused($nameFocused)
                .onSubmit(commitName)
                .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                .accessibilityLabel("Name of \(title)")
            TextField("Value", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 220)
                .focused($valueFocused)
                .disabled(!isEditableValue)
                .onSubmit(commitValue)
                .onChange(of: valueFocused) { _, focused in if !focused { commitValue() } }
                .accessibilityLabel("Value of \(title)")
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(role: .destructive) {
                if uses > 0 { confirmingDelete = true } else { onDelete() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(title)")
            .accessibilityLabel("Delete \(title)")
        }
        .onAppear { reset() }
        .onChange(of: token) { _, _ in reset() }
        .confirmationDialog("Delete “\(title)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(uses == 1
                 ? "1 property is linked to this token. It keeps its current value and becomes unlinked."
                 : "\(uses) properties are linked to this token. They keep their current values and become unlinked.")
        }
    }

    private func reset() {
        name = token.name
        value = isEditableValue ? token.value.authoredText : "alias or preserved value"
    }
    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { name = token.name; return }
        if trimmed != token.name { onRename(trimmed) }
    }
    private func commitValue() {
        guard isEditableValue else { return }
        // Empty or unchanged input restores what was there; it never clears a token.
        guard let parsed = DLTokenValue.parsingLength(value), parsed != token.value else {
            value = token.value.authoredText
            return
        }
        onSetValue(parsed)
    }
}


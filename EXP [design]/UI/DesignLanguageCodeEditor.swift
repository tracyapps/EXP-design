import AppKit
import SwiftUI

/// An unapplied draft belongs to the open document. Hiding Settings or
/// switching documents doesn't discard it or put it into the saved file.
@Observable
final class DLCodeSession {
    var text = ""
    private(set) var baseline: DesignLanguageCode.Content?
    private var originalText = ""

    var isEdited: Bool { baseline != nil && text != originalText }

    func load(_ content: DesignLanguageCode.Content) throws {
        let json = try DesignLanguageCode.encode(content)
        baseline = content
        originalText = json
        text = json
    }
}

struct DesignLanguageCodeEditor: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    @Bindable var session: DLCodeSession

    @State private var format = DLCodeFormat.json
    @State private var sourceControls = DLSourceControls()
    @State private var exported = ""
    @State private var failure: String?
    @State private var notice: String?
    @State private var preview: DesignLanguageCode.Preview?
    @State private var confirmReload = false

    private var content: DesignLanguageCode.Content { .init(document.model.designLanguage) }
    private var stale: Bool { session.baseline.map { $0 != content } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Code format", selection: $format) {
                    ForEach(DLCodeFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Menu("Folding", systemImage: "chevron.left.forwardslash.chevron.right") {
                    Button("Toggle Fold at Cursor") { sourceControls.perform?(.toggleBlock) }
                    Button("Fold All") { sourceControls.perform?(.foldAll) }
                    Button("Expand All") { sourceControls.perform?(.expandAll) }
                        .disabled(!sourceControls.hasFolds)
                }
                .accessibilityLabel("Code folding")
                Button("Copy \(format.rawValue)", systemImage: "doc.on.doc", action: copyText)
                    .disabled(format == .json ? session.text.isEmpty : exported.isEmpty)
            }

            if format == .json {
                Text("Keep IDs when editing existing entries. To add a solid swatch, add an object such as { \"name\": \"Accent\", \"value\": \"#336699\" } to assets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Generated from the current document. Apply your JSON draft to include its changes here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            DLSourceTextView(source: format == .json ? session.text : exported, format: format,
                             onEdit: format == .json ? { session.text = $0 } : nil, controls: sourceControls)
                .id(format)
                .frame(minHeight: 130, maxHeight: .infinity)
                .layoutPriority(1)
                .onChange(of: session.text) { _, _ in
                    if session.isEdited { failure = nil; notice = nil }
                }

            if format == .json {
                HStack {
                    Button("Reload from Document") {
                        if session.isEdited { confirmReload = true }
                        else { reload() }
                    }
                    .disabled(!session.isEdited && !stale && session.baseline != nil)
                    if sourceControls.hasFolds {
                        Button("Expand to Edit") { sourceControls.perform?(.expandAll) }
                    }
                    Spacer()
                    Button("Review Changes…", action: review)
                        .buttonStyle(.borderedProminent)
                        .disabled(session.baseline == nil || !session.isEdited || stale)
                        .accessibilityIdentifier("designLanguage.code.review")
                }
            }

            if stale {
                Label(DesignLanguageCode.Issue.stale.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if session.isEdited && format != .json {
                Text("Unapplied JSON draft")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Text(notice).foregroundStyle(.secondary)
            }
        }
        .onChange(of: content, initial: true) { _, _ in
            if !session.isEdited { reload() }
            if format != .json { refreshExport() }
        }
        .onChange(of: format) { _, _ in
            sourceControls.hasFolds = false
            refreshExport()
        }
        .confirmationDialog("Reload JSON from the document?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Discard Draft and Reload", role: .destructive, action: reload)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unapplied edits will be discarded.")
        }
        .sheet(item: $preview) { selection in
            DLCodeChangeSheet(preview: selection, document: document) {
                apply(selection)
            }
        }
    }

    private func reload() {
        do { try session.load(content); failure = nil; notice = nil }
        catch { show(error) }
    }

    private func refreshExport() {
        failure = nil
        notice = nil
        exported = ""
        guard let name = format.filename else { return }
        do {
            let guide = try DesignLanguageGuideBuilder.build(document: document.model, title: "Design Language")
            exported = guide.files[name] ?? ""
        } catch { show(error) }
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(format == .json ? session.text : exported, forType: .string) {
            notice = "Copied \(format.rawValue)."
            announce(notice)
        }
    }

    private func review() {
        guard let baseline = session.baseline else { return }
        failure = nil
        notice = nil
        do {
            let result = try DesignLanguageCode.preview(session.text, from: baseline, in: document.model)
            if result.changes.isEmpty {
                notice = "No token changes to apply."
                announce(notice)
            } else {
                preview = result
            }
        } catch { show(error) }
    }

    private func apply(_ result: DesignLanguageCode.Preview) {
        do {
            let next = try result.applying(to: document.model)
            document.setModel(next, undoManager: undoManager, actionName: "Apply Design Language Code")
            preview = nil
            reload()
            if failure == nil {
                notice = "Design Language updated."
                announce(notice)
            }
        } catch {
            preview = nil
            show(error)
        }
    }

    private func show(_ error: Error) {
        failure = error.localizedDescription
        announce(failure)
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct DLCodeChangeSheet: View {
    let preview: DesignLanguageCode.Preview
    @ObservedObject var document: ExpDocument
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Design Language Changes").font(.headline)
            let links = preview.affectedLinkCount(in: document.model)
            if links > 0 {
                let message = links == 1
                    ? "1 linked property will keep its current value and lose its link."
                    : "\(links) linked properties will keep their current values and lose their links."
                Label(message, systemImage: "link.badge.minus")
                    .fixedSize(horizontal: false, vertical: true)
            }
            List(preview.changes) { change in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(change.action.rawValue) \(change.kind) · \(change.title)")
                        .fontWeight(.medium)
                    if let detail = change.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 150, idealHeight: 230)
            .accessibilityLabel("Proposed Design Language changes")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply Changes", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 490)
    }
}

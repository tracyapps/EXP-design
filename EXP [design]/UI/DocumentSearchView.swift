import AppKit
import SwiftUI

struct DocumentSearchView: View {
    let pages: [CanvasPage]
    let search: DocumentSearch
    let finish: (DocumentSearch.Target?) -> Void

    @State private var query = ""
    @State private var kind: DocumentSearch.Kind?
    @State private var pageID: UUID?
    @State private var componentNameOnly = false
    @State private var selection: DocumentSearch.Target?

    private var currentMatches: [DocumentSearch.Result] {
        search.matches(query, kind: kind, pageID: pageID, componentNameOnly: componentNameOnly)
    }

    var body: some View {
        let matches = currentMatches
        VStack(alignment: .leading, spacing: 10) {
            Text("Find in Document").font(.headline).accessibilityAddTraits(.isHeader)
            DocumentSearchField(
                query: $query,
                move: { moveSelection($0, in: currentMatches) },
                submit: { open(from: currentMatches) },
                cancel: { finish(nil) }
            )
            .frame(height: EXPInterfaceAccessibility.shared.targetHeight(24))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { filters }
                VStack(alignment: .leading, spacing: 6) { filters }
            }
            ScrollViewReader { proxy in
                List(matches, selection: $selection) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).lineLimit(1)
                            Text(result.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(result.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: EXPInterfaceAccessibility.shared.targetHeight(24))
                    .tag(result.id)
                    .contentShape(Rectangle())
                    .help(result.location)
                    .onTapGesture(count: 2) { finish(result.id) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Open") { finish(result.id) }
                }
                .accessibilityLabel("Search results")
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                    }
                }
                .onChange(of: selection) { _, target in
                    if let target { proxy.scrollTo(target) }
                }
                .onChange(of: query) { selectFirst(in: matches) }
                .onChange(of: kind) { selectFirst(in: matches) }
                .onChange(of: pageID) { selectFirst(in: matches) }
                .onChange(of: componentNameOnly) { selectFirst(in: matches) }
                .onAppear { selectFirst(in: matches) }
            }
            HStack {
                Text(matches.count == 1 ? "1 result" : "\(matches.count) results")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Open") { open(from: matches) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(matches.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 600, height: 420)
        .expInterfaceTypeSize()
    }

    @ViewBuilder private var filters: some View {
        Picker("Type", selection: $kind) {
            Text("All Types").tag(nil as DocumentSearch.Kind?)
            ForEach(DocumentSearch.Kind.allCases, id: \.self) { kind in
                Text(kind.filterName).tag(Optional(kind))
            }
        }
        Picker("Page", selection: $pageID) {
            Text("All Pages").tag(nil as UUID?)
            ForEach(pages) { page in
                Text(page.name).tag(Optional(page.id))
            }
        }
        Toggle("Component name only", isOn: $componentNameOnly)
    }

    private func selectFirst(in matches: [DocumentSearch.Result]) {
        selection = matches.first?.id
    }

    private func moveSelection(_ delta: Int, in matches: [DocumentSearch.Result]) {
        guard !matches.isEmpty else { return }
        let current = matches.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + delta, 0), matches.count - 1) } ?? 0
        selection = matches[next].id
    }

    private func open(from matches: [DocumentSearch.Result]) {
        if let target = matches.first(where: { $0.id == selection })?.id ?? matches.first?.id {
            finish(target)
        }
    }
}

private struct DocumentSearchField: NSViewRepresentable {
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = SearchField()
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.updateQuery(_:))
        field.placeholderString = "Search names and locations"
        field.setAccessibilityLabel("Search document")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.view = self
        field.font = .systemFont(ofSize: NSFont.systemFontSize * EXPInterfaceAccessibility.shared.textScale)
        if field.stringValue != query { field.stringValue = query }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var view: DocumentSearchField

        init(_ view: DocumentSearchField) { self.view = view }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            updateQuery(field)
        }

        @objc func updateQuery(_ field: NSSearchField) {
            view.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): view.move(1)
            case #selector(NSResponder.moveUp(_:)): view.move(-1)
            case #selector(NSResponder.insertNewline(_:)): view.submit()
            case #selector(NSResponder.cancelOperation(_:)): view.cancel()
            default: return false
            }
            return true
        }
    }

    private final class SearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.initialFirstResponder = self
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.isKeyWindow else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

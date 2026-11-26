import AppKit
import SwiftUI

enum DLColorModeEdit {
    case enable
    case adoptLibrary
    case name(String, UUID?)
    case defaultColor(RGBAColor, DLModeColorRole, UUID)
    case document(UUID)
    case page(UUID?, UUID)
    case icon(String?, UUID)
    case artboards(UUID?, Set<UUID>)
    case artboardBackground(Set<UUID>)

    private var undoName: String {
        switch self {
        case .enable: "Enable Color Modes"
        case .adoptLibrary: "Adopt Library Color Modes"
        case .name(_, nil): "Add Color Mode"
        case .name: "Rename Color Mode"
        case .defaultColor: "Edit Mode Colors"
        case .document: "Change Document Color Mode"
        case .page: "Change Page Color Mode"
        case .icon: "Change Color Mode Icon"
        case .artboards: "Change Artboard Color Mode"
        case .artboardBackground: "Use Mode Background"
        }
    }

    @discardableResult
    func commit(to document: ExpDocument, undoManager: UndoManager?, pageID: UUID? = nil) -> Bool {
        var model = document.model
        let changed: Bool
        switch self {
        case .enable: changed = model.designLanguage.enableColorModes()
        case .adoptLibrary: changed = model.adoptLibraryColorModes()
        case .name(let name, let id): changed = model.designLanguage.nameColorMode(name, id: id)
        case .defaultColor(let color, let role, let id):
            changed = model.designLanguage.setModeColor(color, for: role, modeID: id)
        case .document(let id): changed = model.designLanguage.selectDocumentColorMode(id)
        case .page(let id, let page): changed = model.selectPageColorMode(id, on: page)
        case .icon(let symbol, let id): changed = model.designLanguage.setModeIcon(symbol, modeID: id)
        case .artboards(let id, let boards):
            changed = model.selectArtboardColorMode(id, for: boards, on: pageID)
        case .artboardBackground(let boards):
            changed = model.useModeBackground(for: boards, on: pageID)
        }
        guard changed else { return false }
        document.setModel(model, undoManager: undoManager, actionName: undoName)
        return true
    }

    /// A represented object works for AppKit context menus and SwiftUI commands.
    func sendToCanvas() {
        let item = NSMenuItem()
        item.representedObject = self
        sendCanvasAction(NSStringFromSelector(#selector(CanvasNSView.editColorModeAction(_:))), from: item)
    }
}

extension CanvasNSView {
    @objc func editColorModeAction(_ sender: Any?) {
        guard let document, let edit = (sender as? NSMenuItem)?.representedObject as? DLColorModeEdit else { return }
        switch edit {
        case .page, .artboards, .artboardBackground: guard scope == .document else { return }
        default: break
        }
        if !edit.commit(to: document, undoManager: undoManager, pageID: app?.activeCanvasPageID),
           case .adoptLibrary = edit { NSSound.beep() }
    }
}

private struct DLModeChoice: Identifiable {
    let id: UUID?
    let title: String
    let selected: Bool
    let action: DLColorModeEdit
}

/// Mode choices are shared by the artboard header and the Inspector.
struct DLColorModePicker: View {
    let language: DesignLanguage
    var artboard: Artboard?
    var page: CanvasPage?
    var inArtboardHeader = false
    let edit: (DLColorModeEdit) -> Void

    var body: some View {
        if let set = language.colorModeSet, let mode = language.colorMode(for: artboard, on: page) {
            let overrideID = artboard?.modeOverrides?[set.id.uuidString]
            let hasOverride = set.modes.contains { $0.id == overrideID }
            let label = artboard.map { "Color mode for \($0.name)" } ?? "Document color mode"
            let value = artboard != nil && !hasOverride ? "\(mode.name), follows page" : mode.name
            let pageMode = language.colorMode(on: page)
            let inherit = artboard.flatMap { board in
                pageMode.map {
                    DLModeChoice(id: nil, title: "Use Page Mode (\($0.name))", selected: !hasOverride,
                                 action: .artboards(nil, [board.id]))
                }
            }
            let options = set.modes.map { option in
                if let artboard {
                    return DLModeChoice(id: option.id, title: option.name, selected: overrideID == option.id,
                                        action: .artboards(option.id, [artboard.id]))
                }
                return DLModeChoice(id: option.id, title: option.name, selected: mode.id == option.id,
                                    action: .document(option.id))
            }

            if inArtboardHeader, let pageMode {
                DLArtboardModePopUp(title: mode.name, label: label, value: value,
                                    foreground: pageMode.canvasWallLabelColor, inherit: inherit,
                                    options: options, edit: edit)
                    .frame(height: 20)
                    .overlay {
                        if hasOverride {
                            RoundedRectangle(cornerRadius: 5).strokeBorder(EXPColor.accent)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            } else {
                Menu {
                    if let inherit {
                        choice(inherit)
                        Divider()
                    }
                    ForEach(options) { choice($0) }
                } label: {
                    Text(mode.name).lineLimit(1).truncationMode(.tail)
                }
                .font(.caption)
                .controlSize(.small)
                .accessibilityLabel(label)
                .accessibilityValue(value)
                .help(value)
            }
        }
    }

    private func choice(_ option: DLModeChoice) -> some View {
        Button { edit(option.action) } label: {
            if option.selected { Label(option.title, systemImage: "checkmark") }
            else { Text(option.title) }
        }
        .accessibilityAddTraits(option.selected ? .isSelected : [])
    }
}

/// AppKit draws this title and arrow as part of the menu control. Give the
/// control its own appearance so it follows the wall rather than the app chrome.
private struct DLArtboardModePopUp: NSViewRepresentable {
    let title: String
    let label: String
    let value: String
    let foreground: RGBAColor
    let inherit: DLModeChoice?
    let options: [DLModeChoice]
    let edit: (DLColorModeEdit) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = HeaderPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.lineBreakMode = .byTruncatingTail
        if let cell = button.cell as? NSPopUpButtonCell {
            cell.altersStateOfSelectedItem = false
            cell.arrowPosition = .arrowAtCenter
        }
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.edit = edit
        button.appearance = NSAppearance(named: foreground == .black ? .aqua : .darkAqua)
        button.toolTip = value
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)

        let menu = NSMenu()
        menu.autoenablesItems = false
        // A pull-down uses its first item as the collapsed control's title.
        let caption = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        caption.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: PaintRender.nsColor(foreground),
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
        menu.addItem(caption)

        func add(_ option: DLModeChoice) {
            let item = NSMenuItem(title: option.title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.representedObject = option.action
            item.target = coordinator
            item.state = option.selected ? .on : .off
            menu.addItem(item)
        }
        if let inherit {
            add(inherit)
            menu.addItem(.separator())
        }
        for option in options { add(option) }
        button.menu = menu
        (button.cell as? NSPopUpButtonCell)?.synchronizeTitleAndSelectedItem()
    }

    private final class HeaderPopUpButton: NSPopUpButton {
        // Keep AppKit's alignment padding out of the neighboring Notes button.
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    }

    final class Coordinator: NSObject {
        var edit: ((DLColorModeEdit) -> Void)?

        @objc func choose(_ item: NSMenuItem) {
            if let action = item.representedObject as? DLColorModeEdit { edit?(action) }
        }
    }
}

/// The mode control sits beside the page title so activating it can edit an
/// inactive page without switching tabs or changing the current selection.
struct DLPageColorModeControl: View {
    let page: CanvasPage
    let language: DesignLanguage
    let edit: (DLColorModeEdit) -> Void

    var body: some View {
        if let set = language.colorModeSet, let mode = language.colorMode(on: page) {
            let explicit = set.modes.first { $0.id == page.modeOverrides?[set.id.uuidString] }
            let value = explicit == nil ? "\(mode.name), follows document" : mode.name
            if set.modes.count == 2, let next = set.modes.first(where: { $0.id != mode.id }) {
                Button { edit(.page(next.id, page.id)) } label: { icon(mode) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color mode for \(page.name)")
                    .accessibilityValue(value)
                    .accessibilityHint("Switches to \(next.name)")
                    .help("\(value) · Switch to \(next.name)")
            } else if set.modes.count > 2 {
                Menu {
                    Button {
                        edit(.page(nil, page.id))
                    } label: {
                        let name = "Use Document Mode (\(language.colorMode()?.name ?? mode.name))"
                        if explicit == nil { Label(name, systemImage: "checkmark") }
                        else { Text(name) }
                    }
                    Divider()
                    ForEach(set.modes) { option in
                        Button {
                            edit(.page(option.id, page.id))
                        } label: {
                            Label(option.name, systemImage: explicit?.id == option.id ? "checkmark" : option.resolvedIconSymbol)
                        }
                    }
                } label: {
                    icon(mode)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Color mode for \(page.name)")
                .accessibilityValue(value)
                .help(value)
            }
        }
    }

    private func icon(_ mode: DLMode) -> some View {
        Image(systemName: mode.resolvedIconSymbol)
            .font(.system(size: EXPType.small, weight: .medium))
            .frame(width: 24, height: 25)
            .contentShape(Rectangle())
    }
}

enum DLArtboardModeHeader {
    static let width: CGFloat = 78

    static func showsPicker(_ board: Artboard, enabled: Bool, zoom: CGFloat, selected: Bool) -> Bool {
        enabled && (selected || board.frame.width * zoom >= 120)
    }

    static func nameInset(_ board: Artboard, enabled: Bool, zoom: CGFloat, selected: Bool) -> CGFloat {
        showsPicker(board, enabled: enabled, zoom: zoom, selected: selected) ? width + 5 : 0
    }
}

struct DLColorModeSettingsGroup: View {
    @ObservedObject var document: ExpDocument
    let undoManager: UndoManager?
    @State private var showingName = false
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var editingDefault: ModeDefaultField?

    private var language: DesignLanguage { document.model.designLanguage }

    var body: some View {
        SettingsGroup("Color Modes") {
            if let set = language.colorModeSet {
                HStack {
                    Text("Document Mode")
                    DLColorModePicker(language: language, edit: commit)
                    Spacer()
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Mode")
                        Text("Icon")
                        Text("Background")
                        Text("Text Color")
                    }
                    .font(.caption.weight(.semibold))
                    ForEach(set.modes) { mode in
                        GridRow {
                            Text(mode.name)
                            iconMenu(for: mode)
                            defaultSwatch(mode, role: .background)
                            defaultSwatch(mode, role: .foreground)
                            Button("Rename…") { prompt(for: mode) }
                                .accessibilityLabel("Rename color mode \(mode.name)")
                        }
                        .contextMenu { Button("Rename…") { prompt(for: mode) } }
                    }
                }
                Button("Add Mode…") { prompt(for: nil) }
            } else {
                Button("Enable Color Modes") { commit(.enable) }
            }
            if document.model.hasLibraryColorModes {
                Button("Adopt Library Modes") { commit(.adoptLibrary) }
                    .help("Fill missing Light and Dark values from imported library colors.")
            }
        }
        .alert(editingID == nil ? "Add Color Mode" : "Rename Color Mode", isPresented: $showingName) {
            TextField("Mode name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commit(.name(name, editingID)) }
                .disabled(!validName)
        }
        .sheet(item: $editingDefault) { field in
            ModeDefaultColorEditor(field: field, language: language) {
                commit(.defaultColor($0, field.role, field.mode.id))
            }
        }
    }

    private static let modeIcons = [
        ("Sun", "sun.max"), ("Moon", "moon"), ("Moon and Stars", "moon.stars"),
        ("Half Circle", "circle.lefthalf.filled"), ("Sunrise", "sunrise"),
        ("Sunset", "sunset"), ("Cloud", "cloud"), ("Star", "star"),
        ("Sparkles", "sparkles"), ("Bolt", "bolt"), ("Diamond", "diamond")
    ]

    private func iconMenu(for mode: DLMode) -> some View {
        Menu {
            Button("Use Default Icon") { commit(.icon(nil, mode.id)) }
                .disabled(mode.iconSymbol == nil)
            Divider()
            ForEach(Self.modeIcons, id: \.1) { option in
                Button {
                    commit(.icon(option.1, mode.id))
                } label: {
                    Label(option.0, systemImage: mode.resolvedIconSymbol == option.1 ? "checkmark" : option.1)
                }
            }
        } label: {
            Image(systemName: mode.resolvedIconSymbol)
        }
        .fixedSize()
        .accessibilityLabel("Change icon for \(mode.name)")
        .accessibilityValue(Self.modeIcons.first { $0.1 == mode.resolvedIconSymbol }?.0 ?? mode.resolvedIconSymbol)
        .help("Change icon for \(mode.name)")
    }

    private func defaultSwatch(_ mode: DLMode, role: DLModeColorRole) -> some View {
        let field = ModeDefaultField(mode: mode, role: role)
        let hex = ColorMath.string(role.color(in: mode), .hex)
        return Button { editingDefault = field } label: {
            HStack(spacing: 5) {
                SwatchView(color: role.color(in: mode)).frame(width: 24, height: 16)
                Text(hex).font(.system(.caption, design: .monospaced))
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Edit \(field.title)")
        .accessibilityValue(hex)
    }

    private var validName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && language.colorModeSet?.modes.contains {
            $0.id != editingID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        } != true
    }

    private func prompt(for mode: DLMode?) {
        editingID = mode?.id
        name = mode?.name ?? ""
        showingName = true
    }

    private func commit(_ edit: DLColorModeEdit) {
        if !edit.commit(to: document, undoManager: undoManager), case .adoptLibrary = edit { NSSound.beep() }
    }
}

private struct ModeDefaultField: Identifiable {
    let mode: DLMode
    let role: DLModeColorRole
    var id: String { "\(mode.id)-\(role.rawValue)" }
    var title: String { "\(mode.name) \(role == .background ? "background" : "text color")" }
}

private struct ModeDefaultColorEditor: View {
    let field: ModeDefaultField
    let language: DesignLanguage
    let save: (RGBAColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RGBAColor

    init(field: ModeDefaultField, language: DesignLanguage, save: @escaping (RGBAColor) -> Void) {
        self.field = field
        self.language = language
        self.save = save
        _draft = State(initialValue: field.role.color(in: field.mode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(field.title).font(.headline)
            DLSavedColorMenu(language: language, modeID: field.mode.id) { color in
                draft = color
                if field.role == .background { draft.a = 1 }
            }
            ColorPopover(color: $draft, supportsOpacity: field.role == .foreground, showsDesignLanguageLink: false)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == field.role.color(in: field.mode))
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}

//
//  FontFamilyPicker.swift
//  EXP [design]
//
//  FEAT-008. One previewed font list with one mutually-exclusive filter rail.
//  All / Fonts Used / Recent and the type categories are alternative views of
//  the SAME list, never facets that silently intersect into an empty result.
//

import SwiftUI
import AppKit

/// A popover owns keyboard input while it is open. The app-wide single-letter
/// tool monitor must yield or typing A/F/T/etc. in Search changes canvas tools.
@MainActor
enum FontPickerKeyboardSession {
    static var isActive = false
}

@MainActor
private enum RecentFontStore {
    static let key = "fontPicker.recentFamilies.v1"
    static let limit = 12

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return stored
    }

    @discardableResult
    static func record(_ family: String) -> [String] {
        var updated = load().filter { $0 != family }
        updated.insert(family, at: 0)
        if updated.count > limit { updated.removeLast(updated.count - limit) }
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return updated
    }
}

struct FontFamilyPicker: View {
    /// Family currently applied, or "" for the system face. May be "Mixed".
    let currentFamily: String
    /// What the collapsed control shows. Usually `currentFamily`; multi-selection
    /// callers pass a fixed label because there is no single value.
    let label: String
    /// Delayed until popover-open so ordinary inspector redraws never walk a large
    /// document merely to prepare the Fonts Used filter.
    var fontsUsed: () -> Set<String> = { [] }
    let onPick: (String) -> Void
    let onPickSystem: () -> Void

    @State private var open = false
    @State private var recentFamilies: [String] = []
    @State private var usedFamilies: Set<String> = []
    @State private var searchText = ""
    @State private var hoveredFilter: FontFilter?
    @State private var searchAnnouncementToken = UUID()
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedFilter: FontFilter?

    @AppStorage("fontPicker.filter.v2") private var storedFilter = FontFilter.all.rawValue
    @AppStorage("fontPicker.railHidden.v1") private var railHidden = false

    private static let systemRowID = "__exp_system__"
    private static let railWidth: CGFloat = 132
    private static let rowHeight: CGFloat = 26

    /// One group, one selected option. Keeping scope + category in separate groups
    /// looked like useful faceting but made it too easy to filter every font away.
    private enum FontFilter: String, CaseIterable, Identifiable {
        case all, used, recent
        case sansSerif, serif, monospaced, handwriting, display, symbol, other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All Fonts"
            case .used: "Fonts Used"
            case .recent: "Recent"
            case .sansSerif: "Sans Serif"
            case .serif: "Serif"
            case .monospaced: "Monospaced"
            case .handwriting: "Handwriting"
            case .display: "Display"
            case .symbol: "Symbol"
            case .other: "Other"
            }
        }

        var catalogCategory: FontCatalog.Category? {
            switch self {
            case .all, .used, .recent: nil
            case .sansSerif: .sansSerif
            case .serif: .serif
            case .monospaced: .monospaced
            case .handwriting: .handwriting
            case .display: .display
            case .symbol: .symbol
            case .other: .other
            }
        }
    }

    private struct Option: Identifiable {
        let value: String
        let title: String
        var id: String { value.isEmpty ? FontFamilyPicker.systemRowID : value }
    }

    private var selectedFilter: FontFilter {
        FontFilter(rawValue: storedFilter) ?? .all
    }

    private var filterBinding: Binding<FontFilter> {
        Binding(get: { selectedFilter }, set: { storedFilter = $0.rawValue })
    }

    private var allOptions: [Option] {
        [Option(value: "", title: "System")]
            + FontCatalog.families.map { Option(value: $0, title: $0) }
    }

    private func options(for filter: FontFilter) -> [Option] {
        switch filter {
        case .all:
            return allOptions
        case .used:
            return allOptions.filter { usedFamilies.contains($0.value) }
        case .recent:
            // Preserve MRU order rather than alphabetizing it back away.
            return recentFamilies.compactMap { value in
                allOptions.first { $0.value == value }
            }
        default:
            guard let category = filter.catalogCategory else { return allOptions }
            return allOptions.filter { FontCatalog.category(for: $0.value) == category }
        }
    }

    private var filteredOptions: [Option] {
        let base = options(for: selectedFilter)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var selectedRowID: String {
        currentFamily.isEmpty ? Self.systemRowID : currentFamily
    }

    /// Let a large display do useful work without letting the popover become a
    /// nearly full-screen wall. `visibleFrame` excludes the menu bar and Dock, and
    /// the active window's screen makes this correct for multi-monitor setups.
    private var preferredPopoverHeight: CGFloat {
        let visibleHeight = (NSApp.keyWindow?.screen
                             ?? NSApp.mainWindow?.screen
                             ?? NSScreen.main)?.visibleFrame.height ?? 900
        return min(780, max(480, visibleHeight * 0.62))
    }

    private var emptyState: (title: String, detail: String) {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("No fonts found", "Try a different search or choose another filter.")
        }
        switch selectedFilter {
        case .recent where recentFamilies.isEmpty:
            return ("No recent fonts", "Choose a font and it will appear here next time.")
        case .recent:
            return ("No available recent fonts", "Your recent fonts are not currently installed on this Mac.")
        case .used:
            return ("No fonts used", "This document does not reference an installed font yet.")
        case .all:
            return ("No installed fonts", "No fonts are currently available to the app.")
        default:
            return ("No matching fonts", "No installed fonts are classified as \(selectedFilter.title.lowercased()).")
        }
    }

    private func preview(_ family: String, size: CGFloat) -> Font {
        family == FontCatalog.systemMonospacedFamily
            ? .system(size: size, design: .monospaced)
            : .custom(family, size: size)
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack {
                Text(label).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(EXPColor.textSecondary)
            }
            .contentShape(Rectangle())
            .expDropdownChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Typeface")
        .accessibilityValue(label)
        .accessibilityHint("Opens a searchable font list with optional filters.")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            pickerPopover
        }
        .onChange(of: open) { _, isOpen in
            if !isOpen { FontPickerKeyboardSession.isActive = false }
        }
    }

    private var pickerPopover: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    if !railHidden {
                        filterRail
                        Divider()
                    }
                    resultList
                }
            }
            .frame(width: railHidden ? 350 : 440, height: preferredPopoverHeight)
            .onAppear {
                FontPickerKeyboardSession.isActive = true
                recentFamilies = RecentFontStore.load()
                usedFamilies = fontsUsed()
                searchText = ""
                scrollToSelection(proxy)
                DispatchQueue.main.async {
                    searchFocused = true
                    scrollToSelection(proxy)
                }
            }
            .onDisappear {
                FontPickerKeyboardSession.isActive = false
                searchFocused = false
            }
            .onChange(of: storedFilter) { _, _ in filterChanged(proxy) }
            .onChange(of: railHidden) { _, isHidden in
                announce(isHidden
                         ? "Font filters hidden. Current filter: \(selectedFilter.title)."
                         : "Font filters shown. Current filter: \(selectedFilter.title).")
            }
            .onChange(of: searchText) { _, _ in searchChanged(proxy) }
        }
    }

    /// Filter control occupies the same leading header cell as its rail. Search's
    /// magnifier/checkmark columns are equal widths, aligning typed text exactly
    /// with the family names below whenever the rail is visible.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .accessibilityHidden(true)
                Text("Filters")
                    .fontWeight(.medium)
                Spacer(minLength: 2)
                Toggle("Show Filters", isOn: Binding(
                    get: { !railHidden },
                    set: { railHidden = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(railHidden ? "Show Filters" : "Hide Filters")
                .accessibilityValue("Current filter: \(selectedFilter.title)")
            }
            .padding(.horizontal, 8)
            .frame(width: Self.railWidth, height: 42)
            .help(railHidden ? "Show font filters" : "Hide font filters")

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EXPColor.textTertiary)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search fonts")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(EXPColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear font search")
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EXPColor.surfaceField.opacity(searchFocused ? 1 : 0))
        }
        .font(.caption)
        .foregroundStyle(EXPColor.textSecondary)
        .frame(height: 42)
    }

    private var filterRail: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(FontFilter.allCases) { filter in
                    filterButton(filter)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        // The icon buttons are visual; VoiceOver gets the exact exclusive-choice
        // model as a native radio group, including stable full labels + counts.
        .accessibilityRepresentation {
            Picker("Filters", selection: filterBinding) {
                ForEach(FontFilter.allCases) { filter in
                    Text("\(filter.title), \(options(for: filter).count) fonts")
                        .tag(filter)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("Font Filters")
            .accessibilityHint("Choose one filter. Use the arrow keys to move between filters.")
        }
    }

    @ViewBuilder
    private func filterButton(_ filter: FontFilter) -> some View {
        let isSelected = filter == selectedFilter
        let isHovered = filter == hoveredFilter
        let count = options(for: filter).count
        Button {
            storedFilter = filter.rawValue
            DispatchQueue.main.async { focusedFilter = filter }
        } label: {
            HStack(spacing: 4) {
                filterIcon(filter)
                    .frame(width: 38, height: 34)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 25, minHeight: 21)
                    .background(
                        (isSelected ? EXPColor.accentForeground : EXPColor.textSecondary)
                            .opacity(0.18),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 7)
            .frame(width: 94, height: 44)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? EXPColor.accentForeground : EXPColor.textPrimary)
        .background(
            isSelected ? EXPColor.accent
                       : (isHovered ? EXPColor.rowHover : EXPColor.surfaceCard),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.clear : EXPColor.borderSoft, lineWidth: 1)
        }
        .focusable(isSelected)
        .focused($focusedFilter, equals: filter)
        .onMoveCommand { moveFilter(from: filter, direction: $0) }
        .onHover { inside in hoveredFilter = inside ? filter : nil }
        .help("\(filter.title) — \(count) fonts")
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func filterIcon(_ filter: FontFilter) -> some View {
        switch filter {
        case .all:
            Text("ALL").font(.system(size: 11, weight: .black))
        case .used:
            Image(systemName: "doc.text").font(.system(size: 20, weight: .regular))
        case .recent:
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 20, weight: .regular))
        case .sansSerif:
            Text("S").font(.system(size: 28, weight: .regular, design: .default))
        case .serif:
            Text("S").font(.system(size: 29, weight: .regular, design: .serif))
        case .monospaced:
            Text("M").font(.system(size: 25, weight: .regular, design: .monospaced))
        case .handwriting:
            Image(systemName: "signature").font(.system(size: 23, weight: .regular))
        case .display:
            Image(systemName: "textformat.size").font(.system(size: 21, weight: .semibold))
        case .symbol:
            Image(systemName: "diamond.inset.filled").font(.system(size: 21, weight: .regular))
        case .other:
            Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold))
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if filteredOptions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(.title2)
                    .foregroundStyle(EXPColor.textTertiary)
                    .accessibilityHidden(true)
                Text(emptyState.title).font(.headline)
                Text(emptyState.detail)
                    .font(.caption)
                    .foregroundStyle(EXPColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredOptions) { option in
                        row(option: option)
                        if option.value.isEmpty && filteredOptions.count > 1 {
                            Divider().padding(.vertical, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel("Fonts")
            .accessibilityValue("\(filteredOptions.count) results")
            .accessibilityHint("Use Search or Filters to narrow the list.")
        }
    }

    @ViewBuilder
    private func row(option: Option) -> some View {
        Button {
            recentFamilies = RecentFontStore.record(option.value)
            if option.value.isEmpty { onPickSystem() }
            else { onPick(option.value) }
            open = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(option.value == currentFamily ? 1 : 0)
                    .frame(width: 12)
                Text(option.title)
                    .font(option.value.isEmpty ? .system(size: 13)
                                               : preview(option.value, size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(option.id)
        .background(option.value == currentFamily ? EXPColor.accentSubtle2 : Color.clear)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(option.value == currentFamily ? [.isSelected] : [])
    }

    private func moveFilter(from filter: FontFilter, direction: MoveCommandDirection) {
        guard direction == .up || direction == .down
                || direction == .left || direction == .right,
              let index = FontFilter.allCases.firstIndex(of: filter) else { return }
        let delta = (direction == .down || direction == .right) ? 1 : -1
        let count = FontFilter.allCases.count
        let next = FontFilter.allCases[(index + delta + count) % count]
        storedFilter = next.rawValue
        DispatchQueue.main.async { focusedFilter = next }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard filteredOptions.contains(where: { $0.id == selectedRowID }) else { return }
        proxy.scrollTo(selectedRowID, anchor: .center)
    }

    private func filterChanged(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if let first = filteredOptions.first { proxy.scrollTo(first.id, anchor: .top) }
            announce("\(selectedFilter.title), \(filteredOptions.count) fonts.")
        }
    }

    private func searchChanged(_ proxy: ScrollViewProxy) {
        let token = UUID()
        searchAnnouncementToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard searchAnnouncementToken == token else { return }
            if let first = filteredOptions.first { proxy.scrollTo(first.id, anchor: .top) }
            announce("\(filteredOptions.count) fonts found.")
        }
    }

    private func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [.announcement: message,
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }
}

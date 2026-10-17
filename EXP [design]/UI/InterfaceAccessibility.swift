import AppKit
import Observation
import SwiftUI

extension AppPreferences {
    static let interfaceTypeSize = "exp.pref.interfaceTypeSize"
    static let largerInterfaceTargets = "exp.pref.largerInterfaceTargets"
    static let interfaceGuidance = "exp.pref.interfaceGuidance"
    static let toolbarLabels = "exp.pref.toolbarLabels"
    static let defaultInterfaceTypeSize = EXPInterfaceTypeSize.system.rawValue
}

/// App-wide chrome type size. Shared point-size tokens scale explicitly; native
/// semantic text also receives the corresponding SwiftUI type-size environment.
enum EXPInterfaceTypeSize: String, CaseIterable, Identifiable {
    case system, compact, standard, large, extraLarge
    var id: String { rawValue }
    var label: String {
        switch self { case .system: "System default"; case .compact: "Compact"; case .standard: "Standard"; case .large: "Large"; case .extraLarge: "Extra Large" }
    }
    func scale(system: CGFloat) -> CGFloat {
        switch self {
        case .system: system
        case .compact: 0.92
        case .standard: 1
        case .large: 1.25
        case .extraLarge: 1.5
        }
    }
    var dynamicTypeSize: DynamicTypeSize {
        switch self { case .system, .standard: .large; case .compact: .medium; case .large: .xxLarge; case .extraLarge: .xxxLarge }
    }
}


/// Visual choices are independent. VoiceOver is a signal for optional guidance,
/// never a reason to infer a person's preferred text or pointer-target size.
enum EXPInterfaceGuidance: String, CaseIterable, Identifiable {
    case automatic, always, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automatic with VoiceOver"
        case .always: "Show"
        case .never: "Hide"
        }
    }
    func showsGuidance(voiceOver: Bool) -> Bool {
        switch self { case .automatic: voiceOver; case .always: true; case .never: false }
    }
}

/// Drawing-toolbar text can be chosen without changing other visible guidance.
/// This controls presentation only; tool accessibility names remain unconditional.
enum EXPToolbarLabels: String, CaseIterable, Identifiable {
    case automatic, iconsOnly, iconsAndText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automatic with VoiceOver"
        case .iconsOnly: "Icons only"
        case .iconsAndText: "Icons and text"
        }
    }
    func showsLabels(voiceOver: Bool) -> Bool {
        switch self { case .automatic: voiceOver; case .iconsOnly: false; case .iconsAndText: true }
    }
}

/// A local, observable presentation preference source shared by docked, floating,
/// Settings and source-editor windows. It never writes document data or persists
/// assistive-technology status. All public system reads are permission-free.
@MainActor @Observable
final class EXPInterfaceAccessibility {
    static let shared = EXPInterfaceAccessibility()
    private(set) var typeSize: EXPInterfaceTypeSize = .system
    private(set) var largerTargets = false
    private(set) var guidance: EXPInterfaceGuidance = .automatic
    private(set) var toolbarLabels: EXPToolbarLabels = .automatic
    private(set) var voiceOverEnabled = false
    private(set) var systemTextScale: CGFloat = 1
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var displayObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var voiceOverObserver: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard, observeSystem: Bool = true) {
        self.defaults = defaults
        migrateToolbarLabels()
        refresh()
        guard observeSystem else { return }
        voiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled
        voiceOverObserver = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { [weak self] _, change in
            let enabled = change.newValue ?? false
            Task { @MainActor [weak self] in self?.voiceOverEnabled = enabled }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.voiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled
                self?.refresh()
            }
        }
    }

    private func migrateToolbarLabels() {
        // Preserve the old combined setting once, then make the two choices
        // independent. Seed a fresh install too, so a later help change cannot
        // be mistaken for a legacy inherited default on the next launch.
        // Unknown future values are never erased.
        let storedToolbar = defaults.string(forKey: AppPreferences.toolbarLabels)
        if storedToolbar == "followGuidance" || storedToolbar == nil {
            let oldGuidance = EXPInterfaceGuidance(rawValue: defaults.string(forKey: AppPreferences.interfaceGuidance) ?? "") ?? .automatic
            let migrated: EXPToolbarLabels = switch oldGuidance {
            case .automatic: .automatic
            case .always: .iconsAndText
            case .never: .iconsOnly
            }
            defaults.set(migrated.rawValue, forKey: AppPreferences.toolbarLabels)
        }
    }

    func refresh() {
        typeSize = EXPInterfaceTypeSize(rawValue: defaults.string(forKey: AppPreferences.interfaceTypeSize) ?? "") ?? .system
        largerTargets = defaults.bool(forKey: AppPreferences.largerInterfaceTargets)
        guidance = EXPInterfaceGuidance(rawValue: defaults.string(forKey: AppPreferences.interfaceGuidance) ?? "") ?? .automatic
        toolbarLabels = EXPToolbarLabels(rawValue: defaults.string(forKey: AppPreferences.toolbarLabels) ?? "") ?? .automatic
        // AppKit's public preferred font is the available system baseline. We do
        // not read protected/private text-size defaults or promise Apple's app-
        // specific text overrides are available to a third-party editor.
        systemTextScale = NSFont.preferredFont(forTextStyle: .body, options: [:]).pointSize / NSFont.systemFontSize
    }

    var textScale: CGFloat { typeSize.scale(system: systemTextScale) }
    var showGuidance: Bool { guidance.showsGuidance(voiceOver: voiceOverEnabled) }
    var showToolbarLabels: Bool { toolbarLabels.showsLabels(voiceOver: voiceOverEnabled) }
    func targetHeight(_ compact: CGFloat) -> CGFloat {
        max(compact * textScale, largerTargets ? 44 : compact)
    }
}

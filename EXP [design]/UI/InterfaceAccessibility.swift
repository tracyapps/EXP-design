import AppKit
import Observation
import SwiftUI

extension AppPreferences {
    static let interfaceTypeSize = "exp.pref.interfaceTypeSize"
    static let largerInterfaceTargets = "exp.pref.largerInterfaceTargets"
    static let interfaceGuidance = "exp.pref.interfaceGuidance"
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
        case .always: "Always show"
        case .never: "Keep compact"
        }
    }
    func showsGuidance(voiceOver: Bool) -> Bool {
        switch self { case .automatic: voiceOver; case .always: true; case .never: false }
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
    private(set) var voiceOverEnabled = false
    private(set) var systemTextScale: CGFloat = 1
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var displayObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var voiceOverObserver: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard, observeSystem: Bool = true) {
        self.defaults = defaults
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

    func refresh() {
        typeSize = EXPInterfaceTypeSize(rawValue: defaults.string(forKey: AppPreferences.interfaceTypeSize) ?? "") ?? .system
        largerTargets = defaults.bool(forKey: AppPreferences.largerInterfaceTargets)
        guidance = EXPInterfaceGuidance(rawValue: defaults.string(forKey: AppPreferences.interfaceGuidance) ?? "") ?? .automatic
        // AppKit's public preferred font is the available system baseline. We do
        // not read protected/private text-size defaults or promise Apple's app-
        // specific text overrides are available to a third-party editor.
        systemTextScale = NSFont.preferredFont(forTextStyle: .body, options: [:]).pointSize / NSFont.systemFontSize
    }

    var textScale: CGFloat { typeSize.scale(system: systemTextScale) }
    var showGuidance: Bool { guidance.showsGuidance(voiceOver: voiceOverEnabled) }
    func targetHeight(_ compact: CGFloat) -> CGFloat {
        max(compact * textScale, largerTargets ? 44 : compact)
    }
}

import AppKit

// Supply only the host namespace. Actual keys, policies and model are compiled
// from the production InterfaceAccessibility.swift, not mirrored in this check.
enum AppPreferences {}

@main struct InterfaceAccessibilityCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "design.tapps.exp.accessibility-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
        precondition(preferences.typeSize == .system && !preferences.largerTargets)
        precondition(preferences.guidance == .automatic)
        precondition(!EXPInterfaceGuidance.automatic.showsGuidance(voiceOver: false))
        precondition(EXPInterfaceGuidance.automatic.showsGuidance(voiceOver: true))
        precondition(EXPInterfaceGuidance.always.showsGuidance(voiceOver: false))
        precondition(!EXPInterfaceGuidance.never.showsGuidance(voiceOver: true))
        precondition(EXPInterfaceTypeSize.system.scale(system: 1.4) == 1.4)
        precondition(EXPInterfaceTypeSize.standard.scale(system: 1.4) == 1)
        precondition(EXPInterfaceTypeSize.large.scale(system: 1.4) == 1.25)
        precondition(EXPInterfaceTypeSize.extraLarge.scale(system: 1.4) == 1.5)
        for legacy in ["compact", "standard", "large"] {
            defaults.set(legacy, forKey: AppPreferences.interfaceTypeSize)
            preferences.refresh()
            precondition(preferences.typeSize.rawValue == legacy)
        }
        defaults.set("extraLarge", forKey: AppPreferences.interfaceTypeSize)
        defaults.set(true, forKey: AppPreferences.largerInterfaceTargets)
        defaults.set("never", forKey: AppPreferences.interfaceGuidance)
        preferences.refresh()
        precondition(preferences.textScale == 1.5 && preferences.largerTargets)
        precondition(preferences.targetHeight(24) == 44)
        precondition(preferences.targetHeight(42) == 63)
        precondition(!preferences.showGuidance)
        let reopened = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
        precondition(reopened.typeSize == .extraLarge && reopened.largerTargets && reopened.guidance == .never)
        defaults.set("unknown-future-size", forKey: AppPreferences.interfaceTypeSize)
        defaults.set("unknown-future-guidance", forKey: AppPreferences.interfaceGuidance)
        preferences.refresh()
        precondition(preferences.typeSize == .system && preferences.guidance == .automatic)
        // Defaults recovery must not silently erase the stored value.
        precondition(defaults.string(forKey: AppPreferences.interfaceTypeSize) == "unknown-future-size")
        print("Interface policy, explicit override, legacy values, target geometry, persistence and fallback checks passed.")
    }
}

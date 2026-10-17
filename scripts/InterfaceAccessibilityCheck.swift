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
        precondition(preferences.toolbarLabels == .automatic)
        precondition(!preferences.showToolbarLabels)
        defaults.set("always", forKey: AppPreferences.interfaceGuidance)
        preferences.refresh()
        precondition(preferences.toolbarLabels == .automatic && !preferences.showToolbarLabels)
        let independentAfterRestart = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
        precondition(independentAfterRestart.toolbarLabels == .automatic)
        defaults.set("iconsOnly", forKey: AppPreferences.toolbarLabels)
        preferences.refresh()
        precondition(preferences.showGuidance && !preferences.showToolbarLabels)
        defaults.set("never", forKey: AppPreferences.interfaceGuidance)
        defaults.set("iconsAndText", forKey: AppPreferences.toolbarLabels)
        preferences.refresh()
        precondition(!preferences.showGuidance && preferences.showToolbarLabels)
        for guidance in ["always", "never"] {
            defaults.set(guidance, forKey: AppPreferences.interfaceGuidance)
            defaults.set("followGuidance", forKey: AppPreferences.toolbarLabels)
            let upgraded = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
            precondition(upgraded.showToolbarLabels == upgraded.showGuidance)
            precondition(defaults.string(forKey: AppPreferences.toolbarLabels) == (guidance == "always" ? "iconsAndText" : "iconsOnly"))
        }
        defaults.removeObject(forKey: AppPreferences.toolbarLabels)
        let inherited = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
        precondition(inherited.toolbarLabels == .iconsOnly) // Old default inherited "never".
        defaults.set("automatic", forKey: AppPreferences.interfaceGuidance)
        defaults.set("followGuidance", forKey: AppPreferences.toolbarLabels)
        let automaticUpgrade = EXPInterfaceAccessibility(defaults: defaults, observeSystem: false)
        precondition(automaticUpgrade.toolbarLabels == .automatic)
        defaults.set("automatic", forKey: AppPreferences.toolbarLabels)
        defaults.set("always", forKey: AppPreferences.interfaceGuidance)
        preferences.refresh()
        precondition(preferences.showGuidance && !preferences.showToolbarLabels)
        precondition(EXPToolbarLabels.automatic.showsLabels(voiceOver: true))
        precondition(!EXPToolbarLabels.automatic.showsLabels(voiceOver: false))
        defaults.set("iconsOnly", forKey: AppPreferences.toolbarLabels)
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
        precondition(reopened.toolbarLabels == .iconsOnly && !reopened.showToolbarLabels)
        defaults.set("unknown-future-toolbar", forKey: AppPreferences.toolbarLabels)
        defaults.set("unknown-future-size", forKey: AppPreferences.interfaceTypeSize)
        defaults.set("unknown-future-guidance", forKey: AppPreferences.interfaceGuidance)
        preferences.refresh()
        precondition(preferences.typeSize == .system && preferences.guidance == .automatic)
        precondition(preferences.toolbarLabels == .automatic)
        precondition(defaults.string(forKey: AppPreferences.toolbarLabels) == "unknown-future-toolbar")
        // Defaults recovery must not silently erase the stored value.
        precondition(defaults.string(forKey: AppPreferences.interfaceTypeSize) == "unknown-future-size")
        print("Interface policy, explicit override, legacy values, target geometry, persistence and fallback checks passed.")
    }
}

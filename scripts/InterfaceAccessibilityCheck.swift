import AppKit
import SwiftUI

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
        checkCodeGutterDrawing()
    }

    @MainActor private static func checkCodeGutterDrawing() {
        let view = DLSourceTextView(source: "{\n  \"name\": \"Example\"\n}", format: .json,
                                    onEdit: nil, controls: DLSourceControls())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 450, height: 300))
        host.view.layoutSubtreeIfNeeded()
        window.display()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        func findRuler(in view: NSView) -> NSRulerView? {
            (view as? NSRulerView) ?? view.subviews.lazy.compactMap { findRuler(in: $0) }.first
        }
        guard let ruler = findRuler(in: host.view) else { fatalError("Missing code gutter") }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { fatalError("Could not create a drawing surface") }
        canvas.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: true)
        canvas.translateBy(x: 48, y: 0)
        ruler.drawHashMarksAndLabels(in: ruler.bounds.insetBy(dx: -100, dy: -50))
        NSGraphicsContext.restoreGraphicsState()

        guard let image = canvas.makeImage() else { fatalError("Missing gutter rendering") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let background = bitmap.colorAt(x: 240, y: 128)
        precondition(bitmap.colorAt(x: 62, y: 128) != background, "The gutter should still draw")
        precondition(bitmap.colorAt(x: 125, y: 128) == background, "The gutter must not paint over the source")
        print("Code gutter confines an oversized AppKit redraw to its own bounds.")
    }
}

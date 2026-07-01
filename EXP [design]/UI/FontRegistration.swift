//
//  FontRegistration.swift
//  EXP [design]
//
//  Phase 17a (font bundling) — registers the bundled SF Compact Display weights
//  at launch so the condensed "layer name" voice renders IDENTICALLY on every
//  Mac, not just those that happen to have SF Compact installed (it's an Apple
//  download / primarily a watchOS face, so it is NOT guaranteed system-side).
//
//  WHY ONLY SF COMPACT: SF Pro and SF Mono are the macOS system fonts — present
//  and identical on every target Mac — so we reference them via `.system(...)`
//  and do NOT bundle them (redundant + cleaner license posture). SF Compact is
//  the one family that varies, so it's the only one embedded.
//
//  ⚠ LICENSING (revisit before any public distribution — owner may distribute
//  later): these .otf are Apple's SF fonts. Apple's license covers USING the
//  system fonts to build UIs; EMBEDDING the files in a shipping app is
//  redistribution and is restricted by that license. For a personal build the
//  practical risk is nil. Before releasing EXP, either (a) confirm an acceptable
//  license path, or (b) swap the condensed voice to an open-licensed (SIL OFL)
//  condensed face — `EXPType.layerFont` is the single switch-point, so the swap
//  is one function. See `Resources/Fonts/LICENSE-NOTE.md`.
//
//  Registration is PROCESS-scoped (CTFontManager) and idempotent. It runs from
//  the App's init, before any view renders, so `EXPType.hasSFCompact()` sees the
//  family on first use. Resources are looked up by name (not a fixed path) so it
//  doesn't matter how the synchronized-folder build flattens them into the bundle.
//

import AppKit
import CoreText

enum EXPFonts {
    /// The bundled faces we embed (SF Compact Display, the weights the chrome uses).
    static let bundledPrefix = "SF-Compact-Display"

    private static var didRegister = false

    /// Register the bundled fonts for this process. Safe to call more than once.
    @MainActor static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        let urls = (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(bundledPrefix) }

        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Most common "failure" is a duplicate (the face is already
                // registered/installed) — that's fine, the font is usable. Only
                // log anything genuinely unexpected.
                if let e = error?.takeRetainedValue() {
                    let code = CFErrorGetCode(e)
                    // kCTFontManagerErrorAlreadyRegistered == 105
                    if code != 105 {
                        NSLog("EXP: font register failed for \(url.lastPathComponent): \(e)")
                    }
                }
            }
        }
    }
}

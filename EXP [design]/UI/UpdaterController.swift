//
//  UpdaterController.swift
//  EXP [design]
//
//  Sparkle auto-update wiring (Phase 20). The app is distributed outside the
//  App Store (expdesign.app/download), so Sparkle checks a self-hosted appcast
//  (SUFeedURL in Info.plist) and verifies each downloaded archive against our
//  EdDSA public key (SUPublicEDKey) — on top of Developer ID + notarization.
//
//  The Sparkle import is guarded by `#if canImport(Sparkle)` so the project
//  still COMPILES before the package is added in Xcode (File ▸ Add Package
//  Dependencies… ▸ https://github.com/sparkle-project/Sparkle, app target
//  only — NOT EXPThumbnail). Until then the menu item stays disabled via the
//  no-op fallback below. DO NOT "fix" a missing-Sparkle build error by
//  stubbing or deleting this file — add the package.
//

import SwiftUI
import Combine

#if canImport(Sparkle)
import Sparkle

/// Owns the app's single SPUStandardUpdaterController for the process
/// lifetime and publishes `canCheckForUpdates` so the menu item
/// enables/disables correctly (the SwiftUI-commands equivalent of a
/// validateMenuItem case).
@MainActor
final class UpdaterModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true boots Sparkle's scheduled-check cycle.
        // Consent-first: we deliberately do NOT set SUEnableAutomaticChecks in
        // Info.plist, so Sparkle asks the user for permission (on the second
        // launch) before any automatic checking begins. Manual "Check for
        // Updates…" always works regardless of that choice.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

#else

/// Build-before-package fallback: same shape, permanently disabled item.
@MainActor
final class UpdaterModel: ObservableObject {
    @Published var canCheckForUpdates = false
    func checkForUpdates() {}
}

#endif

import AppKit
import SwiftUI

/// Settings follows the active canvas's display, not the detached palette that
/// requested it. Observe real presentations, rather than raising it on every
/// SwiftUI update (which would steal ordering back from a panel the user chose).
struct EXPSettingsWindowPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("exp.settings")
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.present() }
                }
            DispatchQueue.main.async { [weak self] in self?.present() }
        }

        private func present() {
            guard let window else { return }
            PaintPopoverActivity.shared.dismiss()
            window.level = .normal
            if let anchor = PanelHub.shared.activeEditorWindow,
               let screen = anchor.screen,
               window.screen !== screen {
                let visible = screen.visibleFrame
                var origin = CGPoint(x: anchor.frame.midX - window.frame.width / 2,
                                     y: anchor.frame.midY - window.frame.height / 2)
                origin.x = max(visible.minX, min(origin.x, visible.maxX - window.frame.width))
                origin.y = max(visible.minY, min(origin.y, visible.maxY - window.frame.height))
                window.setFrameOrigin(origin)
            }
            window.orderFront(nil)
        }
    }
}

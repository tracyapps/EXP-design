import AppKit
import QuartzCore

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private final class Scene: NSView {
    var draws = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { draws += 1; NSColor.white.setFill(); dirtyRect.fill() }
}
@main enum Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        let scene = Scene(frame: CGRect(x: 0, y: 0, width: 400, height: 300)); scene.wantsLayer = true
        window.contentView = scene
        let overlay = RulerPointerOverlay(frame: scene.bounds); scene.addSubview(overlay)
        scene.display()
        let baseline = scene.draws
        require(baseline > 0, "initial artwork actually draws")
        for i in 0..<500 {
            if overlay.frame != scene.bounds { overlay.frame = scene.bounds }
            overlay.update(pointer: CGPoint(x: 25 + i % 350, y: 30 + i % 240), thickness: 20, enabled: true)
            CATransaction.flush(); scene.displayIfNeeded()
        }
        require(scene.draws == baseline, "500 pointer moves must not redraw scene")
        require(!overlay.isHidden && overlay.hitTest(CGPoint(x: 40, y: 10)) == nil, "markers visible and click through to rulers")
        require(!overlay.isAccessibilityElement(), "decorative overlay stays outside AX focus")
        let layers = overlay.layer!.sublayers!.compactMap { $0 as? CAShapeLayer }
        require(layers.count == 2 && layers.allSatisfy { $0.animationKeys()?.isEmpty != false }, "two retained markers with no animation")
        overlay.update(pointer: CGPoint(x: 100, y: 140), thickness: 20, enabled: true)
        require(layers[0].path?.boundingBox == CGRect(x: 100, y: 0, width: 0, height: 20), "horizontal ruler marker follows x")
        require(layers[1].path?.boundingBox == CGRect(x: 0, y: 140, width: 20, height: 0), "vertical ruler marker follows y")
        overlay.update(pointer: .zero, thickness: 20, enabled: false)
        require(overlay.isHidden, "ruler toggle/source scope hides markers")
        print("PASS: 500 retained marker updates, zero parent artwork redraws, exact positions, no animation, click-through, decorative AX, hide")
    }
}

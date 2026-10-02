import AppKit
import QuartzCore

/// Decorative, click-through ruler markers. Updating these retained layers must
/// never invalidate the parent canvas's expensive artwork drawing.
final class RulerPointerOverlay: NSView {
    private let horizontal = CAShapeLayer()
    private let vertical = CAShapeLayer()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        horizontal.lineWidth = 1; vertical.lineWidth = 1
        layer?.addSublayer(horizontal); layer?.addSublayer(vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(pointer: CGPoint, thickness: CGFloat, enabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isHidden = !enabled
        horizontal.frame = bounds; vertical.frame = bounds
        effectiveAppearance.performAsCurrentDrawingAppearance {
            horizontal.strokeColor = NSColor.controlAccentColor.cgColor
            vertical.strokeColor = NSColor.controlAccentColor.cgColor
        }
        let x = CGMutablePath(), y = CGMutablePath()
        if pointer.x >= thickness, pointer.x <= bounds.width {
            x.move(to: CGPoint(x: pointer.x, y: 0)); x.addLine(to: CGPoint(x: pointer.x, y: thickness))
        }
        if pointer.y >= thickness, pointer.y <= bounds.height {
            y.move(to: CGPoint(x: 0, y: pointer.y)); y.addLine(to: CGPoint(x: thickness, y: pointer.y))
        }
        horizontal.path = x; vertical.path = y
        CATransaction.commit()
    }
}

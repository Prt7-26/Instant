import AppKit

/// The accepted MaterialLab edge: a 1 pt stroked gradient, with transparent
/// interior and no hit testing. Geometry follows the same frame as the glass.
final class DirectionalHighlightView: NSView {
    let highlightOpacity: CGFloat = 0.62
    let lineWidth: CGFloat = 1
    private let gradient = CAGradientLayer()
    private let outline = CAShapeLayer()

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        let strengths: [CGFloat] = [1, 0.28, 0.06, 0.2, 0.65]
        gradient.colors = strengths.map { NSColor.white.withAlphaComponent(highlightOpacity * $0).cgColor }
        gradient.locations = [0, 0.24, 0.52, 0.78, 1]
        outline.fillColor = NSColor.clear.cgColor
        outline.strokeColor = NSColor.white.cgColor
        outline.lineWidth = lineWidth
        gradient.mask = outline
        layer?.addSublayer(gradient)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(frame: NSRect, cornerRadius: CGFloat, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        layer?.contentsScale = scale
        gradient.contentsScale = scale
        gradient.frame = bounds
        outline.contentsScale = scale
        outline.frame = bounds
        let inset = lineWidth / 2
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                              cornerWidth: max(0, cornerRadius - inset),
                              cornerHeight: max(0, cornerRadius - inset), transform: nil)
        CATransaction.commit()
    }
}

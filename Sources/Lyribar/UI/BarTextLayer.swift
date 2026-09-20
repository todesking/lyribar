import AppKit

/// Text of the bar on a layer. Moving a layer does not invalidate its view, which matters inside a
/// status bar button: on every invalidation AppKit snapshots the whole button again, several times.
@MainActor
enum BarTextLayer {
    static func make() -> CATextLayer {
        let layer = CATextLayer()
        let font = MarqueeTextView.font
        layer.font = font
        layer.fontSize = font.pointSize
        layer.anchorPoint = .zero
        return layer
    }

    static func setText(_ text: String, size: CGSize, on layer: CATextLayer) {
        layer.string = text
        layer.bounds = CGRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height))
    }

    /// Layers do not follow the appearance by themselves.
    static func labelColor(for view: NSView) -> CGColor {
        var color = NSColor.labelColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.cgColor
        }
        return color
    }

    static func scale(for view: NSView) -> CGFloat {
        view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    static func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

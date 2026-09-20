import AppKit

/// Text of the bar on a layer. Moving a layer does not invalidate its view, which matters inside a
/// status bar button: on every invalidation AppKit snapshots the whole button again, several times.
@MainActor
enum BarTextLayer {
    static let dimmedAlpha: CGFloat = 0.7
    static let settleDuration: TimeInterval = 0.25
    /// Farther than that is a seek.
    static let maxSettleDistance: CGFloat = 80

    static func make() -> CATextLayer {
        let layer = CATextLayer()
        let font = MarqueeTextView.font
        layer.font = font
        layer.fontSize = font.pointSize
        layer.anchorPoint = .zero
        // The text is redrawn when the transaction commits, outside of `withoutActions`; a fade
        // there would show the old text at the new position.
        layer.actions = ["contents": NSNull(), "string": NSNull()]
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

    static func dimmed(_ color: CGColor) -> CGColor {
        color.copy(alpha: color.alpha * dimmedAlpha) ?? color
    }

    /// For every snapshot of the status bar button AppKit swaps the appearance of the views and puts
    /// it back. Following that redraws every text layer twice per snapshot, so views read the color
    /// on the next turn of the run loop, when the appearance is back.
    static func afterAppearanceSettled(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { work() }
        }
    }

    static func scale(for view: NSView) -> CGFloat {
        view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    /// A pause arrives late, so the text has scrolled past the position it reports; resyncs are a
    /// little off too. Small corrections glide instead of jumping. Nil for seeks and for no correction.
    static func settleAnimation(
        from delta: CGFloat, duration: TimeInterval = settleDuration, limit: CGFloat = maxSettleDistance
    ) -> CABasicAnimation? {
        guard delta != 0, abs(delta) <= limit else { return nil }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.isAdditive = true
        animation.fromValue = delta
        animation.toValue = 0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    static func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

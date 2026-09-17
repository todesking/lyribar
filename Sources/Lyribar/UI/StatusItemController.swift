import AppKit

@MainActor
final class StatusItemController {
    static let tickInterval: TimeInterval = 0.1

    private struct Snapshot: Equatable {
        var content: BarContent
        var maxWidth: CGFloat
        var trackTitle: String
        var lyricsTitle: String?
    }

    private let monitor: PlaybackMonitor
    private let resolver: LyricsResolver
    private let settings: Settings

    private let menu = StatusMenu()
    private var statusItem: NSStatusItem?
    private var barView: LyricsBarView?
    private var timer: Timer?
    private var lastSnapshot: Snapshot?

    init(monitor: PlaybackMonitor, resolver: LyricsResolver, settings: Settings) {
        self.monitor = monitor
        self.resolver = resolver
        self.settings = settings
    }

    func start() {
        guard statusItem == nil else { return }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu.menu
        self.statusItem = statusItem

        if let button = statusItem.button {
            // The bar view ignores mouse events, so every click lands on the button and opens the menu.
            let barView = LyricsBarView(frame: button.bounds)
            barView.autoresizingMask = [.height]
            button.addSubview(barView)
            self.barView = barView
        }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] timer in
            let alive = MainActor.assumeIsolated {
                self?.tick(now: Date())
                return self != nil
            }
            if !alive {
                timer.invalidate()
            }
        }
        // .common keeps the lyrics following the playback while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick(now: Date())
    }

    private func tick(now: Date) {
        let state = monitor.state
        let status = effectiveStatus(state: state, resolvedTrack: resolver.track, status: resolver.status)
        let lineIndex = currentLineIndex(state: state, status: status, now: now)
        let snapshot = Snapshot(
            content: barContent(state: state, status: status, lineIndex: lineIndex, settings: settings),
            maxWidth: CGFloat(settings.maxWidth),
            trackTitle: StatusMenu.trackTitle(state.track),
            lyricsTitle: StatusMenu.lyricsTitle(status)
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        menu.update(track: state.track, status: status)
        if let barView {
            barView.update(content: snapshot.content, maxWidth: snapshot.maxWidth)
            statusItem?.length = barView.preferredWidth
            if let button = statusItem?.button {
                barView.frame = NSRect(x: 0, y: 0, width: barView.preferredWidth, height: button.bounds.height)
            }
        }
    }
}

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

    let menu = StatusMenu()
    var onOpenSettings: (() -> Void)? {
        get { menu.onOpenSettings }
        set { menu.onOpenSettings = newValue }
    }

    // Internal so tests can drive the updates without a real status bar item.
    var barView: LyricsBarView?

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastSnapshot: Snapshot?
    private var settingsObservation: ObservationLoop?

    init(
        monitor: PlaybackMonitor,
        resolver: LyricsResolver,
        settings: Settings,
        schedule: @escaping ObservationLoop.Schedule = ObservationLoop.mainActorSchedule
    ) {
        self.monitor = monitor
        self.resolver = resolver
        self.settings = settings
        observeSettings(schedule: schedule)
    }

    /// The tick already reads the settings, so this only removes the delay of up to one tick.
    private func observeSettings(schedule: @escaping ObservationLoop.Schedule) {
        settingsObservation = ObservationLoop(
            read: { [weak self] in
                guard let self else { return }
                _ = settings.maxWidth
                _ = settings.showTrackInfo
            },
            onChange: { [weak self] in
                self?.tick(now: Date())
            },
            schedule: schedule)
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
        render(state: state, status: status, now: now)
    }

    // Internal so tests can drive the rendering without Spotify running.
    func render(state: PlaybackState, status: LyricsResolver.Status, now: Date) {
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
            let width = barView.preferredWidth
            // Resizing the status item shifts every item to its left, so only do it when the width
            // really changed.
            if let statusItem, statusItem.length != width {
                statusItem.length = width
            }
            if let button = statusItem?.button {
                let frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
                if barView.frame != frame {
                    barView.frame = frame
                }
            }
        }
    }
}

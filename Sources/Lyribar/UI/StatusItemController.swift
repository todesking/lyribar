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
    private var changeObservation: ObservationLoop?
    private var spaceObserver: NSObjectProtocol?

    init(
        monitor: PlaybackMonitor,
        resolver: LyricsResolver,
        settings: Settings,
        schedule: @escaping ObservationLoop.Schedule = ObservationLoop.mainActorSchedule
    ) {
        self.monitor = monitor
        self.resolver = resolver
        self.settings = settings
        observeChanges(schedule: schedule)
    }

    /// Everything that changes the bar without the playback position moving on, so that the tick
    /// only has to follow the position. `resolver.track` is not observable, but `resolve(track:)`
    /// always assigns `status`, so observing it also catches the changes of `effectiveStatus`.
    private func observeChanges(schedule: @escaping ObservationLoop.Schedule) {
        changeObservation = ObservationLoop(
            read: { [weak self] in
                guard let self else { return }
                _ = monitor.state
                _ = resolver.status
                _ = settings.maxWidth
                _ = settings.showTrackInfo
                _ = settings.lyricsDisplayMode
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

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.barView?.ribbonView.activeSpaceDidChange()
            }
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
        // The ribbon interpolates the position between ticks, so it needs every state, not only
        // the ones that change the snapshot.
        barView?.playback = state
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

import AppKit
import Observation

// Track changes and play/pause come from the com.spotify.client.PlaybackStateChanged distributed
// notification (userInfo keys: see SpotifyNotification.Key). Seeks post no notification, so they are
// only picked up by the 1-second AppleScript resync while playing.
@MainActor
@Observable
final class PlaybackMonitor {
    private(set) var state: PlaybackState = .empty()

    @ObservationIgnored private let snapshot: @Sendable () async -> SpotifySnapshot
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    // Exposed so tests can see whether the periodic resync is running.
    @ObservationIgnored private(set) var resyncTask: Task<Void, Never>?
    // Bumped on every state change so that a snapshot started earlier is not applied over newer data.
    @ObservationIgnored private var generation = 0

    init(snapshot: (@Sendable () async -> SpotifySnapshot)? = nil) {
        let script = SpotifyScript()
        self.snapshot = snapshot ?? { await script.snapshot() }
    }

    func start() {
        guard observers.isEmpty else { return }

        let distributed = DistributedNotificationCenter.default()
        let playbackObserver = distributed.addObserver(
            forName: SpotifyNotification.name, object: nil, queue: .main
        ) { [weak self] notification in
            let parsed = SpotifyNotification.playbackState(from: notification.userInfo, now: Date())
            MainActor.assumeIsolated {
                self?.handleNotification(parsed)
            }
        }
        observers.append((distributed, playbackObserver))

        let workspace = NSWorkspace.shared.notificationCenter
        let terminateObserver = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SpotifyScript.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.apply(.empty())
            }
        }
        observers.append((workspace, terminateObserver))

        resync()
    }

    func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        resyncTask?.cancel()
        resyncTask = nil
    }

    private func handleNotification(_ parsed: PlaybackState?) {
        if let parsed {
            apply(parsed)
        } else {
            resync()
        }
    }

    private func resync() {
        let expected = generation
        Task {
            let result = await snapshot()
            guard expected == generation else { return }
            apply(result)
        }
    }

    /// A failed snapshot leaves the state and the resync loop alone: the script fails while Spotify
    /// keeps playing (Apple Event timeout, Automation denied), and dropping the track there would
    /// clear the lyrics. Spotify quitting is covered by the workspace notification instead.
    private func apply(_ snapshot: SpotifySnapshot) {
        switch snapshot {
        case .state(let newState): apply(newState)
        case .notRunning: apply(.empty())
        case .failed: break
        }
    }

    private func apply(_ newState: PlaybackState) {
        generation += 1
        state = newState
        updateResyncTask()
    }

    // Periodic resync covers seeks and missed notifications; it only runs while playing.
    private func updateResyncTask() {
        let shouldRun = state.isPlaying && state.track != nil
        if shouldRun, resyncTask == nil {
            resyncTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    await self.periodicResync()
                }
            }
        } else if !shouldRun {
            resyncTask?.cancel()
            resyncTask = nil
        }
    }

    // Not private so that tests can drive one round without waiting for the timer.
    func periodicResync() async {
        let expected = generation
        let result = await snapshot()
        guard !Task.isCancelled, expected == generation else { return }
        apply(result)
    }
}

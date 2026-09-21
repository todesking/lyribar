import Foundation
import Testing

@testable import Lyribar

/// Hands out the snapshot the test set last, so the periodic loop can keep asking for it.
private actor SnapshotSource {
    private var next: SpotifySnapshot

    init(_ initial: SpotifySnapshot) {
        next = initial
    }

    func set(_ snapshot: SpotifySnapshot) {
        next = snapshot
    }

    func take() -> SpotifySnapshot {
        next
    }
}

/// `start()` needs the real notification centers, so these tests drive `periodicResync()` directly.
@MainActor
struct PlaybackMonitorTests {
    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 354)

    private func playing(at position: TimeInterval = 12.5) -> SpotifySnapshot {
        .state(PlaybackState(track: track, isPlaying: true, syncedPosition: position, syncedAt: Date()))
    }

    private func makeMonitor(_ source: SnapshotSource) -> PlaybackMonitor {
        PlaybackMonitor(snapshot: { await source.take() })
    }

    @Test func failedSnapshotKeepsTheTrackPlaying() async {
        let source = SnapshotSource(playing())
        let monitor = makeMonitor(source)
        defer { monitor.stop() }
        await monitor.periodicResync()
        #expect(monitor.state.track == track)

        await source.set(.failed)
        await monitor.periodicResync()
        #expect(monitor.state.track == track)
        #expect(monitor.state.isPlaying)
    }

    @Test func failedSnapshotKeepsTheResyncLoopRunning() async {
        let source = SnapshotSource(playing())
        let monitor = makeMonitor(source)
        defer { monitor.stop() }
        await monitor.periodicResync()
        #expect(monitor.resyncTask != nil)

        await source.set(.failed)
        await monitor.periodicResync()
        #expect(monitor.resyncTask != nil)
    }

    @Test func stateAfterAFailureIsApplied() async {
        let source = SnapshotSource(.failed)
        let monitor = makeMonitor(source)
        defer { monitor.stop() }
        await monitor.periodicResync()
        #expect(monitor.state.track == nil)

        await source.set(playing(at: 30))
        await monitor.periodicResync()
        #expect(monitor.state.track == track)
        #expect(monitor.state.syncedPosition == 30)
        #expect(monitor.state.isPlaying)
    }

    @Test func notRunningClearsTheTrack() async {
        let source = SnapshotSource(playing())
        let monitor = makeMonitor(source)
        defer { monitor.stop() }
        await monitor.periodicResync()
        #expect(monitor.state.track == track)

        await source.set(.notRunning)
        await monitor.periodicResync()
        #expect(monitor.state.track == nil)
        #expect(monitor.state.isPlaying == false)
        #expect(monitor.resyncTask == nil)
    }
}

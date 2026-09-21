import Foundation
import Observation

/// How much disk the lyrics cache takes, as shown in the settings. The reading lives outside the
/// view so that whoever opens the window can refresh it; the view has no lifecycle of its own once
/// the window is reused across open/close cycles.
@MainActor
@Observable
final class LyricsCacheUsage {
    private(set) var bytes = 0

    @ObservationIgnored private let cache: LyricsCache

    init(cache: LyricsCache) {
        self.cache = cache
    }

    func refresh() {
        bytes = cache.totalSize()
    }

    func clear() {
        cache.clear()
        refresh()
    }
}

import AppKit

// Owns the NSMenu instead of subclassing it: NSMenu's designated initializer is nonisolated.
@MainActor
final class StatusMenu: NSObject {
    let menu = NSMenu(title: "Lyribar")
    var onOpenSettings: (() -> Void)?

    private let trackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lyricsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        menu.autoenablesItems = false
        trackItem.isEnabled = false
        lyricsItem.isEnabled = false

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let quitItem = NSMenuItem(
            title: "Quit Lyribar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.addItem(trackItem)
        menu.addItem(lyricsItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        update(track: nil, status: .idle)
    }

    func update(track: TrackInfo?, status: LyricsResolver.Status) {
        trackItem.title = Self.trackTitle(track)
        let lyricsTitle = track == nil ? nil : Self.lyricsTitle(status)
        lyricsItem.title = lyricsTitle ?? ""
        lyricsItem.isHidden = lyricsTitle == nil
    }

    static func trackTitle(_ track: TrackInfo?) -> String {
        track?.displayText ?? "Not playing"
    }

    static func lyricsTitle(_ status: LyricsResolver.Status) -> String? {
        switch status {
        case .idle: nil
        case .loading: "Loading lyrics…"
        case .found(_, let source): "Lyrics from \(sourceName(source))"
        case .notFound: "No lyrics found"
        case .failed: "Failed to load lyrics"
        }
    }

    private static func sourceName(_ source: String) -> String {
        source == LRCLibProvider.source ? "LRCLIB" : source
    }

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings?()
    }
}

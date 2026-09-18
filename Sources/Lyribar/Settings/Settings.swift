import Foundation
import Observation

enum LyricsDisplayMode: String, CaseIterable, Sendable {
    /// Every line on a ribbon that scrolls with the playback position.
    case scrolling
    /// Only the current line, with a marquee when it does not fit.
    case currentLine
}

@MainActor
@Observable
final class Settings {
    enum Key {
        static let maxWidth = "maxWidth"
        static let showTrackInfo = "showTrackInfo"
        static let launchAtLogin = "launchAtLogin"
        static let lyricsDisplayMode = "lyricsDisplayMode"
    }

    static let defaultMaxWidth: Double = 300
    static let defaultLyricsDisplayMode = LyricsDisplayMode.scrolling

    var maxWidth: Double {
        didSet { defaults.set(maxWidth, forKey: Key.maxWidth) }
    }
    var showTrackInfo: Bool {
        didSet { defaults.set(showTrackInfo, forKey: Key.showTrackInfo) }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    var lyricsDisplayMode: LyricsDisplayMode {
        didSet { defaults.set(lyricsDisplayMode.rawValue, forKey: Key.lyricsDisplayMode) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.maxWidth: Self.defaultMaxWidth,
            Key.showTrackInfo: true,
            Key.launchAtLogin: false,
            Key.lyricsDisplayMode: Self.defaultLyricsDisplayMode.rawValue,
        ])
        maxWidth = defaults.double(forKey: Key.maxWidth)
        showTrackInfo = defaults.bool(forKey: Key.showTrackInfo)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        lyricsDisplayMode =
            defaults.string(forKey: Key.lyricsDisplayMode).flatMap(LyricsDisplayMode.init(rawValue:))
            ?? Self.defaultLyricsDisplayMode
    }
}

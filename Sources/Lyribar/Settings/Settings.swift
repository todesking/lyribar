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
        static let spotifySecretsURL = "spotifySecretsURL"
    }

    static let defaultMaxWidth: Double = 300
    static let defaultLyricsDisplayMode = LyricsDisplayMode.scrolling
    static let defaultSpotifySecretsURL = URL(
        string: "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json")!

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

    /// Hidden setting, changed with `defaults write` when the published secrets move. It is not
    /// registered as a default, so an unset key stays unset.
    var spotifySecretsURL: URL {
        guard let string = defaults.object(forKey: Key.spotifySecretsURL) as? String,
            let url = URL(string: string), url.scheme == "https", url.host() != nil
        else { return Self.defaultSpotifySecretsURL }
        return url
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

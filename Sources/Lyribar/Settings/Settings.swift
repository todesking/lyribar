import Foundation
import Observation

@MainActor
@Observable
final class Settings {
    enum Key {
        static let maxWidth = "maxWidth"
        static let showTrackInfo = "showTrackInfo"
        static let launchAtLogin = "launchAtLogin"
    }

    static let defaultMaxWidth: Double = 300

    var maxWidth: Double {
        didSet { defaults.set(maxWidth, forKey: Key.maxWidth) }
    }
    var showTrackInfo: Bool {
        didSet { defaults.set(showTrackInfo, forKey: Key.showTrackInfo) }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.maxWidth: Self.defaultMaxWidth,
            Key.showTrackInfo: true,
            Key.launchAtLogin: false,
        ])
        maxWidth = defaults.double(forKey: Key.maxWidth)
        showTrackInfo = defaults.bool(forKey: Key.showTrackInfo)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }
}

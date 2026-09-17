import Foundation
import Testing
@testable import Lyribar

@MainActor
struct SettingsTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func defaultValues() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = Settings(defaults: defaults)
        #expect(settings.maxWidth == 300)
        #expect(settings.showTrackInfo)
        #expect(!settings.launchAtLogin)
    }

    @Test func persistsChanges() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = Settings(defaults: defaults)
        settings.maxWidth = 420
        settings.showTrackInfo = false
        settings.launchAtLogin = true

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.maxWidth == 420)
        #expect(!reloaded.showTrackInfo)
        #expect(reloaded.launchAtLogin)
    }
}

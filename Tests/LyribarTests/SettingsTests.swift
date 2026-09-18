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
        #expect(settings.lyricsDisplayMode == .scrolling)
    }

    @Test func persistsChanges() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = Settings(defaults: defaults)
        settings.maxWidth = 420
        settings.showTrackInfo = false
        settings.launchAtLogin = true
        settings.lyricsDisplayMode = .currentLine

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.maxWidth == 420)
        #expect(!reloaded.showTrackInfo)
        #expect(reloaded.launchAtLogin)
        #expect(reloaded.lyricsDisplayMode == .currentLine)
        #expect(defaults.string(forKey: Settings.Key.lyricsDisplayMode) == "currentLine")
    }

    @Test func readsValuesStoredBefore() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(180.0, forKey: Settings.Key.maxWidth)
        defaults.set(false, forKey: Settings.Key.showTrackInfo)
        defaults.set(true, forKey: Settings.Key.launchAtLogin)

        let settings = Settings(defaults: defaults)
        #expect(settings.maxWidth == 180)
        #expect(!settings.showTrackInfo)
        #expect(settings.launchAtLogin)
    }

    @Test func readsLyricsDisplayModeStoredBefore() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("currentLine", forKey: Settings.Key.lyricsDisplayMode)

        #expect(Settings(defaults: defaults).lyricsDisplayMode == .currentLine)
    }

    @Test func unknownLyricsDisplayModeFallsBackToTheDefault() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("karaoke", forKey: Settings.Key.lyricsDisplayMode)

        #expect(Settings(defaults: defaults).lyricsDisplayMode == .scrolling)

        defaults.set(42, forKey: Settings.Key.lyricsDisplayMode)
        #expect(Settings(defaults: defaults).lyricsDisplayMode == .scrolling)
    }

    @Test func writesOnlyToTheInjectedSuite() {
        let (defaults, suite) = makeDefaults()
        let (otherDefaults, otherSuite) = makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
            otherDefaults.removePersistentDomain(forName: otherSuite)
        }

        let settings = Settings(defaults: defaults)
        settings.maxWidth = 555

        #expect(defaults.double(forKey: Settings.Key.maxWidth) == 555)
        #expect(Settings(defaults: otherDefaults).maxWidth == 300)
    }
}

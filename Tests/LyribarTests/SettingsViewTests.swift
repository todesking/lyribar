import Foundation
import Testing

@testable import Lyribar

@MainActor
struct SettingsViewTests {
    private let locale = Locale(identifier: "en_US")

    @Test func cacheSizeIsHumanReadable() {
        #expect(Lyribar.cacheSizeText(bytes: 1_200_000, locale: locale) == "Cache: 1.2 MB")
        #expect(Lyribar.cacheSizeText(bytes: 512, locale: locale) == "Cache: 512 bytes")
    }

    @Test func emptyCacheHasItsOwnText() {
        #expect(Lyribar.cacheSizeText(bytes: 0, locale: locale) == "Cache: empty")
    }

    @Test func maxWidthSliderCoversTheSettingRange() {
        #expect(SettingsView.maxWidthRange == 150...600)
        #expect(SettingsView.maxWidthStep == 10)
        #expect(SettingsView.maxWidthRange.contains(Settings.defaultMaxWidth))
    }

    @Test func lyricsDisplayPickerOffersEveryMode() {
        #expect(SettingsView.lyricsDisplayTitle == "Lyrics display")
        #expect(SettingsView.lyricsDisplayOptions.map(\.mode) == [.scrolling, .currentLine])
        #expect(SettingsView.lyricsDisplayOptions.map(\.title) == ["Scrolling lyrics", "Current line only"])
        #expect(Set(SettingsView.lyricsDisplayOptions.map(\.mode)) == Set(LyricsDisplayMode.allCases))
    }

    @Test func spotifySectionTexts() {
        #expect(SettingsView.spotifyTitle == "Spotify lyrics (unofficial)")
        #expect(SettingsView.spotifyCookiePrompt == "sp_dc cookie")
        #expect(
            SettingsView.spotifyFooter
                == "Uses your Spotify web session to fetch the lyrics Spotify shows. Unofficial and may stop working. Falls back to LRCLIB."
        )
    }

    @Test func saveNeedsSomethingThatNormalizesToACookie() {
        #expect(!SettingsView.canSaveSpotifyCookie(""))
        #expect(!SettingsView.canSaveSpotifyCookie("  \n"))
        #expect(!SettingsView.canSaveSpotifyCookie("sp_dc=;"))
        #expect(SettingsView.canSaveSpotifyCookie("abc"))
        #expect(SettingsView.canSaveSpotifyCookie("sp_dc=abc; sp_key=x"))
    }

    @Test func onlyFailedChecksAreShownAsProblems() {
        #expect(SettingsView.isSpotifyProblem(.rejected))
        #expect(SettingsView.isSpotifyProblem(.unverified("boom")))
        #expect(!SettingsView.isSpotifyProblem(.notConfigured))
        #expect(!SettingsView.isSpotifyProblem(.checking))
        #expect(!SettingsView.isSpotifyProblem(.connected))
    }
}

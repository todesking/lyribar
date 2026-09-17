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
}

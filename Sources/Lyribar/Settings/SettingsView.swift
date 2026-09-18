import SwiftUI

/// "Cache: 1.2 MB". The locale is a parameter so the text can be tested.
func cacheSizeText(bytes: Int, locale: Locale = .current) -> String {
    guard bytes > 0 else { return "Cache: empty" }
    return "Cache: " + Int64(bytes).formatted(.byteCount(style: .file).locale(locale))
}

struct SettingsView: View {
    static let maxWidthRange: ClosedRange<Double> = 150...600
    static let maxWidthStep: Double = 10
    static let width: CGFloat = 380
    static let lyricsDisplayTitle = "Lyrics display"
    static let lyricsDisplayOptions: [(mode: LyricsDisplayMode, title: String)] = [
        (.scrolling, "Scrolling lyrics"),
        (.currentLine, "Current line only"),
    ]

    static let spotifyTitle = "Spotify lyrics (unofficial)"
    static let spotifyCookiePrompt = "sp_dc cookie"
    static let spotifyFooter =
        "Uses your Spotify web session to fetch the lyrics Spotify shows. Unofficial and may stop working. Falls back to LRCLIB."

    @Bindable var settings: Settings
    let launchAtLogin: LaunchAtLoginController
    let spotify: SpotifyAccountController
    let cache: LyricsCache

    @State private var cacheSize = 0
    @State private var spotifyCookie = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Maximum width")
                        Spacer()
                        Text("\(Int(settings.maxWidth)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.maxWidth, in: Self.maxWidthRange, step: Self.maxWidthStep)
                }
                Picker(Self.lyricsDisplayTitle, selection: $settings.lyricsDisplayMode) {
                    ForEach(Self.lyricsDisplayOptions, id: \.mode) { option in
                        Text(option.title).tag(option.mode)
                    }
                }
                Toggle("Show track name and artist", isOn: $settings.showTrackInfo)
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if let status = SpotifyAccountController.statusText(spotify.state) {
                    HStack {
                        Text(status)
                            .foregroundStyle(Self.isSpotifyProblem(spotify.state) ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Remove") { spotify.remove() }
                    }
                } else {
                    HStack {
                        SecureField(
                            Self.spotifyCookiePrompt, text: $spotifyCookie,
                            prompt: Text(Self.spotifyCookiePrompt)
                        )
                        .labelsHidden()
                        Button("Save") { saveSpotifyCookie() }
                            .disabled(!Self.canSaveSpotifyCookie(spotifyCookie))
                    }
                }
            } header: {
                Text(Self.spotifyTitle)
            } footer: {
                Text(Self.spotifyFooter)
            }

            Section {
                HStack {
                    Button("Clear lyrics cache") {
                        cache.clear()
                        cacheSize = cache.totalSize()
                    }
                    Spacer()
                    Text(cacheSizeText(bytes: cacheSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .onAppear {
            launchAtLogin.syncFromSystem()
            cacheSize = cache.totalSize()
            Task { await spotify.refresh() }
        }
    }

    static func canSaveSpotifyCookie(_ input: String) -> Bool {
        SpotifyCookie.normalize(input) != nil
    }

    static func isSpotifyProblem(_ state: SpotifyAccountController.State) -> Bool {
        switch state {
        case .rejected, .unverified: true
        case .notConfigured, .checking, .connected: false
        }
    }

    // The field is emptied right away: the cookie should not linger on screen while it is checked.
    private func saveSpotifyCookie() {
        let input = spotifyCookie
        spotifyCookie = ""
        Task { await spotify.save(input) }
    }

    // Writing through the controller instead of the setting: a failed registration must leave the
    // toggle where it was.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: { launchAtLogin.setEnabled($0) })
    }
}

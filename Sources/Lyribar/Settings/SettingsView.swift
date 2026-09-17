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

    @Bindable var settings: Settings
    let launchAtLogin: LaunchAtLoginController
    let cache: LyricsCache

    @State private var cacheSize = 0

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
        }
    }

    // Writing through the controller instead of the setting: a failed registration must leave the
    // toggle where it was.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: { launchAtLogin.setEnabled($0) })
    }
}

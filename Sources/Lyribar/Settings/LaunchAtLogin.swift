import Foundation
import Observation
import ServiceManagement

/// Registering the app as a login item is a side effect on the user's system, so it sits behind a
/// protocol: tests drive the controller with a fake instead of touching the real login items.
@MainActor
protocol LaunchAtLoginService {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct SystemLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Keeps `Settings.launchAtLogin` in step with the real login item registration.
@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var errorMessage: String?

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let service: any LaunchAtLoginService

    init(settings: Settings, service: any LaunchAtLoginService = SystemLaunchAtLoginService()) {
        self.settings = settings
        self.service = service
    }

    /// The login item can be removed in System Settings without telling us, so the stored flag is
    /// only a cache of the real state.
    func syncFromSystem() {
        settings.launchAtLogin = service.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        let previous = settings.launchAtLogin
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            settings.launchAtLogin = enabled
            errorMessage = nil
        } catch {
            settings.launchAtLogin = previous
            errorMessage = Self.errorMessage(enabling: enabled, error: error)
        }
    }

    static func errorMessage(enabling: Bool, error: Error) -> String {
        let action = enabling ? "enable" : "disable"
        return "Could not \(action) launch at login: \(error.localizedDescription)"
    }
}

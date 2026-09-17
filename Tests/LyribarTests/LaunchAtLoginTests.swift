import Foundation
import Testing

@testable import Lyribar

private struct FakeError: LocalizedError {
    var errorDescription: String? { "denied" }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled = false
    var failure: Error?
    var calls: [String] = []

    func register() throws {
        calls.append("register")
        if let failure { throw failure }
        isEnabled = true
    }

    func unregister() throws {
        calls.append("unregister")
        if let failure { throw failure }
        isEnabled = false
    }
}

@MainActor
struct LaunchAtLoginTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "LyribarTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func make(
        launchAtLogin: Bool = false, isEnabled: Bool = false
    ) -> (LaunchAtLoginController, Settings, FakeLaunchAtLoginService, () -> Void) {
        let (defaults, suite) = makeDefaults()
        defaults.set(launchAtLogin, forKey: Settings.Key.launchAtLogin)
        let settings = Settings(defaults: defaults)
        let service = FakeLaunchAtLoginService()
        service.isEnabled = isEnabled
        let controller = LaunchAtLoginController(settings: settings, service: service)
        return (controller, settings, service, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func enablingRegisters() {
        let (controller, settings, service, cleanup) = make()
        defer { cleanup() }

        controller.setEnabled(true)

        #expect(service.calls == ["register"])
        #expect(service.isEnabled)
        #expect(settings.launchAtLogin)
        #expect(controller.errorMessage == nil)
    }

    @Test func disablingUnregisters() {
        let (controller, settings, service, cleanup) = make(launchAtLogin: true, isEnabled: true)
        defer { cleanup() }

        controller.setEnabled(false)

        #expect(service.calls == ["unregister"])
        #expect(!service.isEnabled)
        #expect(!settings.launchAtLogin)
        #expect(controller.errorMessage == nil)
    }

    @Test func failedRegistrationRollsBack() {
        let (controller, settings, service, cleanup) = make()
        defer { cleanup() }
        service.failure = FakeError()

        controller.setEnabled(true)

        #expect(!settings.launchAtLogin)
        #expect(controller.errorMessage == "Could not enable launch at login: denied")
    }

    @Test func failedUnregistrationRollsBack() {
        let (controller, settings, service, cleanup) = make(launchAtLogin: true, isEnabled: true)
        defer { cleanup() }
        service.failure = FakeError()

        controller.setEnabled(false)

        #expect(settings.launchAtLogin)
        #expect(controller.errorMessage == "Could not disable launch at login: denied")
    }

    @Test func successClearsAnEarlierError() {
        let (controller, settings, service, cleanup) = make()
        defer { cleanup() }
        service.failure = FakeError()
        controller.setEnabled(true)
        #expect(controller.errorMessage != nil)

        service.failure = nil
        controller.setEnabled(true)

        #expect(controller.errorMessage == nil)
        #expect(settings.launchAtLogin)
    }

    @Test func syncAdoptsTheSystemState() {
        let (controller, settings, _, cleanup) = make(launchAtLogin: true, isEnabled: false)
        defer { cleanup() }
        #expect(settings.launchAtLogin)

        controller.syncFromSystem()

        #expect(!settings.launchAtLogin)
    }

    @Test func syncTurnsTheFlagOnWhenAlreadyRegistered() {
        let (controller, settings, _, cleanup) = make(launchAtLogin: false, isEnabled: true)
        defer { cleanup() }

        controller.syncFromSystem()

        #expect(settings.launchAtLogin)
    }
}

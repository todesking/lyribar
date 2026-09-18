import AppKit

/// Handing focus over to another app is a side effect on the whole session, so it sits behind a
/// protocol: tests drive the settings window with a fake instead of shuffling real apps around.
@MainActor
protocol ActivationService {
    /// The app that holds focus right now, or nil when this app itself holds it.
    func frontmostApplication() -> (any ActivatableApp)?
    /// Hides this app, which makes the system bring the app behind it forward.
    func hideSelf()
}

/// An app focus can be handed back to.
@MainActor
protocol ActivatableApp {
    var isTerminated: Bool { get }
    /// Returns false when the system turns the hand-off down.
    func activate() -> Bool
}

@MainActor
struct SystemActivationService: ActivationService {
    func frontmostApplication() -> (any ActivatableApp)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return nil }
        return RunningApp(app)
    }

    func hideSelf() {
        NSApplication.shared.hide(nil)
    }
}

/// Keeps NSRunningApplication out of the callers, which are unit tested.
@MainActor
private struct RunningApp: ActivatableApp {
    let app: NSRunningApplication

    init(_ app: NSRunningApplication) {
        self.app = app
    }

    var isTerminated: Bool { app.isTerminated }

    func activate() -> Bool {
        // Activation is cooperative since macOS 14: the active app has to yield first, otherwise
        // the system may ignore the other app's activate() and focus stays here.
        NSApplication.shared.yieldActivation(to: app)
        return app.activate()
    }
}

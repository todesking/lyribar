import AppKit

/// Handing focus over to another app is a side effect on the whole session, so it sits behind a
/// protocol: tests drive the settings window with a fake instead of shuffling real apps around.
@MainActor
protocol ActivationService {
    /// The app that holds focus right now, this one included.
    func frontmostApplication() -> (any ActivatableApp)?
    /// Hides this app, which makes the system bring the app behind it forward.
    func hideSelf()
}

/// An app focus can be handed back to.
@MainActor
protocol ActivatableApp {
    /// True for Lyribar itself, which is never worth handing focus back to.
    var isCurrentApp: Bool { get }
    var isTerminated: Bool { get }
    /// Returns false when the system turns the hand-off down.
    func activate() -> Bool
}

@MainActor
struct SystemActivationService: ActivationService {
    func frontmostApplication() -> (any ActivatableApp)? {
        NSWorkspace.shared.frontmostApplication.map(RunningApp.init)
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

    var isCurrentApp: Bool {
        app.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    var isTerminated: Bool { app.isTerminated }

    func activate() -> Bool {
        // Activation is cooperative since macOS 14: the active app has to yield first, otherwise
        // the system may ignore the other app's activate() and focus stays here.
        NSApplication.shared.yieldActivation(to: app)
        return app.activate()
    }
}

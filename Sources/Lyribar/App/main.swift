import AppKit

// NSApplication is started manually so the delegate can be owned by top-level code.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
// Info.plist's LSUIElement only applies to an .app bundle, so setting the policy here is what
// keeps `swift run` (a bare binary, otherwise .regular) behaving like the shipped app.
application.setActivationPolicy(.accessory)
application.run()

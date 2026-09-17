import AppKit

// NSApplication is started manually so the delegate can be owned by top-level code.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()

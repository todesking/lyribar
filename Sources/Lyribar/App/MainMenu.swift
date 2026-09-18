import AppKit

/// Cmd+W is dispatched by AppKit through a main menu item, not by the window itself, so an
/// accessory app needs a main menu too. Nothing shows in the menu bar while the app stays
/// accessory; only the key equivalents become live.
@MainActor
func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: "Window")
    // No target: the action travels the responder chain and reaches the key window.
    windowMenu.addItem(
        NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    return mainMenu
}

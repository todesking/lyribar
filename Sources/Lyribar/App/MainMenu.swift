import AppKit

/// Cmd+W is dispatched by AppKit through a main menu item, not by the window itself, so an
/// accessory app needs a main menu too. The menu only shows in the menu bar while the settings
/// window turns the app regular; the rest of the time just its key equivalents are live.
@MainActor
func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    // AppKit treats the first item as the app menu whatever its title, so it has to come first.
    let appItem = NSMenuItem(title: "Lyribar", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "Lyribar")
    appMenu.addItem(
        NSMenuItem(
            title: "About Lyribar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
    appMenu.addItem(.separator())
    appMenu.addItem(
        NSMenuItem(
            title: "Quit Lyribar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: "Window")
    // No target: the action travels the responder chain and reaches the key window.
    windowMenu.addItem(
        NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    return mainMenu
}

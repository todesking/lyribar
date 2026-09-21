import AppKit
import Testing

@testable import Lyribar

@MainActor
struct MainMenuTests {
    @Test func windowMenuHasACloseItemBoundToCmdW() throws {
        let windowMenu = try #require(makeMainMenu().item(withTitle: "Window")?.submenu)
        let closeItems = windowMenu.items.filter { $0.keyEquivalent == "w" }

        #expect(closeItems.count == 1)
        let close = try #require(closeItems.first)
        #expect(close.keyEquivalentModifierMask == [.command])
        #expect(close.action == #selector(NSWindow.performClose(_:)))
        // The key window, not a fixed target, is what has to receive the action.
        #expect(close.target == nil)
    }

    /// The first submenu is shown as the app menu while the settings window makes the app regular,
    /// so the Window menu must not sit in that place.
    @Test func theFirstMenuIsTheAppMenu() throws {
        let mainMenu = makeMainMenu()

        #expect(mainMenu.items.map(\.title) == ["Lyribar", "Window"])
        let appMenu = try #require(mainMenu.items.first?.submenu)
        #expect(appMenu.items.map(\.title) == ["About Lyribar", "", "Quit Lyribar"])
        #expect(appMenu.items[1].isSeparatorItem)
    }

    @Test func theAppMenuHasAboutAndQuit() throws {
        let appMenu = try #require(makeMainMenu().items.first?.submenu)

        let about = try #require(appMenu.item(withTitle: "About Lyribar"))
        #expect(about.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        #expect(about.keyEquivalent.isEmpty)
        #expect(about.target == nil)

        let quit = try #require(appMenu.item(withTitle: "Quit Lyribar"))
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == [.command])
        #expect(quit.target == nil)
    }

    @Test func theWindowMenuOnlyHasClose() {
        let mainMenu = makeMainMenu()

        #expect(mainMenu.item(withTitle: "Window")?.submenu?.items.map(\.title) == ["Close"])
    }
}

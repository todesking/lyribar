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

    @Test func onlyTheCloseItemIsAdded() {
        let mainMenu = makeMainMenu()
        #expect(mainMenu.items.map(\.title) == ["Window"])
        #expect(mainMenu.item(withTitle: "Window")?.submenu?.items.map(\.title) == ["Close"])
    }
}

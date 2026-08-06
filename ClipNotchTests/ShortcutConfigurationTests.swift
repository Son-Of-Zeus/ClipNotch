import ApplicationServices
import XCTest
@testable import ClipNotch

final class ShortcutConfigurationTests: XCTestCase {
    func testGlobalShortcutRequiresExactModifiers() {
        let shortcut = GlobalShortcut(keyCode: 0x26, modifiers: [.command, .shift])

        XCTAssertTrue(ShortcutMatcher.matchesGlobalShortcut(
            keyCode: 0x26,
            flags: [.maskCommand, .maskShift],
            shortcut: shortcut
        ))
        XCTAssertFalse(ShortcutMatcher.matchesGlobalShortcut(
            keyCode: 0x26,
            flags: [.maskCommand],
            shortcut: shortcut
        ))
        XCTAssertFalse(ShortcutMatcher.matchesGlobalShortcut(
            keyCode: 0x26,
            flags: [.maskCommand, .maskShift, .maskAlternate],
            shortcut: shortcut
        ))
    }

    func testHoldModeLetsOpenerKeyReachNavigationWhenDrawerIsOpen() {
        let shortcut = GlobalShortcut(keyCode: 0x26, modifiers: [.command, .shift])

        XCTAssertFalse(ShortcutMatcher.shouldHandleOpenShortcut(
            keyCode: 0x26,
            flags: [.maskCommand, .maskShift],
            isAutoRepeat: false,
            drawerIsOpen: true,
            shortcut: shortcut,
            mode: .holdToPaste
        ))
    }

    func testOpenerStillHandlesClosedDrawerAndToggleMode() {
        let shortcut = GlobalShortcut(keyCode: 0x26, modifiers: [.command, .shift])

        XCTAssertTrue(ShortcutMatcher.shouldHandleOpenShortcut(
            keyCode: 0x26,
            flags: [.maskCommand, .maskShift],
            isAutoRepeat: false,
            drawerIsOpen: false,
            shortcut: shortcut,
            mode: .holdToPaste
        ))
        XCTAssertTrue(ShortcutMatcher.shouldHandleOpenShortcut(
            keyCode: 0x26,
            flags: [.maskCommand, .maskShift],
            isAutoRepeat: false,
            drawerIsOpen: true,
            shortcut: shortcut,
            mode: .toggle
        ))
    }

    func testHoldModePastesOnlyAfterAllOpenerModifiersRelease() {
        let opener = GlobalShortcut(keyCode: 0x26, modifiers: [.command, .shift])

        XCTAssertFalse(ShortcutMatcher.shouldPasteAfterModifierChange(
            flags: [.maskCommand, .maskShift], opener: opener, mode: .holdToPaste
        ))
        XCTAssertFalse(ShortcutMatcher.shouldPasteAfterModifierChange(
            flags: [.maskCommand], opener: opener, mode: .holdToPaste
        ))
        XCTAssertTrue(ShortcutMatcher.shouldPasteAfterModifierChange(
            flags: [], opener: opener, mode: .holdToPaste
        ))
        XCTAssertFalse(ShortcutMatcher.shouldPasteAfterModifierChange(
            flags: [], opener: opener, mode: .toggle
        ))
    }

    func testConfigurationDetectsDuplicateNavigationKeys() {
        var configuration = ShortcutConfiguration.default
        configuration.nextItem = NavigationShortcut(keyCode: configuration.previousItem.keyCode)
        XCTAssertTrue(configuration.hasDuplicateNavigationKeys)
    }

    func testDefaultConfigurationPreservesExistingShortcuts() {
        let configuration = ShortcutConfiguration.default
        XCTAssertEqual(configuration.openDrawer, .default)
        XCTAssertEqual(configuration.previousItem, .previous)
        XCTAssertEqual(configuration.nextItem, .next)
        XCTAssertEqual(configuration.interactionMode, .holdToPaste)
    }

    func testConfigurationRoundTripsThroughPersistenceEncoding() throws {
        let configuration = ShortcutConfiguration(
            openDrawer: GlobalShortcut(keyCode: 0x26, modifiers: [.command, .option, .shift]),
            previousItem: NavigationShortcut(keyCode: 0x7E),
            nextItem: NavigationShortcut(keyCode: 0x7D),
            interactionMode: .toggle
        )

        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(decoded, configuration)
    }
}

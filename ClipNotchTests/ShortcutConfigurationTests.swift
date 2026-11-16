import ApplicationServices
import XCTest
@testable import ClipNotch

final class ShortcutConfigurationTests: XCTestCase {
    func testBothNavigationKeysOpenTheirDerivedPages() {
        let configuration = ShortcutConfiguration.default
        for key in [configuration.previousItem, configuration.nextItem] {
            XCTAssertEqual(ShortcutMatcher.openingPage(keyCode: key.keyCode, flags: .maskCommand, configuration: configuration), .clipboard)
            XCTAssertEqual(ShortcutMatcher.openingPage(keyCode: key.keyCode, flags: [.maskCommand, .maskShift], configuration: configuration), .dataTypes)
            XCTAssertNil(ShortcutMatcher.openingPage(keyCode: key.keyCode, flags: [.maskCommand, .maskAlternate], configuration: configuration))
            XCTAssertNil(ShortcutMatcher.openingPage(keyCode: key.keyCode, flags: [], configuration: configuration))
        }
    }

    func testDuplicateAndReservedKeysAreRejected() {
        var configuration = ShortcutConfiguration.default
        configuration.nextItem = configuration.previousItem
        XCTAssertFalse(configuration.isValid)
        for keyCode: UInt16 in [0x24, 0x30, 0x35, 0x37, 0x38, 0x4C] {
            XCTAssertFalse(NavigationShortcut(keyCode: keyCode).isValid)
        }
    }

    @MainActor
    func testShortcutConfigurationSurvivesEncryptedPreferencesReload() throws {
        let directory = makeStorageDirectory()
        let preferences = try PreferencesStore(directory: directory, encryption: testEncryption)
        let configuration = ShortcutConfiguration(
            previousItem: NavigationShortcut(keyCode: 126),
            nextItem: NavigationShortcut(keyCode: 125),
            interactionMode: .toggle
        )
        preferences.set(\.shortcutConfiguration, to: configuration)
        let reloaded = try PreferencesStore(directory: directory, encryption: testEncryption)
        XCTAssertEqual(reloaded.values.shortcutConfiguration, configuration)
    }
}

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

    func testMigrationPreservesNavigationAndRemovesOldOpener() throws {
        let suite = "ClipNotchTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Data("""
        {"openDrawer":{"keyCode":40,"modifiers":9},"previousItem":{"keyCode":126},"nextItem":{"keyCode":125},"interactionMode":"toggle"}
        """.utf8)
        defaults.set(legacy, forKey: ShortcutConfiguration.storageKey)

        let configuration = ShortcutConfiguration.load(defaults: defaults)

        XCTAssertEqual(configuration.previousItem.keyCode, 126)
        XCTAssertEqual(configuration.nextItem.keyCode, 125)
        XCTAssertEqual(configuration.interactionMode, .toggle)
        let saved = try XCTUnwrap(defaults.data(forKey: ShortcutConfiguration.storageKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(object["openDrawer"])
        XCTAssertEqual(try JSONDecoder().decode(ShortcutConfiguration.self, from: saved), configuration)
    }
}

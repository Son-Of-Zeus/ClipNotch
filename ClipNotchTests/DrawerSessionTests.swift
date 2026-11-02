import ApplicationServices
import XCTest
@testable import ClipNotch

final class DrawerSessionTests: XCTestCase {
    private let commandShift: CGEventFlags = [.maskCommand, .maskShift]

    private func openedPalette(mode: DrawerInteractionMode = .holdToPaste) -> DrawerSession {
        var session = DrawerSession()
        let configuration = ShortcutConfiguration(interactionMode: mode)
        XCTAssertEqual(session.keyDown(0x26, flags: commandShift, isRepeat: false, configuration: configuration), .open)
        return session
    }

    func testShiftSelectsDataTypeThenCommandConfirmsProfileValue() {
        var session = openedPalette()
        XCTAssertEqual(session.flagsChanged(.maskCommand, mode: .holdToPaste), .confirm)
        session.show(.profileValues)
        XCTAssertEqual(session.flagsChanged([], mode: .holdToPaste), .confirm)
    }

    func testCommandReleaseAtDataTypesCancelsIncludingSimultaneousRelease() {
        for flags: CGEventFlags in [.maskShift, []] {
            var session = openedPalette()
            XCTAssertEqual(session.flagsChanged(flags, mode: .holdToPaste), .close)
            XCTAssertNil(session.flagsChanged([], mode: .holdToPaste))
        }
    }

    func testPressingShiftReturnsToDataTypesAndReleasingItConfirmsAgain() {
        var session = openedPalette()
        _ = session.flagsChanged(.maskCommand, mode: .holdToPaste)
        session.show(.profileValues)
        XCTAssertEqual(session.flagsChanged(commandShift, mode: .holdToPaste), .showDataTypes)
        XCTAssertEqual(session.page, .dataTypes)
        XCTAssertEqual(session.flagsChanged(.maskCommand, mode: .holdToPaste), .confirm)
    }

    func testClipboardSwitchesToDataTypesWhileCommandRemainsHeld() {
        var session = DrawerSession()
        _ = session.keyDown(0x28, flags: .maskCommand, isRepeat: false, configuration: .default)
        XCTAssertEqual(session.flagsChanged(commandShift, mode: .holdToPaste), .showDataTypes)
        XCTAssertEqual(session.flagsChanged(.maskCommand, mode: .holdToPaste), .confirm)
    }

    func testToggleModeIgnoresModifierReleasesAndReturnConfirms() {
        var session = openedPalette(mode: .toggle)
        XCTAssertNil(session.flagsChanged(.maskCommand, mode: .toggle))
        XCTAssertNil(session.flagsChanged([], mode: .toggle))
        XCTAssertEqual(session.keyDown(0x24, flags: [], isRepeat: false, configuration: ShortcutConfiguration(interactionMode: .toggle)), .confirm)
    }

    func testSwitchingWithShiftDoesNotImmediatelyToggleClosed() {
        var session = DrawerSession()
        let configuration = ShortcutConfiguration(interactionMode: .toggle)
        _ = session.keyDown(0x26, flags: .maskCommand, isRepeat: false, configuration: configuration)
        XCTAssertEqual(session.flagsChanged(commandShift, mode: .toggle), .showDataTypes)
        XCTAssertEqual(session.keyDown(0x28, flags: commandShift, isRepeat: false, configuration: configuration), .next)
    }

    func testMouseTypeSelectionDisarmsReleaseUntilNextCommandHold() {
        var session = openedPalette()
        session.show(.profileValues, fromMouse: true)
        XCTAssertNil(session.flagsChanged(.maskCommand, mode: .holdToPaste))
        XCTAssertNil(session.flagsChanged([], mode: .holdToPaste))
        XCTAssertNil(session.flagsChanged(.maskCommand, mode: .holdToPaste))
        XCTAssertEqual(session.flagsChanged([], mode: .holdToPaste), .confirm)
    }

    func testEscapeReturnsToDataTypesThenClosesWithoutConfirming() {
        var session = openedPalette()
        session.show(.profileValues)
        XCTAssertEqual(session.keyDown(0x35, flags: commandShift, isRepeat: false, configuration: .default), .showDataTypes)
        XCTAssertFalse(session.releaseArmed)
        XCTAssertEqual(session.keyDown(0x35, flags: commandShift, isRepeat: false, configuration: .default), .close)
    }

    func testNavigationNeverSelectsAndAutoRepeatDoesNotMove() {
        var session = openedPalette()
        XCTAssertEqual(session.keyDown(0x28, flags: commandShift, isRepeat: false, configuration: .default), .next)
        XCTAssertNil(session.keyDown(0x28, flags: commandShift, isRepeat: true, configuration: .default))
        XCTAssertEqual(session.page, .dataTypes)
    }
}

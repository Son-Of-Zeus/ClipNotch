import AppKit
import XCTest
@testable import ClipNotch

final class ScreenUtilitiesTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSingleScreenConvertsQuartzY() {
        XCTAssertEqual(screenIndex(x: 100, y: 100, frames: [primary]), 0)
        XCTAssertNil(screenIndex(x: 100, y: -100, frames: [primary]))
    }

    func testHorizontalScreensPreserveX() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(screenIndex(x: 1500, y: 100, frames: [primary, right]), 1)
        XCTAssertEqual(screenIndex(x: 100, y: 100, frames: [primary, right]), 0)
    }

    func testScreenAbovePrimaryMatchesNegativeQuartzY() {
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(screenIndex(x: 100, y: -100, frames: [primary, above]), 1)
        XCTAssertEqual(screenIndex(x: 100, y: 100, frames: [primary, above]), 0)
    }

    func testScreenBelowPrimaryMatchesQuartzYBeyondPrimaryHeight() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        XCTAssertEqual(screenIndex(x: 100, y: 1000, frames: [primary, below]), 1)
    }

    func testScreenWithNegativeX() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(screenIndex(x: -100, y: 100, frames: [primary, left]), 1)
    }

    func testVerticallyOffsetScreenUsesFirstScreenAsReference() {
        let offset = CGRect(x: 1440, y: 450, width: 1920, height: 1080)
        XCTAssertEqual(screenIndex(x: 1500, y: -500, frames: [primary, offset]), 1)
        XCTAssertNil(screenIndex(x: 1500, y: 500, frames: [primary, offset]))
    }

    func testPointOutsideAllScreensAndEmptyScreensReturnNil() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertNil(screenIndex(x: 4000, y: 100, frames: [primary, right]))
        XCTAssertNil(screenIndex(x: 100, y: 100, frames: []))
    }

    private func screenIndex(x: CGFloat, y: CGFloat, frames: [CGRect]) -> Int? {
        ScreenUtilities.screenIndex(forQuartzPoint: CGPoint(x: x, y: y), screenFrames: frames)
    }
}

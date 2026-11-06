import AppKit
import XCTest
@testable import ClipNotch

final class OnboardingAndPermissionTests: XCTestCase {
    @MainActor
    func testGrantedPermissionDoesNotAdvanceWithoutWorkingShortcuts() {
        let name = "OnboardingTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults)
        progress.advance(hasPermission: true, shortcutsReady: false)
        XCTAssertEqual(progress.step, .permission)
        progress.reconcilePermission(true, shortcutsReady: false)
        XCTAssertEqual(progress.step, .permission)
        progress.reconcilePermission(true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .practice)
        progress.reconcilePermission(true, shortcutsReady: false)
        XCTAssertEqual(progress.step, .permission)
    }

    @MainActor
    func testOnboardingResumesAndSkipsOptionalSteps() {
        let name = "OnboardingTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .practice)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .profiles)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .ready)
        XCTAssertFalse(defaults.bool(forKey: "hasCompletedOnboarding"))
        progress.back(hasPermission: true)
        XCTAssertEqual(progress.step, .profiles)
        progress.move(to: .practice)
        progress.back(hasPermission: true)
        XCTAssertEqual(progress.step, .welcome)
    }

    @MainActor
    func testPermissionIsRequiredAndRevocationReturnsToPermission() {
        let name = "OnboardingTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults)
        progress.advance(hasPermission: false, shortcutsReady: false)
        progress.advance(hasPermission: false, shortcutsReady: false)
        XCTAssertEqual(progress.step, .permission)
        progress.reconcilePermission(true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .practice)
        progress.move(to: .ready)
        progress.reconcilePermission(false, shortcutsReady: false)
        XCTAssertEqual(progress.step, .permission)
        XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .permission)
    }

    func testGuideWaitsForPermissionAndStopsOnGrantCloseCancelAndTimeout() {
        let now = Date()
        var session = PermissionGuideSession()
        session.start(at: now)
        // A visible Settings window or an app drop does not establish trust.
        XCTAssertTrue(session.update(granted: false, settingsVisible: true, at: now.addingTimeInterval(1)))
        XCTAssertFalse(session.update(granted: true, settingsVisible: true, at: now.addingTimeInterval(2)))
        XCTAssertFalse(session.isActive)
        session.start(at: now)
        XCTAssertTrue(session.update(granted: false, settingsVisible: true, at: now))
        XCTAssertFalse(session.update(granted: false, settingsVisible: false, at: now.addingTimeInterval(1)))
        session.start(at: now)
        XCTAssertFalse(session.update(granted: false, settingsVisible: true, at: now.addingTimeInterval(120)))
        session.start(at: now)
        session.stop()
        XCTAssertFalse(session.update(granted: false, settingsVisible: true, at: now))
    }

    func testGuideAllowsSettingsLaunchButStopsIfItNeverOpens() {
        let now = Date()
        var session = PermissionGuideSession()
        session.start(at: now)
        XCTAssertTrue(session.update(granted: false, settingsVisible: false, at: now.addingTimeInterval(5)))
        XCTAssertFalse(session.update(granted: false, settingsVisible: false, at: now.addingTimeInterval(10)))
    }

    func testGuidePillIsCenteredAboveDockOnEachScreen() {
        let screens = [CGRect(x: 0, y: 80, width: 1440, height: 790),
                       CGRect(x: -1920, y: 350, width: 1920, height: 1080),
                       CGRect(x: 0, y: 900, width: 1280, height: 800),
                       CGRect(x: 1440, y: -1000, width: 1280, height: 800)]
        for screen in screens {
            let frame = PermissionGuidePlacement.frame(in: screen)
            XCTAssertTrue(screen.contains(frame), "\(frame) outside \(screen)")
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.minY, screen.minY + 20)
            XCTAssertEqual(frame.size, CGSize(width: 360, height: 76))
        }
    }

    @MainActor
    func testGuideCancellationRemovesPanelAndPollingState() {
        let guide = AccessibilityGuideController()
        guide.cancel()
        XCTAssertFalse(guide.isRunning)
        XCTAssertTrue(guide.message.contains("try again"))
    }
}


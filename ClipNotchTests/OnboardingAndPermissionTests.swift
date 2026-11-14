import AppKit
import XCTest
@testable import ClipNotch

final class OnboardingAndPermissionTests: XCTestCase {
    @MainActor
    func testUnfinishedOnboardingReopensButCompletedOnboardingStaysClosed() {
        let state = AppState()
        let completed = UserDefaults.standard.object(forKey: "hasCompletedOnboarding")
        let step = state.onboarding.step
        defer {
            UserDefaults.standard.set(completed, forKey: "hasCompletedOnboarding")
            state.onboarding.move(to: step)
        }
        let coordinator = AppCoordinator(appState: state)
        let originalWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        state.hasCompletedOnboarding = true
        coordinator.showOnboardingIfNeeded()
        XCTAssertFalse(NSApp.windows.contains { !originalWindows.contains(ObjectIdentifier($0)) && $0.isVisible })

        state.hasCompletedOnboarding = false
        coordinator.showOnboardingIfNeeded()
        let window = NSApp.windows.first { !originalWindows.contains(ObjectIdentifier($0)) && $0.isVisible }
        XCTAssertNotNil(window)
        window?.close()
        coordinator.showOnboardingIfNeeded()
        XCTAssertTrue(NSApp.windows.contains { !originalWindows.contains(ObjectIdentifier($0)) && $0.isVisible })
        coordinator.shutdown()
    }

    @MainActor
    func testReplayedOnboardingRestoresTheSameSettingsWindow() {
        let state = AppState()
        let originalStep = state.onboarding.step
        defer { state.onboarding.move(to: originalStep) }
        let coordinator = AppCoordinator(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 780, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let settingsView = NSView()
        window.contentView = settingsView
        let frame = window.frame
        let style = window.styleMask

        coordinator.showOnboarding(in: window)
        XCTAssertEqual(window.title, "Welcome to ClipNotch")
        XCTAssertFalse(window.contentView === settingsView)
        coordinator.finishOnboarding()
        XCTAssertTrue(window.contentView === settingsView)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(window.styleMask, style)

        coordinator.showOnboarding(in: window)
        window.close()
        XCTAssertTrue(window.contentView === settingsView)
        XCTAssertEqual(window.styleMask, style)
        coordinator.shutdown()
    }

    @MainActor
    func testDrawerLoadsHistoryBeforePresentingAndCancelsPendingOpen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try ClipboardPersistence(baseDirectory: directory)
        let history = ClipboardHistoryStore(persistence: persistence, limits: ClipboardLimits(maxAge: 86_400, maxCount: 10, maxMemoryBytes: 1_048_576, maxDiskBytes: 10_485_760))
        await history.start()
        let entry = ClipboardEntry(summary: ClipboardSummary(
            id: "sample", createdAt: Date(), kind: .text, sourceBundleID: nil, appName: nil,
            displayTitle: nil, preview: "Sample", byteSize: 12, contentHash: "sample"
        ), payload: .text("Sample"))
        await history.insert(entry)
        let state = AppState()
        let panel = PanelManager()
        let coordinator = AppCoordinator(appState: state, history: history, panelManager: panel)
        state.drawer.open(.clipboard)
        coordinator.openDrawer()
        XCTAssertFalse(panel.isOpen)
        let deadline = Date().addingTimeInterval(2)
        while !panel.isOpen && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(panel.isOpen)
        XCTAssertEqual(state.items.map(\.id), ["sample"])
        coordinator.closeDrawer()
        panel.close()
        state.drawer.open(.clipboard)
        coordinator.openDrawer()
        coordinator.closeDrawer()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(panel.isOpen)
        await history.shutdown()
        coordinator.shutdown()
    }

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
        XCTAssertEqual(progress.step, .shortcuts)
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
        XCTAssertEqual(progress.step, .shortcuts)
        XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .shortcuts)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .practice)
        progress.back(hasPermission: true)
        XCTAssertEqual(progress.step, .shortcuts)
        progress.advance(hasPermission: true, shortcutsReady: true)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .profiles)
        progress.advance(hasPermission: true, shortcutsReady: true)
        XCTAssertEqual(progress.step, .ready)
        XCTAssertFalse(defaults.bool(forKey: "hasCompletedOnboarding"))
        progress.back(hasPermission: true)
        XCTAssertEqual(progress.step, .profiles)
        progress.move(to: .shortcuts)
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
        XCTAssertEqual(progress.step, .shortcuts)
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


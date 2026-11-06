import AppKit
import ApplicationServices
import Observation
import SwiftUI

struct PermissionGuideSession {
    private(set) var startedAt: Date?
    private(set) var hasSeenSettings = false

    var isActive: Bool { startedAt != nil }

    mutating func start(at date: Date) {
        startedAt = date
        hasSeenSettings = false
    }

    mutating func update(granted: Bool, settingsVisible: Bool, at date: Date) -> Bool {
        guard let startedAt else { return false }
        hasSeenSettings = hasSeenSettings || settingsVisible
        if granted || date.timeIntervalSince(startedAt) >= 120
            || (!settingsVisible && (hasSeenSettings || date.timeIntervalSince(startedAt) >= 10)) {
            stop()
        }
        return isActive
    }

    mutating func stop() { startedAt = nil }
}

enum PermissionGuidePlacement {
    static let size = CGSize(width: 360, height: 76)

    static func frame(in screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2,
            y: screen.minY + 20,
            width: size.width, height: size.height
        )
    }
}

@Observable
@MainActor
final class AccessibilityGuideController {
    private(set) var isRunning = false
    private(set) var message = "Drag ClipNotch into the Accessibility list, then enable its switch if needed."
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var session = PermissionGuideSession()
    @ObservationIgnored var onGranted: (() -> Void)?

    static var settingsURL: URL {
        let pane = if #available(macOS 26, *) {
            "com.apple.settings.PrivacySecurity.extension"
        } else {
            "com.apple.preference.security"
        }
        return URL(string: "x-apple.systempreferences:\(pane)?Privacy_Accessibility")!
    }

    func start() {
        stop()
        guard !AXIsProcessTrusted() else { onGranted?(); return }
        guard NSWorkspace.shared.open(Self.settingsURL) else {
            message = "Open System Settings → Privacy & Security → Accessibility to add ClipNotch."
            return
        }
        message = "Drag ClipNotch into the Accessibility list, then enable its switch if needed."
        session.start(at: Date())
        isRunning = true
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                guard self.isRunning else { return }
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        session.stop()
        isRunning = false
    }

    func cancel() {
        stop()
        message = "The guide is closed. Choose Enable Accessibility to try again."
    }

    private func refresh() {
        let granted = AXIsProcessTrusted()
        let settings = settingsFrame()
        guard session.update(granted: granted, settingsVisible: settings != nil, at: Date()) else {
            stop()
            if granted { onGranted?() }
            else { message = "The guide has ended. Choose Enable Accessibility to try again." }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences",
              let settings else {
            panel?.orderOut(nil)
            return
        }
        let screen = NSScreen.screens.max {
            $0.frame.intersection(settings).area < $1.frame.intersection(settings).area
        }
        guard let screen else { return }
        let frame = PermissionGuidePlacement.frame(in: screen.visibleFrame)
        if panel == nil {
            let panel = PermissionGuidePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: PermissionGuideView(onCancel: { [weak self] in self?.cancel() }))
            self.panel = panel
        }
        guard let panel else { return }
        if !panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame.offsetBy(dx: 0, dy: -12), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func settingsFrame() -> CGRect? {
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? Int32) == settings.processIdentifier
                      && ($0[kCGWindowLayer as String] as? Int) == 0
              }),
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"] else { return nil }
        let topLeft = ScreenUtilities.appKitPoint(fromQuartzPoint: CGPoint(x: x, y: y))
        return CGRect(x: x, y: topLeft.y - height, width: width, height: height)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private final class PermissionGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct AccessibilityManualInstructions: View {
    var body: some View {
        DisclosureGroup("Use the keyboard instead") {
            VStack(alignment: .leading, spacing: 9) {
                Text("In Accessibility, choose +. In the file picker, press Shift–Command–G and enter the app path below. Select the app, then enable its switch.")
                Text(Bundle.main.bundlePath).textSelection(.enabled).font(.system(size: 11, design: .monospaced))
                Button("Open Accessibility Settings") { NSWorkspace.shared.open(AccessibilityGuideController.settingsURL) }
            }
            .font(ClipNotchTypography.callout)
            .buttonStyle(ClipNotchButtonStyle())
            .padding(.top, 8)
        }
    }
}

private struct PermissionGuideView: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppBundleDragView().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drag into Accessibility")
                    .font(ClipNotchTypography.label)
                Text("Then turn on ClipNotch.")
                    .font(ClipNotchTypography.caption)
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up")
                .foregroundStyle(ClipNotchDesign.accent)
                .accessibilityHidden(true)
            Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(ClipNotchButtonStyle(.icon))
                .accessibilityLabel("Close permission guide")
        }
        .padding(.horizontal, 18)
        .frame(width: PermissionGuidePlacement.size.width, height: PermissionGuidePlacement.size.height)
        .background { ClipNotchWindowSurface().clipShape(Capsule()) }
        .overlay(Capsule().stroke(ClipNotchDesign.separator))
    }
}

private struct AppBundleDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> AppBundleDragSource { AppBundleDragSource() }
    func updateNSView(_ nsView: AppBundleDragSource, context: Context) {}
}

private final class AppBundleDragSource: NSImageView, NSDraggingSource, NSPasteboardItemDataProvider {
    init() {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityLabel("ClipNotch app. Drag into the Accessibility list.")
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.fileURL])
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(Bundle.main.bundleURL.absoluteString, forType: type)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

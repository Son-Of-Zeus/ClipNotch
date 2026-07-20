import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct ClipNotchSettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: PreferencesSection = .storage
    @State private var recorder: RecorderTarget?

    private let panelWidth: CGFloat = 320
    private let sidebarWidth: CGFloat = 156
    private let panelHeight: CGFloat = 440

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentPanel
        }
        .frame(width: sidebarWidth + panelWidth, height: panelHeight)
        .background(ClipNotchDesign.surface)
        .background(PreferencesWindowSizing(width: sidebarWidth + panelWidth, height: panelHeight))
        .onAppear { appState.hasAccessibilityPermission = AXIsProcessTrusted() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ClipNotch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClipNotchDesign.onSurface)
                Text("v\(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(ClipNotchDesign.onSurfaceVariant)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(PreferencesSection.allCases, id: \.self) { item in
                    sidebarItem(item)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
            Text("Local only · no network")
                .font(.system(size: 10))
                .foregroundStyle(ClipNotchDesign.onSurfaceVariant.opacity(0.7))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    ClipNotchDesign.outlineVariant.opacity(0.35).frame(height: 1)
                }
        }
        .frame(width: sidebarWidth)
        .background(ClipNotchDesign.surfaceDim)
        .overlay(alignment: .trailing) { ClipNotchDesign.outlineVariant.opacity(0.35).frame(width: 1) }
    }

    private func sidebarItem(_ item: PreferencesSection) -> some View {
        Button {
            withAnimation(sectionAnimation) { section = item }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon).font(.system(size: 13)).frame(width: 18)
                Text(item.title).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(section == item ? ClipNotchDesign.surfaceContainer : .clear)
            }
            .foregroundStyle(section == item ? ClipNotchDesign.primary : ClipNotchDesign.onSurfaceVariant)
        }
        .buttonStyle(.plain)
    }

    private var contentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClipNotchDesign.paperText)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { ClipNotchDesign.paperTextMuted.opacity(0.12).frame(height: 1).offset(y: 6) }

                sectionContent
                    .id(section)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: panelWidth)
        .background(ClipNotchDesign.paper)
        .animation(sectionAnimation, value: section)
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .general: generalContent
        case .storage: storageContent
        case .shortcuts: shortcutsContent
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            toggleRow(title: "Open at login", isOn: launchAtLoginBinding).tint(ClipNotchDesign.primaryContainer)
            Divider().overlay(ClipNotchDesign.paperTextMuted.opacity(0.14))
            accessibilityStatus
        }
    }

    private var accessibilityStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(appState.hasAccessibilityPermission ? ClipNotchDesign.secondaryContainer : Color.orange).frame(width: 7, height: 7)
                Text(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClipNotchDesign.paperText)
            }
            Text(appState.hasAccessibilityPermission
                 ? "Global shortcuts are ready."
                 : "Grant access for global shortcuts and hold-to-paste.")
                .font(.system(size: 11))
                .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.75))
            if !appState.hasAccessibilityPermission {
                Button("Open System Settings…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    private var storageContent: some View {
        VStack(spacing: 12) {
            stepperRow(title: "Keep items for", value: retentionDays, range: 1...90, step: 1, suffix: "d") {
                appState.retentionHours = Double($0 * 24)
            }
            ClipNotchDesign.paperTextMuted.opacity(0.12).frame(height: 1)
            stepperRow(title: "Max items", value: appState.maxItemCount, range: 10...10_000, step: 10) { appState.maxItemCount = $0 }
            stepperRow(title: "Max disk", value: appState.maxDiskMB, range: 50...5000, step: 50, suffix: " MB") { appState.maxDiskMB = $0 }
        }
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutRow(title: "Open drawer", subtitle: "Global shortcut", target: .openDrawer, keys: appState.shortcutConfiguration.openDrawer.displayKeys)
            shortcutRow(title: "Previous item", subtitle: "While drawer is open", target: .previousItem, keys: appState.shortcutConfiguration.previousItem.displayKeys)
            shortcutRow(title: "Next item", subtitle: "While drawer is open", target: .nextItem, keys: appState.shortcutConfiguration.nextItem.displayKeys)

            if appState.shortcutConfiguration.hasDuplicateNavigationKeys {
                Label("Previous and next must use different keys.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            Divider().overlay(ClipNotchDesign.paperTextMuted.opacity(0.14))

            VStack(alignment: .leading, spacing: 7) {
                Text("Interaction").font(.system(size: 12, weight: .medium)).foregroundStyle(ClipNotchDesign.paperText)
                interactionModePicker
                Text(interactionHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("The global shortcut is exclusive to ClipNotch.")
                    .font(.system(size: 10))
                    .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.65))
                Spacer()
                Button("Reset") { updateConfiguration(.default) }
                    .foregroundStyle(ClipNotchDesign.paperText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ClipNotchDesign.primaryContainer.opacity(0.45))
                    )
                    .buttonStyle(.plain)
            }
        }
    }

    private func shortcutRow(title: String, subtitle: String, target: RecorderTarget, keys: [String]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(ClipNotchDesign.paperText)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.65))
            }
            Spacer(minLength: 8)
            ShortcutRecorder(
                isRecording: Binding(
                    get: { recorder == target },
                    set: { isRecording in recorder = isRecording ? target : nil }
                ),
                keys: keys,
                captureGlobalShortcut: target == .openDrawer,
                onCapture: { keyCode, modifiers in capture(keyCode: keyCode, modifiers: modifiers, for: target) },
                onCancel: { recorder = nil }
            )
            .frame(width: 108, height: 28)
        }
    }

    private var interactionModeBinding: Binding<DrawerInteractionMode> {
        Binding(get: { appState.shortcutConfiguration.interactionMode }, set: { mode in
            var configuration = appState.shortcutConfiguration
            configuration.interactionMode = mode
            updateConfiguration(configuration)
        })
    }

    private var interactionModePicker: some View {
        HStack(spacing: 4) {
            ForEach(DrawerInteractionMode.allCases, id: \.self) { mode in
                let isSelected = appState.shortcutConfiguration.interactionMode == mode
                Button {
                    interactionModeBinding.wrappedValue = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ClipNotchDesign.paperText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? ClipNotchDesign.primaryContainer.opacity(0.72) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClipNotchDesign.paperTextMuted.opacity(0.2), lineWidth: 1))
    }

    private var interactionHint: String {
        switch appState.shortcutConfiguration.interactionMode {
        case .holdToPaste: "Hold the opener, use navigation keys, then release all opener modifiers to paste."
        case .toggle: "Press the opener to show or hide the drawer. Use Return to paste and Escape to dismiss."
        }
    }

    private var retentionDays: Int { max(1, Int(appState.retentionHours / 24)) }
    private var sectionAnimation: Animation { reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.28, bounce: 0.08) }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { appState.launchAtLogin }, set: { newValue in
            appState.launchAtLogin = newValue
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { appState.launchAtLogin = !newValue }
        })
    }

    private func capture(keyCode: UInt16, modifiers: ShortcutModifiers, for target: RecorderTarget) {
        var configuration = appState.shortcutConfiguration
        switch target {
        case .openDrawer:
            guard !modifiers.isEmpty else { return }
            configuration.openDrawer = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
        case .previousItem:
            guard keyCode != configuration.nextItem.keyCode else { return }
            configuration.previousItem = NavigationShortcut(keyCode: keyCode)
        case .nextItem:
            guard keyCode != configuration.previousItem.keyCode else { return }
            configuration.nextItem = NavigationShortcut(keyCode: keyCode)
        }
        recorder = nil
        updateConfiguration(configuration)
    }

    private func updateConfiguration(_ configuration: ShortcutConfiguration) {
        withAnimation(sectionAnimation) { appState.shortcutConfiguration = configuration }
        AppBootstrap.shared.coordinator?.applyShortcutConfiguration(configuration)
    }

    private func stepperRow(title: String, value: Int, range: ClosedRange<Int>, step: Int, suffix: String = "", onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(ClipNotchDesign.paperText)
            Spacer(minLength: 8)
            CompactStepper(value: value, range: range, step: step, suffix: suffix, onChange: onChange)
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(ClipNotchDesign.paperText)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }
}

private enum PreferencesSection: CaseIterable { case general, storage, shortcuts
    var title: String { switch self { case .general: "General"; case .storage: "Storage"; case .shortcuts: "Shortcuts" } }
    var icon: String { switch self { case .general: "gearshape"; case .storage: "internaldrive"; case .shortcuts: "keyboard" } }
}

private enum RecorderTarget: Hashable { case openDrawer, previousItem, nextItem }

private struct ShortcutBadge: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ClipNotchDesign.shortcutBg)).foregroundStyle(.white)
            }
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var isRecording: Bool
    let keys: [String]
    let captureGlobalShortcut: Bool
    let onCapture: (UInt16, ShortcutModifiers) -> Void
    let onCancel: () -> Void
    @State private var monitor = ShortcutCaptureMonitor()

    var body: some View {
        Button {
            beginRecording()
        } label: {
            ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isRecording ? ClipNotchDesign.primary.opacity(0.22) : Color.white.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isRecording ? ClipNotchDesign.primary : ClipNotchDesign.paperTextMuted.opacity(0.18), lineWidth: isRecording ? 1.5 : 1))
            if isRecording {
                Text(captureGlobalShortcut ? "Press shortcut" : "Press key")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(ClipNotchDesign.paperText)
            } else {
                ShortcutBadge(keys: keys)
            }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Record shortcut")
        .onChange(of: isRecording) { _, recording in
            if !recording { monitor.stop() }
        }
        .onDisappear { monitor.stop() }
    }

    private func beginRecording() {
        isRecording = true
        monitor.start(
            onCapture: { keyCode, modifiers in
                isRecording = false
                onCapture(keyCode, modifiers)
            },
            onCancel: {
                isRecording = false
                onCancel()
            }
        )
    }
}

@MainActor
private final class ShortcutCaptureMonitor {
    private var eventMonitor: Any?

    func start(
        onCapture: @escaping (UInt16, ShortcutModifiers) -> Void,
        onCancel: @escaping () -> Void
    ) {
        stop()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !event.isARepeat else { return nil }
            self.stop()
            if event.keyCode == 0x35 {
                onCancel()
            } else {
                onCapture(event.keyCode, ShortcutModifiers(eventFlags: event.modifierFlags))
            }
            return nil
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}

private struct CompactStepper: View {
    let value: Int; let range: ClosedRange<Int>; let step: Int; var suffix: String = ""; let onChange: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value - step >= range.lowerBound) { onChange(max(value - step, range.lowerBound)) }
            Text("\(value)\(suffix)").font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(ClipNotchDesign.paperTextMuted).frame(minWidth: 44).padding(.horizontal, 4)
                .overlay(alignment: .leading) { ClipNotchDesign.paperTextMuted.opacity(0.15).frame(width: 1) }.overlay(alignment: .trailing) { ClipNotchDesign.paperTextMuted.opacity(0.15).frame(width: 1) }
            button("plus", enabled: value + step <= range.upperBound) { onChange(min(value + step, range.upperBound)) }
        }.padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.5))).overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ClipNotchDesign.paperTextMuted.opacity(0.2), lineWidth: 1))
    }
    private func button(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemName).font(.system(size: 9, weight: .bold)).frame(width: 22, height: 20).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(enabled ? ClipNotchDesign.paperTextMuted : ClipNotchDesign.paperTextMuted.opacity(0.35)).disabled(!enabled)
    }
}

private struct PreferencesWindowSizing: NSViewRepresentable {
    let width: CGFloat; let height: CGFloat
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { apply(to: view) }; return view }
    func updateNSView(_ nsView: NSView, context: Context) { DispatchQueue.main.async { apply(to: nsView) } }
    private func apply(to view: NSView) { guard let window = view.window else { return }; let size = NSSize(width: width, height: height); window.title = "ClipNotch"; window.setContentSize(size); window.minSize = size; window.maxSize = size }
}

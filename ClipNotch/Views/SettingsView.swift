import AppKit
import ApplicationServices
import SwiftUI

struct ClipNotchSettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: PreferencesSection = .general

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            ClipNotchWindowHeader(detail: "", canMinimize: true, canResize: true)
            Divider().overlay(ClipNotchDesign.accent.opacity(0.1))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SETTINGS")
                        .font(ClipNotchTypography.captionLabel)
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    ForEach(PreferencesSection.allCases) { item in
                        Button { section = item } label: {
                            Label(item.title, systemImage: item.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(ClipNotchButtonStyle(section == item ? .secondary : .quiet))
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                    Spacer()
                    Text("Version \(appVersion)")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                        .padding(.horizontal, 14)
                }
                .padding(14)
                .padding(.vertical, 14)
                .frame(width: 180)
                .background(ClipNotchDesign.accent.opacity(0.035))
                detailContent
            }
        }
        .buttonStyle(ClipNotchButtonStyle())
        .background(ClipNotchWindowSurface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .font(ClipNotchTypography.body)
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            AppBootstrap.shared.coordinator?.refreshAccessibilityAndEventTap()
            showRequestedSection()
        }
        .onChange(of: appState.showsDataPalettePreferences) { _, _ in showRequestedSection() }
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: section)
    }

    @ViewBuilder private var detailContent: some View {
        let visibleSection = section
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AccentIcon(symbol: visibleSection.icon)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(visibleSection.title).font(.system(size: 26, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(visibleSection.subtitle).font(ClipNotchTypography.body).foregroundStyle(ClipNotchDesign.secondaryLabel)
                    }
                }
                .padding(.bottom, 8)
                sectionContent(for: visibleSection)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(visibleSection)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder private func sectionContent(for section: PreferencesSection) -> some View {
        switch section {
            case .general: generalContent
            case .storage: storageContent
            case .shortcuts: ShortcutSettingsView(appState: appState)
            case .dataPalette: DataPaletteSettingsView(store: appState.dataPalette)
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Startup").font(ClipNotchTypography.heading)
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: launchAtLoginBinding) {
                        Text("Open at login").frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch)
                    Text("Keep your clipboard close, from the moment you start your Mac.")
                        .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                    if let error = appState.loginError {
                        Text(error).font(ClipNotchTypography.caption).foregroundStyle(.red)
                    }
                }
            }
            Text("Browser autofill").font(ClipNotchTypography.heading)
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                            get: { appState.autofillSettings.isEnabled },
                            set: {
                                appState.autofillSettings.isEnabled = $0
                                AppBootstrap.shared.coordinator?.refreshAutofill()
                            }
                    )) {
                        Text("Suggest autofill in Chrome and Safari").frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch)
                    Text("Matches form labels on this Mac. Always asks before filling saved details.")
                        .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                    if !appState.autofillSettings.excludedHosts.isEmpty {
                        Divider()
                        Text("Excluded sites").font(ClipNotchTypography.label)
                        ForEach(appState.autofillSettings.excludedHosts, id: \.self) { host in
                            HStack {
                                Text(host).font(ClipNotchTypography.callout)
                                Spacer()
                                Button("Allow") {
                                    appState.autofillSettings.allow(host)
                                    AppBootstrap.shared.coordinator?.refreshAutofill()
                                }
                            }
                        }
                    }
                }
            }
            Text("Getting started").font(ClipNotchTypography.heading)
            SettingsCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A quick tour of ClipNotch").font(ClipNotchTypography.label)
                        Text("Revisit shortcuts, saved details, and setup.")
                            .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                    }
                    Spacer(minLength: 0)
                    Button("Show onboarding…") { AppBootstrap.shared.showOnboarding() }
                }
            }
            Text("Accessibility").font(ClipNotchTypography.heading)
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: appState.hasAccessibilityPermission ? "checkmark.shield.fill" : "lock.shield")
                        .font(.system(size: 24))
                        .foregroundStyle(appState.hasAccessibilityPermission ? Color(nsColor: .systemGreen) : ClipNotchDesign.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.areShortcutsReady ? "You're all set" : appState.hasAccessibilityPermission ? "Shortcuts are not ready" : "Enable shortcuts and pasting")
                            .font(ClipNotchTypography.label)
                        Text(appState.areShortcutsReady
                            ? "Global shortcuts, paste delivery, and browser autofill have access."
                            : appState.hasAccessibilityPermission ? "Accessibility is enabled, but shortcuts could not start. Retry, or quit and reopen ClipNotch."
                            : "ClipNotch needs access to respond to shortcuts and paste into your apps.")
                            .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                        if !appState.areShortcutsReady {
                            Button(appState.hasAccessibilityPermission ? "Retry shortcuts" : "Enable Accessibility…") {
                                if appState.hasAccessibilityPermission {
                                    AppBootstrap.shared.coordinator?.refreshAccessibilityAndEventTap()
                                } else { openAccessibilitySettings() }
                            }
                                .buttonStyle(ClipNotchButtonStyle(.primary))
                            if let guide = AppBootstrap.shared.coordinator?.accessibilityGuide {
                                Text(guide.message).font(ClipNotchTypography.caption)
                                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                                if guide.isRunning {
                                    Button("Close guide") { guide.cancel() }
                                }
                            }
                            if !appState.hasAccessibilityPermission { AccessibilityManualInstructions() }
                        }
                    }
                }
            }
        }
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clipboard history").font(ClipNotchTypography.heading)
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    limitControl(title: "Keep items for", value: retentionDays, range: 1...90, step: 1, suffix: " days") {
                        appState.retentionHours = Double($0 * 24)
                        applyStorageConfiguration()
                    }
                    Divider()
                    limitControl(title: "Maximum items", value: appState.maxItemCount, range: 10...10_000, step: 10) {
                        appState.maxItemCount = $0
                        applyStorageConfiguration()
                    }
                }
            }
            Text("Resource limits").font(ClipNotchTypography.heading)
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    limitControl(title: "Maximum memory usage", value: appState.maxMemoryMB, range: 64...512, step: 64, suffix: " MB") {
                        appState.maxMemoryMB = $0
                        applyStorageConfiguration()
                    }
                    Divider()
                    limitControl(title: "Maximum disk usage", value: appState.maxDiskMB, range: 50...5_000, step: 50, suffix: " MB") {
                        appState.maxDiskMB = $0
                        applyStorageConfiguration()
                    }
                }
            }
        }
    }

    private var retentionDays: Int { max(1, Int(appState.retentionHours / 24)) }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) })
    }

    private func limitControl(title: String, value: Int, range: ClosedRange<Int>, step: Int, suffix: String = "", onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(ClipNotchTypography.label)
            Spacer(minLength: 8)
            Button { onChange(max(range.lowerBound, value - step)) } label: { Image(systemName: "minus") }
                .buttonStyle(ClipNotchButtonStyle(.icon))
                .disabled(value <= range.lowerBound)
                .accessibilityLabel("Decrease \(title.lowercased())")
            Text("\(value)\(suffix)")
                .font(ClipNotchTypography.label).monospacedDigit()
                .frame(minWidth: 64)
                .accessibilityLabel("\(title): \(value)\(suffix)")
            Button { onChange(min(range.upperBound, value + step)) } label: { Image(systemName: "plus") }
                .buttonStyle(ClipNotchButtonStyle(.icon))
                .disabled(value >= range.upperBound)
                .accessibilityLabel("Increase \(title.lowercased())")
        }
    }

    private func showRequestedSection() {
        guard appState.showsDataPalettePreferences else { return }
        section = .dataPalette
        appState.showsDataPalettePreferences = false
    }

    private func applyStorageConfiguration() {
        AppBootstrap.shared.coordinator?.applyStorageConfiguration()
    }

    private func openAccessibilitySettings() {
        AppBootstrap.shared.coordinator?.accessibilityGuide.start()
    }
}

struct ShortcutSettingsView: View {
    @Bindable var appState: AppState
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorder: RecorderTarget?
    @State private var shortcutError: String?

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                shortcutRow(title: "Previous item", subtitle: "While the drawer is open", target: .previousItem, keys: appState.shortcutConfiguration.previousItem.displayKeys)
                shortcutRow(title: "Next item", subtitle: "While the drawer is open", target: .nextItem, keys: appState.shortcutConfiguration.nextItem.displayKeys)

                if let shortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Clipboard: \(shortcutPair(palette: false))")
                    Text("Data Palette: \(shortcutPair(palette: true))")
                    Text("Command is fixed. Shift opens Data Palette.")
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                }
                .font(ClipNotchTypography.caption)

                if !compact { Divider() }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Interaction").font(ClipNotchTypography.label)
                    HStack(spacing: 4) {
                        ForEach(DrawerInteractionMode.allCases, id: \.self) { mode in
                            Button { interactionModeBinding.wrappedValue = mode } label: {
                                Text(mode.title).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ClipNotchButtonStyle(appState.shortcutConfiguration.interactionMode == mode ? .secondary : .quiet))
                            .accessibilityAddTraits(appState.shortcutConfiguration.interactionMode == mode ? .isSelected : [])
                        }
                    }
                    .padding(4)
                    .background(ClipNotchDesign.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    if !compact {
                        Text(interactionHint)
                            .font(ClipNotchTypography.caption)
                            .foregroundStyle(ClipNotchDesign.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    if !compact {
                        Text("The global shortcut is exclusive to ClipNotch.")
                            .font(ClipNotchTypography.footnote)
                            .foregroundStyle(ClipNotchDesign.tertiaryLabel)
                    }
                    Spacer()
                    Button("Restore Defaults") { updateConfiguration(.default) }
                        .controlSize(.small)
                }
            }
        }
        .onChange(of: recorder) { _, target in appState.isRecordingShortcut = target != nil }
        .onDisappear { appState.isRecordingShortcut = false }
    }

    private func shortcutRow(title: String, subtitle: String, target: RecorderTarget, keys: [String]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ClipNotchTypography.label)
                Text(subtitle).font(ClipNotchTypography.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
            Spacer(minLength: 12)
            ShortcutRecorder(
                isRecording: Binding(
                    get: { recorder == target },
                    set: { recorder = $0 ? target : nil }
                ),
                keys: keys,
                onCapture: { keyCode in capture(keyCode: keyCode, for: target) },
                onCancel: { recorder = nil }
            )
                .frame(width: 128, height: 28)
        }
    }

    private var interactionModeBinding: Binding<DrawerInteractionMode> {
        Binding(get: { appState.shortcutConfiguration.interactionMode }, set: { mode in
                var configuration = appState.shortcutConfiguration
                configuration.interactionMode = mode
                updateConfiguration(configuration)
        })
    }

    private var interactionHint: String {
        switch appState.shortcutConfiguration.interactionMode {
            case .holdToPaste: "Hold Command and use the navigation keys. For Data Palette, also hold Shift: release Shift to choose a data type, then choose a profile and release Command to paste its value."
            case .toggle: "Press a shortcut to open or close its tab. Use navigation keys to choose a data type, then a profile. Press Return to confirm and Escape to go back or dismiss."
        }
    }

    private func shortcutPair(palette: Bool) -> String {
        let configuration = appState.shortcutConfiguration
        return [configuration.previousItem, configuration.nextItem]
            .map { configuration.displayKeys(for: $0, palette: palette).joined() }
            .joined(separator: " or ")
    }

    private func capture(keyCode: UInt16, for target: RecorderTarget) {
        let shortcut = NavigationShortcut(keyCode: keyCode)
        guard shortcut.isValid else {
            shortcutError = "Choose a key other than Return, Tab, Escape, or a modifier."
            recorder = nil
            return
        }
        var configuration = appState.shortcutConfiguration
        switch target {
            case .previousItem: configuration.previousItem = shortcut
            case .nextItem: configuration.nextItem = shortcut
        }
        recorder = nil
        guard configuration.isValid else {
            shortcutError = "Previous and next must use different keys."
            return
        }
        shortcutError = nil
        updateConfiguration(configuration)
    }

    private func updateConfiguration(_ configuration: ShortcutConfiguration) {
        withAnimation(ClipNotchMotion.emphasis(reduceMotion: reduceMotion)) {
            appState.shortcutConfiguration = configuration
        }
        AppBootstrap.shared.coordinator?.shortcutConfigurationDidChange()
    }

}

private enum PreferencesSection: CaseIterable, Identifiable {
    case general, storage, shortcuts, dataPalette

    var id: Self { self }
    var title: String { switch self { case .general: "General"; case .storage: "Storage"; case .shortcuts: "Shortcuts"; case .dataPalette: "Data Palette" } }
    var subtitle: String {
        switch self {
            case .general: "Startup and permissions"
            case .storage: "Retention and storage limits"
            case .shortcuts: "Drawer shortcuts and interaction"
            case .dataPalette: "Saved values for your forms"
        }
    }
    var icon: String { switch self { case .general: "gear"; case .storage: "internaldrive"; case .shortcuts: "keyboard"; case .dataPalette: "person.crop.rectangle" } }
}

private enum RecorderTarget: Hashable { case previousItem, nextItem }

struct ShortcutBadge: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(ClipNotchTypography.shortcut)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(ClipNotchDesign.label)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ClipNotchDesign.groupedBackground))
            }
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var isRecording: Bool
    let keys: [String]
    let onCapture: (UInt16) -> Void
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitor = ShortcutCaptureMonitor()

    var body: some View {
        Button { beginRecording() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? ClipNotchDesign.accentSurface : ClipNotchDesign.controlBackground)
                    .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isRecording ? ClipNotchDesign.accent : ClipNotchDesign.separator, lineWidth: 1)
                )
                if isRecording {
                    Text("Press key")
                        .font(ClipNotchTypography.captionLabel)
                        .foregroundStyle(ClipNotchDesign.label)
                } else {
                    ShortcutBadge(keys: keys)
                }
            }
            .scaleEffect(isRecording && !reduceMotion ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Record shortcut")
        .animation(ClipNotchMotion.emphasis(reduceMotion: reduceMotion), value: isRecording)
        .onChange(of: isRecording) { _, recording in if !recording { monitor.stop() } }
        .onDisappear { monitor.stop() }
    }

    private func beginRecording() {
        isRecording = true
        monitor.start(
            onCapture: { keyCode in
                isRecording = false
                onCapture(keyCode)
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

    func start(onCapture: @escaping (UInt16) -> Void, onCancel: @escaping () -> Void) {
        stop()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !event.isARepeat else { return nil }
            self.stop()
            if event.keyCode == 0x35 { onCancel() }
            else { onCapture(event.keyCode) }
            return nil
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}

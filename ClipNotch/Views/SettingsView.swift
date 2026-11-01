import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct ClipNotchSettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: PreferencesSection? = .general
    @State private var recorder: RecorderTarget?
    @State private var shortcutError: String?

    private let windowWidth: CGFloat = 640
    private let windowHeight: CGFloat = 472

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section {
                    ForEach(PreferencesSection.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ClipNotch").font(.headline)
                        Text("Version \(appVersion)").font(.caption2).foregroundStyle(ClipNotchDesign.secondaryLabel)
                    }
                    .textCase(nil)
                    .padding(.bottom, 8)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(ClipNotchDesign.groupedBackground)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: windowWidth, height: windowHeight)
        .background(PreferencesWindowSizing(width: windowWidth, height: windowHeight))
        .onAppear {
            appState.hasAccessibilityPermission = AXIsProcessTrusted()
            showRequestedSection()
        }
        .onChange(of: appState.showsDataPalettePreferences) { _, _ in showRequestedSection() }
        .onChange(of: recorder) { _, target in appState.isRecordingShortcut = target != nil }
        .onDisappear { appState.isRecordingShortcut = false }
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: section)
    }

    @ViewBuilder private var detailContent: some View {
        let visibleSection = section ?? .general
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(visibleSection.title).font(.title2.weight(.semibold))
                    Text(visibleSection.subtitle).font(.subheadline).foregroundStyle(ClipNotchDesign.secondaryLabel)
                }

                GroupBox {
                    sectionContent(for: visibleSection)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .groupBoxStyle(SettingsGroupBoxStyle())
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(visibleSection)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
        .background(ClipNotchDesign.windowBackground)
    }

    @ViewBuilder private func sectionContent(for section: PreferencesSection) -> some View {
        switch section {
        case .general: generalContent
        case .storage: storageContent
        case .shortcuts: shortcutsContent
        case .dataPalette: DataPaletteSettingsView(store: appState.dataPalette)
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Open at login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)

            Toggle("Show onboarding on every launch", isOn: $appState.showOnboardingOnLaunch)
                .toggleStyle(.switch)

            Text("Developer option: reopens the onboarding screen each time ClipNotch starts.")
                .font(.caption)
                .foregroundStyle(ClipNotchDesign.secondaryLabel)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility required")
                } icon: {
                    Image(systemName: appState.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.hasAccessibilityPermission ? .green : .orange)
                }
                .font(.subheadline.weight(.medium))

                Text(appState.hasAccessibilityPermission
                     ? "Global shortcuts are ready to use."
                     : "Grant access for global shortcuts and hold-to-paste.")
                    .font(.caption)
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)

                if !appState.hasAccessibilityPermission {
                    Button("Open System Settings…") { openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            nativeStepper(title: "Keep items for", value: retentionDays, range: 1...90, step: 1, suffix: " days") {
                appState.retentionHours = Double($0 * 24)
                applyStorageConfiguration()
            }
            Divider()
            nativeStepper(title: "Maximum items", value: appState.maxItemCount, range: 10...10_000, step: 10) {
                appState.maxItemCount = $0
                applyStorageConfiguration()
            }
            Divider()
            nativeStepper(title: "Maximum memory usage", value: appState.maxMemoryMB, range: 64...512, step: 64, suffix: " MB") {
                appState.maxMemoryMB = $0
                applyStorageConfiguration()
            }
            Divider()
            nativeStepper(title: "Maximum disk usage", value: appState.maxDiskMB, range: 50...5_000, step: 50, suffix: " MB") {
                appState.maxDiskMB = $0
                applyStorageConfiguration()
            }
        }
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            shortcutRow(title: "Previous item", subtitle: "While the drawer is open", target: .previousItem, keys: appState.shortcutConfiguration.previousItem.displayKeys)
            shortcutRow(title: "Next item", subtitle: "While the drawer is open", target: .nextItem, keys: appState.shortcutConfiguration.nextItem.displayKeys)

            if let shortcutError {
                Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Clipboard: \(shortcutPair(palette: false))")
                Text("Data Palette: \(shortcutPair(palette: true))")
                Text("Command is fixed. Shift opens Data Palette.")
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
            .font(.caption)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Interaction").font(.subheadline.weight(.medium))
                GraphiteModePicker(selection: interactionModeBinding, reduceMotion: reduceMotion)
                Text(interactionHint)
                    .font(.caption)
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("The global shortcut is exclusive to ClipNotch.")
                    .font(.caption2)
                    .foregroundStyle(ClipNotchDesign.tertiaryLabel)
                Spacer()
                Button("Restore Defaults") { updateConfiguration(.default) }
                    .controlSize(.small)
            }
        }
    }

    private func shortcutRow(title: String, subtitle: String, target: RecorderTarget, keys: [String]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
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
        case .holdToPaste: "Hold Command and use the navigation keys. For Data Palette, also hold Shift: release Shift to choose a profile, then release Command to paste a value."
        case .toggle: "Press a shortcut to open or close its tab. Use navigation keys to choose, Return to open a profile or paste, and Escape to go back or dismiss."
        }
    }

    private var retentionDays: Int { max(1, Int(appState.retentionHours / 24)) }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { appState.launchAtLogin }, set: { newValue in
            appState.launchAtLogin = newValue
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                appState.launchAtLogin = !newValue
            }
        })
    }

    private func nativeStepper(title: String, value: Int, range: ClosedRange<Int>, step: Int, suffix: String = "", onChange: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: onChange), in: range, step: step) {
            LabeledContent(title) {
                Text("\(value)\(suffix)")
                    .monospacedDigit()
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        }
    }

    private func showRequestedSection() {
        guard appState.showsDataPalettePreferences else { return }
        section = .dataPalette
        appState.showsDataPalettePreferences = false
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

    private func applyStorageConfiguration() {
        AppBootstrap.shared.coordinator?.applyStorageConfiguration()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
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

private struct SettingsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ClipNotchDesign.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ClipNotchDesign.separator.opacity(0.65), lineWidth: 1)
            )
    }
}

private struct GraphiteModePicker: View {
    @Binding var selection: DrawerInteractionMode
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DrawerInteractionMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(ClipNotchMotion.standard(reduceMotion: reduceMotion)) { selection = mode }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ClipNotchDesign.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == mode ? ClipNotchDesign.graphiteSelectionStrong : .clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ClipNotchDesign.groupedBackground))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ClipNotchDesign.separator, lineWidth: 1))
    }
}

private struct ShortcutBadge: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                    .fill(isRecording ? ClipNotchDesign.graphiteSelectionStrong : ClipNotchDesign.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isRecording ? ClipNotchDesign.label.opacity(0.45) : ClipNotchDesign.separator, lineWidth: 1)
                    )
                if isRecording {
                    Text("Press key")
                        .font(.caption.weight(.medium))
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

private struct PreferencesWindowSizing: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        let size = NSSize(width: width, height: height)
        window.title = "ClipNotch"
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
    }
}

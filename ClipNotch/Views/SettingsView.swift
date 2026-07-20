import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Root view

struct ClipNotchSettingsView: View {
    @Bindable var appState: AppState
    @State private var section: PreferencesSection = .storage

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private let panelWidth: CGFloat = 300
    private let sidebarWidth: CGFloat = 156
    private let panelHeight: CGFloat = 360

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentPanel
        }
        .frame(width: sidebarWidth + panelWidth, height: panelHeight)
        .background(ClipNotchDesign.surface)
        .background(PreferencesWindowSizing(
            width: sidebarWidth + panelWidth,
            height: panelHeight
        ))
        .onAppear {
            appState.hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    // MARK: Sidebar

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
        .overlay(alignment: .trailing) {
            ClipNotchDesign.outlineVariant.opacity(0.35).frame(width: 1)
        }
    }

    private func sidebarItem(_ item: PreferencesSection) -> some View {
        Button {
            section = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                if section == item {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ClipNotchDesign.surfaceContainer)
                }
            }
            .foregroundStyle(section == item ? ClipNotchDesign.primary : ClipNotchDesign.onSurfaceVariant)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content panel

    private var contentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClipNotchDesign.paperText)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        ClipNotchDesign.paperTextMuted.opacity(0.12).frame(height: 1).offset(y: 6)
                    }

                switch section {
                case .general:
                    generalContent
                case .storage:
                    storageContent
                case .shortcuts:
                    shortcutsContent
                case .privacy:
                    privacyContent
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: panelWidth)
        .background(ClipNotchDesign.paper)
    }

    // MARK: Section content

    private var generalContent: some View {
        toggleRow(title: "Open at login", isOn: launchAtLoginBinding)
            .tint(ClipNotchDesign.primaryContainer)
    }

    private var storageContent: some View {
        VStack(spacing: 12) {
            stepperRow(
                title: "Keep items for",
                value: retentionDays,
                range: 1...90,
                step: 1,
                suffix: "d"
            ) { days in
                appState.retentionHours = Double(days * 24)
            }

            ClipNotchDesign.paperTextMuted.opacity(0.12).frame(height: 1)

            stepperRow(
                title: "Max items",
                value: appState.maxItemCount,
                range: 10...10_000,
                step: 10
            ) { appState.maxItemCount = $0 }

            stepperRow(
                title: "Max disk",
                value: appState.maxDiskMB,
                range: 50...5000,
                step: 50,
                suffix: " MB"
            ) { appState.maxDiskMB = $0 }
        }
    }

    private var shortcutsContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open drawer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClipNotchDesign.paperText)
                Text("Hold ⌘, press J · navigate J/K · release to paste")
                    .font(.system(size: 10))
                    .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ShortcutBadge(keys: ["⌘", "J"])
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.hasAccessibilityPermission ? ClipNotchDesign.secondaryContainer : Color.orange)
                    .frame(width: 7, height: 7)
                Text(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClipNotchDesign.paperText)
            }

            if appState.hasAccessibilityPermission {
                Text("Global ⌘J shortcuts are active.")
                    .font(.system(size: 11))
                    .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.75))
            } else {
                Text("Grant access so global shortcuts and hold-to-paste work.")
                    .font(.system(size: 11))
                    .foregroundStyle(ClipNotchDesign.paperTextMuted.opacity(0.75))

                Button("Open System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Bindings

    private var retentionDays: Int {
        max(1, Int(appState.retentionHours / 24))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLogin },
            set: { newValue in
                appState.launchAtLogin = newValue
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    appState.launchAtLogin = !newValue
                }
            }
        )
    }

    // MARK: Row builders

    private func stepperRow(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String = "",
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipNotchDesign.paperText)
            Spacer(minLength: 8)
            CompactStepper(value: value, range: range, step: step, suffix: suffix, onChange: onChange)
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipNotchDesign.paperText)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

// MARK: - Sections

private enum PreferencesSection: CaseIterable {
    case general, storage, shortcuts, privacy

    var title: String {
        switch self {
        case .general: "General"
        case .storage: "Storage"
        case .shortcuts: "Shortcuts"
        case .privacy: "Privacy"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .storage: "internaldrive"
        case .shortcuts: "keyboard"
        case .privacy: "lock"
        }
    }
}

// MARK: - Shortcut badge

private struct ShortcutBadge: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ClipNotchDesign.shortcutBg)
                    )
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Compact stepper

private struct CompactStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    var suffix: String = ""
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", enabled: value - step >= range.lowerBound) {
                onChange(max(value - step, range.lowerBound))
            }

            Text("\(value)\(suffix)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ClipNotchDesign.paperTextMuted)
                .frame(minWidth: 44)
                .padding(.horizontal, 4)
                .overlay(alignment: .leading) {
                    ClipNotchDesign.paperTextMuted.opacity(0.15).frame(width: 1)
                }
                .overlay(alignment: .trailing) {
                    ClipNotchDesign.paperTextMuted.opacity(0.15).frame(width: 1)
                }

            stepButton(systemName: "plus", enabled: value + step <= range.upperBound) {
                onChange(min(value + step, range.upperBound))
            }
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ClipNotchDesign.paperTextMuted.opacity(0.2), lineWidth: 1)
        )
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? ClipNotchDesign.paperTextMuted : ClipNotchDesign.paperTextMuted.opacity(0.35))
        .disabled(!enabled)
    }
}

// MARK: - Window sizing

/// Pins the NSWindow content size to match the SwiftUI layout (not just the inner view).
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

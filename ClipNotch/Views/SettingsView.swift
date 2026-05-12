import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    settingsRow(
                        icon: "clock",
                        color: .blue,
                        title: "Retention",
                        detail: "\(Int(appState.retentionHours))h"
                    ) {
                        Stepper(
                            value: $appState.retentionHours,
                            in: 1...720
                        ) {
                            Text("\(Int(appState.retentionHours)) hours")
                                .monospacedDigit()
                        }
                    }

                    settingsRow(
                        icon: "doc.on.doc",
                        color: .orange,
                        title: "Max Items",
                        detail: "\(appState.maxItemCount)"
                    ) {
                        Stepper(
                            value: $appState.maxItemCount,
                            in: 10...10000,
                            step: 10
                        ) {
                            Text("\(appState.maxItemCount)")
                                .monospacedDigit()
                        }
                    }

                    settingsRow(
                        icon: "internaldrive",
                        color: .purple,
                        title: "Max Disk Usage",
                        detail: "\(appState.maxDiskMB) MB"
                    ) {
                        Stepper(
                            value: $appState.maxDiskMB,
                            in: 50...5000,
                            step: 50
                        ) {
                            Text("\(appState.maxDiskMB) MB")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Storage")
                        .font(.headline)
                        .padding(.bottom, 4)
                }

                Section {
                    Toggle(isOn: Binding(
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
                    )) {
                        Label {
                            Text("Launch at Login")
                        } icon: {
                            Image(systemName: "power")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("System")
                        .font(.headline)
                        .padding(.bottom, 4)
                }

                Section {
                    HStack {
                        Label {
                            Text("Open Drawer")
                        } icon: {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("⌘J")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                } header: {
                    Text("Shortcuts")
                        .font(.headline)
                        .padding(.bottom, 4)
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("ClipNotch")
                    .font(.title2.bold())
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            permissionBadge

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Components

    private var permissionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.hasAccessibilityPermission
                  ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            Text(appState.hasAccessibilityPermission
                 ? "Accessibility Granted" : "Accessibility Required")
                .font(.caption)
        }
        .foregroundStyle(appState.hasAccessibilityPermission ? .green : .red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (appState.hasAccessibilityPermission ? Color.green : Color.red)
                .opacity(0.1),
            in: Capsule()
        )
    }

    @ViewBuilder
    private func settingsRow<Control: View>(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Spacer()
            control()
        }
    }
}

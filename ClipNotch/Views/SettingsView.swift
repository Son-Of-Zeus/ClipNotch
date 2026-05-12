import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            statusTab
                .tabItem {
                    Label("Status", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 280)
        .scenePadding()
    }

    private var generalTab: some View {
        Form {
            Section("Retention") {
                Stepper(
                    "Keep items for \(Int(appState.retentionHours)) hours",
                    value: Binding(
                        get: { appState.retentionHours },
                        set: { appState.retentionHours = $0 }
                    ),
                    in: 1...720
                )

                Stepper(
                    "Maximum \(appState.maxItemCount) items",
                    value: Binding(
                        get: { appState.maxItemCount },
                        set: { appState.maxItemCount = $0 }
                    ),
                    in: 10...10000,
                    step: 10
                )

                Stepper(
                    "Maximum \(appState.maxDiskMB) MB disk usage",
                    value: Binding(
                        get: { appState.maxDiskMB },
                        set: { appState.maxDiskMB = $0 }
                    ),
                    in: 50...5000,
                    step: 50
                )
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
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
                ))
            }

            Section("Shortcut") {
                LabeledContent("Open ClipNotch", value: "⌘J")
            }
        }
    }

    private var statusTab: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Circle()
                        .fill(appState.hasAccessibilityPermission ? .green : .red)
                        .frame(width: 8, height: 8)

                    Text(appState.hasAccessibilityPermission
                         ? "Accessibility: Granted"
                         : "Accessibility: Not Granted")
                }
            }
        }
    }
}

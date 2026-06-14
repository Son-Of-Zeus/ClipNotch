import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// Single-window preferences UI (hosted in the app’s primary `WindowGroup`).
struct ClipNotchSettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        ZStack {
            chromeBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    chromeCard { storageSection }
                    chromeCard { systemSection }
                    chromeCard { shortcutsSection }
                    chromeCard { trustSection }
                    footer
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    // MARK: - Chrome

    private var chromeBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                ]
                : [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.90, green: 0.92, blue: 0.97),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func chromeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.18),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.06),
                        radius: 20,
                        y: 12
                    )
            }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.35), .indigo.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    }
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ClipNotch")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Clipboard history from your notch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Storage", systemImage: "internaldrive")

            LabeledContent {
                Text("\(Int(appState.retentionHours))h")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label("Keep items for", systemImage: "clock.arrow.circlepath")
                    .symbolRenderingMode(.hierarchical)
            }
            Slider(value: $appState.retentionHours, in: 1...720, step: 1)
                .tint(.cyan)

            Divider().opacity(0.35)

            LabeledContent {
                Text("\(appState.maxItemCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label("Max items in history", systemImage: "square.stack.3d.up")
                    .symbolRenderingMode(.hierarchical)
            }
            Stepper("", value: $appState.maxItemCount, in: 10...10_000, step: 10)
                .labelsHidden()

            Divider().opacity(0.35)

            LabeledContent {
                Text("\(appState.maxDiskMB) MB")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label("Max disk for files", systemImage: "externaldrive")
                    .symbolRenderingMode(.hierarchical)
            }
            Stepper("", value: $appState.maxDiskMB, in: 50...5000, step: 50)
                .labelsHidden()
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("System", systemImage: "gearshape.2")

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
                Label("Open at login", systemImage: "power.circle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            .tint(.green)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Shortcuts", systemImage: "keyboard")

            HStack(spacing: 12) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open drawer")
                        .font(.body.weight(.medium))
                    Text("Hold ⌘ and press J, navigate with J / K, release ⌘ to paste.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("⌘J")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Accessibility", systemImage: "hand.raised.fill")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: appState.hasAccessibilityPermission ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(appState.hasAccessibilityPermission ? .green : .orange)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        appState.hasAccessibilityPermission
                            ? "ClipNotch can listen for ⌘J globally."
                            : "Grant Accessibility so global shortcuts and hold-to-paste work."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Open Accessibility settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Local only · no network", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Spacer()
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.top, 8)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

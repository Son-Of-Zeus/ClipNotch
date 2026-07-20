import SwiftUI
import ApplicationServices

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pollingTimer: Timer?
    @State private var permissionGranted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(ClipNotchDesign.label)

            Text("ClipNotch needs Accessibility access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This allows ClipNotch to detect keyboard shortcuts globally and paste into any app.")
                .font(.body)
                .foregroundStyle(ClipNotchDesign.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Open Accessibility Settings") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Open System Settings → Privacy & Security → Accessibility, then enable ClipNotch.")
                .font(.caption)
                .foregroundStyle(ClipNotchDesign.tertiaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if permissionGranted {
                Label("Permission Granted!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }

            Spacer()
        }
        .frame(width: 440, height: 340)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            promptForAccessibility()
            startPolling()
        }
        .onDisappear {
            pollingTimer?.invalidate()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        promptForAccessibility()
    }

    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let granted = AXIsProcessTrusted()
            Task { @MainActor in
                if granted {
                    withAnimation(ClipNotchMotion.emphasis(reduceMotion: reduceMotion)) {
                        permissionGranted = true
                    }
                    appState.hasAccessibilityPermission = true

                    try? await Task.sleep(for: .milliseconds(500))
                    appState.hasCompletedOnboarding = true
                }
            }
        }
    }
}

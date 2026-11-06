import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    let guide: AccessibilityGuideController
    var onPermissionChange: () -> Void
    var onCopySample: () async -> Bool
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var practiceText = ""
    @State private var sampleReady = false
    @State private var isCopying = false
    @State private var copyError = false
    @State private var editingProfile: DataPaletteProfile?
    @FocusState private var practiceFocused: Bool

    static let windowSize = NSSize(width: 760, height: 600)
    static let sample = "A little less copying. A lot more doing."
    private var step: OnboardingStep { appState.onboarding.step }
    private var practiceSucceeded: Bool {
        sampleReady && practiceText.trimmingCharacters(in: .whitespacesAndNewlines) == Self.sample
    }

    private var title: String {
        switch step {
        case .welcome: "A little more room\nfor your clipboard."
        case .permission: "One permission.\nA smoother workflow."
        case .practice: "Give it a try."
        case .profiles: "Your details.\nReady to go."
        case .ready: "Make yourself\nat home."
        }
    }

    private var subtitle: String {
        switch step {
        case .welcome: "Keep the things you copy. Bring them back from the top of your Mac, whenever you need them."
        case .permission: "Accessibility lets ClipNotch respond to global shortcuts and paste into your apps. You can change access at any time."
        case .practice: "Copy the sample, open your history, then paste it into the field below."
        case .profiles: "Save details once and use them again. Browser autofill always asks before filling a form."
        case .ready: "Your clipboard is one shortcut away. You can also open it from the menu bar."
        }
    }

    private var illustration: String {
        switch step {
        case .welcome, .permission: "OnboardingWelcome"
        case .practice: "ClipboardEmpty"
        case .profiles: "OnboardingProfiles"
        case .ready: "OnboardingReady"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ClipNotchWindowHeader(detail: "\(step.rawValue + 1) of \(OnboardingStep.allCases.count) · \(step.name)")

            HStack(spacing: 28) {
                VStack(spacing: 18) {
                    Image(illustration)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 286)
                        .accessibilityHidden(true)
                    Label("Made for your Mac", systemImage: "lock.shield")
                        .font(ClipNotchTypography.callout)
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                    Text("Your history and saved details\nstay on this Mac.")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .background(ClipNotchDesign.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title)
                                .font(.system(size: 29, weight: .bold))
                                .tracking(-0.7)
                                .accessibilityAddTraits(.isHeader)
                            Text(subtitle)
                                .font(ClipNotchTypography.body)
                                .foregroundStyle(ClipNotchDesign.secondaryLabel)
                                .lineSpacing(4)
                        }
                        detail
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.trailing, 4)
                    .id(step)
                }
            }
            .padding(28)

            Divider()
            footer
        }
        .font(ClipNotchTypography.body)
        .frame(minWidth: 700, minHeight: 520)
        .buttonStyle(ClipNotchButtonStyle())
        .background(ClipNotchWindowSurface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: step)
        .sheet(item: $editingProfile) { profile in
            DataPaletteProfileEditor(profile: profile, store: appState.dataPalette)
        }
        .task {
            onPermissionChange()
            refreshPermission()
            await appState.dataPalette.load()
            while !Task.isCancelled {
                refreshPermission()
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
        .onChange(of: step) { _, _ in
            guide.stop()
            sampleReady = false
            practiceText = ""
        }
        .onDisappear { guide.stop() }
    }

    @ViewBuilder private var detail: some View {
        switch step {
        case .welcome:
            feature("doc.on.doc", title: "Copy. Keep. Use again.", text: "Text, images, and files in one place.")
            feature("person.crop.rectangle", title: "Skip the repeat typing.", text: "Keep reusable details in Data Palette.")
        case .permission:
            VStack(alignment: .leading, spacing: 12) {
                Label(appState.hasAccessibilityPermission ? "Accessibility is enabled" : guide.isRunning ? "Waiting for access" : "You’re in control",
                      systemImage: appState.hasAccessibilityPermission ? "checkmark.shield" : guide.isRunning ? "clock" : "lock.shield")
                    .font(ClipNotchTypography.label).foregroundStyle(ClipNotchDesign.accent)
                Text(appState.hasAccessibilityPermission
                     ? "Global shortcuts could not start. Retry below. If this continues, check access for this copy of ClipNotch, then quit and reopen the app."
                     : guide.message)
                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                if guide.isRunning {
                    Button("Close guide") { guide.cancel() }.controlSize(.small)
                }
                if !appState.hasAccessibilityPermission { AccessibilityManualInstructions() }
            }
        case .practice:
            VStack(alignment: .leading, spacing: 14) {
                Text(Self.sample).font(ClipNotchTypography.label)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                Button(isCopying ? "Copying…" : sampleReady ? "Copy sample again" : "Copy sample", systemImage: "doc.on.doc") {
                    isCopying = true
                    Task {
                        let copied = await onCopySample()
                        isCopying = false
                        guard step == .practice else { return }
                        sampleReady = copied
                        copyError = !sampleReady
                        practiceText = ""
                        practiceFocused = sampleReady
                    }
                }
                .disabled(isCopying)
                if copyError {
                    Text("The sample could not be copied. Try again.").foregroundStyle(.red)
                }
                shortcutHelp
                Text("Paste here").font(ClipNotchTypography.label)
                TextEditor(text: $practiceText)
                    .font(ClipNotchTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 68)
                    .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(practiceFocused ? ClipNotchDesign.accent : ClipNotchDesign.separator))
                    .focused($practiceFocused)
                    .accessibilityLabel("Paste the practice sample here")
                if practiceSucceeded {
                    Label("That’s it. Your clipboard, within reach.", systemImage: "checkmark.circle.fill")
                        .font(ClipNotchTypography.callout).foregroundStyle(Color(nsColor: .systemGreen))
                }
            }
        case .profiles:
            VStack(alignment: .leading, spacing: 12) {
                if let error = appState.dataPalette.errorMessage {
                    Text(error).font(ClipNotchTypography.callout).foregroundStyle(.red)
                }
                ForEach(appState.dataPalette.profiles) { profile in
                    Button { editingProfile = profile } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle").foregroundStyle(ClipNotchDesign.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(ClipNotchTypography.label).lineLimit(1)
                                Text("\(profile.filledFields.count) saved values").font(ClipNotchTypography.caption)
                                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(ClipNotchTypography.caption)
                        }
                        .padding(12)
                        .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Button("Add Profile", systemImage: "plus") { editingProfile = DataPaletteProfile(name: "") }
                    .disabled(!appState.dataPalette.isLoaded || appState.dataPalette.isSaving)
                Text("Profiles are separate from clipboard history limits. You can edit them later in Settings.")
                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        case .ready:
            shortcutHelp
            feature(ClipNotchDesign.menuBarSymbol, title: "Find us in the menu bar.", text: "Open history, manage saved details, or change Settings.")
            Toggle("Open ClipNotch at login", isOn: Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
            if let error = appState.loginError {
                Text(error).font(ClipNotchTypography.caption).foregroundStyle(.red)
            }
        }
    }

    private var shortcutHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Open history").font(ClipNotchTypography.callout)
                Spacer()
                ShortcutBadge(keys: appState.shortcutConfiguration.displayKeys(for: appState.shortcutConfiguration.previousItem))
            }
            if step == .ready {
                HStack {
                    Text("Open saved details").font(ClipNotchTypography.callout)
                    Spacer()
                    ShortcutBadge(keys: appState.shortcutConfiguration.displayKeys(for: appState.shortcutConfiguration.previousItem, palette: true))
                }
            }
            Text(appState.shortcutConfiguration.interactionMode == .holdToPaste
                 ? "Hold Command. Use \(appState.shortcutConfiguration.previousItem.displayKeys.joined()) and \(appState.shortcutConfiguration.nextItem.displayKeys.joined()) to choose. Release Command to paste."
                 : "Use \(appState.shortcutConfiguration.previousItem.displayKeys.joined()) and \(appState.shortcutConfiguration.nextItem.displayKeys.joined()) to choose. Press Return to paste, or Escape to close.")
                .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
            if step == .ready && appState.shortcutConfiguration.interactionMode == .holdToPaste {
                Text("For saved details, also hold Shift. Release Shift to choose a data type, then choose a profile and release Command to paste.")
                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        }
    }

    private func feature(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AccentIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(ClipNotchTypography.label)
                Text(text).font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if step != .welcome {
                Button("Back") { appState.onboarding.back(hasPermission: appState.hasAccessibilityPermission && appState.areShortcutsReady) }
            }
            Spacer()
            if step == .practice || step == .profiles {
                Button("Skip for now") { advance() }.buttonStyle(ClipNotchButtonStyle(.quiet))
            }
            Button(step == .permission ? (appState.hasAccessibilityPermission ? "Retry shortcuts" : "Enable Accessibility…") : step == .ready ? "Start using ClipNotch" : "Continue") {
                if step == .permission {
                    if appState.hasAccessibilityPermission {
                        onPermissionChange()
                        refreshPermission()
                    } else { guide.start() }
                }
                else if step == .ready {
                    refreshPermission()
                    if appState.hasAccessibilityPermission { onFinish() }
                } else { advance() }
            }
            .buttonStyle(ClipNotchButtonStyle(.primary))
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(step == .practice && !practiceSucceeded)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
    }

    private func advance() {
        refreshPermission()
        appState.onboarding.advance(hasPermission: appState.hasAccessibilityPermission, shortcutsReady: appState.areShortcutsReady)
    }

    private func refreshPermission() {
        let granted = AXIsProcessTrusted()
        if granted != appState.hasAccessibilityPermission {
            appState.hasAccessibilityPermission = granted
            onPermissionChange()
        }
        appState.onboarding.reconcilePermission(granted, shortcutsReady: appState.areShortcutsReady)
    }
}

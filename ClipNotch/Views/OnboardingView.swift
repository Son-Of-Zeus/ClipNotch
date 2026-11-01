import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onPermissionChange: () -> Void
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var hasAppeared = false
    @State private var hasOpenedSettings = false

    static let windowSize = NSSize(width: 560, height: 580)

    private enum Step: Int, CaseIterable {
        case welcome, permission, ready

        var title: String {
            switch self {
            case .welcome: "A little more room for your clipboard."
            case .permission: "One small permission."
            case .ready: "Everything is at your fingertips."
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "The things you copy, ready when you need them.\nRight at the top of your Mac."
            case .permission: "Allow Accessibility access so ClipNotch can\nrespond to shortcuts and paste into your apps."
            case .ready: "Copy something, then bring up your history\nwithout leaving what you’re doing."
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "doc.on.clipboard"
            case .permission: "accessibility"
            case .ready: "checkmark"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 14)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(ClipNotchDesign.windowBackground)
        .task {
            withAnimation(ClipNotchMotion.emphasis(reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
            while !Task.isCancelled {
                refreshPermission()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private var page: some View {
        VStack(spacing: 22) {
            hero
                .padding(.top, 24)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)
                    .frame(maxWidth: 400)
                    .accessibilityAddTraits(.isHeader)
                Text(step.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                    .lineSpacing(4)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            detail
                .frame(width: 400, height: 132)
        }
        .padding(.horizontal, 40)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: reduceMotion || hasAppeared ? 0 : 12)
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.05))
                .frame(width: 144, height: 144)
            Circle()
                .fill(Color.accentColor.opacity(0.07))
                .frame(width: 112, height: 112)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill((step == .ready ? Color.green : Color.accentColor).gradient)
                .frame(width: 84, height: 84)
                .shadow(color: Color.accentColor.opacity(0.16), radius: 16, y: 8)

            Image(systemName: step.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            if step == .welcome {
                satellite("photo", rotation: -12, x: -80, y: 24)
                satellite("doc.text", rotation: 12, x: 80, y: -24)
            }
        }
        .frame(height: 144)
        .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.9)
        .accessibilityHidden(true)
    }

    private func satellite(_ symbol: String, rotation: Double, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 52, height: 60)
            .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ClipNotchDesign.separator.opacity(0.4)))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .offset(x: hasAppeared || reduceMotion ? x : 0, y: hasAppeared || reduceMotion ? y : 0)
    }

    @ViewBuilder
    private var detail: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 18) {
                feature("doc.on.doc", title: "Copy. Keep. Use again.", subtitle: "Text, images, and files, all in one place.")
                feature("lock.shield", title: "Stays on your Mac.", subtitle: "Your clipboard history is stored locally.")
            }
        case .permission:
            VStack(alignment: .leading, spacing: 14) {
                instruction(number: "1", text: "Open Privacy & Security → Accessibility.")
                instruction(number: "2", text: "Turn on the switch next to ClipNotch.")
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(hasOpenedSettings ? "We’ll continue when access is enabled." : "You’re in control. Change access at any time.")
                }
                .font(.caption)
                .foregroundStyle(ClipNotchDesign.secondaryLabel)
                .padding(.top, 2)
            }
        case .ready:
            VStack(spacing: 12) {
                shortcutRow("Open your clipboard", keys: appState.shortcutConfiguration.displayKeys(for: appState.shortcutConfiguration.previousItem))
                shortcutRow("Choose an item", keys: appState.shortcutConfiguration.previousItem.displayKeys + appState.shortcutConfiguration.nextItem.displayKeys)
                Divider()
                Text(appState.shortcutConfiguration.interactionMode == .holdToPaste
                     ? "Hold Command as you choose. Release to paste. Add Shift for Data Palette; release Shift to choose a profile."
                     : "Press Return to paste. Press Escape to dismiss.")
                    .font(.caption)
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func feature(_ symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        }
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.1), in: Circle())
            Text(text).font(.system(size: 13))
        }
    }

    private func shortcutRow(_ title: String, keys: [String]) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            HStack(spacing: 5) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .frame(minWidth: 26, minHeight: 26)
                        .padding(.horizontal, 3)
                        .background(ClipNotchDesign.windowBackground, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(ClipNotchDesign.separator.opacity(0.5)))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            Button(action: advance) {
                Text(step == .welcome ? "Continue" : step == .permission ? "Open System Settings…" : "Start Using ClipNotch")
                    .frame(width: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : ClipNotchDesign.secondaryLabel.opacity(0.2))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of 3")
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

    private func advance() {
        switch step {
        case .welcome:
            refreshPermission()
            move(to: appState.hasAccessibilityPermission ? .ready : .permission)
        case .permission:
            refreshPermission()
            guard !appState.hasAccessibilityPermission else { return }
            hasOpenedSettings = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .ready:
            refreshPermission()
            guard appState.hasAccessibilityPermission else { return }
            onFinish()
        }
    }

    private func refreshPermission() {
        let granted = AXIsProcessTrusted()
        if granted != appState.hasAccessibilityPermission {
            appState.hasAccessibilityPermission = granted
            onPermissionChange()
        }
        if step == .permission && granted {
            move(to: .ready)
        } else if step == .ready && !granted {
            move(to: .permission)
        }
    }

    private func move(to newStep: Step) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.5, bounce: 0.12)) {
            step = newStep
        }
    }
}

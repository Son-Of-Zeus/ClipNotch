import SwiftUI

struct AutofillPromptView: View {
    let session: FormAutofillSession
    let metrics: NotchMetrics
    var onAccept: () -> Void
    var onNotNow: () -> Void
    var onNever: () -> Void
    var onProfile: (DataPaletteProfile) -> Void
    var onValue: (DataPaletteValue) -> Void
    var onHeightChange: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isVisible = false

    private var preferredProfile: DataPaletteProfile? {
        session.profiles.first { $0.id == session.preferredProfileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            VStack(spacing: 14) {
                if session.stage != .result {
                    Label(session.page.host, systemImage: "globe")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ClipNotchDesign.drawerControl, in: Capsule())
                }
                content
                if session.stage != .filling && session.stage != .result {
                    if session.stage != .prompt {
                        Button("Not now", action: onNotNow)
                            .font(ClipNotchTypography.button)
                            .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                            .padding(.vertical, 4)
                    }
                    Button(action: onNever) {
                        Label("Never suggest on this site", systemImage: "minus.circle")
                    }
                    .font(ClipNotchTypography.caption)
                    .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .font(ClipNotchTypography.body)
        .multilineTextAlignment(.center)
        .buttonStyle(.plain)
        .foregroundStyle(ClipNotchDesign.drawerText)
        .environment(\.colorScheme, .dark)
        .frame(width: session.stage == .result ? min(220, metrics.bodyWidth) : metrics.bodyWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(ClipNotchDesign.drawerBackground)
        .clipShape(NotchShape())
        .overlay {
            if contrast == .increased { NotchShape().stroke(.white.opacity(0.6), lineWidth: 1) }
        }
        .background(GeometryReader { geometry in
            Color.clear.onAppear { onHeightChange(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in onHeightChange(height) }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion || isVisible ? 0 : -10)
        .scaleEffect(reduceMotion || isVisible ? 1 : 0.98, anchor: .top)
        .animation(ClipNotchMotion.drawer(reduceMotion: reduceMotion), value: isVisible)
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: session.stage)
        .onAppear { isVisible = !session.isClosing }
        .onChange(of: session.isClosing) { _, closing in isVisible = !closing }
    }

    @ViewBuilder private var content: some View {
        switch session.stage {
        case .prompt:
            VStack(spacing: 6) {
                Text("Fill this form?").font(ClipNotchTypography.title)
                Text(session.suggestedProfileName.map { "Use your \($0) details." } ?? "Choose your saved details.")
                    .font(ClipNotchTypography.callout)
                    .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
            }
            HStack(spacing: 7) {
                ForEach(session.categories.prefix(3)) { category in
                    Label(category.label, systemImage: symbol(for: category.id))
                        .font(ClipNotchTypography.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ClipNotchDesign.drawerControl, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClipNotchDesign.drawerBorder, lineWidth: 0.5))
                }
                if session.categories.count > 3 {
                    Text("+\(session.categories.count - 3)")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            HStack(spacing: 8) {
                Button("Not now", action: onNotNow)
                    .buttonStyle(AutofillActionStyle())
                Button(session.isPreparing ? "Checking fields…" : "Fill \(session.fields.count) \(session.fields.count == 1 ? "field" : "fields")", action: onAccept)
                    .buttonStyle(AutofillActionStyle(isPrimary: true))
                    .disabled(session.isPreparing)
            }
            .padding(.top, 2)

        case .profiles:
            let profiles = AutofillProfileResolver.eligibleProfiles(for: Set(session.categories.map(\.id)), profiles: session.profiles)
            VStack(spacing: 6) {
                Text("Choose a profile").font(ClipNotchTypography.title)
                Text("Use one profile for this form.")
                    .font(ClipNotchTypography.callout)
                    .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        AutofillChoiceRow(title: profile.name, subtitle: session.coverage(for: profile),
                                          symbol: profileSymbol(for: profile.name)) {
                            onProfile(profile)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(profiles.count) * 66 - 8, 180))

        case .valueChoice:
            let label = session.categories.first { $0.id == session.choiceCategoryID }?.label ?? "this field"
            VStack(spacing: 6) {
                Text(session.choiceCategoryID == "phone" ? "Which phone number?" : "Choose \(label)")
                    .font(ClipNotchTypography.title)
                    .lineLimit(2)
                if let preferredProfile, !session.choices.contains(where: { $0.profileID == preferredProfile.id }) {
                    Text("\(preferredProfile.name) has no saved \(label.lowercased()).")
                        .font(ClipNotchTypography.callout)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(session.choices) { value in
                        AutofillChoiceRow(title: value.profileName, subtitle: value.field.value,
                                          symbol: profileSymbol(for: value.profileName)) {
                            onValue(value)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(session.choices.count) * 72 - 8, 180))

        case .filling:
            VStack(spacing: 12) {
                progressRing
                VStack(spacing: 4) {
                    Text("Filling your form…").font(ClipNotchTypography.heading)
                    Text("\(session.filledCount) of \(session.fields.count) fields")
                        .font(ClipNotchTypography.caption)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                        .monospacedDigit()
                }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(session.categories) { category in
                        if let value = session.selectedValues[category.id] {
                            Label("\(category.label) · \(value.profileName)", systemImage: symbol(for: category.id))
                                .font(ClipNotchTypography.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(ClipNotchDesign.drawerControl, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ClipNotchDesign.drawerBorder, lineWidth: 0.5))
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(session.selectedValues.count) * 36, 120))

        case .result:
            AutofillCompletionMark(isComplete: !session.wasStopped && session.skippedLabels.isEmpty)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Filled \(session.filledCount) of \(session.fields.count) fields")
        }
    }

    private var progressRing: some View {
        let progress = Double(session.filledCount) / Double(max(session.fields.count, 1))
        return ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.08, progress))
                .stroke(ClipNotchDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
        .accessibilityHidden(true)
    }

    private func symbol(for categoryID: String) -> String {
        switch categoryID {
        case "email": "envelope"
        case "phone": "phone"
        default: "doc.text"
        }
    }

    private func profileSymbol(for name: String) -> String {
        switch name.lowercased() {
        case "work", "office": "briefcase"
        case "home": "house"
        default: "person"
        }
    }
}

private struct AutofillActionStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClipNotchTypography.button)
            .foregroundStyle(isPrimary ? Color(nsColor: .selectedControlTextColor) : ClipNotchDesign.drawerText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isPrimary ? ClipNotchDesign.accent : ClipNotchDesign.drawerControl, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isPrimary ? .clear : ClipNotchDesign.drawerBorder, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AutofillChoiceRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ClipNotchTypography.label).lineLimit(1)
                    Text(subtitle).font(ClipNotchTypography.caption).lineLimit(2)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(isHovered ? ClipNotchDesign.drawerSelection : ClipNotchDesign.drawerControl,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ClipNotchDesign.drawerBorder, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: isHovered)
    }
}

private struct AutofillCompletionMark: View {
    let isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(isComplete ? ClipNotchDesign.accent.opacity(0.65) : Color.orange.opacity(0.65),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isComplete {
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 12))
                    path.addLine(to: CGPoint(x: 9, y: 20))
                    path.addLine(to: CGPoint(x: 25, y: 3))
                }
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(ClipNotchDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 24)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.15), value: isDrawn)
            } else {
                Image(systemName: "exclamationmark").font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .frame(width: 48, height: 48)
        .scaleEffect(reduceMotion || isDrawn ? 1 : 0.85)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: isDrawn)
        .onAppear { isDrawn = true }
    }
}

import SwiftUI

/// A shape matching the MacBook notch aesthetic (BoringNotch / DynamicNotchKit design language):
/// small top corners that curve *inward* so the tray appears to hang from the notch, and large
/// bottom corners that curve outward for the tray.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 22) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topR = topCornerRadius
        let botR = bottomCornerRadius

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct DrawerView: View {
    var appState: AppState
    let metrics: NotchMetrics
    var onSelectPage: (DrawerSession.Page) -> Void
    var onConfirm: () -> Void
    var onOpenPreferences: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var tabIndicator
    @State private var isVisible = false

    private var page: DrawerSession.Page { appState.drawer.page }
    private var palette: DataPaletteStore { appState.dataPalette }
    private var selection: Int {
        switch page {
        case .clipboard: appState.selectedIndex
        case .dataTypes: palette.typeIndex
        case .profileValues: palette.valueIndex
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            VStack(spacing: 0) {
                if page.isPalette { paletteHeader }
                listContent
                footer
            }
            .id(page)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: page == .clipboard ? -12 : 12)),
                removal: .opacity
            ))
        }
        .animation(ClipNotchMotion.emphasis(reduceMotion: reduceMotion), value: page)
        .font(ClipNotchTypography.body)
        .environment(\.colorScheme, .dark)
        .frame(width: metrics.bodyWidth, height: appState.drawerBodyHeight)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: metrics.notchHeight) }
        .frame(width: metrics.bodyWidth, height: metrics.notchHeight + appState.drawerBodyHeight)
        .background(ClipNotchDesign.drawerBackground)
        .clipShape(NotchShape())
        .overlay {
            if contrast == .increased {
                NotchShape().stroke(.white.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion || isVisible ? 0 : -10)
        .scaleEffect(reduceMotion || isVisible ? 1 : 0.98, anchor: .top)
        .animation(ClipNotchMotion.drawer(reduceMotion: reduceMotion), value: isVisible)
        .animation(reduceMotion ? nil : ClipNotchMotion.standard(reduceMotion: false), value: appState.drawerBodyHeight)
        .onAppear { isVisible = appState.isDrawerOpen }
        .onChange(of: appState.isDrawerOpen) { _, open in isVisible = open }
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            tab("Clipboard", symbol: "doc.on.clipboard", page: .clipboard)
            tab("Data Palette", symbol: "person.crop.rectangle", page: .dataTypes)
        }
        .padding(4)
        .background(ClipNotchDesign.drawerControl, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private func tab(_ title: String, symbol: String, page target: DrawerSession.Page) -> some View {
        let selected = target.isPalette == page.isPalette
        return Button { onSelectPage(target) } label: {
            Label(title, systemImage: symbol)
                .font(ClipNotchTypography.button)
                .foregroundStyle(selected ? ClipNotchDesign.drawerText : ClipNotchDesign.drawerSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        if reduceMotion {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(ClipNotchDesign.drawerSelection)
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(ClipNotchDesign.drawerSelection)
                                .matchedGeometryEffect(id: "selectedTab", in: tabIndicator)
                        }
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule().fill(ClipNotchDesign.accent).frame(width: 20, height: 2)
                            .padding(.bottom, 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var paletteHeader: some View {
        HStack(spacing: 8) {
            if page == .profileValues {
                Button { onSelectPage(.dataTypes) } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to data types")
            }
            Text(page == .profileValues ? palette.selectedType?.label ?? "Choose a profile" : "Choose a data type")
                .font(ClipNotchTypography.button)
                .lineLimit(1)
            Spacer()
            Button(action: onOpenPreferences) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage Data Palette")
        }
        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
        .padding(.horizontal, 22)
        .frame(height: 32)
    }

    @ViewBuilder private var listContent: some View {
        if page == .clipboard && appState.items.isEmpty {
            EmptyStateView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if page.isPalette && (!palette.isLoaded || (page == .dataTypes ? palette.dataTypes.isEmpty : palette.profileValues.isEmpty)) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 24))
                Text(palette.errorMessage ?? (palette.isLoaded ? "No saved values yet" : "Loading Data Palette…"))
                    .font(ClipNotchTypography.callout).multilineTextAlignment(.center)
                Button("Open Preferences", action: onOpenPreferences).buttonStyle(.plain)
                    .font(ClipNotchTypography.button)
            }
            .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        switch page {
                        case .clipboard:
                            ForEach(Array(appState.items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    appState.selectedIndex = index
                                    onConfirm()
                                } label: {
                                    ClipboardItemRow(item: item, isHighlighted: index == selection, appState: appState)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        case .dataTypes:
                            ForEach(Array(palette.dataTypes.enumerated()), id: \.element.id) { index, type in
                                paletteRow(
                                    title: type.label,
                                    detail: palette.profileCount(for: type) == 1 ? "1 profile" : "\(palette.profileCount(for: type)) profiles",
                                    symbol: "text.alignleft",
                                    selected: index == selection
                                ) {
                                    palette.typeIndex = index
                                    onConfirm()
                                }
                                .id(index)
                            }
                        case .profileValues:
                            ForEach(Array(palette.profileValues.enumerated()), id: \.element.id) { index, value in
                                paletteRow(title: value.profileName, detail: value.field.value, symbol: "person.crop.rectangle", selected: index == selection) {
                                    palette.valueIndex = index
                                    onConfirm()
                                }
                                .id(index)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: selection) { _, value in
                    withAnimation(ClipNotchMotion.standard(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }
        }
    }

    private func paletteRow(title: String, detail: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(ClipNotchTypography.callout)
                    .foregroundStyle(selected ? ClipNotchDesign.drawerText : ClipNotchDesign.accent)
                    .frame(width: 28, height: 28)
                    .background(selected ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ClipNotchTypography.label)
                        .foregroundStyle(ClipNotchDesign.drawerText)
                    Text(detail).font(ClipNotchTypography.footnote)
                        .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
                        .help(detail)
                }
                .lineLimit(1)
                Spacer(minLength: 2)
                if page == .dataTypes { Image(systemName: "chevron.right").font(ClipNotchTypography.footnote) }
            }
            .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
            .padding(.horizontal, 20)
            .frame(height: 42)
            .background(Rectangle().fill(selected ? ClipNotchDesign.drawerSelection : Color.clear))
            .overlay(Rectangle().strokeBorder(selected && contrast == .increased ? ClipNotchDesign.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        Text(appState.shortcutConfiguration.interactionMode == .toggle
             ? "Return to choose · Escape to go back"
             : page == .dataTypes ? "Release Shift to choose · Escape to close" : "Release Command to paste")
            .font(ClipNotchTypography.footnote)
            .foregroundStyle(ClipNotchDesign.drawerTertiaryText)
            .frame(height: 24)
    }
}

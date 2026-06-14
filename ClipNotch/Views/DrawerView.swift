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
    @State private var isVisible: Bool = false

    private let topCornerRadius: CGFloat = 10
    private let bottomCornerRadius: CGFloat = 22

    var body: some View {
        listContent
            .frame(width: metrics.bodyWidth, height: metrics.bodyHeight)
            // Reserve the notch height at the top so content clears the camera; this also extends the
            // tray up into the notch region.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: metrics.notchHeight)
            }
            // Pin the tray to its intrinsic size, fill solid black (so the physical notch is absorbed
            // into the tray), then clip to the notch shape. Sizing happens before the centering frame
            // so the black hugs the content instead of filling the whole overlay window.
            .frame(width: metrics.bodyWidth, height: metrics.notchHeight + metrics.bodyHeight)
            .background(Color.black)
            .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -10)
            .animation(.spring(duration: 0.34, bounce: 0.12), value: isVisible)
            .onAppear { isVisible = true }
    }

    @ViewBuilder
    private var listContent: some View {
        if appState.items.isEmpty {
            EmptyStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(appState.items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemRow(
                                item: item,
                                isHighlighted: index == appState.selectedIndex
                            )
                            .id(item.id)
                            .opacity(isVisible ? 1 : 0)
                            .animation(
                                .easeOut(duration: 0.25)
                                    .delay(Double(min(index, 8)) * 0.02),
                                value: isVisible
                            )
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 10)
                }
                .onChange(of: appState.selectedIndex) { _, newValue in
                    if let item = appState.items[safe: newValue] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

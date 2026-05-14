import SwiftUI

struct DrawerView: View {
    var appState: AppState
    let notchInset: CGFloat
    @State private var isVisible: Bool = false

    private let drawerWidth: CGFloat = ScreenUtilities.drawerWidth

    private let bottomRadius: CGFloat = 22

    private var drawerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, notchInset))

            if appState.items.isEmpty {
                EmptyStateView()
                    .padding(.vertical, 8)
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
        .frame(width: drawerWidth)
        .background {
            ZStack {
                drawerShape
                    .fill(.ultraThinMaterial)
                drawerShape
                    .fill(Color.black.opacity(0.58))
            }
            .shadow(color: .black.opacity(0.55), radius: 48, y: 28)
        }
        .clipShape(drawerShape)
        .ignoresSafeArea(.container, edges: .top)
        .offset(y: isVisible ? 0 : -36)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(duration: 0.38, bounce: 0.11), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

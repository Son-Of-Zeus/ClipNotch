import SwiftUI

struct DrawerView: View {
    var appState: AppState
    let isDegraded: Bool
    let notchInset: CGFloat
    @State private var isVisible: Bool = false

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
            Spacer()
                .frame(height: notchInset)

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
                        .padding(.horizontal, 6)
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

            if isDegraded {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 9))
                    Text("Enable Accessibility for hold-to-paste")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.35))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 340)
        .background(
            drawerShape
                .fill(.black)
                .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
        )
        .clipShape(drawerShape)
        .offset(y: isVisible ? 0 : -30)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(duration: 0.35, bounce: 0.12), value: isVisible)
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

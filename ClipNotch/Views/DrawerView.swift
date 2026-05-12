import SwiftUI

struct DrawerView: View {
    var appState: AppState
    let isDegraded: Bool
    let notchInset: CGFloat
    @State private var isVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: notchInset)

            if appState.items.isEmpty {
                EmptyStateView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(appState.items.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemRow(
                                    item: item,
                                    isHighlighted: index == appState.selectedIndex
                                )
                                .id(item.id)
                                .opacity(isVisible ? 1 : 0)
                                .animation(
                                    .easeOut(duration: 0.2)
                                        .delay(Double(min(index, 5)) * 0.01),
                                    value: isVisible
                                )
                            }
                        }
                        .padding(.vertical, 8)
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
                Text("Enable Accessibility for hold-to-paste mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)))
            }
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)))
                .shadow(color: .black.opacity(0.8), radius: 30, y: 20)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .offset(y: isVisible ? 0 : -20)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.28), value: isVisible)
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

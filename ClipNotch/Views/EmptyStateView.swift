import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image("ClipboardEmpty")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 64)
                .accessibilityHidden(true)

            Text("Copy something to get started")
                .font(ClipNotchTypography.label)
                .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

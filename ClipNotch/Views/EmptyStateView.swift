import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(ClipNotchDesign.drawerTertiaryText)

            Text("Copy something to get started")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipNotchDesign.drawerSecondaryText)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

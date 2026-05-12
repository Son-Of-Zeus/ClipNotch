import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24))
                .foregroundStyle(.primary.opacity(0.3))

            Text("Copy something to get started")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.4))
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

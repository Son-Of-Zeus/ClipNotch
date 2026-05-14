import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.2))

            Text("Copy something to get started")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

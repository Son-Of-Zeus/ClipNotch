import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHighlighted ? .white : .white.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHighlighted
                              ? Color.accentColor.opacity(0.8)
                              : Color.white.opacity(0.06))
                )

            Text(item.preview)
                .font(.system(size: 12.5, weight: isHighlighted ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isHighlighted ? .white : .white.opacity(0.75))

            Spacer(minLength: 4)

            Text(item.relativeTimestamp)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted
                      ? Color.white.opacity(0.1)
                      : Color.clear)
        )
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
    }
}

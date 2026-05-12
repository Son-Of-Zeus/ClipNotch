import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
                .frame(width: 3)

            Image(systemName: item.contentType.iconName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(item.preview)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer()

            Text(item.relativeTimestamp)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.1), value: isHighlighted)
    }
}

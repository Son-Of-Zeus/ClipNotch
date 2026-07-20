import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHighlighted ? ClipNotchDesign.drawerText : ClipNotchDesign.drawerSecondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHighlighted ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl)
                )

            Text(item.preview)
                .font(.system(size: 12.5, weight: isHighlighted ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isHighlighted ? ClipNotchDesign.drawerText : ClipNotchDesign.drawerText.opacity(0.78))

            Spacer(minLength: 4)

            Text(item.relativeTimestamp)
                .font(.system(size: 10))
                .foregroundStyle(ClipNotchDesign.drawerTertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? ClipNotchDesign.drawerSelection : Color.clear)
        )
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: isHighlighted)
    }
}

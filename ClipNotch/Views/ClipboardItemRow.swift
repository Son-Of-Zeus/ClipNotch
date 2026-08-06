import AppKit
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            leadingBadge

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

    @ViewBuilder
    private var leadingBadge: some View {
        if item.contentType == .image,
           let thumbnailPath = item.thumbnailPath,
           let thumbnail = NSImage(contentsOfFile: thumbnailPath) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            isHighlighted ? Color.white.opacity(0.28) : Color.clear,
                            lineWidth: 0.5
                        )
                }
        } else if item.contentType == .image {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHighlighted ? ClipNotchDesign.drawerText : ClipNotchDesign.drawerSecondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHighlighted ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl)
                )
        }
    }
}

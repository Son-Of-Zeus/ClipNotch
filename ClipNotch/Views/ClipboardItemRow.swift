import AppKit
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardSummary
    let isHighlighted: Bool
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            leadingBadge

            Text(item.preview)
                .font(isHighlighted ? ClipNotchTypography.label : ClipNotchTypography.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isHighlighted ? ClipNotchDesign.drawerText : ClipNotchDesign.drawerText.opacity(0.78))

            Spacer(minLength: 4)

            Text(item.relativeTimestamp)
                .font(ClipNotchTypography.footnote)
                .foregroundStyle(ClipNotchDesign.drawerTertiaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(height: 42)
        .background(Rectangle().fill(isHighlighted ? ClipNotchDesign.drawerSelection : Color.clear))
        .overlay(Rectangle().strokeBorder(isHighlighted && contrast == .increased ? ClipNotchDesign.accent : .clear, lineWidth: 2))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: isHighlighted)
        .task(id: item.id) {
            guard item.kind == .image else { return }
            thumbnail = await appState.thumbnail(for: item.id)
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        if let thumbnail {
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
        } else if item.kind == .image {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: item.kind.iconName)
                .font(ClipNotchTypography.captionLabel)
                .foregroundStyle(isHighlighted ? ClipNotchDesign.drawerText : ClipNotchDesign.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHighlighted ? ClipNotchDesign.drawerSelectionIcon : ClipNotchDesign.drawerControl)
                )
        }
    }
}

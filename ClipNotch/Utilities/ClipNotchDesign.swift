import AppKit
import SwiftUI

/// Semantic colors shared by the app. AppKit supplies their light/dark variants.
enum ClipNotchDesign {
    // MARK: App surfaces

    static let windowBackground = Color(nsColor: .textBackgroundColor)
    static let groupedBackground = Color(nsColor: .controlBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    static let accent = Color.accentColor
    static let accentSurface = Color.accentColor.opacity(0.12)
    static let cardRadius: CGFloat = 14
    static let menuBarSymbol = "doc.on.clipboard"

    // MARK: Drawer

    static let drawerBackground = Color.black
    static let drawerText = Color.white.opacity(0.92)
    static let drawerSecondaryText = Color.white.opacity(0.74)
    static let drawerTertiaryText = Color.white.opacity(0.60)
    static let drawerControl = Color.white.opacity(0.07)
    static let drawerSelection = Color.accentColor.opacity(0.28)
    static let drawerSelectionIcon = Color.accentColor.opacity(0.32)
    static let drawerBorder = Color.white.opacity(0.18)
}

struct ClipNotchWindowSurface: View {
    var body: some View {
        ClipNotchDesign.windowBackground
            .overlay {
                LinearGradient(colors: [ClipNotchDesign.accent.opacity(0.055), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
    }
}

struct ClipNotchButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, icon }
    var kind: Kind = .secondary

    init(_ kind: Kind = .secondary) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, kind: kind)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.controlSize) private var controlSize
        @State private var isHovered = false

        private var color: Color { configuration.role == .destructive ? Color(nsColor: .systemRed) : ClipNotchDesign.accent }
        private var height: CGFloat { controlSize == .large ? 42 : controlSize == .small ? 30 : 36 }
        private var foreground: Color {
            if kind == .primary {
                let background = (configuration.role == .destructive ? NSColor.systemRed : NSColor.controlAccentColor)
                    .usingColorSpace(.sRGB)!
                let channels = [background.redComponent, background.greenComponent, background.blueComponent].map {
                    $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                }
                let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
                return luminance > 0.179 ? .black : .white
            }
            return configuration.role == .destructive ? color : ClipNotchDesign.label
        }
        private var fill: Color {
            switch kind {
            case .primary: color.opacity(configuration.isPressed ? 0.80 : isHovered ? 0.90 : 1)
            case .secondary: color.opacity(configuration.isPressed ? 0.20 : isHovered ? 0.16 : 0.10)
            case .quiet, .icon: color.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.09 : 0)
            }
        }

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .icon ? 0 : 14)
                .frame(minWidth: kind == .icon ? height : nil, minHeight: height)
                .background(fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(color.opacity(isFocused ? 1 : kind == .secondary ? 0.22 : 0), lineWidth: isFocused || contrast == .increased ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .onHover { isHovered = $0 }
                .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: isHovered)
                .animation(ClipNotchMotion.standard(reduceMotion: reduceMotion), value: configuration.isPressed)
        }
    }
}

struct ClipNotchTextFieldStyle: TextFieldStyle {
    @Environment(\.isFocused) private var isFocused

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFocused ? ClipNotchDesign.accent : ClipNotchDesign.accent.opacity(0.18)))
    }
}

enum ClipNotchWindowChrome {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
    }
}

struct ClipNotchWindowHeader: View {
    let detail: String
    var canMinimize = false
    var canResize = false
    @State private var window = WindowReference()

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 5) {
                windowButton("xmark", label: "Close window", color: .red) { window.value?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
                if canMinimize {
                    windowButton("minus", label: "Minimize window", color: .yellow) { window.value?.miniaturize(nil) }
                        .keyboardShortcut("m", modifiers: .command)
                }
                if canResize {
                    windowButton("arrow.up.left.and.arrow.down.right", label: "Zoom window", color: .green) { window.value?.zoom(nil) }
                }
            }
            Label("ClipNotch", systemImage: ClipNotchDesign.menuBarSymbol)
                .font(ClipNotchTypography.label)
            Spacer()
            Text(detail).font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(WindowDragRegion(reference: window))
    }

    private func windowButton(_ symbol: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.black.opacity(0.65))
                .frame(width: 13, height: 13)
                .background(color, in: Circle())
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private final class WindowReference {
    weak var value: NSWindow?
}

private struct WindowDragRegion: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> DragView { DragView(reference: reference) }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        let reference: WindowReference

        init(reference: WindowReference) {
            self.reference = reference
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { reference.value = window }
        override func hitTest(_ point: NSPoint) -> NSView? {
            point.x < 100 ? nil : super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// Shared San Francisco text styles for every app surface.
enum ClipNotchTypography {
    static let display = Font.system(size: 28, weight: .bold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let label = Font.system(size: 13, weight: .medium)
    static let button = Font.system(size: 12, weight: .semibold)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let captionLabel = Font.system(size: 11, weight: .medium)
    static let footnote = Font.system(size: 11)
    static let shortcut = Font.system(size: 12, weight: .medium, design: .monospaced)
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: ClipNotchDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipNotchDesign.cardRadius)
                    .stroke(ClipNotchDesign.separator, lineWidth: contrast == .increased ? 1.5 : 0.5)
            }
    }
}

struct AccentIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(ClipNotchDesign.accent)
            .frame(width: 42, height: 42)
            .background(ClipNotchDesign.accentSurface, in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }
}

/// Short, consistent motion that respects the system Reduce Motion preference.
enum ClipNotchMotion {
    static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22)
    }

    static func emphasis(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.32, bounce: 0.10)
    }

    static func drawer(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(duration: 0.34, bounce: 0.12)
    }
}

import AppKit
import SwiftUI
import OracleControllerShared

enum ControllerTheme {
    static let accent = Color(red: 0.05, green: 0.43, blue: 0.80)
    static let canvas = Color(nsColor: NSColor.windowBackgroundColor)
    static let panel = Color.white.opacity(0.78)
    static let border = Color.black.opacity(0.08)
    static let success = Color(red: 0.16, green: 0.55, blue: 0.35)
    static let warning = Color(red: 0.82, green: 0.52, blue: 0.11)
    static let danger = Color(red: 0.76, green: 0.19, blue: 0.18)
    static let muted = Color.secondary
    
    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
    }
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    
    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ControllerTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        )
    }
}

struct StatusBadge: View {
    let label: String
    let tone: Tone

    enum Tone {
        case good
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .good: return ControllerTheme.success
            case .warning: return ControllerTheme.warning
            case .danger: return ControllerTheme.danger
            case .neutral: return ControllerTheme.accent
            }
        }

        init(_ string: String) {
            switch string {
            case "good": self = .good
            case "warning": self = .warning
            case "danger": self = .danger
            default: self = .neutral
            }
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.color.opacity(0.14), in: Capsule())
            .foregroundStyle(tone.color)
    }
}

struct KVRow: View {
    let key: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .foregroundStyle(ControllerTheme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ControllerTheme.accent)
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(ControllerTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct ScreenshotPreview: View {
    let screenshot: ScreenshotFrame?

    private static let imageCache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image = screenshotImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
            } else {
                EmptyStateView(
                    systemImage: "display",
                    title: "No Snapshot",
                    message: "Refresh the monitor to capture a live screenshot of the selected app."
                )
            }
        }
    }

    private var screenshotImage: NSImage? {
        guard let screenshot
        else {
            return nil
        }

        let cacheKey = NSString(string: "\(screenshot.width)x\(screenshot.height)-\(screenshot.base64PNG.prefix(64))")
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let data = Data(base64Encoded: screenshot.base64PNG),
              let image = NSImage(data: data)
        else {
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: phase - 0.5),
                            .init(color: .white.opacity(0.3), location: phase),
                            .init(color: .clear, location: phase + 0.5),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.overlay)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 2
                        }
                    }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

struct PulseEffect: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.05 : 1.0)
            .opacity(isAnimating ? 0.8 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseEffect())
    }
}

struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    
    init(gradient: LinearGradient = LinearGradient(
        colors: [ControllerTheme.accent, ControllerTheme.accent.opacity(0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )) {
        self.gradient = gradient
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GlassCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: title != nil ? 12 : 0) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

struct AnimatedCounter: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring, value: value)
            
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusIndicator: View {
    let isActive: Bool
    let size: CGFloat
    
    init(isActive: Bool, size: CGFloat = 8) {
        self.isActive = isActive
        self.size = size
    }
    
    var body: some View {
        Circle()
            .fill(isActive ? ControllerTheme.success : ControllerTheme.muted)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .fill(isActive ? ControllerTheme.success.opacity(0.3) : .clear)
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(isActive ? 1 : 0)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: isActive
                    )
            )
    }
}

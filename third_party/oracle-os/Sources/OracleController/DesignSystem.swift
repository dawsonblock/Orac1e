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

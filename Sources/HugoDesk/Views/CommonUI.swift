import SwiftUI

struct ModernCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        let surfaceTop = colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.90)
        let surfaceBottom = colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.78)
        let strokeTop = colorScheme == .dark ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.35)
        let strokeBottom = colorScheme == .dark ? Color.white.opacity(0.08) : Color.primary.opacity(0.10)
        let shadowColor = colorScheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.06)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [surfaceTop, surfaceBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [strokeTop, strokeBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: shadowColor, radius: 10, x: 0, y: 4)
    }
}

struct ScopeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct SettingRow<Content: View>: View {
    let key: String
    let title: String
    let helpText: String
    let scope: String
    @ViewBuilder var field: Content

    init(
        key: String,
        title: String,
        helpText: String,
        scope: String,
        @ViewBuilder field: () -> Content
    ) {
        self.key = key
        self.title = title
        self.helpText = helpText
        self.scope = scope
        self.field = field()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                field
                    .frame(width: 420, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                field
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.body)
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(helpText)
            }
            HStack(spacing: 8) {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                ScopeBadge(text: scope)
            }
        }
    }
}

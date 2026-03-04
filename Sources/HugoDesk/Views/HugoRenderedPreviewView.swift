import SwiftUI
import WebKit

struct HugoRenderedPreviewView: View {
    let project: BlogProject
    let postFileURL: URL
    let refreshToken: Int
    let markdownSource: String

    @State private var resolvedHTMLURL: URL?
    @State private var fallbackMarkdown: AttributedString = AttributedString("")

    var body: some View {
        Group {
            if let resolvedHTMLURL {
                HugoRenderedWebView(
                    fileURL: resolvedHTMLURL,
                    readAccessURL: project.rootURL.appendingPathComponent("public", isDirectory: true),
                    refreshToken: refreshToken
                )
            } else {
                MarkdownFallbackPreviewView(
                    markdown: fallbackMarkdown,
                    candidates: project.renderedHTMLCandidates(for: postFileURL)
                )
            }
        }
        .onAppear {
            reload()
            reloadFallbackMarkdown()
        }
        .onChange(of: refreshToken) { _ in
            reload()
        }
        .onChange(of: postFileURL.path) { _ in
            reload()
            reloadFallbackMarkdown()
        }
        .onChange(of: markdownSource) { _ in
            reloadFallbackMarkdown()
        }
    }

    private func reload() {
        let fm = FileManager.default
        resolvedHTMLURL = project
            .renderedHTMLCandidates(for: postFileURL)
            .first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func reloadFallbackMarkdown() {
        let source = markdownSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            fallbackMarkdown = AttributedString("正文为空，暂无可预览内容。")
            return
        }

        do {
            fallbackMarkdown = try AttributedString(
                markdown: source,
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            fallbackMarkdown = AttributedString(source)
        }
    }
}

private struct HugoRenderedWebView: NSViewRepresentable {
    let fileURL: URL
    let readAccessURL: URL
    let refreshToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        load(fileURL, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != fileURL || context.coordinator.lastRefreshToken != refreshToken {
            load(fileURL, in: nsView, coordinator: context.coordinator)
        }
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastLoadedURL = url
        coordinator.lastRefreshToken = refreshToken
        webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
    }

    final class Coordinator {
        var lastLoadedURL: URL?
        var lastRefreshToken: Int = -1
    }
}

private struct MarkdownFallbackPreviewView: View {
    let markdown: AttributedString
    let candidates: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已启用内置 Markdown 预览（即时）")
                .font(.subheadline.weight(.semibold))
            Text("未定位到 Hugo 最终页面时，将自动显示此预览。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if !candidates.isEmpty {
                Divider()
                Text("Hugo 渲染页面候选路径")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(candidates, id: \.path) { candidate in
                    Text(candidate.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

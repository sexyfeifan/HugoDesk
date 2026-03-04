import SwiftUI
import WebKit

struct HugoRenderedPreviewView: View {
    let project: BlogProject
    let postFileURL: URL
    let refreshToken: Int

    @State private var resolvedHTMLURL: URL?

    var body: some View {
        Group {
            if let resolvedHTMLURL {
                HugoRenderedWebView(fileURL: resolvedHTMLURL, refreshToken: refreshToken)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未找到最终渲染页面。")
                        .font(.headline)
                    Text("请点击“刷新最终预览（构建）”后重试。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(project.renderedHTMLCandidates(for: postFileURL), id: \.path) { candidate in
                        Text(candidate.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: refreshToken) { _ in
            reload()
        }
        .onChange(of: postFileURL.path) { _ in
            reload()
        }
    }

    private func reload() {
        let fm = FileManager.default
        resolvedHTMLURL = project
            .renderedHTMLCandidates(for: postFileURL)
            .first(where: { fm.fileExists(atPath: $0.path) })
    }
}

private struct HugoRenderedWebView: NSViewRepresentable {
    let fileURL: URL
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
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    final class Coordinator {
        var lastLoadedURL: URL?
        var lastRefreshToken: Int = -1
    }
}

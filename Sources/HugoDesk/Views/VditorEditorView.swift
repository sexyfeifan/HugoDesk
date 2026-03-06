import SwiftUI
import WebKit

@MainActor
final class VditorEditorBridge: ObservableObject {
    fileprivate var focusHandler: (() -> Void)?
    fileprivate var rememberSelectionHandler: (() -> Void)?
    fileprivate var insertMarkdownHandler: ((String) -> Void)?
    fileprivate var reloadHandler: (() -> Void)?

    func focus() {
        focusHandler?()
    }

    func rememberSelection() {
        rememberSelectionHandler?()
    }

    func insertMarkdown(_ markdown: String) {
        insertMarkdownHandler?(markdown)
    }

    func reload() {
        reloadHandler?()
    }
}

struct VditorEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var statusMessage: String

    let bridge: VditorEditorBridge
    var onRequestImageImport: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "vditor")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView
        context.coordinator.configureBridge()
        context.coordinator.loadEditorHTML()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureBridge()
        context.coordinator.syncTextToEditorIfNeeded(force: false)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.parent.bridge.focusHandler = nil
        coordinator.parent.bridge.rememberSelectionHandler = nil
        coordinator.parent.bridge.insertMarkdownHandler = nil
        coordinator.parent.bridge.reloadHandler = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "vditor")
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: VditorEditorView
        weak var webView: WKWebView?

        private var lastKnownText = ""
        private var isReady = false

        init(parent: VditorEditorView) {
            self.parent = parent
        }

        func configureBridge() {
            parent.bridge.focusHandler = { [weak self] in
                self?.focusEditor()
            }
            parent.bridge.rememberSelectionHandler = { [weak self] in
                self?.rememberSelection()
            }
            parent.bridge.insertMarkdownHandler = { [weak self] markdown in
                self?.insertMarkdown(markdown)
            }
            parent.bridge.reloadHandler = { [weak self] in
                self?.loadEditorHTML()
            }
        }

        func loadEditorHTML() {
            guard let webView else { return }
            guard let url = Bundle.module.url(forResource: "vditor", withExtension: "html") else {
                parent.statusMessage = "未找到 Vditor 编辑器资源。"
                return
            }

            isReady = false
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "vditor",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            let value = body["value"] as? String ?? ""
            switch type {
            case "ready":
                isReady = true
                parent.statusMessage = "Vditor 编辑器已就绪。"
                syncTextToEditorIfNeeded(force: true)
            case "input":
                lastKnownText = value
                if parent.text != value {
                    parent.text = value
                }
            case "pickImage":
                parent.onRequestImageImport()
            case "error":
                parent.statusMessage = value
            default:
                break
            }
        }

        func syncTextToEditorIfNeeded(force: Bool) {
            guard isReady, let webView else { return }
            guard force || lastKnownText != parent.text else { return }

            let next = parent.text
            lastKnownText = next
            let script = "window.HugoDeskVditorBridge && window.HugoDeskVditorBridge.setValue(\(quotedJavaScriptString(next)));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func focusEditor() {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.HugoDeskVditorBridge && window.HugoDeskVditorBridge.focus();", completionHandler: nil)
        }

        private func rememberSelection() {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.HugoDeskVditorBridge && window.HugoDeskVditorBridge.rememberSelection();", completionHandler: nil)
        }

        private func insertMarkdown(_ markdown: String) {
            guard isReady, let webView else { return }
            let script = "window.HugoDeskVditorBridge && window.HugoDeskVditorBridge.insertMarkdown(\(quotedJavaScriptString(markdown)));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func quotedJavaScriptString(_ value: String) -> String {
            if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
               let json = String(data: data, encoding: .utf8),
               json.count >= 2 {
                return String(json.dropFirst().dropLast())
            }
            return "\"\""
        }
    }
}

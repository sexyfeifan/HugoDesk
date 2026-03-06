import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: AppViewModel

    @StateObject private var vditorBridge = VditorEditorBridge()
    @SceneStorage("editor.columnVisibility") private var columnVisibilityRawValue = NavigationSplitViewVisibility.all.storageKey
    @State private var tagsInput = ""
    @State private var categoriesInput = ""
    @State private var keywordsInput = ""
    @State private var imageAltText = ""
    @State private var showDeleteConfirm = false
    @State private var showingAIWritingSheet = false
    @State private var aiWritingSourceText = ""
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var imageInsertMode: ImageInsertMode = .cursor
    @State private var editorImplementation: EditorImplementation = .vditor

    var body: some View {
        NavigationSplitView(columnVisibility: editorColumnVisibility) {
            List(selection: $viewModel.selectedPostID) {
                ForEach(viewModel.posts) { post in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.title.isEmpty ? post.fileName : post.title)
                            .font(.headline)
                        Text(post.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(post.id)
                    .contextMenu {
                        Button("删除这篇文章", role: .destructive) {
                            selectAndDelete(post)
                        }
                    }
                }
            }
            .navigationTitle("文章")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .onChange(of: viewModel.selectedPostID) { _ in
                viewModel.loadSelectedPost()
                viewModel.cancelLivePreviewRefresh()
                editorSelection = NSRange(location: 0, length: 0)
                refreshInputsFromPost()
            }
        } detail: {
            ScrollView {
                VStack(spacing: 14) {
                    ModernCard(title: "新建文章", subtitle: "支持自定义文件名（默认拼音 slug）") {
                        VStack(spacing: 10) {
                            HStack {
                                TextField("文章标题（例如：你好世界）", text: $viewModel.newPostTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: viewModel.newPostTitle) { _ in
                                        viewModel.updateSuggestedFileName()
                                    }
                                Button("按标题生成文件名") {
                                    viewModel.updateSuggestedFileName()
                                }
                            }
                            HStack {
                                TextField("文件名（例如：hello-world.md）", text: $viewModel.newPostFileName)
                                    .textFieldStyle(.roundedBorder)
                                Button("创建文章") {
                                    viewModel.createPostFromForm()
                                    editorSelection = NSRange(location: 0, length: 0)
                                    refreshInputsFromPost()
                                }
                            }
                            Text("建议文件名使用英文或拼音并用 - 连接。若重名会自动追加序号。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ModernCard(title: "文章元数据", subtitle: "Front Matter") {
                        VStack(spacing: 10) {
                            HStack {
                                TextField("标题", text: $viewModel.editorPost.title)
                                    .font(.title3)
                                Button("获取标题") {
                                    viewModel.updateTitleFromFileName()
                                }
                                DatePicker("", selection: $viewModel.editorPost.date, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                Toggle("草稿", isOn: $viewModel.editorPost.draft)
                                    .toggleStyle(.switch)
                            }

                            HStack {
                                TextField("摘要", text: $viewModel.editorPost.summary)
                                Button("获取摘要") {
                                    viewModel.updateSummaryFromBody()
                                }
                                Picker("编辑模式", selection: $viewModel.editorMode) {
                                    ForEach(EditorMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            HStack {
                                TextField("标签（逗号分隔）", text: $tagsInput)
                                TextField("分类（逗号分隔）", text: $categoriesInput)
                                TextField("关键词（逗号分隔）", text: $keywordsInput)
                            }

                            HStack {
                                Toggle("置顶", isOn: $viewModel.editorPost.pin)
                                Toggle("KaTeX", isOn: $viewModel.editorPost.math)
                                Toggle("MathJax", isOn: $viewModel.editorPost.mathJax)
                                Toggle("私有", isOn: $viewModel.editorPost.isPrivate)
                                Toggle("可搜索", isOn: $viewModel.editorPost.searchable)
                            }
                        }
                    }

                    ModernCard(title: "AI 写作", subtitle: "读取素材与链接，生成可追加到正文的 Markdown") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("保留在原来的编辑区域位置，独立运行，不再隶属文本工具。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("支持文字、链接，或文字 + 链接混合素材。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Button("打开 AI 写作") {
                                    openAIWritingSheet()
                                }
                                .buttonStyle(.borderedProminent)

                                Spacer()
                            }

                            if viewModel.isAIFormatting {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: viewModel.aiFormattingProgress)
                                        .progressViewStyle(.linear)
                                    Text(viewModel.aiFormattingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    ModernCard(title: "正文编辑", subtitle: "新编辑器已内置预览与格式工具") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("编辑器", selection: $editorImplementation) {
                                    ForEach(EditorImplementation.allCases) { implementation in
                                        Text(implementation.rawValue).tag(implementation)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)

                                TextField("图片 alt 文本", text: $imageAltText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 180)

                                if editorImplementation == .native {
                                    Picker("插入位置", selection: $imageInsertMode) {
                                        ForEach(availableImageInsertModes) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                }

                                Button(editorImplementation == .native ? "上传并插入图片" : "选择图片并插入当前光标") {
                                    importImageFromPanel()
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }

                            if editorImplementation == .vditor {
                                Text("Vditor 已作为默认编辑器启用；如遇兼容问题，可临时切回兼容模式。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("预览、分栏、代码主题等功能请直接使用编辑器顶部工具栏和 More 菜单。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("兼容模式不再提供旧的内嵌预览切换，仅用于保留原生文本编辑能力。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if editorImplementation == .vditor {
                                VditorEditorView(
                                    text: $viewModel.editorPost.body,
                                    statusMessage: $viewModel.statusText,
                                    bridge: vditorBridge,
                                    onRequestImageImport: importImageFromPanel
                                )
                                .frame(minHeight: 540)
                                .background(Color.black.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                MarkdownTextEditor(
                                    text: $viewModel.editorPost.body,
                                    selection: $editorSelection,
                                    onMenuAction: applyMarkdownAction
                                )
                                .frame(minHeight: 540)
                                .background(Color.black.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    HStack {
                        Button("保存文章") {
                            applyInputsToPost()
                            viewModel.saveCurrentPost()
                        }
                        Button("保存并构建预览") {
                            applyInputsToPost()
                            viewModel.saveCurrentPost()
                            viewModel.runBuild()
                        }
                        Button("删除当前文章", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        Spacer()
                        Text(viewModel.editorPost.fileURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                refreshInputsFromPost()
            }
            .onDisappear {
                viewModel.cancelLivePreviewRefresh()
            }
            .onChange(of: editorImplementation) { _ in
                editorSelection = NSRange(location: 0, length: 0)
                if editorImplementation == .vditor {
                    vditorBridge.focus()
                }
            }
            .alert("确认删除这篇文章？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    viewModel.deleteCurrentPost()
                    viewModel.cancelLivePreviewRefresh()
                    editorSelection = NSRange(location: 0, length: 0)
                    refreshInputsFromPost()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(viewModel.editorPost.fileName)
            }
            .sheet(isPresented: $showingAIWritingSheet) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI 写作")
                                .font(.headline)
                            Text("可粘贴文字、链接，或文字 + 链接混合素材。HugoDesk 会读取可访问链接，并把模型返回的 Markdown 追加到正文编辑器。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("关闭") {
                            if !viewModel.isAIFormatting {
                                showingAIWritingSheet = false
                            }
                        }
                        .disabled(viewModel.isAIFormatting)
                    }

                    TextEditor(text: $aiWritingSourceText)
                        .font(.body.monospaced())
                        .frame(minHeight: 260)
                        .padding(8)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if viewModel.isAIFormatting {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: viewModel.aiFormattingProgress)
                                .progressViewStyle(.linear)
                            Text(viewModel.aiFormattingStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("粘贴剪贴板") {
                            pasteAIWritingSourceFromClipboard()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("取消") {
                            showingAIWritingSheet = false
                        }
                        .disabled(viewModel.isAIFormatting)

                        Button("开始生成") {
                            runAIWriting()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(aiWritingSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAIFormatting)
                    }
                }
                .padding(16)
                .frame(minWidth: 760, minHeight: 430)
            }
        }
    }

    private func refreshInputsFromPost() {
        tagsInput = viewModel.editorPost.tags.joined(separator: ", ")
        categoriesInput = viewModel.editorPost.categories.joined(separator: ", ")
        keywordsInput = viewModel.editorPost.keywords.joined(separator: ", ")
    }

    private func applyInputsToPost() {
        viewModel.editorPost.tags = splitCSV(tagsInput)
        viewModel.editorPost.categories = splitCSV(categoriesInput)
        viewModel.editorPost.keywords = splitCSV(keywordsInput)
    }

    private func splitCSV(_ input: String) -> [String] {
        input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func applyMarkdownAction(_ action: MarkdownAction) {
        let result = MarkdownEditing.apply(action: action, to: viewModel.editorPost.body, selection: editorSelection)
        viewModel.editorPost.body = result.text
        editorSelection = result.selection
    }

    private func targetImageInsertionRange() -> NSRange? {
        switch imageInsertMode {
        case .cursor:
            return NSRange(location: editorSelection.location, length: 0)
        case .selection:
            return editorSelection
        case .appendToEnd:
            return NSRange(location: (viewModel.editorPost.body as NSString).length, length: 0)
        }
    }

    private func importImageFromPanel() {
        guard let imageURL = pickImage() else { return }

        if editorImplementation == .native {
            let next = viewModel.importImageIntoPost(
                from: imageURL,
                altText: imageAltText,
                insertionRange: targetImageInsertionRange()
            )
            editorSelection = next
            return
        }

        do {
            vditorBridge.rememberSelection()
            let snippet = try viewModel.makeImportedImageMarkdown(from: imageURL, altText: imageAltText)
            vditorBridge.insertMarkdown(snippet)
            vditorBridge.focus()
        } catch {
            viewModel.statusText = error.localizedDescription
        }
    }

    private func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
        panel.prompt = "选择"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func selectAndDelete(_ post: BlogPost) {
        viewModel.selectedPostID = post.id
        viewModel.loadSelectedPost()
        viewModel.deleteCurrentPost()
        editorSelection = NSRange(location: 0, length: 0)
        refreshInputsFromPost()
    }

    private func openAIWritingSheet() {
        if editorImplementation == .vditor {
            vditorBridge.rememberSelection()
        }
        showingAIWritingSheet = true
    }

    private func runAIWriting() {
        let source = aiWritingSourceText
        viewModel.generateWritingWithAI(sourceInput: source) { generated in
            let snippet = normalizedAIWritingSnippet(generated)
            guard !snippet.isEmpty else { return }

            if editorImplementation == .vditor {
                vditorBridge.insertMarkdown(snippet)
                vditorBridge.focus()
            } else {
                let insertionPoint = max(0, editorSelection.location + editorSelection.length)
                let next = viewModel.insertPostSnippet(snippet, at: NSRange(location: insertionPoint, length: 0))
                editorSelection = next
            }

            aiWritingSourceText = ""
            showingAIWritingSheet = false
        }
    }

    private func pasteAIWritingSourceFromClipboard() {
        if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
            aiWritingSourceText = pasted
        }
    }

    private func normalizedAIWritingSnippet(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed + "\n"
    }

    private var availableImageInsertModes: [ImageInsertMode] {
        editorImplementation == .native ? ImageInsertMode.allCases : [.appendToEnd]
    }

    private var editorColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { NavigationSplitViewVisibility(storedValue: columnVisibilityRawValue) },
            set: { columnVisibilityRawValue = $0.storageKey }
        )
    }
}

private enum ImageInsertMode: String, CaseIterable, Identifiable {
    case cursor = "光标位置"
    case selection = "替换选区"
    case appendToEnd = "追加到文末"

    var id: String { rawValue }
}

private enum EditorImplementation: String, CaseIterable, Identifiable {
    case vditor = "Vditor 编辑器"
    case native = "兼容模式"

    var id: String { rawValue }
}

private extension NavigationSplitViewVisibility {
    init(storedValue: String) {
        switch storedValue {
        case Self.automatic.storageKey:
            self = .automatic
        case Self.doubleColumn.storageKey:
            self = .doubleColumn
        case Self.detailOnly.storageKey:
            self = .detailOnly
        default:
            self = .all
        }
    }

    var storageKey: String {
        if self == .automatic {
            return "automatic"
        }
        if self == .all {
            return "all"
        }
        if self == .doubleColumn {
            return "doubleColumn"
        }
        if self == .detailOnly {
            return "detailOnly"
        }
        return "all"
    }
}

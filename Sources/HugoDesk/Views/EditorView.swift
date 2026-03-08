import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: AppViewModel

    @StateObject private var vditorBridge = VditorEditorBridge()
    @SceneStorage("editor.columnVisibility") private var columnVisibilityRawValue = NavigationSplitViewVisibility.all.storageKey
    @State private var tagsInput = ""
    @State private var categoriesInput = ""
    @State private var keywordsInput = ""
    @State private var aliasesInput = ""
    @State private var dynamicTaxonomyInputs: [String: String] = [:]
    @State private var imageAltText = ""
    @State private var showDeleteConfirm = false
    @State private var showingAIWritingSheet = false
    @State private var aiWritingSourceText = ""
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var imageInsertMode: ImageInsertMode = .cursor
    @State private var editorImplementation: EditorImplementation = .vditor
    @State private var selectedWorkspacePickerCode = ""
    @State private var selectedTranslationWorkspaceCode = ""
    @State private var selectedReferenceID = ""
    @State private var referenceAnchor = ""
    @State private var referenceUsesRelref = true
    @State private var selectedShortcodeID = ""
    @State private var shortcodeParameters = ""
    @State private var shortcodeParameterValues: [String: String] = [:]
    @State private var shortcodeIsBlock = false
    @State private var selectedResourceID = ""
    @State private var resourceRelativePathDraft = ""
    @State private var inspectorPanel: EditorInspectorPanel = .basic

    var body: some View {
        NavigationSplitView(columnVisibility: editorColumnVisibility) {
            List {
                if sidebarRoots.isEmpty {
                    Text("当前内容目录还没有文章。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(sidebarRoots, children: \.childNodes) { node in
                        sidebarRow(for: node)
                            .contextMenu {
                                if let post = node.post {
                                    Button("删除这篇内容", role: .destructive) {
                                        selectAndDelete(post)
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle("内容")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
            .onChange(of: viewModel.selectedPostID) { _ in
                viewModel.loadSelectedPost()
                viewModel.cancelLivePreviewRefresh()
                editorSelection = NSRange(location: 0, length: 0)
                refreshInputsFromPost()
            }
        } detail: {
            detailView
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
                .onChange(of: viewModel.newPostTitle) { _ in
                    viewModel.updateSuggestedFileName()
                }
                .onChange(of: viewModel.newPostCreationMode) { _ in
                    viewModel.updateSuggestedFileName()
                }
                .onChange(of: viewModel.frontMatterEditorMode) { mode in
                    if mode == .raw {
                        applyInputsToPost()
                        viewModel.syncRawFrontMatterFromStructured()
                    } else {
                        viewModel.syncStructuredFieldsFromRaw()
                        refreshInputsFromPost()
                    }
                }
                .onChange(of: viewModel.editorPost.frontMatterFormat) { _ in
                    if viewModel.frontMatterEditorMode == .raw {
                        viewModel.syncRawFrontMatterFromStructured()
                    }
                }
                .onChange(of: viewModel.languageWorkspaces) { _ in
                    syncAuxiliarySelections()
                }
                .onChange(of: viewModel.availableShortcodes) { _ in
                    syncAuxiliarySelections()
                }
                .alert("确认删除这篇内容？", isPresented: $showDeleteConfirm) {
                    Button("删除", role: .destructive) {
                        viewModel.deleteCurrentPost()
                        viewModel.cancelLivePreviewRefresh()
                        editorSelection = NSRange(location: 0, length: 0)
                        refreshInputsFromPost()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(viewModel.editorPost.displayFileName)
                }
                .sheet(isPresented: $showingAIWritingSheet) {
                    aiWritingSheet
                }
        }
    }

    private var detailView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1280

            ScrollView {
                VStack(spacing: 12) {
                    workbenchCard

                    if compact {
                        VStack(spacing: 12) {
                            inspectorCard
                            editorMainColumn
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            editorMainColumn
                                .frame(minWidth: 720, maxWidth: .infinity, alignment: .topLeading)

                            inspectorCard
                                .frame(width: min(max(proxy.size.width * 0.3, 360), 440), alignment: .topLeading)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorMainColumn: some View {
        VStack(spacing: 12) {
            aiWritingCard
            editorCard
        }
    }

    private func sidebarRow(for node: SidebarNode) -> some View {
        Group {
            if let post = node.post {
                Button {
                    openPost(post)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: post.usesPageBundle ? "folder.fill.badge.person.crop" : "doc.text")
                                .foregroundStyle(post.id == viewModel.selectedPostID ? Color.accentColor : .secondary)
                            Text(post.title.isEmpty ? post.displayFileName : post.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            ContentKindBadge(text: post.bundleDisplayName)
                        }
                        Text(relativeDisplayPath(for: post))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(post.id == viewModel.selectedPostID ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(node.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var workbenchCard: some View {
        ModernCard(title: "写作工作台", subtitle: "把切换目录、新建内容和文档入口都收在这里。正文区只负责写作，不再堆叠过多设置卡片。") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        workspacePickerBlock
                        workspaceSwitchButton

                        if !viewModel.translationTargets.isEmpty {
                            translationTargetPickerBlock
                            createTranslationButton
                        }

                        Spacer()
                        openWikiButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        workspacePickerBlock
                        HStack(spacing: 10) {
                            workspaceSwitchButton
                            openWikiButton
                        }
                        if !viewModel.translationTargets.isEmpty {
                            translationTargetPickerBlock
                            createTranslationButton
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        TextField("内容标题", text: $viewModel.newPostTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("文件名或包名", text: $viewModel.newPostFileName)
                            .textFieldStyle(.roundedBorder)
                        TextField("栏目路径，可选", text: $viewModel.newPostSectionPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("内容标题", text: $viewModel.newPostTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("文件名或包名", text: $viewModel.newPostFileName)
                            .textFieldStyle(.roundedBorder)
                        TextField("栏目路径，可选", text: $viewModel.newPostSectionPath)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        labeledControl(title: "内容形态", width: 220) {
                            Picker("", selection: $viewModel.newPostCreationMode) {
                                ForEach(ContentCreationMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        labeledControl(title: "头部格式", width: 220) {
                            Picker("", selection: $viewModel.newPostFrontMatterFormat) {
                                ForEach(FrontMatterFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        labeledControl(title: "模板类型", width: 170) {
                            Picker("", selection: $viewModel.newPostArchetypeKind) {
                                Text("默认模板").tag("")
                                ForEach(viewModel.availableArchetypes, id: \.self) { kind in
                                    Text(kind).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        createNewContentButton
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        labeledControl(title: "内容形态") {
                            Picker("", selection: $viewModel.newPostCreationMode) {
                                ForEach(ContentCreationMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        labeledControl(title: "头部格式") {
                            Picker("", selection: $viewModel.newPostFrontMatterFormat) {
                                ForEach(FrontMatterFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        labeledControl(title: "模板类型") {
                            Picker("", selection: $viewModel.newPostArchetypeKind) {
                                Text("默认模板").tag("")
                                ForEach(viewModel.availableArchetypes, id: \.self) { kind in
                                    Text(kind).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        createNewContentButton
                    }
                }

                HStack {
                    Text(viewModel.project.contentURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Text(viewModel.newPostCreationMode.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("创建预览")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.newPostPreview.fileURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("模板类型：\(viewModel.newPostArchetypeKind.isEmpty ? "默认模板" : viewModel.newPostArchetypeKind)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: .constant(viewModel.newPostPreview.rawFrontMatter))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 140)
                        .padding(6)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(true)
                }
            }
        }
    }

    private var aiWritingCard: some View {
        ModernCard(title: "AI 写作", subtitle: "使用对话弹窗生成内容，历史会写入项目目录下的 HugoDeskStorage，便于后续复用。") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("可输入文字、链接或二者混合素材。生成后会保留在对话中，可按需“追加到正文”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开 AI 写作窗口") {
                        openAIWritingSheet()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.isAIFormatting {
                    ProgressView(value: viewModel.aiFormattingProgress)
                        .progressViewStyle(.linear)
                    Text(viewModel.aiFormattingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var editorCard: some View {
        ModernCard(title: "正文编辑", subtitle: "写作主区只保留编辑器、图片插入和保存动作。高级 Hugo 功能统一放到右侧检查器。") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        labeledControl(title: "编辑器", width: 220) {
                            Picker("", selection: $editorImplementation) {
                                ForEach(EditorImplementation.allCases) { implementation in
                                    Text(implementation.rawValue).tag(implementation)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        labeledControl(title: "图片去向", width: 140) {
                            Picker("", selection: $viewModel.imageStorageMode) {
                                ForEach(ImageStorageMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if editorImplementation == .native {
                            labeledControl(title: "插入位置", width: 140) {
                                Picker("", selection: $imageInsertMode) {
                                    ForEach(availableImageInsertModes) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        labeledControl(title: "图片说明", width: 220) {
                            TextField("图片说明文字 alt", text: $imageAltText)
                                .textFieldStyle(.roundedBorder)
                        }

                        imageInsertButton
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        labeledControl(title: "编辑器") {
                            Picker("", selection: $editorImplementation) {
                                ForEach(EditorImplementation.allCases) { implementation in
                                    Text(implementation.rawValue).tag(implementation)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        labeledControl(title: "图片去向") {
                            Picker("", selection: $viewModel.imageStorageMode) {
                                ForEach(ImageStorageMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if editorImplementation == .native {
                            labeledControl(title: "插入位置") {
                                Picker("", selection: $imageInsertMode) {
                                    ForEach(availableImageInsertModes) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        labeledControl(title: "图片说明") {
                            TextField("图片说明文字 alt", text: $imageAltText)
                                .textFieldStyle(.roundedBorder)
                        }

                        imageInsertButton
                    }
                }

                Text(editorImplementation == .vditor
                     ? "当前默认是 Vditor。请直接使用它内置的预览能力，不再额外叠加旧预览区。"
                     : "兼容模式仅用于稳定性对照。日常写作建议继续使用 Vditor。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.imageStorageMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if editorImplementation == .vditor {
                    VditorEditorView(
                        text: $viewModel.editorPost.body,
                        statusMessage: $viewModel.statusText,
                        bridge: vditorBridge,
                        onRequestImageImport: importImageFromPanel
                    )
                    .frame(minHeight: 560)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    MarkdownTextEditor(
                        text: $viewModel.editorPost.body,
                        selection: $editorSelection,
                        onMenuAction: applyMarkdownAction
                    )
                    .frame(minHeight: 560)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                HStack {
                    Button("保存当前内容") {
                        applyInputsToPost()
                        viewModel.saveCurrentPost()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("保存并构建站点") {
                        applyInputsToPost()
                        viewModel.saveCurrentPost()
                        viewModel.runBuild()
                    }
                    .buttonStyle(.bordered)

                    Button("删除当前内容", role: .destructive) {
                        showDeleteConfirm = true
                    }

                    Spacer()

                    Text(viewModel.editorPost.fileURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private var inspectorCard: some View {
        ModernCard(title: inspectorPanel.cardTitle, subtitle: inspectorPanel.subtitle) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("检查器", selection: $inspectorPanel) {
                    ForEach(EditorInspectorPanel.allCases) { panel in
                        Text(panel.rawValue).tag(panel)
                    }
                }
                .pickerStyle(.segmented)

                Text(inspectorPanel.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    inspectorContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch inspectorPanel {
        case .basic:
            inspectorSection("内容结构", hint: "先确认当前页面是单文件、页面包还是栏目包，再决定图片和资源的存放方式。") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(viewModel.editorPost.bundleDisplayName, systemImage: viewModel.editorPost.usesPageBundle ? "shippingbox" : "doc.text")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        ContentKindBadge(text: relativeDisplayPath(for: viewModel.editorPost))
                    }
                    Text(bundleStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.editorPost.fileURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(viewModel.editorPost.bundleRootURL?.path ?? "当前内容不是页面包")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            inspectorSection("页面信息", hint: "日常编辑用结构化模式；只有需要手改复杂 Front Matter 时再切到原始模式。") {
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 10) {
                            labeledControl(title: "编辑方式", width: 200) {
                                Picker("", selection: $viewModel.frontMatterEditorMode) {
                                    ForEach(FrontMatterEditorMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }

                            labeledControl(title: "头部格式", width: 220) {
                                Picker("", selection: $viewModel.editorPost.frontMatterFormat) {
                                    ForEach(FrontMatterFormat.allCases) { format in
                                        Text(format.displayName).tag(format)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }

                            if viewModel.frontMatterEditorMode == .raw {
                                Button("从结构化刷新") {
                                    applyInputsToPost()
                                    viewModel.syncRawFrontMatterFromStructured()
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            labeledControl(title: "编辑方式") {
                                Picker("", selection: $viewModel.frontMatterEditorMode) {
                                    ForEach(FrontMatterEditorMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }

                            labeledControl(title: "头部格式") {
                                Picker("", selection: $viewModel.editorPost.frontMatterFormat) {
                                    ForEach(FrontMatterFormat.allCases) { format in
                                        Text(format.displayName).tag(format)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }

                            if viewModel.frontMatterEditorMode == .raw {
                                Button("从结构化刷新") {
                                    applyInputsToPost()
                                    viewModel.syncRawFrontMatterFromStructured()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if viewModel.frontMatterEditorMode == .structured {
                        TextField("标题", text: $viewModel.editorPost.title)
                        DatePicker("日期", selection: $viewModel.editorPost.date, displayedComponents: [.date, .hourAndMinute])
                        Toggle("草稿", isOn: $viewModel.editorPost.draft)
                            .toggleStyle(.switch)
                        TextField("短链接 slug", text: $viewModel.editorPost.slug)
                        TextField("固定网址 url", text: $viewModel.editorPost.urlPath)
                        TextField("别名 aliases，逗号分隔", text: $aliasesInput)
                        TextField("作者", text: $viewModel.editorPost.author)
                        TextField("封面路径", text: $viewModel.editorPost.cover)
                        TextField("关键词，逗号分隔", text: $keywordsInput)
                        Toggle("置顶", isOn: $viewModel.editorPost.pin)
                            .toggleStyle(.switch)
                        Toggle("KaTeX", isOn: $viewModel.editorPost.math)
                            .toggleStyle(.switch)
                        Toggle("MathJax", isOn: $viewModel.editorPost.mathJax)
                            .toggleStyle(.switch)
                        Toggle("私有", isOn: $viewModel.editorPost.isPrivate)
                            .toggleStyle(.switch)
                        Toggle("允许搜索", isOn: $viewModel.editorPost.searchable)
                            .toggleStyle(.switch)
                    } else {
                        TextEditor(text: $viewModel.editorPost.rawFrontMatter)
                            .font(.body.monospaced())
                            .frame(minHeight: 280)
                            .padding(8)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            inspectorSection("分类与摘要", hint: "tags、categories 和自定义 taxonomy 统一放在这里，摘要逻辑也只保留 Hugo 原生工作流。") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("摘要（可选，默认留空）", text: $viewModel.editorPost.summary, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)

                        HStack(alignment: .center, spacing: 8) {
                            ContentKindBadge(text: viewModel.summaryMode.displayName)
                            Spacer()
                            Button("从正文提取摘要") {
                                applyInputsToPost()
                                viewModel.updateSummaryFromBody()
                                refreshInputsFromPost()
                            }
                            .buttonStyle(.bordered)
                            Button("插入 more 标记") {
                                viewModel.insertSummaryDivider()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text(summaryModeDescription + " 默认不会自动写入摘要，只有手动输入或点击“从正文提取摘要”才会写入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    taxonomyInputSection(
                        key: "tags",
                        title: "标签 tags",
                        placeholder: "输入标签，逗号分隔；下方可直接勾选历史标签"
                    )

                    taxonomyInputSection(
                        key: "categories",
                        title: "分类 categories",
                        placeholder: "输入分类，逗号分隔；下方可直接勾选历史分类"
                    )

                    ForEach(allDynamicTaxonomyKeys, id: \.self) { key in
                        taxonomyInputSection(
                            key: key,
                            title: "\(key)",
                            placeholder: "\(key)（逗号分隔，可新建）"
                        )
                    }
                }
            }
        case .hugo:
            inspectorSection("taxonomy 权重与翻译", hint: "这组是 Hugo 高级项：用于 taxonomy 排序和多语言内容对齐。普通单语博客可以不填。") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("翻译键 translationKey（可选）", text: $viewModel.editorPost.translationKey)
                    ForEach(activeTaxonomyWeightKeys, id: \.self) { key in
                        Stepper("\(key)_weight：\(taxonomyWeightValue(for: key))", value: taxonomyWeightBinding(for: key), in: -100...100)
                    }

                    if activeTaxonomyWeightKeys.isEmpty {
                        Text("当前没有可设置权重的 taxonomy 项。先填写 tags、categories 或自定义 taxonomy 后，这里才会出现对应权重。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("translationKey：\(viewModel.editorPost.translationKey.isEmpty ? "未设置" : viewModel.editorPost.translationKey)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if currentMissingTranslationWorkspaces.isEmpty {
                        Text("当前内容的翻译副本已齐全，或暂未发现缺口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("缺少翻译：\(currentMissingTranslationWorkspaces.map { $0.title.isEmpty ? $0.code : $0.title }.joined(separator: "、"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowWrap(spacing: 8) {
                            ForEach(currentMissingTranslationWorkspaces) { workspace in
                                Button("补到 \(workspace.title.isEmpty ? workspace.code : workspace.title)") {
                                    applyInputsToPost()
                                    viewModel.saveCurrentPost()
                                    viewModel.createTranslation(in: workspace)
                                    refreshInputsFromPost()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            inspectorSection("菜单入口", hint: "文档站、导航菜单和栏目排序时再改这里。普通博客文章通常不需要填写。") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("菜单名，例如 main / docs", text: $viewModel.editorPost.menuEntry.menuName)
                    TextField("显示名 name", text: $viewModel.editorPost.menuEntry.entryName)
                    TextField("标识 identifier", text: $viewModel.editorPost.menuEntry.identifier)
                    TextField("父级 parent", text: $viewModel.editorPost.menuEntry.parent)
                    TextField("前缀 pre", text: $viewModel.editorPost.menuEntry.pre)
                    TextField("后缀 post", text: $viewModel.editorPost.menuEntry.post)
                    Stepper("排序权重：\(viewModel.editorPost.menuEntry.weight)", value: $viewModel.editorPost.menuEntry.weight, in: -100...100)
                }
            }

            inspectorSection("构建策略", hint: "只有资料页、目录页或近似 headless 内容时才建议调整。平时保持默认即可。") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("列表行为", selection: $viewModel.editorPost.buildOptions.list) {
                        ForEach(BuildListMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("渲染行为", selection: $viewModel.editorPost.buildOptions.render) {
                        ForEach(BuildRenderMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("发布页面资源", isOn: $viewModel.editorPost.buildOptions.publishResources)
                        .toggleStyle(.switch)
                    Text(buildOptionsDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.editorPost.creationMode == .branchBundle {
                        Divider()
                        Toggle("对下级内容级联 build 规则", isOn: cascadeBuildToggle)
                            .toggleStyle(.switch)
                        Text("仅栏目包（Section Bundle）建议开启。开启后会在 Front Matter 中写入 cascade.build。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.editorPost.cascadeBuildOptions != nil {
                            Picker("级联列表行为", selection: cascadeBuildListBinding) {
                                ForEach(BuildListMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("级联渲染行为", selection: cascadeBuildRenderBinding) {
                                ForEach(BuildRenderMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)

                            Toggle("级联发布页面资源", isOn: cascadePublishResourcesBinding)
                                .toggleStyle(.switch)
                        }
                    }
                }
            }

            inspectorSection("菜单预览", hint: "根据当前工作区的 menus 字段实时生成结构预览，同时提示全站 sectionPagesMenu 设置。") {
                VStack(alignment: .leading, spacing: 8) {
                    if !viewModel.config.sectionPagesMenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("sectionPagesMenu：\(viewModel.config.sectionPagesMenu)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.menuTreeEntries.isEmpty {
                        Text("当前工作区还没有菜单条目。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(menuNames, id: \.self) { menuName in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(menuName)
                                    .font(.subheadline.weight(.semibold))
                                ForEach(menuRootEntries(for: menuName)) { entry in
                                    MenuPreviewTree(entries: viewModel.menuTreeEntries, entry: entry, menuName: menuName, depth: 0)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            inspectorSection("页面引用", hint: "推荐优先插入 relref，相对更稳。ref 只在你明确需要时再用。") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.pageReferenceCandidates.isEmpty {
                        Text("当前工作区还没有可引用的页面。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("目标页面", selection: $selectedReferenceID) {
                            ForEach(viewModel.pageReferenceCandidates) { candidate in
                                Text(candidate.title).tag(candidate.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("引用方式", selection: $referenceUsesRelref) {
                            Text("相对引用 relref").tag(true)
                            Text("绝对引用 ref").tag(false)
                        }
                        .pickerStyle(.segmented)

                        if !selectedReferenceAnchors.isEmpty {
                            Picker("标题锚点", selection: $referenceAnchor) {
                                Text("不使用锚点").tag("")
                                ForEach(selectedReferenceAnchors, id: \.self) { anchor in
                                    Text("#\(anchor)").tag(anchor)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            TextField("锚点，可选", text: $referenceAnchor)
                        }
                        Button("插入页面引用") {
                            insertSelectedReference()
                        }
                        .buttonStyle(.borderedProminent)

                        if let candidate = selectedReferenceCandidate {
                            Text(candidate.referencePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            inspectorSection("短代码", hint: "这里扫描项目本地和当前主题里的 shortcode，插入后仍然可以在正文里继续微调参数。") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.availableShortcodes.isEmpty {
                        Text("当前项目和主题里没有扫描到 shortcode。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("短代码", selection: $selectedShortcodeID) {
                            ForEach(viewModel.availableShortcodes) { shortcode in
                                Text(shortcode.name).tag(shortcode.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if let shortcode = selectedShortcode, !shortcode.summary.isEmpty {
                            Text(shortcode.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let shortcode = selectedShortcode, !shortcode.parameterHints.isEmpty {
                            ForEach(shortcode.parameterHints) { hint in
                                TextField(
                                    hint.isPositional ? "\(hint.name)（位置参数）" : "\(hint.name)（命名参数）",
                                    text: shortcodeParameterBinding(for: hint.name)
                                )
                            }
                        }

                        TextField("补充原始参数，例如 class=\"note\"", text: $shortcodeParameters)
                        Toggle("插入为块级短代码", isOn: $shortcodeIsBlock)
                            .toggleStyle(.switch)
                        Button("插入短代码") {
                            insertSelectedShortcode()
                        }
                        .buttonStyle(.borderedProminent)

                        if let shortcode = selectedShortcode {
                            Text(shortcode.sourcePath + (shortcode.isProjectLocal ? "  · 项目本地" : "  · 主题提供"))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        case .assets:
            inspectorSection("页面资源", hint: "只有页面包模式下，这里才是真正的 Hugo 页面资源管理区。") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.editorPost.usesPageBundle {
                        let resources = viewModel.editorPost.pageResources
                        HStack {
                            Button("导入资源到当前页面") {
                                importPageResourceFromPanel()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("刷新资源列表") {
                                viewModel.refreshCurrentPageResources()
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }

                        if resources.isEmpty {
                            Text("当前页面包还没有资源文件。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            PageResourceManagerSection(
                                resources: resources,
                                selectedResourceID: $selectedResourceID,
                                resourceRelativePathDraft: $resourceRelativePathDraft,
                                onInsert: { resource in
                                    insertSnippetIntoEditor(viewModel.pageResourceSnippet(for: resource))
                                },
                                onMove: { resource, nextPath in
                                    viewModel.moveCurrentPageResource(resource, to: nextPath)
                                    syncAuxiliarySelections()
                                },
                                onDelete: { resource in
                                    viewModel.deleteCurrentPageResource(resource)
                                    syncAuxiliarySelections()
                                }
                            )
                        }
                    } else {
                        Text("当前内容不是页面包。若要体验 Hugo 页面资源，请先创建“页面包（Leaf Bundle）”或“栏目包（Section Bundle）”。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            inspectorSection("引用诊断", hint: "这里会扫描当前工作区中的 ref / relref 失效项，适合发布前快速排错。") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.allWorkspaceReferenceDiagnostics.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("当前所有工作区都没有检测到失效引用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ContentKindBadge(text: "发现 \(viewModel.allWorkspaceReferenceDiagnostics.count) 处")
                        ForEach(viewModel.allWorkspaceReferenceDiagnostics.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.postTitle)
                                    .font(.caption.weight(.semibold))
                                Text(item.reference)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(item.linePreview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.filePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            inspectorSection("翻译缺口", hint: "这里汇总全部工作区的缺失翻译副本，便于你决定先补哪些语言。") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.translationDiagnostics.isEmpty {
                        Text("当前没有检测到缺失翻译副本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentKindBadge(text: "缺口 \(viewModel.translationDiagnostics.count)")
                        ForEach(viewModel.translationDiagnostics.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.sourceTitle)
                                    .font(.caption.weight(.semibold))
                                Text("缺少：\(item.missingLanguages.joined(separator: "、"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("已有：\(item.existingLanguages.joined(separator: "、"))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(item.sourceFilePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func inspectorSection<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    private var aiWritingSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 写作")
                        .font(.headline)
                    Text("对话会保存在项目根目录下的 HugoDeskStorage/ai-writing-history.json，方便后续复用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("复制全部对话") {
                    copyAIWritingTranscript()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.aiWritingMessages.isEmpty)
                Button("清空对话") {
                    viewModel.clearAIWritingHistory()
                }
                .buttonStyle(.bordered)
                Button("关闭") {
                    if !viewModel.isAIFormatting {
                        showingAIWritingSheet = false
                    }
                }
                .disabled(viewModel.isAIFormatting)
            }

            Text(viewModel.aiWritingHistoryDirectoryPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if viewModel.aiWritingMessages.isEmpty {
                            Text("还没有历史对话。你可以先发送一条素材。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(viewModel.aiWritingMessages) { message in
                                aiWritingMessageBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 250, maxHeight: 320)
                .padding(8)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear {
                    if let last = viewModel.aiWritingMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.aiWritingMessages.count) { _ in
                    if let last = viewModel.aiWritingMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            TextEditor(text: $aiWritingSourceText)
                .font(.body.monospaced())
                .frame(minHeight: 130)
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

                Button("发送并生成") {
                    runAIWriting()
                }
                .buttonStyle(.borderedProminent)
                .disabled(aiWritingSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAIFormatting)
            }
        }
        .padding(16)
        .frame(minWidth: 840, minHeight: 560)
    }

    private func aiWritingMessageBubble(_ message: AIWritingMessage) -> some View {
        let isUser = message.role == .user
        let isSystem = message.role == .system
        return HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 60)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.role.displayName)
                        .font(.caption.weight(.semibold))
                    Text(aiMessageTimestampText(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("复制") {
                        copyAIWritingMessage(message)
                    }
                    .buttonStyle(.bordered)
                    if message.role == .assistant {
                        Button("追加到正文") {
                            appendAIMessageToEditor(message.content)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isUser
                        ? Color.accentColor.opacity(0.16)
                        : (isSystem ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.12))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isUser
                        ? Color.accentColor.opacity(0.35)
                        : (isSystem ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.2)),
                        lineWidth: 1
                    )
            )
            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }

    private var sidebarRoots: [SidebarNode] {
        SidebarNode.buildTree(posts: viewModel.posts, relativePath: relativeDisplayPath(for:))
    }

    private var selectedTranslationWorkspace: HugoLanguageProfile? {
        viewModel.translationTargets.first(where: { $0.code == selectedTranslationWorkspaceCode })
    }

    private var selectedReferenceCandidate: PageReferenceCandidate? {
        viewModel.pageReferenceCandidates.first(where: { $0.id == selectedReferenceID })
    }

    private var selectedShortcode: ShortcodeDefinition? {
        viewModel.availableShortcodes.first(where: { $0.id == selectedShortcodeID })
    }

    private var selectedReferenceAnchors: [String] {
        viewModel.referenceAnchors(for: selectedReferenceCandidate)
    }

    private var selectedResource: PageResourceItem? {
        viewModel.editorPost.pageResources.first(where: { $0.id == selectedResourceID })
    }

    private var allDynamicTaxonomyKeys: [String] {
        Array(Set(viewModel.dynamicTaxonomyKeys).union(viewModel.editorPost.customTaxonomies.keys))
            .sorted()
    }

    private var activeTaxonomyWeightKeys: [String] {
        var keys: [String] = []
        if !viewModel.editorPost.tags.isEmpty {
            keys.append("tags")
        }
        if !viewModel.editorPost.categories.isEmpty {
            keys.append("categories")
        }
        keys.append(contentsOf: allDynamicTaxonomyKeys.filter {
            !(viewModel.editorPost.customTaxonomies[$0] ?? []).isEmpty
        })
        return Array(Set(keys)).sorted()
    }

    private var currentMissingTranslationWorkspaces: [HugoLanguageProfile] {
        viewModel.missingTranslationWorkspaces(for: viewModel.editorPost)
    }

    private var menuNames: [String] {
        Array(Set(viewModel.menuTreeEntries.map(\.menuName))).sorted()
    }

    private var bundleStatusText: String {
        switch viewModel.editorPost.creationMode {
        case .singleFile:
            return "当前内容是普通单文件文章，图片更适合统一放到静态目录。"
        case .leafBundle:
            return "当前内容是页面包，正文与资源文件可以保存在同一个目录下。"
        case .branchBundle:
            return "当前内容是栏目包，适合作为栏目首页或文档目录入口。"
        }
    }

    private var summaryModeDescription: String {
        switch viewModel.summaryMode {
        case .auto:
            return "当前页面依赖 Hugo 自动摘要规则。"
        case .frontMatter:
            return "当前摘要优先来自摘要字段。"
        case .manualDivider:
            return "正文里已有 <!--more-->，Hugo 会用它作为摘要分隔点。"
        }
    }

    private var buildOptionsDescription: String {
        if viewModel.editorPost.buildOptions.list == .never && viewModel.editorPost.buildOptions.render == .never {
            return "当前组合接近 headless 页面：不进列表，也不直接渲染。"
        }
        return "如果你不确定是否需要改 build，保持默认即可。"
    }

    private var workspacePickerBlock: some View {
        labeledControl(title: "当前工作区", width: 210) {
            Picker("", selection: $selectedWorkspacePickerCode) {
                ForEach(viewModel.languageWorkspaces) { workspace in
                    Text(workspace.title.isEmpty ? workspace.code : workspace.title)
                        .tag(workspace.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var workspaceSwitchButton: some View {
        Button("切换内容目录") {
            applyInputsToPost()
            viewModel.saveCurrentPost()
            viewModel.switchContentWorkspace(to: selectedWorkspacePickerCode)
            refreshInputsFromPost()
        }
        .buttonStyle(.bordered)
        .disabled(selectedWorkspacePickerCode.isEmpty || selectedWorkspacePickerCode == viewModel.selectedWorkspaceCode)
    }

    private var translationTargetPickerBlock: some View {
        labeledControl(title: "翻译目标", width: 210) {
            Picker("", selection: $selectedTranslationWorkspaceCode) {
                Text("选择目标工作区")
                    .tag("")
                ForEach(viewModel.translationTargets) { workspace in
                    Text(workspace.title.isEmpty ? workspace.code : workspace.title)
                        .tag(workspace.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var createTranslationButton: some View {
        Button("创建翻译副本") {
            applyInputsToPost()
            viewModel.saveCurrentPost()
            if let workspace = selectedTranslationWorkspace {
                viewModel.createTranslation(in: workspace)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedTranslationWorkspace == nil)
    }

    private var openWikiButton: some View {
        Button("打开使用说明") {
            openWikiHome()
        }
        .buttonStyle(.bordered)
    }

    private var createNewContentButton: some View {
        Button("创建新内容") {
            viewModel.createPostFromForm()
            editorSelection = NSRange(location: 0, length: 0)
            refreshInputsFromPost()
        }
        .buttonStyle(.borderedProminent)
    }

    private var imageInsertButton: some View {
        Button(editorImplementation == .native ? "上传并插入图片" : "插入图片到当前光标") {
            importImageFromPanel()
        }
        .buttonStyle(.bordered)
    }

    private func labeledControl<Content: View>(title: String, width: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func taxonomyInputSection(key: String, title: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: taxonomyInputBinding(for: key))
                .textFieldStyle(.roundedBorder)
            let suggestions = taxonomySuggestions(for: key)
            if suggestions.isEmpty {
                Text("暂无本地可选项，可直接输入新值。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                FlowWrap(spacing: 6) {
                    ForEach(suggestions, id: \.self) { term in
                        taxonomyTermButton(term, key: key, isSelected: currentTaxonomyValues(for: key).contains(term))
                    }
                }
            }
        }
    }

    private func taxonomyTermButton(_ term: String, key: String, isSelected: Bool) -> some View {
        Button {
            toggleTaxonomyTerm(term, key: key)
        } label: {
            Text(term)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func taxonomyInputBinding(for key: String) -> Binding<String> {
        switch key {
        case "tags":
            return $tagsInput
        case "categories":
            return $categoriesInput
        default:
            return dynamicTaxonomyBinding(for: key)
        }
    }

    private func currentTaxonomyValues(for key: String) -> [String] {
        switch key {
        case "tags":
            return splitCSV(tagsInput)
        case "categories":
            return splitCSV(categoriesInput)
        default:
            return splitCSV(dynamicTaxonomyInputs[key] ?? "")
        }
    }

    private func setTaxonomyValues(_ values: [String], for key: String) {
        let text = values.joined(separator: ", ")
        switch key {
        case "tags":
            tagsInput = text
        case "categories":
            categoriesInput = text
        default:
            dynamicTaxonomyInputs[key] = text
        }
    }

    private func toggleTaxonomyTerm(_ term: String, key: String) {
        var values = currentTaxonomyValues(for: key)
        if let index = values.firstIndex(of: term) {
            values.remove(at: index)
        } else {
            values.append(term)
        }
        setTaxonomyValues(normalizeTerms(values), for: key)
    }

    private func taxonomySuggestions(for key: String) -> [String] {
        var terms = Set(currentTaxonomyValues(for: key))
        for post in viewModel.posts {
            let candidates: [String]
            switch key {
            case "tags":
                candidates = post.tags
            case "categories":
                candidates = post.categories
            default:
                candidates = post.customTaxonomies[key] ?? []
            }
            for term in candidates {
                let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    terms.insert(normalized)
                }
            }
        }
        return terms.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizeTerms(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(normalized)
        }
        return output
    }

    private func refreshInputsFromPost() {
        tagsInput = viewModel.editorPost.tags.joined(separator: ", ")
        categoriesInput = viewModel.editorPost.categories.joined(separator: ", ")
        keywordsInput = viewModel.editorPost.keywords.joined(separator: ", ")
        aliasesInput = viewModel.editorPost.aliases.joined(separator: ", ")
        dynamicTaxonomyInputs = viewModel.editorPost.customTaxonomies.mapValues { $0.joined(separator: ", ") }
        syncAuxiliarySelections()
    }

    private func syncAuxiliarySelections() {
        selectedWorkspacePickerCode = viewModel.selectedWorkspaceCode
        if viewModel.translationTargets.contains(where: { $0.code == selectedTranslationWorkspaceCode }) == false {
            selectedTranslationWorkspaceCode = viewModel.translationTargets.first?.code ?? viewModel.selectedWorkspaceCode
        }
        if viewModel.pageReferenceCandidates.contains(where: { $0.id == selectedReferenceID }) == false {
            selectedReferenceID = viewModel.pageReferenceCandidates.first?.id ?? ""
        }
        if !selectedReferenceAnchors.contains(referenceAnchor) {
            referenceAnchor = ""
        }
        if viewModel.availableShortcodes.contains(where: { $0.id == selectedShortcodeID }) == false {
            selectedShortcodeID = viewModel.availableShortcodes.first?.id ?? ""
        }
        if let shortcode = selectedShortcode {
            let keys = Set(shortcode.parameterHints.map(\.name))
            shortcodeParameterValues = shortcodeParameterValues.filter { keys.contains($0.key) }
        } else {
            shortcodeParameterValues.removeAll()
        }
        if viewModel.editorPost.pageResources.contains(where: { $0.id == selectedResourceID }) == false {
            selectedResourceID = viewModel.editorPost.pageResources.first?.id ?? ""
            resourceRelativePathDraft = selectedResource?.relativePath ?? ""
        } else if let selectedResource {
            resourceRelativePathDraft = selectedResource.relativePath
        }
    }

    private func applyInputsToPost() {
        viewModel.editorPost.tags = normalizeTerms(splitCSV(tagsInput))
        viewModel.editorPost.categories = normalizeTerms(splitCSV(categoriesInput))
        viewModel.editorPost.keywords = normalizeTerms(splitCSV(keywordsInput))
        viewModel.editorPost.aliases = normalizeTerms(splitCSV(aliasesInput))

        var preserved = viewModel.editorPost.customTaxonomies
        for key in allDynamicTaxonomyKeys {
            let values = normalizeTerms(splitCSV(dynamicTaxonomyInputs[key] ?? ""))
            if values.isEmpty {
                preserved.removeValue(forKey: key)
            } else {
                preserved[key] = values
            }
        }
        viewModel.editorPost.customTaxonomies = preserved
    }

    private func dynamicTaxonomyBinding(for key: String) -> Binding<String> {
        Binding(
            get: { dynamicTaxonomyInputs[key, default: ""] },
            set: { dynamicTaxonomyInputs[key] = $0 }
        )
    }

    private func taxonomyWeightBinding(for key: String) -> Binding<Int> {
        Binding(
            get: { taxonomyWeightValue(for: key) },
            set: { newValue in
                if newValue == 0 {
                    viewModel.editorPost.taxonomyWeights.removeValue(forKey: key)
                } else {
                    viewModel.editorPost.taxonomyWeights[key] = newValue
                }
            }
        )
    }

    private func taxonomyWeightValue(for key: String) -> Int {
        viewModel.editorPost.taxonomyWeights[key, default: 0]
    }

    private func shortcodeParameterBinding(for key: String) -> Binding<String> {
        Binding(
            get: { shortcodeParameterValues[key, default: ""] },
            set: { shortcodeParameterValues[key] = $0 }
        )
    }

    private var cascadeBuildToggle: Binding<Bool> {
        Binding(
            get: { viewModel.editorPost.cascadeBuildOptions != nil },
            set: { newValue in
                viewModel.editorPost.cascadeBuildOptions = newValue ? (viewModel.editorPost.cascadeBuildOptions ?? viewModel.editorPost.buildOptions) : nil
            }
        )
    }

    private var cascadeBuildListBinding: Binding<BuildListMode> {
        Binding(
            get: { viewModel.editorPost.cascadeBuildOptions?.list ?? viewModel.editorPost.buildOptions.list },
            set: { newValue in
                if viewModel.editorPost.cascadeBuildOptions == nil {
                    viewModel.editorPost.cascadeBuildOptions = viewModel.editorPost.buildOptions
                }
                viewModel.editorPost.cascadeBuildOptions?.list = newValue
            }
        )
    }

    private var cascadeBuildRenderBinding: Binding<BuildRenderMode> {
        Binding(
            get: { viewModel.editorPost.cascadeBuildOptions?.render ?? viewModel.editorPost.buildOptions.render },
            set: { newValue in
                if viewModel.editorPost.cascadeBuildOptions == nil {
                    viewModel.editorPost.cascadeBuildOptions = viewModel.editorPost.buildOptions
                }
                viewModel.editorPost.cascadeBuildOptions?.render = newValue
            }
        )
    }

    private var cascadePublishResourcesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.editorPost.cascadeBuildOptions?.publishResources ?? viewModel.editorPost.buildOptions.publishResources },
            set: { newValue in
                if viewModel.editorPost.cascadeBuildOptions == nil {
                    viewModel.editorPost.cascadeBuildOptions = viewModel.editorPost.buildOptions
                }
                viewModel.editorPost.cascadeBuildOptions?.publishResources = newValue
            }
        )
    }

    private func splitCSV(_ input: String) -> [String] {
        input
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
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

    private func importPageResourceFromPanel() {
        guard let fileURL = pickAnyFile() else { return }
        viewModel.importCurrentPageResource(from: fileURL)
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

    private func pickAnyFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func insertSelectedReference() {
        guard let candidate = selectedReferenceCandidate else { return }
        let snippet = viewModel.insertReferenceSnippet(target: candidate, useRelref: referenceUsesRelref, anchor: referenceAnchor)
        insertSnippetIntoEditor(snippet + "\n")
    }

    private func insertSelectedShortcode() {
        guard let shortcode = selectedShortcode else { return }
        let snippet = viewModel.makeShortcodeSnippet(name: shortcode.name, parameters: compiledShortcodeParameters, isBlock: shortcodeIsBlock)
        guard !snippet.isEmpty else { return }
        insertSnippetIntoEditor(snippet + "\n")
    }

    private var compiledShortcodeParameters: String {
        var segments: [String] = []
        if let shortcode = selectedShortcode {
            for hint in shortcode.parameterHints {
                let value = shortcodeParameterValues[hint.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
                if hint.isPositional {
                    segments.append("\"\(escaped)\"")
                } else {
                    segments.append("\(hint.name)=\"\(escaped)\"")
                }
            }
        }
        let raw = shortcodeParameters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            segments.append(raw)
        }
        return segments.joined(separator: " ")
    }

    private func insertSnippetIntoEditor(_ snippet: String) {
        if editorImplementation == .vditor {
            vditorBridge.insertMarkdown(snippet)
            vditorBridge.focus()
            return
        }

        let insertionPoint = max(0, editorSelection.location + editorSelection.length)
        let next = viewModel.insertPostSnippet(snippet, at: NSRange(location: insertionPoint, length: 0))
        editorSelection = next
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
        viewModel.loadAIWritingHistory()
        showingAIWritingSheet = true
    }

    private func runAIWriting() {
        let source = aiWritingSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        viewModel.appendAIWritingMessage(role: .user, content: source)
        aiWritingSourceText = ""
        viewModel.generateWritingWithAI(
            sourceInput: source,
            onComplete: { generated in
                let reply = generated.trimmingCharacters(in: .whitespacesAndNewlines)
                if reply.isEmpty {
                    viewModel.appendAIWritingMessage(role: .system, content: "AI 返回为空，请调整提示词后重试。")
                } else {
                    viewModel.appendAIWritingMessage(role: .assistant, content: reply)
                }
            },
            onFailure: { errorText in
                viewModel.appendAIWritingMessage(role: .system, content: errorText)
            }
        )
    }

    private func pasteAIWritingSourceFromClipboard() {
        if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
            aiWritingSourceText = pasted
        }
    }

    private func copyAIWritingTranscript() {
        let text = viewModel.aiWritingTranscriptText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        viewModel.statusText = "已复制全部 AI 对话。"
    }

    private func copyAIWritingMessage(_ message: AIWritingMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        viewModel.statusText = "已复制一条对话内容。"
    }

    private func appendAIMessageToEditor(_ content: String) {
        let snippet = normalizedAIWritingSnippet(content)
        guard !snippet.isEmpty else { return }
        insertSnippetIntoEditor(snippet)
        viewModel.statusText = "已将 AI 回复追加到正文。"
    }

    private func aiMessageTimestampText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func normalizedAIWritingSnippet(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed + "\n"
    }

    private var availableImageInsertModes: [ImageInsertMode] {
        editorImplementation == .native ? ImageInsertMode.allCases : [.appendToEnd]
    }

    private func openWikiHome() {
        guard let url = wikiHomeURL() else {
            viewModel.statusText = "未找到本地使用说明。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func wikiHomeURL() -> URL? {
        if let bundled = Bundle.module.url(forResource: "index", withExtension: "md", subdirectory: "wiki") {
            return bundled
        }
        if let bundled = Bundle.module.url(forResource: "index", withExtension: "md") {
            return bundled
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
        let docsURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Docs/wiki/index.md")
        return FileManager.default.fileExists(atPath: docsURL.path) ? docsURL : nil
    }

    private var editorColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { NavigationSplitViewVisibility(storedValue: columnVisibilityRawValue) },
            set: { columnVisibilityRawValue = $0.storageKey }
        )
    }

    private func relativeDisplayPath(for post: BlogPost) -> String {
        let root = viewModel.project.contentURL.standardizedFileURL.path
        let target: String
        if post.usesPageBundle, let bundleRoot = post.bundleRootURL?.standardizedFileURL.path {
            target = bundleRoot
        } else {
            target = post.fileURL.standardizedFileURL.path
        }
        guard target.hasPrefix(root) else { return post.fileURL.lastPathComponent }
        var relative = String(target.dropFirst(root.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? "." : relative
    }

    private func openPost(_ post: BlogPost) {
        viewModel.selectedPostID = post.id
        viewModel.loadSelectedPost()
        viewModel.cancelLivePreviewRefresh()
        editorSelection = NSRange(location: 0, length: 0)
        refreshInputsFromPost()
    }

    private func menuRootEntries(for menuName: String) -> [MenuTreeEntry] {
        viewModel.menuTreeEntries.filter { $0.menuName == menuName && $0.parent.isEmpty }
    }
}

private struct SidebarNode: Identifiable {
    let id: String
    let name: String
    let post: BlogPost?
    let children: [SidebarNode]

    var childNodes: [SidebarNode]? {
        children.isEmpty ? nil : children
    }

    static func buildTree(posts: [BlogPost], relativePath: (BlogPost) -> String) -> [SidebarNode] {
        final class Box {
            let id: String
            let name: String
            var post: BlogPost?
            var children: [String: Box] = [:]

            init(id: String, name: String) {
                self.id = id
                self.name = name
            }
        }

        let root = Box(id: "root", name: "root")
        for post in posts {
            let rawRelative = relativePath(post)
            let components = rawRelative.split(separator: "/").map(String.init)
            let pathComponents: [String]
            if post.usesPageBundle {
                pathComponents = components
            } else {
                pathComponents = components.isEmpty ? [post.displayFileName] : components
            }

            var current = root
            for (index, component) in pathComponents.enumerated() {
                let isLast = index == pathComponents.count - 1
                let key = current.id + "/" + component
                let node = current.children[component] ?? Box(id: key, name: component)
                current.children[component] = node
                if isLast {
                    node.post = post
                }
                current = node
            }
        }

        func freeze(_ box: Box) -> [SidebarNode] {
            box.children.values.map { child in
                SidebarNode(
                    id: child.id,
                    name: child.name,
                    post: child.post,
                    children: freeze(child)
                )
            }
            .sorted { left, right in
                if left.children.isEmpty != right.children.isEmpty {
                    return !left.children.isEmpty && right.children.isEmpty
                }
                let leftName = left.post?.title.isEmpty == false ? left.post!.title : left.name
                let rightName = right.post?.title.isEmpty == false ? right.post!.title : right.name
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
        }

        return freeze(root)
    }
}

private struct MenuPreviewTree: View {
    let entries: [MenuTreeEntry]
    let entry: MenuTreeEntry
    let menuName: String
    let depth: Int

    private var children: [MenuTreeEntry] {
        entries.filter { $0.menuName == menuName && $0.parent == entry.identifier }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(repeating: "　", count: depth) + entry.title)
                    .font(.caption.weight(depth == 0 ? .semibold : .regular))
                if entry.weight != 0 {
                    ContentKindBadge(text: "w \(entry.weight)")
                }
            }
            Text(entry.identifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            ForEach(children) { child in
                MenuPreviewTree(entries: entries, entry: child, menuName: menuName, depth: depth + 1)
            }
        }
    }
}

private struct PageResourceManagerSection: View {
    let resources: [PageResourceItem]
    @Binding var selectedResourceID: String
    @Binding var resourceRelativePathDraft: String
    var onInsert: (PageResourceItem) -> Void
    var onMove: (PageResourceItem, String) -> Void
    var onDelete: (PageResourceItem) -> Void

    private var selectedResource: PageResourceItem? {
        resources.first(where: { $0.id == selectedResourceID })
    }

    var body: some View {
        let rows = resources.enumerated().map { ($0.offset, $0.element) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.1.id) { _, resource in
                Button {
                    selectedResourceID = resource.id
                    resourceRelativePathDraft = resource.relativePath
                } label: {
                    HStack(spacing: 10) {
                        ContentKindBadge(text: resource.mediaKind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resource.relativePath)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            Text(resource.url.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedResource?.id == resource.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if let resource = selectedResource {
                Divider()
                TextField("资源路径（支持改名或移动到子目录）", text: $resourceRelativePathDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("插入正文") {
                        onInsert(resource)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("复制相对路径") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resource.relativePath, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Button("保存路径") {
                        onMove(resource, resourceRelativePathDraft)
                    }
                    .buttonStyle(.bordered)

                    Button("删除资源", role: .destructive) {
                        onDelete(resource)
                    }
                }
            }
        }
    }
}

private struct ContentKindBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

private struct FlowWrap<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 88), spacing: spacing)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content()
        }
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

private enum EditorInspectorPanel: String, CaseIterable, Identifiable {
    case basic = "基础信息"
    case hugo = "Hugo 高级"
    case assets = "资源与诊断"

    var id: String { rawValue }

    var cardTitle: String {
        switch self {
        case .basic:
            return "基础信息"
        case .hugo:
            return "Hugo 高级"
        case .assets:
            return "资源与诊断"
        }
    }

    var subtitle: String {
        switch self {
        case .basic:
            return "把最常改的字段集中在一栏，不再拆成多个拥挤卡片。"
        case .hugo:
            return "只有你真的在用 Hugo 结构能力时，才需要频繁看这一栏。"
        case .assets:
            return "页面资源和失效引用检查放在同一组，方便发布前排查。"
        }
    }

    var detailText: String {
        switch self {
        case .basic:
            return "这里是日常写作最常用的一组设置。标题、摘要、taxonomy 和内容结构都在这里。"
        case .hugo:
            return "这里保留 Hugo 原生能力：菜单、build、引用和短代码。普通博客写作时可以很少打开。"
        case .assets:
            return "这里处理页面包资源与站内引用诊断，属于排查与整理区，不参与正文主视觉。"
        }
    }
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

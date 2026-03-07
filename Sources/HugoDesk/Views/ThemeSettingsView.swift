import AppKit
import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var customCSSInput = ""
    @State private var customJSInput = ""
    @State private var outputsInput = ""
    @State private var taxonomyEntries: [TaxonomyDraft] = []
    @State private var languageEntries: [LanguageDraft] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ModernCard(title: "主题检测与选择", subtitle: "自动扫描 themes 目录并支持手动切换") {
                    VStack(spacing: 10) {
                        SettingRow(
                            key: "themes/",
                            title: "检测到的主题",
                            helpText: "来源于博客目录 themes/ 下的子目录；若配置主题不在目录中，也会作为配置项保留。",
                            scope: "主题"
                        ) {
                            Picker("", selection: themeSelectionBinding) {
                                ForEach(themeOptions, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Button("刷新主题检测") {
                                viewModel.refreshDetectedThemes()
                            }
                            Text("当前：\(viewModel.config.theme)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        if let detected = viewModel.selectedDetectedTheme {
                            Text("\(detected.sourceDescription) · \(detected.capabilitySummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("当前主题来自手动配置，尚未检测到本地主题目录能力标签。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ModernCard(title: "站点基础") {
                    VStack(spacing: 10) {
                        SettingRow(key: "baseURL", title: "站点地址", helpText: "网站最终访问地址，影响 canonical、RSS、分享链接。", scope: "全站") {
                            TextField("https://example.com/", text: $viewModel.config.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "languageCode", title: "语言代码", helpText: "站点主语言，例如 zh-cn、en-us。", scope: "全站") {
                            TextField("zh-cn", text: $viewModel.config.languageCode)
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "title", title: "站点标题", helpText: "浏览器标题、Open Graph 等位置会使用。", scope: "全站") {
                            TextField("站点标题", text: $viewModel.config.title)
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "theme", title: "主题名称", helpText: "手动输入主题目录名后点击“应用主题”，会按该主题能力刷新设置项。", scope: "渲染") {
                            HStack {
                                TextField("github-style", text: $viewModel.config.theme)
                                    .textFieldStyle(.roundedBorder)
                                Button("应用主题") {
                                    viewModel.selectTheme(named: viewModel.config.theme)
                                }
                            }
                        }
                        SettingRow(key: "sectionPagesMenu", title: "sectionPagesMenu", helpText: "让 Hugo 自动把 section 页面加入指定菜单，例如 main 或 docs。", scope: "导航") {
                            TextField("例如：main", text: $viewModel.config.sectionPagesMenu)
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "pygmentsCodeFences", title: "代码块高亮", helpText: "开启 fenced code block 语法高亮。", scope: "渲染") {
                            Toggle("", isOn: $viewModel.config.pygmentsCodeFences)
                                .labelsHidden()
                        }
                        SettingRow(key: "pygmentsUseClasses", title: "高亮样式类", helpText: "使用 CSS class 形式输出高亮样式。", scope: "渲染") {
                            Toggle("", isOn: $viewModel.config.pygmentsUseClasses)
                                .labelsHidden()
                        }
                    }
                }

                ModernCard(title: "内容结构配置", subtitle: "这里管理 Hugo 的 taxonomies 和多语言 contentDir。它们直接决定写作页的分类法字段和工作区切换能力。") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("分类法 taxonomies")
                                    .font(.headline)
                                Spacer()
                                Button("恢复默认") {
                                    taxonomyEntries = [
                                        TaxonomyDraft(key: "tag", value: "tags"),
                                        TaxonomyDraft(key: "category", value: "categories")
                                    ]
                                }
                                Button("新增分类法") {
                                    taxonomyEntries.append(TaxonomyDraft())
                                }
                            }

                            Text("左边是单数键名，右边是内容里实际使用的复数名称。比如 `tag -> tags`、`series -> series`。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if taxonomyEntries.isEmpty {
                                Text("当前没有自定义 taxonomy。你可以恢复默认，也可以手动新增。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(taxonomyEntries.enumerated()), id: \.element.id) { index, _ in
                                    HStack(spacing: 10) {
                                        TextField("单数键名，例如 tag", text: bindingForTaxonomy(index, \.key))
                                            .textFieldStyle(.roundedBorder)
                                        TextField("复数名称，例如 tags", text: bindingForTaxonomy(index, \.value))
                                            .textFieldStyle(.roundedBorder)
                                        Button("删除") {
                                            taxonomyEntries.remove(at: index)
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("多语言内容目录")
                                    .font(.headline)
                                Spacer()
                                Button("新增语言") {
                                    languageEntries.append(LanguageDraft())
                                }
                            }

                            Text("这里对应 `languages.<code>.contentDir`。写作页顶部的“内容工作区”就是基于这里生成的。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if languageEntries.isEmpty {
                                Text("当前没有配置多语言工作区。保留为空时，软件会默认使用主 `content` 目录。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(languageEntries.enumerated()), id: \.element.id) { index, _ in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("语言 \(index + 1)")
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Button("删除") {
                                                languageEntries.remove(at: index)
                                            }
                                        }
                                        HStack(spacing: 10) {
                                            TextField("语言代码，例如 zh-cn / en", text: bindingForLanguage(index, \.code))
                                                .textFieldStyle(.roundedBorder)
                                            TextField("显示名，例如 简体中文 / English", text: bindingForLanguage(index, \.title))
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        HStack(spacing: 10) {
                                            TextField("内容目录，例如 content / content.en", text: bindingForLanguage(index, \.contentDir))
                                                .textFieldStyle(.roundedBorder)
                                            Stepper("权重 \(languageEntries[index].weight)", value: bindingForLanguageWeight(index), in: 0...100)
                                                .frame(width: 160, alignment: .leading)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.black.opacity(0.03))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }

                ModernCard(title: "个人资料与社交") {
                    VStack(spacing: 10) {
                        SettingRow(key: "params.author", title: "作者名", helpText: "侧栏头像旁与文章头部显示。", scope: "首页/文章") {
                            TextField("", text: $viewModel.config.params.author).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.description", title: "个人简介", helpText: "侧栏简介与社交卡片摘要。", scope: "首页/SEO") {
                            TextField("", text: $viewModel.config.params.description).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.tagline", title: "SEO 标语", helpText: "用于首页 meta description（部分模板）。", scope: "SEO") {
                            TextField("", text: $viewModel.config.params.tagline).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.github", title: "GitHub 用户名", helpText: "生成 GitHub 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.github).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.twitter", title: "X/Twitter 用户名", helpText: "生成 Twitter 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.twitter).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.facebook", title: "Facebook 用户名", helpText: "生成 Facebook 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.facebook).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.linkedin", title: "LinkedIn ID", helpText: "生成 LinkedIn 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.linkedin).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.instagram", title: "Instagram 用户名", helpText: "生成 Instagram 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.instagram).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.tumblr", title: "Tumblr 名称", helpText: "生成 Tumblr 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.tumblr).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.stackoverflow", title: "StackOverflow ID", helpText: "生成 StackOverflow 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.stackoverflow).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.bluesky", title: "Bluesky Handle", helpText: "生成 Bluesky 社交入口。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.bluesky).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.email", title: "邮箱", helpText: "侧栏显示并生成 mailto 链接。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.email).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.url", title: "个人链接", helpText: "侧栏个人主页链接。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.url).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.keywords", title: "默认关键词", helpText: "文章没有关键词时使用此项作为 fallback。", scope: "SEO") {
                            TextField("例如：hugo, blog", text: $viewModel.config.params.keywords).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.location", title: "地理位置", helpText: "侧栏位置字段。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.location).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.userStatusEmoji", title: "状态 Emoji", helpText: "头像角标显示。", scope: "侧栏") {
                            TextField("", text: $viewModel.config.params.userStatusEmoji).textFieldStyle(.roundedBorder)
                        }
                        SettingRow(key: "params.avatar", title: "头像路径", helpText: "作者头像图片路径。", scope: "首页/文章/SEO") {
                            HStack {
                                TextField("/images/avatar.png", text: $viewModel.config.params.avatar).textFieldStyle(.roundedBorder)
                                Button("上传") {
                                    if let image = pickImage() {
                                        viewModel.importThemeImage(from: image, field: .avatar)
                                    }
                                }
                            }
                        }
                        SettingRow(key: "params.headerIcon", title: "顶部图标", helpText: "顶部导航中的站点图标。", scope: "导航") {
                            HStack {
                                TextField("/images/github-mark-white.png", text: $viewModel.config.params.headerIcon).textFieldStyle(.roundedBorder)
                                Button("上传") {
                                    if let image = pickImage() {
                                        viewModel.importThemeImage(from: image, field: .headerIcon)
                                    }
                                }
                            }
                        }
                        SettingRow(key: "params.favicon", title: "网站图标", helpText: "浏览器标签页 favicon。", scope: "全站") {
                            HStack {
                                TextField("/images/favicon.ico", text: $viewModel.config.params.favicon).textFieldStyle(.roundedBorder)
                                Button("上传") {
                                    if let image = pickImage() {
                                        viewModel.importThemeImage(from: image, field: .favicon)
                                    }
                                }
                            }
                        }
                    }
                }

                ModernCard(title: "功能开关") {
                    VStack(spacing: 10) {
                        SettingRow(key: "params.rss", title: "启用 RSS", helpText: "显示 RSS 入口，并输出 RSS 订阅内容。", scope: "分发") {
                            Toggle("", isOn: $viewModel.config.params.rss).labelsHidden()
                        }
                        SettingRow(key: "params.lastmod", title: "显示最后修改时间", helpText: "文章页显示 Modified 时间。", scope: "文章页") {
                            Toggle("", isOn: $viewModel.config.params.lastmod).labelsHidden()
                        }
                        if viewModel.shouldShowSearchSettings {
                            SettingRow(key: "params.enableSearch", title: "启用本地搜索", helpText: "开启后会使用 index.json 与 fuse.js。", scope: "搜索") {
                                Toggle("", isOn: $viewModel.config.params.enableSearch).labelsHidden()
                            }
                        }
                        if viewModel.shouldShowGitalkSettings {
                            SettingRow(key: "params.enableGitalk", title: "启用 Gitalk 评论", helpText: "文章底部加载 Gitalk 评论组件。", scope: "评论") {
                                Toggle("", isOn: $viewModel.config.params.enableGitalk).labelsHidden()
                            }
                        }
                        if viewModel.shouldShowMathSettings {
                            SettingRow(key: "params.math", title: "启用 KaTeX", helpText: "全站默认启用 KaTeX 数学渲染。", scope: "文章渲染") {
                                Toggle("", isOn: $viewModel.config.params.math).labelsHidden()
                            }
                            SettingRow(key: "params.MathJax", title: "启用 MathJax", helpText: "全站默认启用 MathJax（与 KaTeX 可同时存在但不建议）。", scope: "文章渲染") {
                                Toggle("", isOn: $viewModel.config.params.mathJax).labelsHidden()
                            }
                        }
                        SettingRow(key: "frontmatter.lastmod", title: "根据文件更新时间追踪 lastmod", helpText: "使用 :fileModTime 自动生成文章最后更新时间。", scope: "文章元数据") {
                            Toggle("", isOn: $viewModel.config.frontmatterTrackLastmod).labelsHidden()
                        }
                        SettingRow(key: "services.googleAnalytics.ID", title: "Google Analytics ID", helpText: "生产环境 HUGO_ENV=production 时生效。", scope: "统计") {
                            TextField("", text: $viewModel.config.googleAnalyticsID).textFieldStyle(.roundedBorder)
                        }

                        if !viewModel.shouldShowSearchSettings || !viewModel.shouldShowGitalkSettings || !viewModel.shouldShowMathSettings {
                            Text("已根据当前主题能力自动精简部分功能开关。若需手动覆盖，可在上方切换主题或手动输入主题名后应用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if viewModel.shouldShowSearchSettings {
                    ModernCard(title: "搜索输出格式") {
                        VStack(spacing: 10) {
                            SettingRow(key: "outputs.home", title: "首页输出类型", helpText: "要开启本地搜索，通常需要包含 html 与 json。", scope: "搜索") {
                                TextField("html, json", text: $outputsInput).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "outputFormats.json.mediaType", title: "JSON 媒体类型", helpText: "一般保持 application/json。", scope: "搜索") {
                                TextField("application/json", text: $viewModel.config.outputFormatJSONMediaType).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "outputFormats.json.baseName", title: "JSON 文件名", helpText: "默认 index，对应 /index.json。", scope: "搜索") {
                                TextField("index", text: $viewModel.config.outputFormatJSONBaseName).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "outputFormats.json.isPlainText", title: "JSON 纯文本输出", helpText: "通常保持 false。", scope: "搜索") {
                                Toggle("", isOn: $viewModel.config.outputFormatJSONIsPlainText).labelsHidden()
                            }
                        }
                    }
                }

                ModernCard(title: "自定义资源") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("params.custom_css（每行一个路径）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("添加后会在 head 中按顺序注入样式文件。")
                        TextEditor(text: $customCSSInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 90)
                            .padding(6)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("params.custom_js（每行一个路径）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("添加后会在 head 中按顺序注入脚本文件。")
                        TextEditor(text: $customJSInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 90)
                            .padding(6)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if viewModel.shouldShowGitalkSettings {
                    ModernCard(title: "Gitalk 评论配置") {
                        VStack(spacing: 10) {
                            SettingRow(key: "params.gitalk.clientID", title: "OAuth Client ID", helpText: "Gitalk GitHub OAuth 应用 ID。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.clientID).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.clientSecret", title: "OAuth Client Secret", helpText: "Gitalk GitHub OAuth 密钥。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.clientSecret).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.repo", title: "评论仓库", helpText: "存放 issue 评论的仓库名。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.repo).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.owner", title: "仓库所有者", helpText: "GitHub 用户名或组织名。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.owner).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.admin", title: "管理员", helpText: "管理员用户名（当前主题模板仍以 owner 为主）。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.admin).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.id", title: "Issue ID 规则", helpText: "通常为 location.pathname，保证文章唯一映射。", scope: "评论") {
                                TextField("location.pathname", text: $viewModel.config.params.gitalk.id).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.labels", title: "Issue 标签", helpText: "新建评论 issue 时默认标签。", scope: "评论") {
                                TextField("gitalk", text: $viewModel.config.params.gitalk.labels).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.perPage", title: "每页评论数", helpText: "评论分页数量，最大 100。", scope: "评论") {
                                Stepper(value: $viewModel.config.params.gitalk.perPage, in: 1...100) {
                                    Text("\(viewModel.config.params.gitalk.perPage)")
                                }
                            }
                            SettingRow(key: "params.gitalk.pagerDirection", title: "评论排序", helpText: "last 或 first。", scope: "评论") {
                                TextField("last / first", text: $viewModel.config.params.gitalk.pagerDirection).textFieldStyle(.roundedBorder)
                            }
                            SettingRow(key: "params.gitalk.createIssueManually", title: "手动创建 Issue", helpText: "true 表示管理员登录后自动创建 issue。", scope: "评论") {
                                Toggle("", isOn: $viewModel.config.params.gitalk.createIssueManually).labelsHidden()
                            }
                            SettingRow(key: "params.gitalk.distractionFreeMode", title: "无干扰模式", helpText: "评论输入框快捷提交模式。", scope: "评论") {
                                Toggle("", isOn: $viewModel.config.params.gitalk.distractionFreeMode).labelsHidden()
                            }
                            SettingRow(key: "params.gitalk.proxy", title: "代理地址", helpText: "GitHub OAuth 代理地址。", scope: "评论") {
                                TextField("", text: $viewModel.config.params.gitalk.proxy).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                if viewModel.shouldShowLinksSettings {
                    ModernCard(title: "自定义外链（params.links）") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(viewModel.config.params.links.enumerated()), id: \.element.id) { index, _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("链接 \(index + 1)")
                                            .font(.headline)
                                        ScopeBadge(text: "侧栏")
                                        Spacer()
                                        Button("删除") {
                                            viewModel.config.params.links.remove(at: index)
                                        }
                                    }
                                    TextField("title", text: bindingForLink(index, \.title))
                                        .textFieldStyle(.roundedBorder)
                                    TextField("href", text: bindingForLink(index, \.href))
                                        .textFieldStyle(.roundedBorder)
                                    TextField("icon（可选）", text: bindingForLink(index, \.icon))
                                        .textFieldStyle(.roundedBorder)
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Button("新增链接") {
                                viewModel.config.params.links.append(ThemeLink())
                            }
                        }
                    }
                }

                HStack {
                    Button("从 hugo.toml 重新读取") {
                        viewModel.loadAll()
                        syncTextInputs()
                    }
                    Button("保存主题配置") {
                        applyTextInputs()
                        viewModel.saveThemeConfig()
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding()
        }
        .onAppear {
            viewModel.refreshDetectedThemes()
            syncTextInputs()
        }
    }

    private var themeOptions: [String] {
        var names = viewModel.detectedThemes.map(\.name)
        let current = viewModel.config.theme.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && !containsTheme(current, in: names) {
            names.append(current)
        }
        if names.isEmpty {
            names.append("github-style")
        }
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var themeSelectionBinding: Binding<String> {
        Binding(
            get: {
                let current = viewModel.config.theme.trimmingCharacters(in: .whitespacesAndNewlines)
                if current.isEmpty {
                    return themeOptions.first ?? "github-style"
                }
                return current
            },
            set: { newValue in
                viewModel.selectTheme(named: newValue)
            }
        )
    }

    private func containsTheme(_ themeName: String, in names: [String]) -> Bool {
        let lower = themeName.lowercased()
        return names.contains { $0.lowercased() == lower }
    }

    private func bindingForLink(_ index: Int, _ keyPath: WritableKeyPath<ThemeLink, String>) -> Binding<String> {
        Binding {
            guard viewModel.config.params.links.indices.contains(index) else { return "" }
            return viewModel.config.params.links[index][keyPath: keyPath]
        } set: { newValue in
            guard viewModel.config.params.links.indices.contains(index) else { return }
            viewModel.config.params.links[index][keyPath: keyPath] = newValue
        }
    }

    private func syncTextInputs() {
        customCSSInput = viewModel.config.params.customCSS.joined(separator: "\n")
        customJSInput = viewModel.config.params.customJS.joined(separator: "\n")
        outputsInput = viewModel.config.outputsHome.joined(separator: ", ")
        taxonomyEntries = viewModel.config.taxonomies
            .sorted { $0.key < $1.key }
            .map { TaxonomyDraft(key: $0.key, value: $0.value) }
        languageEntries = viewModel.config.languageProfiles
            .sorted {
                if $0.weight == $1.weight {
                    return $0.code < $1.code
                }
                return $0.weight < $1.weight
            }
            .map { LanguageDraft(code: $0.code, title: $0.title, contentDir: $0.contentDir, weight: $0.weight) }
    }

    private func applyTextInputs() {
        viewModel.config.params.customCSS = splitLines(customCSSInput)
        viewModel.config.params.customJS = splitLines(customJSInput)
        viewModel.config.outputsHome = outputsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var taxonomies: [String: String] = [:]
        for entry in taxonomyEntries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            taxonomies[key] = value
        }
        viewModel.config.taxonomies = taxonomies

        viewModel.config.languageProfiles = languageEntries.compactMap { entry in
            let code = entry.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentDir = entry.contentDir.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !contentDir.isEmpty else { return nil }
            return HugoLanguageProfile(
                code: code,
                title: title.isEmpty ? code : title,
                contentDir: contentDir,
                weight: entry.weight
            )
        }
        .sorted {
            if $0.weight == $1.weight {
                return $0.code < $1.code
            }
            return $0.weight < $1.weight
        }
    }

    private func splitLines(_ input: String) -> [String] {
        input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func bindingForTaxonomy(_ index: Int, _ keyPath: WritableKeyPath<TaxonomyDraft, String>) -> Binding<String> {
        Binding {
            guard taxonomyEntries.indices.contains(index) else { return "" }
            return taxonomyEntries[index][keyPath: keyPath]
        } set: { newValue in
            guard taxonomyEntries.indices.contains(index) else { return }
            taxonomyEntries[index][keyPath: keyPath] = newValue
        }
    }

    private func bindingForLanguage(_ index: Int, _ keyPath: WritableKeyPath<LanguageDraft, String>) -> Binding<String> {
        Binding {
            guard languageEntries.indices.contains(index) else { return "" }
            return languageEntries[index][keyPath: keyPath]
        } set: { newValue in
            guard languageEntries.indices.contains(index) else { return }
            languageEntries[index][keyPath: keyPath] = newValue
        }
    }

    private func bindingForLanguageWeight(_ index: Int) -> Binding<Int> {
        Binding {
            guard languageEntries.indices.contains(index) else { return 0 }
            return languageEntries[index].weight
        } set: { newValue in
            guard languageEntries.indices.contains(index) else { return }
            languageEntries[index].weight = newValue
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
}

private struct TaxonomyDraft: Identifiable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

private struct LanguageDraft: Identifiable {
    var id = UUID()
    var code: String = ""
    var title: String = ""
    var contentDir: String = ""
    var weight: Int = 0
}

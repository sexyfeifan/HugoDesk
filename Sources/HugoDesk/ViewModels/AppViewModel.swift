import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    private let defaultWorkflowName = "Deploy Hugo site to Pages"
    private let defaultPublishCommitMessage = "通过 HugoDesk 发布博客更新  🎉"

    @Published var project: BlogProject
    @Published var config: ThemeConfig = ThemeConfig()
    @Published var detectedThemes: [DetectedTheme] = []

    @Published var posts: [BlogPost] = []
    @Published var selectedPostID: String?
    @Published var editorPost: BlogPost
    @Published var editorMode: EditorMode = .markdown
    @Published var newPostTitle: String = ""
    @Published var newPostFileName: String = "new-post.md"

    @Published var publishLog: String = ""
    @Published var publishLogEntries: [PublishLogEntry] = []
    @Published var publishMessage: String = "通过 HugoDesk 发布博客更新  🎉"
    @Published var publishRemoteURL: String = ""
    @Published var githubFineGrainedToken: String = ""
    @Published var githubClassicToken: String = ""
    @Published var previewRenderToken: Int = 0
    @Published var aiBaseURL: String = AIProfile.default.baseURL
    @Published var aiModel: String = AIProfile.default.model
    @Published var aiAPIKey: String = ""
    @Published var latestWorkflowStatus: WorkflowRunStatus?
    @Published var latestWorkflowError: String = ""
    @Published var latestWorkflowCheckedAt: Date?
    @Published var pagesSiteStatus: GitHubPagesSiteStatus?
    @Published var pagesSiteError: String = ""
    @Published var githubPingMilliseconds: Double?
    @Published var githubConnectivityError: String = ""
    @Published var isAIFormatting: Bool = false
    @Published var aiFormattingProgress: Double = 0
    @Published var aiFormattingStatus: String = ""
    @Published var lastHugoStructureReport: HugoStructureReport?
    @Published var showHugoStructureRepairPrompt: Bool = false
    @Published var activeAlert: AppAlertItem?
    @Published var isBusy: Bool = false
    @Published var statusText: String = ""

    private let configService = ConfigService()
    private let postService = PostService()
    private let publishService = PublishService()
    private let imageAssetService = ImageAssetService()
    private let actionsService = GitHubActionsService()
    private let pagesService = GitHubPagesService()
    private let credentialStore = CredentialStore()
    private let aiService = AIService()
    private var livePreviewTask: Task<Void, Never>?
    private var preflightMonitorTask: Task<Void, Never>?
    private var actionsStatusMonitorTask: Task<Void, Never>?
    private var aiFormattingProgressTask: Task<Void, Never>?
    private static let hugoToolOperationNames: Set<String> = [
        "检查 Hugo 版本",
        "升级 Hugo",
        "检测 Hugo 文件结构",
        "修复 Hugo 文件结构"
    ]

    init() {
        let project = BlogProject.bootstrap()
        self.project = project
        self.editorPost = BlogPost.empty(in: project.contentURL)
        self.newPostTitle = ""
        self.newPostFileName = "new-post.md"
        loadAll()
    }

    deinit {
        livePreviewTask?.cancel()
        preflightMonitorTask?.cancel()
        actionsStatusMonitorTask?.cancel()
        aiFormattingProgressTask?.cancel()
    }

    var localConfigBundlePath: String {
        project.localConfigBundleURL.path
    }

    var selectedDetectedTheme: DetectedTheme? {
        let current = config.theme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !current.isEmpty else { return nil }
        return detectedThemes.first { $0.name.lowercased() == current }
    }

    var shouldShowGitalkSettings: Bool {
        guard let theme = selectedDetectedTheme else { return true }
        return !theme.hasCapabilitySignals || theme.supportsGitalk
    }

    var shouldShowSearchSettings: Bool {
        guard let theme = selectedDetectedTheme else { return true }
        return !theme.hasCapabilitySignals || theme.supportsSearch
    }

    var shouldShowLinksSettings: Bool {
        guard let theme = selectedDetectedTheme else { return true }
        return !theme.hasCapabilitySignals || theme.supportsLinks
    }

    var shouldShowMathSettings: Bool {
        guard let theme = selectedDetectedTheme else { return true }
        return !theme.hasCapabilitySignals || theme.supportsMath
    }

    var githubTokenUsageSummary: String {
        let hasClassic = !githubClassicToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFine = !githubFineGrainedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (hasClassic, hasFine) {
        case (true, true):
            return "Classic + Fine-grained（API 优先使用 Classic）"
        case (true, false):
            return "Classic"
        case (false, true):
            return "Fine-grained"
        case (false, false):
            return "未配置"
        }
    }

    private var preferredGitHubToken: String {
        let classic = githubClassicToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !classic.isEmpty {
            return classic
        }
        return githubFineGrainedToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasGitHubToken: Bool {
        !preferredGitHubToken.isEmpty
    }

    private var normalizedPublishMessage: String {
        let trimmed = publishMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultPublishCommitMessage : trimmed
    }

    func loadAll() {
        do {
            config = try configService.loadConfig(for: project)
            loadRemoteProfile()
            loadAIProfile()
            let localBundleLoaded = loadLocalConfigBundleIfPresent()
            normalizeContentSubpathIfNeeded(localBundleLoaded: localBundleLoaded)
            refreshDetectedThemes()
            posts = try postService.loadPosts(for: project)
            if let first = posts.first {
                selectedPostID = first.id
                editorPost = first
            } else {
                editorPost = BlogPost.empty(in: project.contentURL)
            }
            persistProjectRootPath(project.rootPath)
            statusText = localBundleLoaded ? "项目已加载（已读取本地配置包）。" : "项目已加载。"
        } catch {
            statusText = error.localizedDescription
        }
        startPreflightMonitor()
        startActionsStatusMonitor()
    }

    func setProjectRootPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "博客根目录不能为空。"
            return
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusText = "目录不存在：\(trimmed)"
            return
        }

        project.rootPath = URL(fileURLWithPath: trimmed, isDirectory: true).path
        loadAll()
    }

    func saveRemoteProfile() {
        do {
            let profile = RemoteProfile(
                remoteURL: publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines),
                workflowName: defaultWorkflowName
            )
            try credentialStore.saveRemoteProfile(profile, for: project.rootPath)
            credentialStore.saveTokenFineGrained(githubFineGrainedToken, for: project.rootPath)
            credentialStore.saveTokenClassic(githubClassicToken, for: project.rootPath)
            try saveLocalConfigBundle()
            statusText = "远程与令牌设置已保存，并同步到项目配置包。"
            Task { await self.runAllPreflightChecksSilently() }
            startActionsStatusMonitor()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func saveAISettings() {
        do {
            let profile = AIProfile(
                baseURL: aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                model: aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try credentialStore.saveAIProfile(profile, for: project.rootPath)
            credentialStore.saveAIAPIKey(aiAPIKey, for: project.rootPath)
            try saveLocalConfigBundle()
            statusText = "AI 设置已保存，并同步到项目配置包。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func loadSelectedPost() {
        guard let selectedPostID else { return }
        guard let file = posts.first(where: { $0.id == selectedPostID })?.fileURL else { return }
        do {
            editorPost = try postService.loadPost(at: file)
        } catch {
            statusText = error.localizedDescription
        }
    }

    func createNewPost() {
        editorPost = postService.createNewPost(title: "未命名文章", fileName: nil, in: project)
        selectedPostID = nil
        statusText = "已创建新草稿。"
    }

    func updateSuggestedFileName() {
        newPostFileName = postService.suggestFileName(from: newPostTitle)
    }

    func updateTitleFromFileName() {
        editorPost.title = postService.suggestTitle(fromFileName: editorPost.fileName)
        statusText = "已根据文件名生成标题。"
    }

    func updateSummaryFromBody() {
        editorPost.summary = postService.suggestSummary(fromMarkdown: editorPost.body)
        statusText = editorPost.summary.isEmpty ? "正文为空，无法提取摘要。" : "已从正文提取摘要。"
    }

    func createPostFromForm() {
        let title = newPostTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.isEmpty ? "未命名文章" : title
        editorPost = postService.createNewPost(title: finalTitle, fileName: newPostFileName, in: project)
        editorPost.body = ""
        selectedPostID = nil
        statusText = "已创建新文章：\(editorPost.fileName)"
    }

    func deleteCurrentPost() {
        do {
            try postService.deletePost(at: editorPost.fileURL)
            posts = try postService.loadPosts(for: project)
            if let first = posts.first {
                selectedPostID = first.id
                editorPost = first
            } else {
                selectedPostID = nil
                editorPost = BlogPost.empty(in: project.contentURL)
            }
            statusText = "文章已删除。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    @discardableResult
    func insertPostSnippet(_ snippet: String, at range: NSRange? = nil) -> NSRange {
        let body = editorPost.body
        let ns = body as NSString

        if let range {
            let clamped = clampRange(range, textLength: ns.length)
            let mutable = NSMutableString(string: body)
            mutable.replaceCharacters(in: clamped, with: snippet)
            editorPost.body = mutable as String
            return NSRange(location: clamped.location + (snippet as NSString).length, length: 0)
        }

        if body.isEmpty {
            editorPost.body = snippet
            return NSRange(location: (snippet as NSString).length, length: 0)
        }

        if body.hasSuffix("\n") {
            editorPost.body += snippet
            return NSRange(location: (editorPost.body as NSString).length, length: 0)
        }

        editorPost.body += "\n" + snippet
        return NSRange(location: (editorPost.body as NSString).length, length: 0)
    }

    @discardableResult
    func importImageIntoPost(from sourceURL: URL, altText: String, insertionRange: NSRange?) -> NSRange {
        do {
            let text = try makeImportedImageMarkdown(from: sourceURL, altText: altText)
            let range = insertPostSnippet(text, at: insertionRange)
            return range
        } catch {
            statusText = error.localizedDescription
            return insertionRange ?? NSRange(location: (editorPost.body as NSString).length, length: 0)
        }
    }

    func makeImportedImageMarkdown(from sourceURL: URL, altText: String) throws -> String {
        let webPath = try imageAssetService.importImage(from: sourceURL, project: project, subfolder: "uploads")
        let resolvedAlt = resolvedImageAltText(altText, fallbackURL: sourceURL)
        statusText = "图片已导入：\(webPath)"
        return "![\(resolvedAlt)](\(webPath))\n"
    }

    func importThemeImage(from sourceURL: URL, field: ThemeImageField) {
        do {
            let webPath = try imageAssetService.importImage(from: sourceURL, project: project, subfolder: "settings")
            switch field {
            case .avatar:
                config.params.avatar = webPath
            case .headerIcon:
                config.params.headerIcon = webPath
            case .favicon:
                config.params.favicon = webPath
            }
            statusText = "主题图片已导入：\(webPath)"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func saveCurrentPost() {
        do {
            try postService.savePost(editorPost)
            posts = try postService.loadPosts(for: project)
            selectedPostID = editorPost.id
            statusText = "文章已保存。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func resolvedImageAltText(_ altText: String, fallbackURL: URL) -> String {
        let trimmed = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallback = fallbackURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fallback.isEmpty ? "image" : fallback
    }

    func saveThemeConfig() {
        do {
            try configService.saveConfig(config, for: project)
            try saveLocalConfigBundle()
            refreshDetectedThemes()
            statusText = "hugo.toml 已保存，并同步到项目配置包。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func selectTheme(named themeName: String) {
        let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        config.theme = trimmed
        refreshDetectedThemes()
    }

    func refreshDetectedThemes() {
        detectedThemes = Self.scanDetectedThemes(in: project.rootURL, configuredThemeName: config.theme)
    }

    func runBuild() {
        runTask(operation: "构建站点", successStatus: "构建完成。") {
            let output = try self.publishService.runHugoBuild(project: self.project)
            return output.isEmpty ? "构建完成（无输出）。" : output
        }
    }

    func refreshRenderedPreview() {
        runTask(operation: "刷新最终预览", successStatus: "最终预览已刷新。") {
            let output = try self.publishService.runHugoBuild(project: self.project)
            self.previewRenderToken &+= 1
            return output.isEmpty ? "构建完成（无输出）。" : output
        }
    }

    func runHugoVersionCheck() {
        runTask(operation: "检查 Hugo 版本", successStatus: "Hugo 版本已更新。") {
            try self.publishService.hugoVersion(project: self.project)
        }
    }

    func runHugoUpgrade() {
        runTask(operation: "升级 Hugo", successStatus: "Hugo 升级流程完成。") {
            try self.publishService.upgradeHugo(project: self.project)
        }
    }

    func runHugoStructureCheck() {
        runTask(operation: "检测 Hugo 文件结构", successStatus: "Hugo 文件结构检测完成。") {
            let report = self.publishService.checkHugoStructure(project: self.project)
            self.lastHugoStructureReport = report
            self.showHugoStructureRepairPrompt = report.hasMissingRequiredItems
            return report.renderCheckLog()
        }
    }

    func runHugoStructureRepair() {
        runTask(operation: "修复 Hugo 文件结构", successStatus: "Hugo 文件结构修复完成。") {
            let report = try self.publishService.repairHugoStructure(project: self.project)
            self.lastHugoStructureReport = report
            self.showHugoStructureRepairPrompt = false
            return report.renderRepairLog()
        }
    }

    func dismissHugoStructureRepairPrompt() {
        showHugoStructureRepairPrompt = false
    }

    func runSyncWithRemote() {
        runTask(operation: "同步远端", successStatus: "已与远端分支同步。") {
            let output = try self.publishService.syncWithRemote(
                project: self.project,
                remoteURL: self.publishRemoteURL,
                githubToken: self.preferredGitHubToken
            )
            return output.isEmpty ? "同步完成（无输出）。" : output
        }
    }

    func runPublish() {
        runUnifiedPublishWorkflow(operation: "提交并推送")
    }

    func runGuidedPublishWorkflow() {
        runUnifiedPublishWorkflow(operation: "一键发布")
    }

    private func runUnifiedPublishWorkflow(operation: String) {
        runAsyncTask(operation: operation, successStatus: "发布流程完成。") {
            try await self.executeUnifiedPublishPipeline()
        }
    }

    private func executeUnifiedPublishPipeline() async throws -> String {
        var logs: [String] = []

        let structure = publishService.checkHugoStructure(project: project)
        lastHugoStructureReport = structure
        guard !structure.hasMissingRequiredItems else {
            showHugoStructureRepairPrompt = true
            throw PublishWorkflowError.missingStructure(items: structure.missingRequiredItemsForPrompt)
        }
        logs.append(structure.renderCheckLog())

        try saveEditorPostIfNeeded()
        let fixed = try imageAssetService.normalizePostImageLinks(project: project)
        if fixed.changedLinks > 0 {
            logs.append("== 图片链接归一化 ==\n已自动修正图片链接：\(fixed.changedLinks) 条，影响文件 \(fixed.changedFiles) 个。")
        }

        let remote = publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = preferredGitHubToken

        let sync = try publishService.syncWithRemote(
            project: project,
            remoteURL: publishRemoteURL,
            githubToken: token
        )
        if !sync.isEmpty {
            logs.append(sync)
        }

        if publishService.hasGitHubPagesWorkflow(project: project) {
            logs.append("== Pages Workflow ==\n已检测到 .github/workflows/hugo.yaml")
        } else {
            let workflow = try publishService.ensureGitHubPagesWorkflow(project: project)
            logs.append("== 自动补齐 Pages Workflow ==\n\(workflow)")
        }

        if !remote.isEmpty, !token.isEmpty {
            do {
                var pages = try await pagesService.fetchSiteStatus(remoteURL: remote, token: token)
                logs.append("""
                == 检查 Pages 来源 ==
                build_type: \(pages.buildType)
                source: \(pages.sourceDescription)
                访问地址: \(pages.htmlURL)
                """)
                if pages.buildType.lowercased() != "workflow" {
                    pages = try await pagesService.switchToWorkflowBuild(
                        remoteURL: remote,
                        token: token,
                        branch: project.publishBranch
                    )
                    logs.append("""
                    == 修复 Pages 来源 ==
                    build_type: \(pages.buildType)
                    source: \(pages.sourceDescription)
                    访问地址: \(pages.htmlURL)
                    """)
                }
                pagesSiteStatus = pages
                pagesSiteError = ""
            } catch {
                let hint: String
                if githubClassicToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !githubFineGrainedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hint = "\n提示：当前仅配置 Fine-grained Token。若 Pages 来源检查/重置持续失败，建议在“项目 > 远程地址与凭据”补充 Classic Token。"
                } else {
                    hint = ""
                }
                let message = error.localizedDescription + hint
                pagesSiteError = message
                presentAlert(title: "Pages 来源检查失败", message: message)
                logs.append("== 检查/修复 Pages 来源 ==\n警告（已跳过，不阻断发布）：\(message)")
            }
        } else {
            logs.append("== 检查 Pages 来源 ==\n跳过：未配置远程地址或 GitHub Token。")
        }

        let publish = try publishService.commitAndPush(
            project: project,
            message: normalizedPublishMessage,
            remoteURL: publishRemoteURL,
            githubToken: token
        )
        logs.append(publish)

        if !remote.isEmpty, !token.isEmpty {
            do {
                let run = try await actionsService.fetchLatestRun(
                    remoteURL: remote,
                    token: token,
                    workflowName: defaultWorkflowName,
                    branch: project.publishBranch
                )
                latestWorkflowStatus = run
                latestWorkflowError = ""
                latestWorkflowCheckedAt = Date()
                logs.append("""
                == 最新 Actions 运行 ==
                Workflow: \(run.name)
                状态: \(run.statusText)
                分支: \(run.branch)
                提交: \(run.sha)
                详情: \(run.htmlURL)
                """)
            } catch {
                latestWorkflowError = error.localizedDescription
                latestWorkflowCheckedAt = Date()
                logs.append("== 最新 Actions 运行 ==\n警告：\(error.localizedDescription)")
            }
        } else {
            logs.append("== 最新 Actions 运行 ==\n跳过：未配置远程地址或 GitHub Token。")
        }

        return logs.joined(separator: "\n\n")
    }

    private func saveEditorPostIfNeeded() throws {
        let hasContent = !editorPost.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorPost.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || FileManager.default.fileExists(atPath: editorPost.fileURL.path)
        if hasContent {
            try postService.savePost(editorPost)
        }
    }

    func refreshActionsStatus() {
        runAsyncTask(operation: "查询 Actions 状态", successStatus: "已获取最新 Actions 状态。") {
            self.latestWorkflowError = ""
            self.latestWorkflowStatus = nil
            let run = try await self.actionsService.fetchLatestRun(
                remoteURL: self.publishRemoteURL,
                token: self.preferredGitHubToken,
                workflowName: self.defaultWorkflowName,
                branch: self.project.publishBranch
            )
            self.latestWorkflowStatus = run
            self.latestWorkflowCheckedAt = Date()
            return """
            Workflow: \(run.name)
            分支: \(run.branch)
            状态: \(run.statusText)
            提交: \(run.sha)
            详情: \(run.htmlURL)
            """
        }
    }

    func refreshPagesSourceStatus() {
        runAsyncTask(operation: "检查 Pages 来源", successStatus: "Pages 来源检查完成。") {
            self.pagesSiteError = ""
            self.pagesSiteStatus = nil
            let status = try await self.pagesService.fetchSiteStatus(
                remoteURL: self.publishRemoteURL,
                token: self.preferredGitHubToken
            )
            self.pagesSiteStatus = status
            return """
            build_type: \(status.buildType)
            source: \(status.sourceDescription)
            访问地址: \(status.htmlURL)
            """
        }
    }

    func repairPagesSourceToWorkflow() {
        runAsyncTask(operation: "修复 Pages 来源", successStatus: "Pages 来源已切换为 GitHub Actions。") {
            self.pagesSiteError = ""
            let status = try await self.pagesService.switchToWorkflowBuild(
                remoteURL: self.publishRemoteURL,
                token: self.preferredGitHubToken,
                branch: self.project.publishBranch
            )
            self.pagesSiteStatus = status
            return """
            build_type: \(status.buildType)
            source: \(status.sourceDescription)
            访问地址: \(status.htmlURL)
            """
        }
    }

    func formatPostWithAI(selectionRange: NSRange?, onComplete: @escaping (NSRange) -> Void) {
        guard !isAIFormatting else {
            statusText = "AI 排版仍在进行中，请稍候。"
            return
        }

        let currentText = editorPost.body
        let ns = currentText as NSString
        let targetRange: NSRange = {
            guard let selectionRange else {
                return NSRange(location: 0, length: ns.length)
            }
            let clamped = clampRange(selectionRange, textLength: ns.length)
            return clamped.length > 0 ? clamped : NSRange(location: 0, length: ns.length)
        }()
        let source = ns.substring(with: targetRange).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            statusText = "文本为空，无法进行 AI 排版。"
            return
        }

        isBusy = true
        startAITaskProgress(.formatting)
        Task {
            defer { isBusy = false }
            do {
                let profile = AIProfile(
                    baseURL: self.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: self.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let formatted = try await self.aiService.formatMarkdown(
                    input: source,
                    profile: profile,
                    apiKey: self.aiAPIKey
                )
                let mutable = NSMutableString(string: self.editorPost.body)
                mutable.replaceCharacters(in: targetRange, with: formatted)
                self.editorPost.body = mutable as String
                let nextRange = NSRange(location: targetRange.location + (formatted as NSString).length, length: 0)
                onComplete(nextRange)
                self.statusText = "AI Markdown 排版完成。"
                self.finishAITaskProgress(.formatting, success: true)
            } catch {
                self.statusText = error.localizedDescription
                self.finishAITaskProgress(.formatting, success: false)
            }
        }
    }

    func generateWritingWithAI(sourceInput: String, onComplete: @escaping (String) -> Void) {
        guard !isAIFormatting else {
            statusText = "AI 写作仍在进行中，请稍候。"
            return
        }

        let source = sourceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            statusText = "请输入写作素材或链接。"
            return
        }

        isBusy = true
        startAITaskProgress(.writing)
        Task {
            defer { isBusy = false }
            do {
                let profile = AIProfile(
                    baseURL: self.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: self.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let generated = try await self.aiService.writeMarkdown(
                    input: source,
                    profile: profile,
                    apiKey: self.aiAPIKey
                )
                onComplete(generated)
                self.statusText = "AI 写作完成，结果已追加到正文。"
                self.finishAITaskProgress(.writing, success: true)
            } catch {
                self.statusText = error.localizedDescription
                self.finishAITaskProgress(.writing, success: false)
            }
        }
    }

    private func startAITaskProgress(_ task: AITaskKind) {
        isAIFormatting = true
        aiFormattingProgress = 0.05
        aiFormattingStatus = task.initialStatus

        aiFormattingProgressTask?.cancel()
        aiFormattingProgressTask = Task { [weak self] in
            for stage in task.stages {
                try? await Task.sleep(nanoseconds: stage.delay)
                guard let self, !Task.isCancelled else { return }
                if self.isAIFormatting, self.aiFormattingProgress < stage.progress {
                    self.aiFormattingProgress = stage.progress
                    self.aiFormattingStatus = stage.message
                }
            }
        }
    }

    private func finishAITaskProgress(_ task: AITaskKind, success: Bool) {
        aiFormattingProgressTask?.cancel()
        aiFormattingProgressTask = nil

        aiFormattingProgress = success ? 1.0 : max(aiFormattingProgress, 0.1)
        aiFormattingStatus = success ? task.successStatus : task.failureStatus

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            self.isAIFormatting = false
            self.aiFormattingProgress = 0
            self.aiFormattingStatus = ""
        }
    }

    private enum AITaskKind {
        case formatting
        case writing

        var initialStatus: String {
            switch self {
            case .formatting:
                return "准备检查 Markdown 结构..."
            case .writing:
                return "准备读取素材内容..."
            }
        }

        var successStatus: String {
            switch self {
            case .formatting:
                return "AI 排版完成。"
            case .writing:
                return "AI 写作完成。"
            }
        }

        var failureStatus: String {
            switch self {
            case .formatting:
                return "AI 排版失败。"
            case .writing:
                return "AI 写作失败。"
            }
        }

        var stages: [(delay: UInt64, progress: Double, message: String)] {
            switch self {
            case .formatting:
                return [
                    (300_000_000, 0.18, "检查标题、列表与代码块边界..."),
                    (600_000_000, 0.36, "校验 Markdown 符号闭合正确性..."),
                    (900_000_000, 0.58, "清理无意义字符与重复标点..."),
                    (1_200_000_000, 0.78, "优化段落与语义结构..."),
                    (1_500_000_000, 0.90, "等待 AI 返回修正结果...")
                ]
            case .writing:
                return [
                    (250_000_000, 0.16, "识别素材中的文字与链接..."),
                    (600_000_000, 0.34, "读取链接内容与上下文..."),
                    (950_000_000, 0.56, "整理可用事实与结构重点..."),
                    (1_250_000_000, 0.76, "调用预设大模型生成 Markdown 草稿..."),
                    (1_600_000_000, 0.90, "等待 AI 返回写作结果...")
                ]
            }
        }
    }

    func runEnvironmentDiagnostics() {
        runTask(operation: "一键检测推送能力", successStatus: "发布环境检测完成。") {
            let report = try self.publishService.diagnosePublishEnvironment(
                project: self.project,
                remoteURL: self.publishRemoteURL,
                githubToken: self.preferredGitHubToken
            )
            return report
        }
    }

    func bootstrapGitHubPagesWorkflow() {
        runTask(operation: "生成 Pages Workflow", successStatus: "Pages Workflow 已生成。") {
            let detail = try self.publishService.ensureGitHubPagesWorkflow(project: self.project)
            return """
            Workflow 文件：
            \(detail)
            下一步：
            1) 点击“提交并推送”
            2) 在 GitHub 仓库设置中确认 Pages Source 为 GitHub Actions
            """
        }
    }

    func exportConfigBundleToProject() {
        do {
            try saveLocalConfigBundle()
            statusText = "配置包已导出到：\(project.localConfigBundleURL.path)"
        } catch {
            statusText = "导出失败：\(error.localizedDescription)"
        }
    }

    func importConfigBundleFromProject() {
        do {
            guard FileManager.default.fileExists(atPath: project.localConfigBundleURL.path) else {
                statusText = "还原失败：项目目录中未找到 .hugodesk.local.json"
                return
            }
            let bundle = try loadConfigBundle(from: project.localConfigBundleURL)
            try restoreConfigBundle(bundle, sourceName: project.localConfigBundleURL.lastPathComponent, persistToProjectBundle: false)
            statusText = "配置包已还原：\(project.localConfigBundleURL.lastPathComponent)"
        } catch {
            statusText = "还原失败：\(error.localizedDescription)"
        }
    }

    private func makeConfigBundleSnapshot() -> ConfigBackupBundle {
        ConfigBackupBundle(
            exportedAt: Date(),
            project: project,
            themeConfig: config,
            remoteProfile: RemoteProfile(
                remoteURL: publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines),
                workflowName: defaultWorkflowName
            ),
            githubTokenClassic: githubClassicToken.trimmingCharacters(in: .whitespacesAndNewlines),
            githubTokenFineGrained: githubFineGrainedToken.trimmingCharacters(in: .whitespacesAndNewlines),
            aiProfile: AIProfile(
                baseURL: aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                model: aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            aiAPIKey: aiAPIKey
        )
    }

    private func loadConfigBundle(from url: URL) throws -> ConfigBackupBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfigBackupBundle.self, from: data)
    }

    private func saveLocalConfigBundle() throws {
        let bundle = makeConfigBundleSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        try data.write(to: project.localConfigBundleURL, options: .atomic)
    }

    private func restoreConfigBundle(
        _ bundle: ConfigBackupBundle,
        sourceName: String,
        persistToProjectBundle: Bool
    ) throws {
        applyProjectSettings(from: bundle.project)
        config = bundle.themeConfig
        publishRemoteURL = bundle.remoteProfile.remoteURL
        githubClassicToken = bundle.githubTokenClassic
        githubFineGrainedToken = bundle.githubTokenFineGrained
        aiBaseURL = bundle.aiProfile.baseURL.isEmpty ? AIProfile.default.baseURL : bundle.aiProfile.baseURL
        aiModel = bundle.aiProfile.model.isEmpty ? AIProfile.default.model : bundle.aiProfile.model
        aiAPIKey = bundle.aiAPIKey

        try configService.saveConfig(config, for: project)
        try credentialStore.saveRemoteProfile(bundle.remoteProfile, for: project.rootPath)
        credentialStore.saveTokenClassic(bundle.githubTokenClassic, for: project.rootPath)
        credentialStore.saveTokenFineGrained(bundle.githubTokenFineGrained, for: project.rootPath)
        try credentialStore.saveAIProfile(bundle.aiProfile, for: project.rootPath)
        credentialStore.saveAIAPIKey(bundle.aiAPIKey, for: project.rootPath)
        if persistToProjectBundle {
            try saveLocalConfigBundle()
        }

        posts = try postService.loadPosts(for: project)
        if let first = posts.first {
            selectedPostID = first.id
            editorPost = first
        } else {
            selectedPostID = nil
            editorPost = BlogPost.empty(in: project.contentURL)
        }

        appendPublishLog(
            operation: "配置还原",
            summary: "已从 \(sourceName) 还原配置。",
            details: "配置源：\(sourceName)",
            level: .success
        )
    }

    private func loadLocalConfigBundleIfPresent() -> Bool {
        guard FileManager.default.fileExists(atPath: project.localConfigBundleURL.path) else {
            return false
        }

        do {
            let bundle = try loadConfigBundle(from: project.localConfigBundleURL)
            applyProjectSettings(from: bundle.project)
            publishRemoteURL = bundle.remoteProfile.remoteURL
            githubClassicToken = bundle.githubTokenClassic.isEmpty
                ? credentialStore.loadTokenClassic(for: project.rootPath)
                : bundle.githubTokenClassic
            githubFineGrainedToken = bundle.githubTokenFineGrained.isEmpty
                ? credentialStore.loadTokenFineGrained(for: project.rootPath)
                : bundle.githubTokenFineGrained
            aiBaseURL = bundle.aiProfile.baseURL.isEmpty ? AIProfile.default.baseURL : bundle.aiProfile.baseURL
            aiModel = bundle.aiProfile.model.isEmpty ? AIProfile.default.model : bundle.aiProfile.model
            aiAPIKey = bundle.aiAPIKey.isEmpty ? credentialStore.loadAIAPIKey(for: project.rootPath) : bundle.aiAPIKey
            return true
        } catch {
            appendPublishLog(
                operation: "读取本地配置包",
                summary: "读取失败",
                details: "错误：\(error.localizedDescription)\n路径：\(project.localConfigBundleURL.path)",
                level: .warning
            )
            return false
        }
    }

    private func applyProjectSettings(from source: BlogProject) {
        project.hugoExecutable = source.hugoExecutable
        project.contentSubpath = source.contentSubpath
        project.gitRemote = source.gitRemote
        project.publishBranch = source.publishBranch
    }

    private func normalizeContentSubpathIfNeeded(localBundleLoaded: Bool) {
        guard !localBundleLoaded else {
            return
        }

        let fm = FileManager.default
        let current = project.contentSubpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            var isDirectory = ObjCBool(false)
            let currentPath = project.rootURL.appendingPathComponent(current, isDirectory: true).path
            if fm.fileExists(atPath: currentPath, isDirectory: &isDirectory), isDirectory.boolValue {
                return
            }
        }

        let postsPath = project.rootURL.appendingPathComponent("content/posts", isDirectory: true).path
        var isDirectory = ObjCBool(false)
        if fm.fileExists(atPath: postsPath, isDirectory: &isDirectory), isDirectory.boolValue {
            project.contentSubpath = "content/posts"
            return
        }

        let postPath = project.rootURL.appendingPathComponent("content/post", isDirectory: true).path
        isDirectory = ObjCBool(false)
        if fm.fileExists(atPath: postPath, isDirectory: &isDirectory), isDirectory.boolValue {
            project.contentSubpath = "content/post"
        }
    }

    private func persistProjectRootPath(_ path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        UserDefaults.standard.set(normalized, forKey: BlogProject.lastRootPathDefaultsKey)
    }

    func clearPublishLogs() {
        publishLogEntries.removeAll()
        publishLog = ""
    }

    func refreshPublishLogSnapshot() {
        publishLog = publishLogEntries.map(\.rendered).joined(separator: "\n\n")
        statusText = "日志已刷新。"
    }

    private func appendPublishLog(
        operation: String,
        summary: String,
        details: String,
        level: PublishLogEntry.Level
    ) {
        let entry = PublishLogEntry(
            timestamp: Date(),
            operation: operation,
            summary: summary,
            details: details,
            level: level
        )
        publishLogEntries.append(entry)
        publishLog = publishLogEntries.map(\.rendered).joined(separator: "\n\n")
    }

    private func runTask(
        operation: String,
        successStatus: String,
        _ action: @escaping () throws -> String
    ) {
        isBusy = true
        appendPublishLog(
            operation: operation,
            summary: "开始执行",
            details: "时间：\(Date().formatted(date: .omitted, time: .standard))",
            level: .info
        )
        Task {
            defer { isBusy = false }
            do {
                let details = try action()
                appendPublishLog(
                    operation: operation,
                    summary: "执行完成",
                    details: details,
                    level: .success
                )
                statusText = successStatus
            } catch {
                let errorText = error.localizedDescription
                appendPublishLog(
                    operation: operation,
                    summary: "执行失败",
                    details: errorText,
                    level: .error
                )
                statusText = "\(operation)失败，请查看日志。"
                presentAlert(title: "\(operation)失败", message: errorText)
                await appendAITroubleshootingIfConfigured(operation: operation, errorLog: errorText)
            }
        }
    }

    private func runAsyncTask(
        operation: String,
        successStatus: String,
        _ action: @escaping () async throws -> String
    ) {
        isBusy = true
        appendPublishLog(
            operation: operation,
            summary: "开始执行",
            details: "时间：\(Date().formatted(date: .omitted, time: .standard))",
            level: .info
        )
        Task {
            defer { isBusy = false }
            do {
                let details = try await action()
                appendPublishLog(
                    operation: operation,
                    summary: "执行完成",
                    details: details,
                    level: .success
                )
                if operation == "查询 Actions 状态" {
                    latestWorkflowError = ""
                    latestWorkflowCheckedAt = Date()
                }
                if operation.contains("Pages") {
                    pagesSiteError = ""
                }
                statusText = successStatus
            } catch {
                let errorText = error.localizedDescription
                if operation == "查询 Actions 状态" {
                    latestWorkflowError = errorText
                    latestWorkflowCheckedAt = Date()
                }
                if operation.contains("Pages") {
                    pagesSiteError = errorText
                }
                appendPublishLog(
                    operation: operation,
                    summary: "执行失败",
                    details: errorText,
                    level: .error
                )
                statusText = "\(operation)失败，请查看日志。"
                presentAlert(title: "\(operation)失败", message: errorText)
                await appendAITroubleshootingIfConfigured(operation: operation, errorLog: errorText)
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        activeAlert = AppAlertItem(title: title, message: message)
    }

    private func appendAITroubleshootingIfConfigured(operation: String, errorLog: String) async {
        let profile = AIProfile(
            baseURL: aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let token = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.baseURL.isEmpty, !profile.model.isEmpty, !token.isEmpty else {
            return
        }

        do {
            let clippedError = String(errorLog.prefix(3000))
            let advice = try await aiService.suggestFix(
                operation: operation,
                errorLog: clippedError,
                profile: profile,
                apiKey: token
            )
            appendPublishLog(
                operation: "AI 排障建议",
                summary: "已生成 \(operation) 的修复建议",
                details: advice,
                level: .warning
            )
        } catch {
            appendPublishLog(
                operation: "AI 排障建议",
                summary: "生成失败",
                details: error.localizedDescription,
                level: .warning
            )
        }
    }

    private func clampRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = max(0, min(range.location, textLength))
        let end = max(location, min(range.location + range.length, textLength))
        return NSRange(location: location, length: end - location)
    }

    private func loadRemoteProfile() {
        if let profile = credentialStore.loadRemoteProfile(for: project.rootPath) {
            publishRemoteURL = profile.remoteURL
        } else {
            publishRemoteURL = publishService.detectRemoteURL(project: project)
        }
        githubClassicToken = credentialStore.loadTokenClassic(for: project.rootPath)
        githubFineGrainedToken = credentialStore.loadTokenFineGrained(for: project.rootPath)
    }

    private func loadAIProfile() {
        let profile = credentialStore.loadAIProfile(for: project.rootPath)
        aiBaseURL = profile.baseURL
        aiModel = profile.model
        aiAPIKey = credentialStore.loadAIAPIKey(for: project.rootPath)
    }

    private func startPreflightMonitor() {
        preflightMonitorTask?.cancel()
        preflightMonitorTask = Task { [weak self] in
            guard let self else { return }
            await self.runAllPreflightChecksSilently()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshGitHubConnectivitySilently()
            }
        }
    }

    private func startActionsStatusMonitor() {
        actionsStatusMonitorTask?.cancel()
        actionsStatusMonitorTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshActionsStatusSilently()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshActionsStatusSilently()
            }
        }
    }

    private func runAllPreflightChecksSilently() async {
        await refreshGitHubConnectivitySilently()
        await refreshPagesSourceStatusSilently()
        await refreshActionsStatusSilently()
    }

    private func refreshPagesSourceStatusSilently() async {
        let remote = publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = preferredGitHubToken
        guard !remote.isEmpty, !token.isEmpty else {
            pagesSiteStatus = nil
            pagesSiteError = ""
            return
        }

        do {
            let status = try await pagesService.fetchSiteStatus(remoteURL: remote, token: token)
            pagesSiteStatus = status
            pagesSiteError = ""
        } catch {
            pagesSiteStatus = nil
            pagesSiteError = error.localizedDescription
        }
    }

    private func refreshGitHubConnectivitySilently() async {
        let result = await Self.measureGitHubPing(in: project.rootURL)
        switch result {
        case let .success(ms):
            githubPingMilliseconds = ms
            githubConnectivityError = ""
        case let .failure(error):
            githubPingMilliseconds = nil
            githubConnectivityError = error.localizedDescription
        }
    }

    private func refreshActionsStatusSilently() async {
        let remote = publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = preferredGitHubToken
        guard !remote.isEmpty, !token.isEmpty else {
            latestWorkflowStatus = nil
            latestWorkflowError = ""
            latestWorkflowCheckedAt = Date()
            return
        }

        do {
            let run = try await actionsService.fetchLatestRun(
                remoteURL: remote,
                token: token,
                workflowName: defaultWorkflowName,
                branch: project.publishBranch
            )
            latestWorkflowStatus = run
            latestWorkflowError = ""
            latestWorkflowCheckedAt = Date()
        } catch {
            latestWorkflowError = error.localizedDescription
            latestWorkflowCheckedAt = Date()
        }
    }

    nonisolated private static func measureGitHubPing(in cwd: URL) async -> Result<Double, PingProbeError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let runner = ProcessRunner()
                do {
                    let result = try runner.run(
                        command: "/sbin/ping",
                        arguments: ["-c", "1", "-t", "2", "github.com"],
                        in: cwd
                    )
                    let joined = [result.stdout, result.stderr].joined(separator: "\n")
                    if let ms = parsePingMilliseconds(from: joined) {
                        continuation.resume(returning: .success(ms))
                    } else {
                        continuation.resume(returning: .failure(.message("未解析到 ping 延迟值。")))
                    }
                } catch let ProcessRunnerError.commandFailed(_, _, output) {
                    continuation.resume(returning: .failure(.message(output.isEmpty ? "ping 执行失败。" : output)))
                } catch {
                    continuation.resume(returning: .failure(.message(error.localizedDescription)))
                }
            }
        }
    }

    nonisolated private static func parsePingMilliseconds(from output: String) -> Double? {
        let pattern = #"time[=<]([0-9]+(?:\.[0-9]+)?)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: output, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let value = ns.substring(with: match.range(at: 1))
        return Double(value)
    }

    nonisolated private static func scanDetectedThemes(in rootURL: URL, configuredThemeName: String) -> [DetectedTheme] {
        let fm = FileManager.default
        let themesRoot = rootURL.appendingPathComponent("themes", isDirectory: true)
        var scannedThemes: [DetectedTheme] = []
        var seenNames = Set<String>()

        var isThemesDir = ObjCBool(false)
        if fm.fileExists(atPath: themesRoot.path, isDirectory: &isThemesDir), isThemesDir.boolValue {
            let directories = (try? fm.contentsOfDirectory(
                at: themesRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for dir in directories {
                guard
                    let values = try? dir.resourceValues(forKeys: [.isDirectoryKey]),
                    values.isDirectory == true
                else {
                    continue
                }
                let name = dir.lastPathComponent
                let key = name.lowercased()
                guard !seenNames.contains(key) else { continue }
                seenNames.insert(key)
                scannedThemes.append(inspectThemeDirectory(dir, name: name))
            }
        }

        let configured = configuredThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            let configuredKey = configured.lowercased()
            if !seenNames.contains(configuredKey) {
                scannedThemes.append(
                    DetectedTheme(
                        name: configured,
                        sourceDescription: "来自配置（未在 themes/ 下找到目录，可能为 Hugo Modules）",
                        supportsGitalk: false,
                        supportsSearch: false,
                        supportsLinks: false,
                        supportsMath: false,
                        referencedParamKeys: []
                    )
                )
            }
        }

        return scannedThemes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func inspectThemeDirectory(_ themeDirectoryURL: URL, name: String) -> DetectedTheme {
        let fm = FileManager.default
        let allowedExtensions: Set<String> = ["toml", "yaml", "yml", "json", "html", "htm", "xml", "md"]

        var supportsGitalk = false
        var supportsSearch = false
        var supportsLinks = false
        var supportsMath = false
        var referencedKeys = Set<String>()
        var scannedFiles = 0
        let maxScannedFiles = 140

        if let enumerator = fm.enumerator(
            at: themeDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard scannedFiles < maxScannedFiles else { break }

                guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }

                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true
                else {
                    continue
                }

                if let fileSize = values.fileSize, fileSize > 400_000 {
                    continue
                }

                guard let content = readTextSnippet(at: fileURL) else {
                    continue
                }

                scannedFiles += 1
                let lower = content.lowercased()
                if lower.contains("gitalk") { supportsGitalk = true }
                if lower.contains("search") || lower.contains("fuse") || lower.contains("index.json") {
                    supportsSearch = true
                }
                if lower.contains("params.links") || lower.contains(".site.params.links") {
                    supportsLinks = true
                }
                if lower.contains("mathjax") || lower.contains("katex") || lower.contains(".site.params.math") {
                    supportsMath = true
                }

                extractParamReferences(from: content, into: &referencedKeys)
                if fileURL.pathExtension.lowercased() == "toml" {
                    extractTomlParamKeys(from: content, into: &referencedKeys)
                }
            }
        }

        if referencedKeys.contains("gitalk") { supportsGitalk = true }
        if referencedKeys.contains("enablesearch") || referencedKeys.contains("search") {
            supportsSearch = true
        }
        if referencedKeys.contains("links") { supportsLinks = true }
        if referencedKeys.contains("math") || referencedKeys.contains("mathjax") || referencedKeys.contains("katex") {
            supportsMath = true
        }

        return DetectedTheme(
            name: name,
            sourceDescription: "themes/\(name)",
            supportsGitalk: supportsGitalk,
            supportsSearch: supportsSearch,
            supportsLinks: supportsLinks,
            supportsMath: supportsMath,
            referencedParamKeys: referencedKeys.sorted()
        )
    }

    nonisolated private static func readTextSnippet(at fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let maxBytes = 200_000
        guard let data = try? handle.read(upToCount: maxBytes) else {
            return nil
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let unicode = String(data: data, encoding: .unicode) {
            return unicode
        }
        return nil
    }

    nonisolated private static func extractParamReferences(from text: String, into keys: inout Set<String>) {
        let patterns = [
            #"(?i)\.site\.params\.([a-z0-9_]+)"#,
            #"(?i)\bparams\.([a-z0-9_]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for value in collectRegexCaptures(regex: regex, in: text) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { continue }
                keys.insert(normalized)
            }
        }
    }

    nonisolated private static func extractTomlParamKeys(from text: String, into keys: inout Set<String>) {
        var inParamsSection = false
        let lines = text.components(separatedBy: .newlines)

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let section = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                inParamsSection = section == "params" || section.hasPrefix("params.")

                if section.hasPrefix("params.") {
                    let nested = String(section.dropFirst("params.".count))
                    if let first = nested.split(separator: ".").first, !first.isEmpty {
                        keys.insert(String(first))
                    }
                }
                continue
            }

            guard inParamsSection, let equalIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<equalIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }
            keys.insert(key)
        }
    }

    nonisolated private static func collectRegexCaptures(regex: NSRegularExpression, in text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    var hugoToolLogEntries: [PublishLogEntry] {
        publishLogEntries.filter { Self.hugoToolOperationNames.contains($0.operation) }
    }

    var hugoToolLog: String {
        hugoToolLogEntries.map(\.rendered).joined(separator: "\n\n")
    }

    var hugoStructurePromptMessage: String {
        guard let report = lastHugoStructureReport else {
            return "检测到结构缺失，是否自动补齐？"
        }
        let lines = report.hasMissingRequiredItems
            ? report.missingRequiredItemsForPrompt
            : report.missingItemsForPrompt
        guard !lines.isEmpty else {
            return "检测到结构缺失，是否自动补齐？"
        }
        return lines.joined(separator: "\n")
    }

    func clearHugoToolLogs() {
        publishLogEntries.removeAll { Self.hugoToolOperationNames.contains($0.operation) }
        publishLog = publishLogEntries.map(\.rendered).joined(separator: "\n\n")
    }

    func preflightChecks() -> [PublishCheck] {
        var checks: [PublishCheck] = []

        let detectedConfig = project.detectedConfigRelativePath
        let configExists = detectedConfig != nil
        checks.append(
            PublishCheck(
                title: "项目配置文件",
                detail: configExists
                    ? "已找到 \(detectedConfig ?? "hugo.toml")。"
                    : "未找到 Hugo 配置文件（支持 hugo.toml、config.toml、config/_default/hugo.toml 等）。",
                level: configExists ? .ok : .error
            )
        )

        let localBundleExists = FileManager.default.fileExists(atPath: project.localConfigBundleURL.path)
        checks.append(
            PublishCheck(
                title: "本地配置包",
                detail: localBundleExists ? ".hugodesk.local.json 已就绪。" : "尚未导出项目配置包。",
                level: localBundleExists ? .ok : .warning
            )
        )

        let remote = publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        checks.append(
            PublishCheck(
                title: "推送地址",
                detail: remote.isEmpty ? "未配置远程仓库 URL。" : remote,
                level: remote.isEmpty ? .error : .ok
            )
        )

        checks.append(
            PublishCheck(
                title: "部署策略",
                detail: "GitHub Actions（固定）",
                level: .ok
            )
        )

        let classic = githubClassicToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let fine = githubFineGrainedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenDetail: String
        if classic.isEmpty, fine.isEmpty {
            tokenDetail = "未配置（公开仓库可不填，但 API 查询可能受限）。"
        } else if !classic.isEmpty, !fine.isEmpty {
            tokenDetail = "Classic + Fine-grained 已配置（Pages/Actions API 优先使用 Classic）。"
        } else if !classic.isEmpty {
            tokenDetail = "Classic 已配置。"
        } else {
            tokenDetail = "Fine-grained 已配置（若 Pages 来源检测失败，可补充 Classic Token）。"
        }
        checks.append(
            PublishCheck(
                title: "GitHub Token",
                detail: tokenDetail,
                level: hasGitHubToken ? .ok : .warning
            )
        )

        if let pagesSiteStatus {
            let isWorkflow = pagesSiteStatus.buildType.lowercased() == "workflow"
            checks.append(
                PublishCheck(
                    title: "Pages 来源",
                    detail: isWorkflow
                        ? "已配置为 GitHub Actions（workflow）。"
                        : "当前为 \(pagesSiteStatus.buildType)，建议切换为 workflow，避免 pages-build-deployment 覆盖站点。",
                    level: isWorkflow ? .ok : .warning
                )
            )
        } else if !pagesSiteError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            checks.append(
                PublishCheck(
                    title: "Pages 来源",
                    detail: "检测失败：\(pagesSiteError)",
                    level: .warning
                )
            )
        } else {
            checks.append(
                PublishCheck(
                    title: "Pages 来源",
                    detail: "尚未检测，点击“检查 Pages 来源”确认是否为 workflow。",
                    level: .warning
                )
            )
        }

        let workflowExists = publishService.hasGitHubPagesWorkflow(project: project)
        checks.append(
            PublishCheck(
                title: "Pages workflow",
                detail: workflowExists ? "已检测到 .github/workflows/hugo.yaml。" : "未检测到 .github/workflows/hugo.yaml。",
                level: workflowExists ? .ok : .error
            )
        )

        let duplicateWorkflows = publishService.duplicatePagesWorkflowFileNames(project: project)
        checks.append(
            PublishCheck(
                title: "重置 Pages workflow",
                detail: duplicateWorkflows.isEmpty
                    ? "无需重置，未检测到重复 workflow。"
                    : "建议重置，检测到重复 workflow：\(duplicateWorkflows.joined(separator: ", "))",
                level: duplicateWorkflows.isEmpty ? .ok : .warning
            )
        )

        let postCount = posts.count
        checks.append(
            PublishCheck(
                title: "文章数量",
                detail: "当前检测到 \(postCount) 篇文章。",
                level: postCount == 0 ? .warning : .ok
            )
        )

        let themeName = config.theme.trimmingCharacters(in: .whitespacesAndNewlines)
        let themeDir = project.rootURL.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent(themeName, isDirectory: true)
        var isThemeDir = ObjCBool(false)
        let themeExists = !themeName.isEmpty
            && FileManager.default.fileExists(atPath: themeDir.path, isDirectory: &isThemeDir)
            && isThemeDir.boolValue
        checks.append(
            PublishCheck(
                title: "当前主题",
                detail: themeName.isEmpty
                    ? "未设置 theme。"
                    : (themeExists
                        ? "\(themeName)（已检测到主题目录）"
                        : "\(themeName)（未在 themes/ 下检测到目录，若使用 Hugo Modules 可忽略）"),
                level: themeName.isEmpty ? .warning : (themeExists ? .ok : .warning)
            )
        )

        let conflicts = publishService.unresolvedConflictFiles(project: project)
        checks.append(
            PublishCheck(
                title: "Git 冲突",
                detail: conflicts.isEmpty ? "未检测到未解决冲突。" : "检测到 \(conflicts.count) 个未解决冲突，请先处理。",
                level: conflicts.isEmpty ? .ok : .error
            )
        )

        if let ping = githubPingMilliseconds {
            let detail = String(format: "github.com RTT: %.1f ms（30 秒自动刷新）", ping)
            checks.append(
                PublishCheck(
                    title: "GitHub 连通性",
                    detail: detail,
                    level: ping <= 250 ? .ok : .warning
                )
            )
        } else if !githubConnectivityError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            checks.append(
                PublishCheck(
                    title: "GitHub 连通性",
                    detail: "检测失败：\(githubConnectivityError)",
                    level: .warning
                )
            )
        } else {
            checks.append(
                PublishCheck(
                    title: "GitHub 连通性",
                    detail: "正在检测 github.com 延迟（30 秒自动刷新）...",
                    level: .warning
                )
            )
        }

        return checks
    }

    func scheduleLivePreviewRefresh(immediate: Bool = false) {
        livePreviewTask?.cancel()

        let delayNanos: UInt64 = immediate ? 0 : 700_000_000
        let projectSnapshot = project
        let postSnapshot = editorPost

        livePreviewTask = Task { [weak self] in
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            guard !Task.isCancelled else {
                return
            }
            do {
                try await Self.performLivePreviewBuild(project: projectSnapshot, post: postSnapshot)
                guard !Task.isCancelled else {
                    return
                }
                self?.previewRenderToken &+= 1
            } catch {
                if Task.isCancelled {
                    return
                }
                self?.statusText = "实时预览更新失败：\(error.localizedDescription)"
            }
        }
    }

    func cancelLivePreviewRefresh() {
        livePreviewTask?.cancel()
        livePreviewTask = nil
    }

    nonisolated private static func performLivePreviewBuild(project: BlogProject, post: BlogPost) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let postService = PostService()
                    let publishService = PublishService()
                    let hasContent = !post.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || FileManager.default.fileExists(atPath: post.fileURL.path)
                    if hasContent {
                        try postService.savePost(post)
                    }
                    _ = try publishService.runHugoBuild(project: project)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct AppAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum PingProbeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text):
            return text
        }
    }
}

private enum PublishWorkflowError: LocalizedError {
    case missingStructure(items: [String])

    var errorDescription: String? {
        switch self {
        case let .missingStructure(items):
            if items.isEmpty {
                return "Hugo 文件结构不完整，请先修复后再发布。"
            }
            return """
            Hugo 文件结构不完整，请先修复后再发布：
            \(items.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
    }
}

struct PublishLogEntry: Identifiable {
    enum Level {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let timestamp: Date
    let operation: String
    let summary: String
    let details: String
    let level: Level

    var rendered: String {
        let clock = timestamp.formatted(date: .omitted, time: .standard)
        if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[\(clock)] \(operation) - \(summary)"
        }
        return "[\(clock)] \(operation) - \(summary)\n\(details)"
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case richText = "富文本"

    var id: String { rawValue }
}

import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    private let defaultWorkflowName = "Deploy Hugo site to Pages"

    @Published var project: BlogProject
    @Published var config: ThemeConfig = ThemeConfig()

    @Published var posts: [BlogPost] = []
    @Published var selectedPostID: String?
    @Published var editorPost: BlogPost
    @Published var editorMode: EditorMode = .markdown
    @Published var newPostTitle: String = ""
    @Published var newPostFileName: String = "new-post.md"

    @Published var publishLog: String = ""
    @Published var publishLogEntries: [PublishLogEntry] = []
    @Published var publishMessage: String = "chore: 发布博客更新"
    @Published var publishRemoteURL: String = ""
    @Published var githubToken: String = ""
    @Published var workflowName: String = "Deploy Hugo site to Pages"
    @Published var aiBaseURL: String = AIProfile.default.baseURL
    @Published var aiModel: String = AIProfile.default.model
    @Published var aiAPIKey: String = ""
    @Published var latestWorkflowStatus: WorkflowRunStatus?
    @Published var latestWorkflowError: String = ""
    @Published var isBusy: Bool = false
    @Published var statusText: String = ""

    private let configService = ConfigService()
    private let postService = PostService()
    private let publishService = PublishService()
    private let imageAssetService = ImageAssetService()
    private let actionsService = GitHubActionsService()
    private let credentialStore = CredentialStore()
    private let aiService = AIService()

    init() {
        let project = BlogProject.bootstrap()
        self.project = project
        self.editorPost = BlogPost.empty(in: project.contentURL)
        self.newPostTitle = ""
        self.newPostFileName = "new-post.md"
        loadAll()
    }

    var localConfigBundlePath: String {
        project.localConfigBundleURL.path
    }

    func loadAll() {
        do {
            config = try configService.loadConfig(for: project)
            loadRemoteProfile()
            loadAIProfile()
            let localBundleLoaded = loadLocalConfigBundleIfPresent()
            posts = try postService.loadPosts(for: project)
            if let first = posts.first {
                selectedPostID = first.id
                editorPost = first
            } else {
                editorPost = BlogPost.empty(in: project.contentURL)
            }
            statusText = localBundleLoaded ? "项目已加载（已读取本地配置包）。" : "项目已加载。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func saveRemoteProfile() {
        do {
            let profile = RemoteProfile(
                remoteURL: publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines),
                workflowName: workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try credentialStore.saveRemoteProfile(profile, for: project.rootPath)
            credentialStore.saveToken(githubToken, for: project.rootPath)
            try saveLocalConfigBundle()
            statusText = "远程与令牌设置已保存，并同步到项目配置包。"
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
            let webPath = try imageAssetService.importImage(from: sourceURL, project: project, subfolder: "uploads")
            let alt = altText.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = "![\(alt.isEmpty ? "image" : alt)](\(webPath))\n"
            let range = insertPostSnippet(text, at: insertionRange)
            statusText = "图片已导入：\(webPath)"
            return range
        } catch {
            statusText = error.localizedDescription
            return insertionRange ?? NSRange(location: (editorPost.body as NSString).length, length: 0)
        }
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

    func saveThemeConfig() {
        do {
            try configService.saveConfig(config, for: project)
            try saveLocalConfigBundle()
            statusText = "hugo.toml 已保存，并同步到项目配置包。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func runBuild() {
        runTask(operation: "构建站点", successStatus: "构建完成。") {
            let output = try self.publishService.runHugoBuild(project: self.project)
            return output.isEmpty ? "构建完成（无输出）。" : output
        }
    }

    func runGitStatus() {
        runTask(operation: "查看 Git 状态", successStatus: "Git 状态已更新。") {
            let output = try self.publishService.gitStatus(project: self.project)
            return output.isEmpty ? "Git 状态为空。" : output
        }
    }

    func runSyncWithRemote() {
        runTask(operation: "同步远端", successStatus: "已与远端分支同步。") {
            let output = try self.publishService.syncWithRemote(
                project: self.project,
                remoteURL: self.publishRemoteURL
            )
            return output.isEmpty ? "同步完成（无输出）。" : output
        }
    }

    func runPublish() {
        runTask(operation: "提交并推送", successStatus: "推送完成。") {
            let hasContent = !self.editorPost.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !self.editorPost.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || FileManager.default.fileExists(atPath: self.editorPost.fileURL.path)
            if hasContent {
                try self.postService.savePost(self.editorPost)
            }

            let fixed = try self.imageAssetService.normalizePostImageLinks(project: self.project)
            let output = try self.publishService.commitAndPush(
                project: self.project,
                message: self.publishMessage,
                remoteURL: self.publishRemoteURL
            )

            if fixed.changedLinks > 0 {
                return "已自动修正图片链接：\(fixed.changedLinks) 条，影响文件 \(fixed.changedFiles) 个。\n\n\(output)"
            }
            return output
        }
    }

    func refreshActionsStatus() {
        runAsyncTask(operation: "查询 Actions 状态", successStatus: "已获取最新 Actions 状态。") {
            self.latestWorkflowError = ""
            self.latestWorkflowStatus = nil
            let run = try await self.actionsService.fetchLatestRun(
                remoteURL: self.publishRemoteURL,
                token: self.githubToken,
                workflowName: self.workflowName
            )
            self.latestWorkflowStatus = run
            return """
            Workflow: \(run.name)
            分支: \(run.branch)
            状态: \(run.statusText)
            提交: \(run.sha)
            详情: \(run.htmlURL)
            """
        }
    }

    func formatPostWithAI(selectionRange: NSRange?, onComplete: @escaping (NSRange) -> Void) {
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
            } catch {
                self.statusText = error.localizedDescription
            }
        }
    }

    func runEnvironmentDiagnostics() {
        runTask(operation: "一键检测推送能力", successStatus: "发布环境检测完成。") {
            let report = try self.publishService.diagnosePublishEnvironment(
                project: self.project,
                remoteURL: self.publishRemoteURL
            )
            return report
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

    func exportConfigBundle(to url: URL) {
        do {
            let bundle = makeConfigBundleSnapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: .atomic)
            statusText = "配置包已导出：\(url.path)"
        } catch {
            statusText = "导出失败：\(error.localizedDescription)"
        }
    }

    func importConfigBundle(from url: URL) {
        do {
            let bundle = try loadConfigBundle(from: url)
            try restoreConfigBundle(bundle, sourceName: url.lastPathComponent, persistToProjectBundle: true)
            statusText = "配置包已还原：\(url.lastPathComponent)"
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
                workflowName: workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            githubToken: githubToken,
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
        workflowName = bundle.remoteProfile.workflowName.isEmpty ? defaultWorkflowName : bundle.remoteProfile.workflowName
        githubToken = bundle.githubToken
        aiBaseURL = bundle.aiProfile.baseURL.isEmpty ? AIProfile.default.baseURL : bundle.aiProfile.baseURL
        aiModel = bundle.aiProfile.model.isEmpty ? AIProfile.default.model : bundle.aiProfile.model
        aiAPIKey = bundle.aiAPIKey

        try configService.saveConfig(config, for: project)
        try credentialStore.saveRemoteProfile(bundle.remoteProfile, for: project.rootPath)
        credentialStore.saveToken(bundle.githubToken, for: project.rootPath)
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
            workflowName = bundle.remoteProfile.workflowName.isEmpty ? defaultWorkflowName : bundle.remoteProfile.workflowName
            githubToken = bundle.githubToken.isEmpty ? credentialStore.loadToken(for: project.rootPath) : bundle.githubToken
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

    func clearPublishLogs() {
        publishLogEntries.removeAll()
        publishLog = ""
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
                latestWorkflowError = ""
                statusText = successStatus
            } catch {
                let errorText = error.localizedDescription
                latestWorkflowError = errorText
                appendPublishLog(
                    operation: operation,
                    summary: "执行失败",
                    details: errorText,
                    level: .error
                )
                statusText = "\(operation)失败，请查看日志。"
                await appendAITroubleshootingIfConfigured(operation: operation, errorLog: errorText)
            }
        }
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
            workflowName = profile.workflowName.isEmpty ? defaultWorkflowName : profile.workflowName
        } else {
            publishRemoteURL = publishService.detectRemoteURL(project: project)
            workflowName = defaultWorkflowName
        }
        githubToken = credentialStore.loadToken(for: project.rootPath)
    }

    private func loadAIProfile() {
        let profile = credentialStore.loadAIProfile(for: project.rootPath)
        aiBaseURL = profile.baseURL
        aiModel = profile.model
        aiAPIKey = credentialStore.loadAIAPIKey(for: project.rootPath)
    }

    func preflightChecks() -> [PublishCheck] {
        var checks: [PublishCheck] = []

        let configExists = FileManager.default.fileExists(atPath: project.configURL.path)
        checks.append(
            PublishCheck(
                title: "项目配置文件",
                detail: configExists ? "已找到 hugo.toml。" : "未找到 hugo.toml，请确认项目目录。",
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

        let hasToken = !githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        checks.append(
            PublishCheck(
                title: "GitHub Token",
                detail: hasToken ? "已配置（保存在系统钥匙串）。" : "未配置（公开仓库可不填，但可能受 API 限流）。",
                level: hasToken ? .ok : .warning
            )
        )

        let workflow = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        checks.append(
            PublishCheck(
                title: "Workflow 过滤名",
                detail: workflow.isEmpty ? "空：将自动使用最新运行记录。" : workflow,
                level: .ok
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

        let conflicts = publishService.unresolvedConflictFiles(project: project)
        checks.append(
            PublishCheck(
                title: "Git 冲突",
                detail: conflicts.isEmpty ? "未检测到未解决冲突。" : "检测到 \(conflicts.count) 个未解决冲突，请先处理。",
                level: conflicts.isEmpty ? .ok : .error
            )
        )

        return checks
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

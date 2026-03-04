import Foundation

final class PublishService {
    private let runner = ProcessRunner()
    private let fm = FileManager.default

    func runHugoBuild(project: BlogProject) throws -> String {
        let executable = resolveCommandPath(name: project.hugoExecutable, cwd: project.rootURL) ?? project.hugoExecutable
        let result = try runner.run(
            command: executable,
            arguments: ["--gc", "--minify"],
            in: project.rootURL
        )
        return renderProcessLog(step: "构建 Hugo 站点", result: result)
    }

    func hugoVersion(project: BlogProject) throws -> String {
        let executable = resolveCommandPath(name: project.hugoExecutable, cwd: project.rootURL) ?? project.hugoExecutable
        let result = try runner.run(
            command: executable,
            arguments: ["version"],
            in: project.rootURL
        )
        return renderProcessLog(step: "检查 Hugo 版本", result: result)
    }

    func upgradeHugo(project: BlogProject) throws -> String {
        guard let brew = resolveCommandPath(name: "brew", cwd: project.rootURL) else {
            throw ProcessRunnerError.commandFailed(
                command: "brew upgrade hugo",
                code: 1,
                output: "未检测到 Homebrew，请先安装后重试：https://brew.sh"
            )
        }

        var logs: [String] = []
        let update = try runner.run(command: brew, arguments: ["update"], in: project.rootURL)
        logs.append(renderProcessLog(step: "更新 Homebrew", result: update))

        let upgrade = try runner.run(command: brew, arguments: ["upgrade", "hugo"], in: project.rootURL)
        logs.append(renderProcessLog(step: "升级 Hugo", result: upgrade))

        let version = try hugoVersion(project: project)
        logs.append(version)

        return logs.joined(separator: "\n\n")
    }

    func checkHugoStructure(project: BlogProject) -> HugoStructureReport {
        inspectHugoStructure(project: project)
    }

    func repairHugoStructure(project: BlogProject) throws -> HugoStructureReport {
        var report = inspectHugoStructure(project: project)
        var createdDirectories: [String] = []
        var createdFiles: [String] = []

        for relativePath in report.missingRequiredDirectories + report.missingRecommendedDirectories {
            let dirURL = project.rootURL.appendingPathComponent(relativePath, isDirectory: true)
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            createdDirectories.append(relativePath)
        }

        for relativePath in report.missingRequiredFiles {
            let fileURL = project.rootURL.appendingPathComponent(relativePath, isDirectory: false)
            if relativePath == "hugo.toml" {
                let defaultConfig = defaultHugoConfigTemplate()
                try defaultConfig.write(to: fileURL, atomically: true, encoding: .utf8)
                createdFiles.append(relativePath)
            }
        }

        if report.missingRecommendedFiles.contains(".github/workflows/hugo.yaml") {
            _ = try ensureGitHubPagesWorkflow(project: project)
            createdFiles.append(".github/workflows/hugo.yaml")
        }

        report = inspectHugoStructure(project: project)
        report.createdDirectories = Array(Set(createdDirectories)).sorted()
        report.createdFiles = Array(Set(createdFiles)).sorted()
        return report
    }

    func commitAndPush(
        project: BlogProject,
        message: String,
        remoteURL: String,
        githubToken: String = ""
    ) throws -> String {
        var logs: [String] = []
        let auth = try makeGitAuthContext(githubToken: githubToken)
        defer { auth.cleanup() }
        let tokenEnv = auth.environment

        let unresolved = unresolvedConflictFiles(project: project)
        if !unresolved.isEmpty {
            let lines = unresolved.map { "- \($0)" }.joined(separator: "\n")
            let detail = """
            检测到未解决的 Git 冲突，无法继续提交。
            当前项目目录：\(project.rootURL.path)

            冲突文件：
            \(lines)

            建议先处理冲突后再发布：
            - git status
            - 打开冲突文件并解决 <<<<<<< ======= >>>>>>> 标记
            - git add <冲突文件>
            - git commit

            若这是误操作合并，可执行：
            - git merge --abort
            或
            - git rebase --abort
            """
            throw ProcessRunnerError.commandFailed(command: "git commit", code: 1, output: detail)
        }

        if !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logs.append(contentsOf: ensureRemoteURLLogs(project: project, remoteURL: remoteURL))
        }

        let add = try stagePublishFiles(project: project)
        logs.append(renderProcessLog(step: "暂存变更", result: add))

        let workflowExists = hasGitHubPagesWorkflow(project: project)
        if !workflowExists {
            logs.append("""
            == 部署链路提示 ==
            未检测到 .github/workflows/hugo.yaml，推送源码后 GitHub Pages 不会自动构建站点。
            请先在发布页点击“一键生成 Pages Workflow”，再执行提交推送。
            """)
        }

        do {
            let commit = try runner.run(command: "git", arguments: ["commit", "-m", message], in: project.rootURL)
            logs.append(renderProcessLog(step: "提交变更", result: commit))
        } catch let ProcessRunnerError.commandFailed(_, _, output) {
            if output.contains("nothing to commit") || output.contains("no changes added") {
                logs.append("== 提交变更 ==\n无需提交：没有新的暂存变更。")
            } else {
                throw ProcessRunnerError.commandFailed(command: "git commit", code: 1, output: output)
            }
        }

        do {
            let push = try runner.run(
                command: "git",
                arguments: ["push", project.gitRemote, project.publishBranch],
                in: project.rootURL,
                environment: tokenEnv
            )
            logs.append(renderProcessLog(step: "推送到远端", result: push))
        } catch let ProcessRunnerError.commandFailed(_, _, output) {
            if containsNonFastForward(output) {
                logs.append("== 推送到远端 ==\nPush 被拒绝（non-fast-forward），已自动执行同步后重试。")
                let syncOutput = try syncWithRemote(project: project, remoteURL: remoteURL, githubToken: githubToken)
                if !syncOutput.isEmpty {
                    logs.append(syncOutput)
                }
                let retryPush = try runner.run(
                    command: "git",
                    arguments: ["push", project.gitRemote, project.publishBranch],
                    in: project.rootURL,
                    environment: tokenEnv
                )
                logs.append(renderProcessLog(step: "重试推送到远端", result: retryPush))
            } else {
                throw ProcessRunnerError.commandFailed(command: "git push", code: 1, output: output)
            }
        }

        return logs.joined(separator: "\n\n")
    }

    func syncWithRemote(project: BlogProject, remoteURL: String, githubToken: String = "") throws -> String {
        var logs: [String] = []
        let auth = try makeGitAuthContext(githubToken: githubToken)
        defer { auth.cleanup() }
        let tokenEnv = auth.environment

        if !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logs.append(contentsOf: ensureRemoteURLLogs(project: project, remoteURL: remoteURL))
        }

        let fetch = try runner.run(
            command: "git",
            arguments: ["fetch", project.gitRemote, project.publishBranch],
            in: project.rootURL,
            environment: tokenEnv
        )
        logs.append(renderProcessLog(step: "拉取远端引用（fetch）", result: fetch))

        let pull = try runner.run(
            command: "git",
            arguments: ["pull", "--rebase", "--autostash", project.gitRemote, project.publishBranch],
            in: project.rootURL,
            environment: tokenEnv
        )
        logs.append(renderProcessLog(step: "变基同步（pull --rebase）", result: pull))

        let status = try runner.run(
            command: "git",
            arguments: ["status", "--short", "--branch"],
            in: project.rootURL
        )
        logs.append(renderProcessLog(step: "同步后状态", result: status))

        return logs.joined(separator: "\n\n")
    }

    func diagnosePublishEnvironment(
        project: BlogProject,
        remoteURL: String,
        githubToken: String = ""
    ) throws -> String {
        var lines: [String] = []
        let auth = try makeGitAuthContext(githubToken: githubToken)
        defer { auth.cleanup() }
        let tokenEnv = auth.environment

        lines.append("== 组件检查 ==")
        let git = toolStatus(name: "git", versionArgs: ["--version"], cwd: project.rootURL)
        let hugo = toolStatus(name: project.hugoExecutable, versionArgs: ["version"], cwd: project.rootURL)
        let brewPath = resolveCommandPath(name: "brew", cwd: project.rootURL)

        lines.append(statusLine(for: git))
        lines.append(statusLine(for: hugo))
        appendMissingToolHints(lines: &lines, git: git, hugo: hugo, brewPath: brewPath)

        if git.requiresXcodeLicense || hugo.requiresXcodeLicense {
            lines.append("⚠️ 检测到 Xcode 许可未同意，请先在终端执行：sudo xcodebuild -license accept")
        }

        lines.append("")
        lines.append("== 推送能力检查 ==")

        if !git.usable {
            lines.append("❌ Git 不可用，跳过推送检查。")
            return lines.joined(separator: "\n")
        }

        let isRepo = capture(command: "git", arguments: ["rev-parse", "--is-inside-work-tree"], in: project.rootURL)
        lines.append(renderCheck(title: "Git 仓库", result: isRepo))
        if !isRepo.success {
            lines.append("❌ 当前目录不是有效 Git 仓库，无法继续推送检查。")
            return lines.joined(separator: "\n")
        }

        let remoteName = project.gitRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCandidate = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTarget = remoteCandidate.isEmpty ? remoteName : remoteCandidate
        if remoteTarget.isEmpty {
            lines.append("❌ 未配置远程地址（remote URL / remote name）。")
            return lines.joined(separator: "\n")
        }

        if remoteCandidate.isEmpty {
            let remoteExists = capture(command: "git", arguments: ["remote", "get-url", remoteName], in: project.rootURL)
            lines.append(renderCheck(title: "远程地址检测（\(remoteName)）", result: remoteExists))
            if !remoteExists.success {
                lines.append("❌ 未找到 remote \"\(remoteName)\"，请先在项目设置中配置推送地址。")
                return lines.joined(separator: "\n")
            }
        }

        let remoteProbe = capture(
            command: "git",
            arguments: ["ls-remote", remoteTarget, "HEAD"],
            in: project.rootURL,
            environment: tokenEnv
        )
        lines.append(renderCheck(title: "远程可达性（git ls-remote）", result: remoteProbe))

        let dryRun = capture(
            command: "git",
            arguments: ["push", "--dry-run", remoteTarget, project.publishBranch],
            in: project.rootURL,
            environment: tokenEnv
        )
        lines.append(renderCheck(title: "推送权限（git push --dry-run）", result: dryRun))

        lines.append("")
        lines.append("== 部署链路检查 ==")
        let workflowExists = hasGitHubPagesWorkflow(project: project)
        lines.append(workflowExists
            ? "✅ GitHub Pages Workflow：已检测到 .github/workflows/hugo.yaml"
            : "❌ GitHub Pages Workflow：未检测到 .github/workflows/hugo.yaml")
        lines.append("部署策略：GitHub Actions（固定）")
        if !workflowExists {
            lines.append("⚠️ 当前使用 GitHub Actions 模式，但 workflow 缺失。")
            lines.append("修复建议：在应用发布页点击“一键生成 Pages Workflow”，然后重新推送。")
        }
        let duplicates = duplicatePagesWorkflowFiles(project: project)
        if duplicates.isEmpty {
            lines.append("✅ 重复 Workflow 检查：未发现重复的 Pages workflow。")
        } else {
            lines.append("⚠️ 重复 Workflow 检查：发现 \(duplicates.count) 个可能重复的 workflow 文件。")
            for file in duplicates {
                lines.append("- \(file.lastPathComponent)")
            }
            lines.append("修复建议：在应用发布页重新点击“一键生成 Pages Workflow”，会自动清理重复文件。")
        }
        lines.append("提示：若出现 Actions 成功后又执行 pages-build-deployment 且站点 File not found，通常是 GitHub Pages 来源仍为 Branch。请在发布页点击“检查 Pages 来源/修复为 GitHub Actions”。")

        if containsTLSError(remoteProbe.output) || containsTLSError(dryRun.output) {
            lines.append("⚠️ 检测到 TLS/SSL 网络异常。可尝试更换网络、关闭系统代理或配置 Git 代理后重试。")
            appendTLSHints(lines: &lines, remoteTarget: remoteTarget, publishBranch: project.publishBranch)
        }

        if containsNonFastForward(dryRun.output) {
            lines.append("⚠️ 检测到 non-fast-forward：本地分支落后于远端。")
            appendNonFastForwardHints(lines: &lines, remote: project.gitRemote, publishBranch: project.publishBranch)
        }

        if remoteProbe.success && dryRun.success {
            lines.append("✅ 推送链路可用，可以执行提交推送。")
        } else {
            lines.append("⚠️ 推送能力存在问题，请先修复上方失败项。")
        }

        return lines.joined(separator: "\n")
    }

    func detectRemoteURL(project: BlogProject) -> String {
        do {
            let result = try runner.run(
                command: "git",
                arguments: ["remote", "get-url", project.gitRemote],
                in: project.rootURL
            )
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    func unresolvedConflictFiles(project: BlogProject) -> [String] {
        let result = capture(
            command: "git",
            arguments: ["diff", "--name-only", "--diff-filter=U"],
            in: project.rootURL
        )
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func ensureRemoteURLLogs(project: BlogProject, remoteURL: String) -> [String] {
        do {
            _ = try runner.run(
                command: "git",
                arguments: ["remote", "get-url", project.gitRemote],
                in: project.rootURL
            )
            let result = try runner.run(
                command: "git",
                arguments: ["remote", "set-url", project.gitRemote, remoteURL],
                in: project.rootURL
            )
            return [renderProcessLog(step: "更新远端地址", result: result)]
        } catch {
            do {
                let result = try runner.run(
                    command: "git",
                    arguments: ["remote", "add", project.gitRemote, remoteURL],
                    in: project.rootURL
                )
                return [renderProcessLog(step: "添加远端地址", result: result)]
            } catch {
                return ["== 配置远端地址 ==\n失败：\(error.localizedDescription)"]
            }
        }
    }

    private func stagePublishFiles(project: BlogProject) throws -> ProcessResult {
        let baseArguments = ["add", "--all", "--", "."]
        let commonExcludes = [
            ":(exclude)HugoDesk",
            ":(exclude)HugoDesk/**",
            ":(exclude)HugoDeskArchive",
            ":(exclude)HugoDeskArchive/**",
            ":(glob,exclude)**/HugoDesk",
            ":(glob,exclude)**/HugoDesk/**",
            ":(glob,exclude)**/HugoDeskArchive",
            ":(glob,exclude)**/HugoDeskArchive/**"
        ]
        let localBundleExcludes = [
            ":(exclude).hugodesk.local.json",
            ":(glob,exclude)**/.hugodesk.local.json"
        ]

        do {
            return try runner.run(
                command: "git",
                arguments: baseArguments + commonExcludes + localBundleExcludes,
                in: project.rootURL
            )
        } catch let ProcessRunnerError.commandFailed(_, _, output) {
            let shouldRetryWithoutBundlePathspec =
                output.contains("ignored by one of your .gitignore files")
                && output.contains(".hugodesk.local.json")

            if shouldRetryWithoutBundlePathspec {
                return try runner.run(
                    command: "git",
                    arguments: baseArguments + commonExcludes,
                    in: project.rootURL
                )
            }

            throw ProcessRunnerError.commandFailed(command: "git add", code: 1, output: output)
        }
    }

    private func renderProcessLog(step: String, result: ProcessResult) -> String {
        var lines: [String] = []
        lines.append("== \(step) ==")
        lines.append("命令：\(result.commandLine)")
        lines.append("目录：\(result.workingDirectory)")
        lines.append("退出码：\(result.exitCode)")
        lines.append(String(format: "耗时：%.2fs", result.duration))

        if !result.stdout.isEmpty {
            lines.append("-- stdout --")
            lines.append(result.stdout)
        }

        if !result.stderr.isEmpty {
            lines.append("-- stderr --")
            lines.append(result.stderr)
        }

        return lines.joined(separator: "\n")
    }

    private func containsTLSError(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("ssl_connect") || text.contains("ssl_error") || text.contains("tls")
    }

    private func containsNonFastForward(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("non-fast-forward")
            || text.contains("fetch first")
            || text.contains("pushed branch tip is behind")
    }

    private func appendMissingToolHints(lines: inout [String], git: ToolStatus, hugo: ToolStatus, brewPath: String?) {
        var hints: [String] = []

        if !git.usable {
            if brewPath != nil {
                hints.append("git 缺失可执行命令：brew install git")
            } else {
                hints.append("git 缺失：先安装 Homebrew，再执行 brew install git")
            }
        }

        if !hugo.usable {
            if brewPath != nil {
                hints.append("hugo 缺失可执行命令：brew install hugo")
            } else {
                hints.append("hugo 缺失：先安装 Homebrew，再执行 brew install hugo")
            }
        }

        if hints.isEmpty {
            return
        }

        lines.append("安装建议：")
        for hint in hints {
            lines.append("- \(hint)")
        }
    }

    private func appendTLSHints(lines: inout [String], remoteTarget: String, publishBranch: String) {
        lines.append("建议按顺序执行以下排查命令：")
        lines.append("- git config --global --get http.proxy")
        lines.append("- git config --global --get https.proxy")
        lines.append("- env | grep -i proxy")
        lines.append("- unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY")
        lines.append("- git ls-remote \(remoteTarget) HEAD")
        lines.append("- git push --dry-run \(remoteTarget) \(publishBranch)")
    }

    private func appendNonFastForwardHints(lines: inout [String], remote: String, publishBranch: String) {
        lines.append("修复命令：")
        lines.append("- git fetch \(remote) \(publishBranch)")
        lines.append("- git pull --rebase --autostash \(remote) \(publishBranch)")
        lines.append("- git push \(remote) \(publishBranch)")
        lines.append("也可在应用中点击“同步远程”后再执行“提交并推送”。")
    }

    private func statusLine(for status: ToolStatus) -> String {
        if status.usable {
            return "✅ \(status.displayName)：\(status.versionText)"
        }
        if status.exists {
            return "⚠️ \(status.displayName)：已安装但不可用（\(status.versionText)）"
        }
        return "❌ \(status.displayName)：未安装"
    }

    private func renderCheck(title: String, result: CommandCapture) -> String {
        if result.success {
            if result.output.isEmpty {
                return "✅ \(title)：通过"
            }
            return "✅ \(title)：\(result.output)"
        }
        if result.output.isEmpty {
            return "❌ \(title)：失败"
        }
        return "❌ \(title)：\(result.output)"
    }

    private func toolStatus(name: String, versionArgs: [String], cwd: URL) -> ToolStatus {
        let executable = resolveCommandPath(name: name, cwd: cwd)
        guard let executable else {
            return ToolStatus(
                displayName: name,
                exists: false,
                usable: false,
                versionText: "无输出",
                requiresXcodeLicense: false
            )
        }

        let version = capture(command: executable, arguments: versionArgs, in: cwd)
        let licenseIssue = version.output.localizedCaseInsensitiveContains("Xcode license agreements")

        return ToolStatus(
            displayName: name,
            exists: true,
            usable: version.success,
            versionText: version.output.isEmpty ? executable : version.output,
            requiresXcodeLicense: licenseIssue
        )
    }

    private func resolveCommandPath(name: String, cwd: URL) -> String? {
        if name.contains("/") {
            return fm.isExecutableFile(atPath: name) ? name : nil
        }

        let commonRoots = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/opt/local/bin"]
        for root in commonRoots {
            let candidate = "\(root)/\(name)"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        let lookup = capture(command: "/usr/bin/env", arguments: ["which", name], in: cwd)
        let path = lookup.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if lookup.success, !path.isEmpty, fm.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private func capture(
        command: String,
        arguments: [String],
        in cwd: URL,
        environment: [String: String] = [:]
    ) -> CommandCapture {
        do {
            let result = try runner.run(command: command, arguments: arguments, in: cwd, environment: environment)
            return CommandCapture(success: true, output: sanitizeOutput(result.output))
        } catch let ProcessRunnerError.commandFailed(_, _, output) {
            return CommandCapture(success: false, output: sanitizeOutput(output))
        } catch {
            return CommandCapture(success: false, output: sanitizeOutput(error.localizedDescription))
        }
    }

    private func makeGitAuthContext(githubToken: String) throws -> GitAuthContext {
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return GitAuthContext(environment: [:], cleanup: {})
        }

        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hugodesk-askpass-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        case "$1" in
          *sername*) echo "x-access-token" ;;
          *assword*) echo "$HUGODESK_GITHUB_TOKEN" ;;
          *) echo "" ;;
        esac
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        return GitAuthContext(
            environment: [
                "GIT_ASKPASS": scriptURL.path,
                "HUGODESK_GITHUB_TOKEN": token,
                "GCM_INTERACTIVE": "Never",
                "GIT_TERMINAL_PROMPT": "0"
            ],
            cleanup: {
                try? FileManager.default.removeItem(at: scriptURL)
            }
        )
    }

    private func sanitizeOutput(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
    }

    func hasGitHubPagesWorkflow(project: BlogProject) -> Bool {
        fm.fileExists(atPath: githubWorkflowURL(project: project).path)
    }

    func ensureGitHubPagesWorkflow(project: BlogProject) throws -> String {
        let workflowURL = githubWorkflowURL(project: project)
        try fm.createDirectory(at: workflowURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let workflow = """
        name: Deploy Hugo site to Pages

        on:
          push:
            branches:
              - \(project.publishBranch)
          workflow_dispatch:

        permissions:
          contents: read
          pages: write
          id-token: write

        concurrency:
          group: "pages"
          cancel-in-progress: false

        defaults:
          run:
            shell: bash

        jobs:
          build:
            runs-on: ubuntu-latest
            env:
              HUGO_VERSION: 0.157.0
            steps:
              - name: Checkout
                uses: actions/checkout@v4
                with:
                  fetch-depth: 0

              - name: Setup Hugo
                uses: peaceiris/actions-hugo@v3
                with:
                  hugo-version: ${{ env.HUGO_VERSION }}
                  extended: true

              - name: Setup Pages
                id: pages
                uses: actions/configure-pages@v5

              - name: Build with Hugo
                run: hugo --gc --minify --baseURL "${{ steps.pages.outputs.base_url }}/"

              - name: Upload artifact
                uses: actions/upload-pages-artifact@v3
                with:
                  path: ./public

          deploy:
            environment:
              name: github-pages
              url: ${{ steps.deployment.outputs.page_url }}
            runs-on: ubuntu-latest
            needs: build
            steps:
              - name: Deploy to GitHub Pages
                id: deployment
                uses: actions/deploy-pages@v4
        """
        try workflow.write(to: workflowURL, atomically: true, encoding: .utf8)

        let duplicates = duplicatePagesWorkflowFiles(project: project)
        var removed: [String] = []
        for file in duplicates {
            do {
                try fm.removeItem(at: file)
                removed.append(file.lastPathComponent)
            } catch {
                continue
            }
        }

        if removed.isEmpty {
            return workflowURL.path
        }
        return """
        \(workflowURL.path)
        已清理重复 workflow：\(removed.joined(separator: ", "))
        """
    }

    private func githubWorkflowURL(project: BlogProject) -> URL {
        project.rootURL
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent("hugo.yaml", isDirectory: false)
    }

    func duplicatePagesWorkflowFileNames(project: BlogProject) -> [String] {
        duplicatePagesWorkflowFiles(project: project).map(\.lastPathComponent)
    }

    private func duplicatePagesWorkflowFiles(project: BlogProject) -> [URL] {
        let workflowDir = project.rootURL
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: workflowDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let canonical = githubWorkflowURL(project: project).standardizedFileURL.path
        return files.filter { file in
            let ext = file.pathExtension.lowercased()
            guard ext == "yml" || ext == "yaml" else { return false }
            guard file.standardizedFileURL.path != canonical else { return false }
            guard let content = try? String(contentsOf: file, encoding: .utf8).lowercased() else { return false }
            return content.contains("deploy hugo site to pages")
                || content.contains("actions/deploy-pages")
        }
    }

    private func inspectHugoStructure(project: BlogProject) -> HugoStructureReport {
        let requiredFiles = ["hugo.toml"]
        var requiredDirectories = ["content"]

        let contentSubpath = project.contentSubpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contentSubpath.isEmpty, contentSubpath != "content", !contentSubpath.hasPrefix("/") {
            requiredDirectories.append(contentSubpath)
        }

        let recommendedDirectories = ["archetypes", "assets", "layouts", "static", "themes"]
        let recommendedFiles = [".github/workflows/hugo.yaml"]

        let missingRequiredFiles = requiredFiles.filter { !fileExists(project: project, relativePath: $0) }
        let missingRequiredDirectories = Array(Set(requiredDirectories))
            .sorted()
            .filter { !directoryExists(project: project, relativePath: $0) }
        let missingRecommendedDirectories = recommendedDirectories.filter {
            !directoryExists(project: project, relativePath: $0)
        }
        let missingRecommendedFiles = recommendedFiles.filter { !fileExists(project: project, relativePath: $0) }

        return HugoStructureReport(
            rootPath: project.rootPath,
            missingRequiredFiles: missingRequiredFiles,
            missingRequiredDirectories: missingRequiredDirectories,
            missingRecommendedFiles: missingRecommendedFiles,
            missingRecommendedDirectories: missingRecommendedDirectories,
            createdFiles: [],
            createdDirectories: []
        )
    }

    private func fileExists(project: BlogProject, relativePath: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let absolute = project.rootURL.appendingPathComponent(relativePath, isDirectory: false).path
        guard fm.fileExists(atPath: absolute, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private func directoryExists(project: BlogProject, relativePath: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let absolute = project.rootURL.appendingPathComponent(relativePath, isDirectory: true).path
        guard fm.fileExists(atPath: absolute, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func defaultHugoConfigTemplate() -> String {
        """
        baseURL = "/"
        languageCode = "zh-cn"
        title = "My Hugo Site"

        [markup]
          [markup.goldmark]
            [markup.goldmark.renderer]
              unsafe = true

        [params]
          author = ""
        """
    }

}

private struct ToolStatus {
    var displayName: String
    var exists: Bool
    var usable: Bool
    var versionText: String
    var requiresXcodeLicense: Bool
}

private struct CommandCapture {
    var success: Bool
    var output: String
}

private struct GitAuthContext {
    var environment: [String: String]
    var cleanup: () -> Void
}

struct HugoStructureReport {
    let rootPath: String
    let missingRequiredFiles: [String]
    let missingRequiredDirectories: [String]
    let missingRecommendedFiles: [String]
    let missingRecommendedDirectories: [String]
    var createdFiles: [String]
    var createdDirectories: [String]

    var hasMissingItems: Bool {
        !missingRequiredFiles.isEmpty
            || !missingRequiredDirectories.isEmpty
            || !missingRecommendedFiles.isEmpty
            || !missingRecommendedDirectories.isEmpty
    }

    var missingItemsForPrompt: [String] {
        var lines: [String] = []
        lines += missingRequiredFiles.map { "必需文件：\($0)" }
        lines += missingRequiredDirectories.map { "必需目录：\($0)" }
        lines += missingRecommendedFiles.map { "推荐文件：\($0)" }
        lines += missingRecommendedDirectories.map { "推荐目录：\($0)" }
        return lines
    }

    func renderCheckLog() -> String {
        var lines: [String] = []
        lines.append("== Hugo 文件结构检测 ==")
        lines.append("项目目录：\(rootPath)")
        lines.append(hasMissingItems ? "检测结果：发现缺失项。" : "检测结果：结构完整。")

        if !missingRequiredFiles.isEmpty {
            lines.append("-- 缺失必需文件 --")
            lines.append(contentsOf: missingRequiredFiles.map { "- \($0)" })
        }
        if !missingRequiredDirectories.isEmpty {
            lines.append("-- 缺失必需目录 --")
            lines.append(contentsOf: missingRequiredDirectories.map { "- \($0)" })
        }
        if !missingRecommendedFiles.isEmpty {
            lines.append("-- 缺失推荐文件 --")
            lines.append(contentsOf: missingRecommendedFiles.map { "- \($0)" })
        }
        if !missingRecommendedDirectories.isEmpty {
            lines.append("-- 缺失推荐目录 --")
            lines.append(contentsOf: missingRecommendedDirectories.map { "- \($0)" })
        }

        if hasMissingItems {
            lines.append("建议：点击“修复缺失结构”自动补齐。")
        }

        return lines.joined(separator: "\n")
    }

    func renderRepairLog() -> String {
        var lines: [String] = []
        lines.append("== Hugo 文件结构修复 ==")
        lines.append("项目目录：\(rootPath)")

        if createdFiles.isEmpty && createdDirectories.isEmpty {
            lines.append("没有创建新文件或目录。")
        } else {
            if !createdFiles.isEmpty {
                lines.append("-- 已创建文件 --")
                lines.append(contentsOf: createdFiles.map { "- \($0)" })
            }
            if !createdDirectories.isEmpty {
                lines.append("-- 已创建目录 --")
                lines.append(contentsOf: createdDirectories.map { "- \($0)" })
            }
        }

        if hasMissingItems {
            lines.append("⚠️ 仍有缺失项，请检查目录权限或手动处理。")
            lines.append(contentsOf: missingItemsForPrompt.map { "- \($0)" })
        } else {
            lines.append("✅ 结构修复完成。")
        }

        return lines.joined(separator: "\n")
    }
}

import AppKit
import SwiftUI

struct ProjectSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedHugoLogIDs: Set<UUID> = []
    @State private var showRawHugoLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ModernCard(title: "项目路径", subtitle: "本地目录与命令工具") {
                    VStack(spacing: 10) {
                        SettingRow(
                            key: "project.rootPath",
                            title: "博客根目录",
                            helpText: "Hugo 项目的根目录，包含 hugo.toml、content、themes 等文件夹。",
                            scope: "项目级"
                        ) {
                            HStack {
                                TextField("例如：/Users/you/Hugo", text: $viewModel.project.rootPath)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        viewModel.setProjectRootPath(viewModel.project.rootPath)
                                    }
                                Button("应用目录") {
                                    viewModel.setProjectRootPath(viewModel.project.rootPath)
                                }
                                Button("选择") {
                                    if let path = pickDirectory() {
                                        viewModel.setProjectRootPath(path)
                                    }
                                }
                            }
                        }

                        SettingRow(
                            key: "project.hugoExecutable",
                            title: "Hugo 可执行命令",
                            helpText: "默认使用 hugo，可填写绝对路径以锁定版本。",
                            scope: "构建流程"
                        ) {
                            TextField("hugo", text: $viewModel.project.hugoExecutable)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingRow(
                            key: "project.contentSubpath",
                            title: "文章目录",
                            helpText: "文章保存目录，默认自动识别 content/posts 或 content/post。",
                            scope: "内容管理"
                        ) {
                            TextField("content/post", text: $viewModel.project.contentSubpath)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                ModernCard(title: "Git 发布目标", subtitle: "推送到远端仓库的配置") {
                    VStack(spacing: 10) {
                        SettingRow(
                            key: "project.gitRemote",
                            title: "远程名称",
                            helpText: "通常为 origin，也可切换为其他 remote。",
                            scope: "发布流程"
                        ) {
                            TextField("origin", text: $viewModel.project.gitRemote)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingRow(
                            key: "project.publishBranch",
                            title: "发布分支",
                            helpText: "默认 main。点击“提交并推送”时会推送到该分支。",
                            scope: "发布流程"
                        ) {
                            TextField("main", text: $viewModel.project.publishBranch)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                ModernCard(title: "远程地址与凭据", subtitle: "自动读取并保存（同步到项目配置包）") {
                    VStack(spacing: 10) {
                        SettingRow(
                            key: "profile.remoteURL",
                            title: "推送仓库地址",
                            helpText: "例如 https://github.com/you/you.github.io.git。用于推送与 Actions 查询。",
                            scope: "发布流程"
                        ) {
                            TextField("https://github.com/you/repo.git", text: $viewModel.publishRemoteURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingRow(
                            key: "keychain.githubTokenFineGrained",
                            title: "GitHub Token（Fine-grained）",
                            helpText: "用于 Git 推送与常规 API 查询。示例前缀：github_pat_...",
                            scope: "发布流程"
                        ) {
                            TextField("github_pat_xxx", text: $viewModel.githubFineGrainedToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingRow(
                            key: "keychain.githubTokenClassic",
                            title: "GitHub Token（Classic）",
                            helpText: "Pages 来源检测/重置建议优先使用 Classic（需 repo/workflow/pages 相关权限）。示例前缀：ghp_...",
                            scope: "Pages 检测"
                        ) {
                            TextField("ghp_xxx", text: $viewModel.githubClassicToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Button("保存远程与令牌") {
                                viewModel.saveRemoteProfile()
                            }
                            Text("当前生效 Token：\(viewModel.githubTokenUsageSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text("配置会同步到项目根目录 .hugodesk.local.json，并写入系统 Keychain 作为兼容备份。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ModernCard(title: "Hugo 工具", subtitle: "本机 Hugo 常用命令与结构修复") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("检查 Hugo 版本") {
                                viewModel.runHugoVersionCheck()
                            }
                            Button("升级 Hugo（Homebrew）") {
                                viewModel.runHugoUpgrade()
                            }
                            Button("检测文件结构") {
                                viewModel.runHugoStructureCheck()
                            }
                            if viewModel.lastHugoStructureReport?.hasMissingItems == true {
                                Button("修复缺失结构") {
                                    viewModel.runHugoStructureRepair()
                                }
                            }
                            Spacer()
                        }

                        if let report = viewModel.lastHugoStructureReport {
                            Text(report.hasMissingItems ? "检测结果：存在缺失项，请按需修复。" : "检测结果：结构完整。")
                                .font(.caption)
                                .foregroundStyle(report.hasMissingItems ? .orange : .green)
                        }

                        Divider()

                        HStack {
                            Text("Hugo 工具日志")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("清空") {
                                viewModel.clearHugoToolLogs()
                                expandedHugoLogIDs.removeAll()
                                showRawHugoLog = false
                            }
                            Button("复制") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(viewModel.hugoToolLog, forType: .string)
                            }
                        }

                        if viewModel.hugoToolLogEntries.isEmpty {
                            Text("暂无 Hugo 工具日志。执行检查/升级/结构检测后会显示进程与错误信息。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(viewModel.hugoToolLogEntries.reversed())) { entry in
                                        DisclosureGroup(isExpanded: bindingForHugoLog(id: entry.id)) {
                                            ScrollView(.horizontal) {
                                                Text(entry.details.isEmpty ? "无详细输出" : entry.details)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .textSelection(.enabled)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(.top, 6)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: icon(for: entry.level))
                                                    .foregroundStyle(color(for: entry.level))
                                                Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.operation)")
                                                    .font(.subheadline.weight(.semibold))
                                                Text(entry.summary)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.black.opacity(0.03))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .frame(minHeight: 160, maxHeight: 280)
                        }

                        DisclosureGroup("完整原始日志（可复制）", isExpanded: $showRawHugoLog) {
                            ScrollView([.vertical, .horizontal]) {
                                Text(viewModel.hugoToolLog.isEmpty ? "暂无输出" : viewModel.hugoToolLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(minHeight: 120, maxHeight: 200)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                ModernCard(title: "项目配置包", subtitle: "固定保存在博客根目录，自动加载，不会被 Git 上传") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localConfigBundlePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Button("重新加载项目") {
                                viewModel.loadAll()
                            }
                            Button("一键导出到项目目录") {
                                viewModel.exportConfigBundleToProject()
                            }
                            Button("一键从项目目录还原") {
                                viewModel.importConfigBundleFromProject()
                            }
                            Spacer()
                        }
                        Text("配置包包含项目设置、主题配置、远程信息、GitHub Token（Classic/Fine-grained）与 AI API 信息。切换博客目录时会自动尝试读取该文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .alert("检测到 Hugo 结构缺失", isPresented: $viewModel.showHugoStructureRepairPrompt) {
            Button("稍后处理", role: .cancel) {
                viewModel.dismissHugoStructureRepairPrompt()
            }
            Button("立即修复") {
                viewModel.runHugoStructureRepair()
            }
        } message: {
            Text(viewModel.hugoStructurePromptMessage)
        }
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func icon(for level: PublishLogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for level: PublishLogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func bindingForHugoLog(id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedHugoLogIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedHugoLogIDs.insert(id)
                } else {
                    expandedHugoLogIDs.remove(id)
                }
            }
        )
    }
}

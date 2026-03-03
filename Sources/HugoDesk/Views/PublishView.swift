import AppKit
import SwiftUI

struct PublishView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedLogIDs: Set<UUID> = []
    @State private var showRawLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModernCard(title: "发布前检查", subtitle: "先检查再发布，减少失败率") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.preflightChecks()) { check in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: iconName(for: check.level))
                                    .foregroundStyle(color(for: check.level))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(check.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                ModernCard(title: "GitHub Actions 状态", subtitle: "显示最新 workflow 运行结果") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("仓库地址（https://github.com/owner/repo.git）", text: $viewModel.publishRemoteURL)
                            .textFieldStyle(.roundedBorder)
                        TextField("Workflow 名称（可留空）", text: $viewModel.workflowName)
                            .textFieldStyle(.roundedBorder)
                        SecureField("GitHub Token（可选，推荐）", text: $viewModel.githubToken)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("保存查询配置") {
                                viewModel.saveRemoteProfile()
                            }
                            Button("查询最新状态") {
                                viewModel.refreshActionsStatus()
                            }
                            if let run = viewModel.latestWorkflowStatus {
                                Text(run.statusText)
                                    .font(.caption2)
                                    .foregroundStyle(statusColor(for: run).opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(statusColor(for: run).opacity(0.16))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }

                        if let run = viewModel.latestWorkflowStatus {
                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                GridRow {
                                    Text("Workflow").foregroundStyle(.secondary)
                                    Text(run.name)
                                }
                                GridRow {
                                    Text("分支").foregroundStyle(.secondary)
                                    Text(run.branch)
                                }
                                GridRow {
                                    Text("提交").foregroundStyle(.secondary)
                                    Text(String(run.sha.prefix(10)))
                                        .font(.system(.body, design: .monospaced))
                                }
                                GridRow {
                                    Text("创建时间").foregroundStyle(.secondary)
                                    Text(run.createdAt)
                                }
                                GridRow {
                                    Text("更新时间").foregroundStyle(.secondary)
                                    Text(run.updatedAt)
                                }
                            }
                            if let note = run.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Link("打开运行详情", destination: URL(string: run.htmlURL)!)
                        } else if !viewModel.latestWorkflowError.isEmpty {
                            Text("查询失败，请在下方日志查看错误详情与 AI 排障建议。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("点击“查询最新状态”后显示结果。")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ModernCard(title: "发布控制台", subtitle: "构建、检查、提交、推送") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("提交信息", text: $viewModel.publishMessage)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("保存配置") {
                                viewModel.saveThemeConfig()
                            }
                            Button("构建站点") {
                                viewModel.runBuild()
                            }
                            Button("查看 Git 状态") {
                                viewModel.runGitStatus()
                            }
                            Button("同步远程") {
                                viewModel.runSyncWithRemote()
                            }
                            Button("提交并推送") {
                                viewModel.runPublish()
                            }
                        }

                        Divider()

                        HStack {
                            Button("一键检测推送能力") {
                                viewModel.runEnvironmentDiagnostics()
                            }
                            Spacer()
                        }
                        Text("检测会验证 git/hugo 可用性、远程可达性与 dry-run 推送权限，并给出可执行命令建议。推送前可先点击“同步远程”。发布时会自动排除 HugoDesk/HugoDeskArchive/hugo.toml/.hugodesk.local.json。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ModernCard(title: "日志输出", subtitle: "可折叠查看详细日志，支持复制") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("清空日志") {
                                viewModel.clearPublishLogs()
                                expandedLogIDs.removeAll()
                                showRawLog = false
                            }
                            Button("复制全部日志") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(viewModel.publishLog, forType: .string)
                            }
                            Spacer()
                            Text("共 \(viewModel.publishLogEntries.count) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.publishLogEntries.isEmpty {
                            Text("暂无日志。执行“构建/检测/推送”后会在这里显示进程与错误详情。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(viewModel.publishLogEntries.reversed())) { entry in
                                        DisclosureGroup(isExpanded: bindingForLog(id: entry.id)) {
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
                            .frame(minHeight: 240, maxHeight: 420)
                        }

                        DisclosureGroup("完整原始日志（可选择复制）", isExpanded: $showRawLog) {
                            ScrollView([.vertical, .horizontal]) {
                                Text(viewModel.publishLog.isEmpty ? "暂无输出" : viewModel.publishLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(minHeight: 140, maxHeight: 260)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Text("应用会在当前项目目录执行本机的 git/hugo/brew 命令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func statusColor(for run: WorkflowRunStatus) -> Color {
        if run.conclusion == "success" { return .green }
        if run.conclusion == "failure" || run.conclusion == "cancelled" { return .red }
        if run.status == "in_progress" || run.status == "queued" { return .orange }
        return .secondary
    }

    private func iconName(for level: PublishCheck.Level) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for level: PublishCheck.Level) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        }
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

    private func bindingForLog(id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedLogIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedLogIDs.insert(id)
                } else {
                    expandedLogIDs.remove(id)
                }
            }
        )
    }
}

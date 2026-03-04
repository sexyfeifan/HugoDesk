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
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                            GridRow {
                                Text("仓库地址").foregroundStyle(.secondary)
                                Text(viewModel.publishRemoteURL.isEmpty ? "未设置（请到项目页配置）" : viewModel.publishRemoteURL)
                                    .textSelection(.enabled)
                            }
                            GridRow {
                                Text("Workflow").foregroundStyle(.secondary)
                                Text(viewModel.workflowName.isEmpty ? "未设置（请到项目页配置）" : viewModel.workflowName)
                            }
                            GridRow {
                                Text("Token").foregroundStyle(.secondary)
                                Text(viewModel.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置（请到项目页配置）" : "已设置")
                            }
                        }
                        Text("远程地址与凭据统一在“项目”页维护，发布页仅展示状态和执行操作，避免重复配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("查询最新状态") {
                                viewModel.refreshActionsStatus()
                            }
                            Button("检查 Pages 来源") {
                                viewModel.refreshPagesSourceStatus()
                            }
                            Button("修复为 GitHub Actions") {
                                viewModel.repairPagesSourceToWorkflow()
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
                            Button("一键生成 Pages Workflow") {
                                viewModel.bootstrapGitHubPagesWorkflow()
                            }
                            Spacer()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pages 构建来源")
                                .font(.subheadline.weight(.semibold))
                            if let site = viewModel.pagesSiteStatus {
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                    GridRow {
                                        Text("build_type").foregroundStyle(.secondary)
                                        Text(site.buildType)
                                    }
                                    GridRow {
                                        Text("source").foregroundStyle(.secondary)
                                        Text(site.sourceDescription)
                                    }
                                    GridRow {
                                        Text("地址").foregroundStyle(.secondary)
                                        Text(site.htmlURL)
                                            .textSelection(.enabled)
                                    }
                                }
                                if site.buildType.lowercased() != "workflow" {
                                    Text("当前不是 workflow 模式，可能触发 pages-build-deployment 覆盖站点并导致 File not found。")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("已使用 workflow 构建来源，不会再走分支直部署链路。")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            } else if !viewModel.pagesSiteError.isEmpty {
                                Text("Pages 来源检查失败：\(viewModel.pagesSiteError)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("点击“检查 Pages 来源”确认是否已切换到 workflow。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

                ModernCard(title: "发布控制台", subtitle: "同步、检测、提交并推送") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("提交信息", text: $viewModel.publishMessage)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("同步远程") {
                                viewModel.runSyncWithRemote()
                            }
                            Button("一键检测推送与部署") {
                                viewModel.runEnvironmentDiagnostics()
                            }
                            Button("提交并推送") {
                                viewModel.runPublish()
                            }
                            Spacer()
                        }

                        Text("检测会验证 git/hugo 可用性、远程可达性、dry-run 推送权限与 Pages 部署链路。发布时自动排除 HugoDesk/HugoDeskArchive/.hugodesk.local.json，hugo.toml 始终随项目发布。")
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
                            Text("暂无日志。执行“同步/检测/推送”后会在这里显示进程与错误详情。")
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

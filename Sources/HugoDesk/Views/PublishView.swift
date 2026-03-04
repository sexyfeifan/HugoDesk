import AppKit
import SwiftUI

struct PublishView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedLogIDs: Set<UUID> = []
    @State private var showRawLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModernCard(title: "发布工作流", subtitle: "替代命令行：检查结构 → 构建验证 → 同步远端 → 推送 → 部署验证") {
                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                            GridRow {
                                Text("仓库地址").foregroundStyle(.secondary)
                                Text(viewModel.publishRemoteURL.isEmpty ? "未设置（请到项目页配置）" : viewModel.publishRemoteURL)
                                    .textSelection(.enabled)
                            }
                            GridRow {
                                Text("发布分支").foregroundStyle(.secondary)
                                Text(viewModel.project.publishBranch)
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

                        TextField("提交信息", text: $viewModel.publishMessage)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("1) 检测结构") {
                                viewModel.runHugoStructureCheck()
                            }
                            Button("2) 生成/更新 Workflow") {
                                viewModel.bootstrapGitHubPagesWorkflow()
                            }
                            Button("3) 检查 Pages 来源") {
                                viewModel.refreshPagesSourceStatus()
                            }
                            Button("修复为 GitHub Actions") {
                                viewModel.repairPagesSourceToWorkflow()
                            }
                            Spacer()
                        }
                        HStack {
                            Button("4) 构建校验") {
                                viewModel.runBuild()
                            }
                            Button("5) 同步远端") {
                                viewModel.runSyncWithRemote()
                            }
                            Button("6) 提交并推送") {
                                viewModel.runPublish()
                            }
                            Button("部署状态") {
                                viewModel.refreshActionsStatus()
                            }
                            Spacer()
                        }

                        HStack {
                            Button("一键检测发布链路") {
                                viewModel.runEnvironmentDiagnostics()
                            }
                            Button("一键发布（推荐）") {
                                viewModel.runGuidedPublishWorkflow()
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
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
                                Text("Pages 来源检查失败（不阻断发布）：\(viewModel.pagesSiteError)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("点击“检查 Pages 来源”确认是否已切换到 workflow。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

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
                            Text("点击“部署状态”后显示结果。")
                                .foregroundStyle(.secondary)
                        }

                        DisclosureGroup("预检详情") {
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
                            .padding(.top, 6)
                        }

                        Text("推荐发布方式：先点击“一键发布（推荐）”。如需手动排障，再按上方 1→6 步骤逐项执行。")
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
                            Text("暂无日志。执行“步骤按钮”或“一键发布”后会在这里显示进程与错误详情。")
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

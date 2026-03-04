import AppKit
import SwiftUI

struct PublishView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedLogIDs: Set<UUID> = []
    @State private var selectedPreflightCheck: PublishCheck?
    private let logRowMinWidth: CGFloat = 1080
    private let preflightCardHeight: CGFloat = 88
    private let preflightColumns = [
        GridItem(.flexible(minimum: 220), spacing: 10),
        GridItem(.flexible(minimum: 220), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModernCard(title: "发布工作流", subtitle: "替代命令行：同步远端 → 提交推送 → GitHub Actions 自动部署") {
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
                                Text("Token").foregroundStyle(.secondary)
                                Text(viewModel.githubTokenUsageSummary == "未配置"
                                    ? "未设置（请到项目页配置）"
                                    : "已设置（\(viewModel.githubTokenUsageSummary)）")
                            }
                        }
                        Text("远程地址与凭据统一在“项目”页维护，发布页仅展示状态和执行操作，避免重复配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("提交信息", text: $viewModel.publishMessage)
                            .textFieldStyle(.roundedBorder)

                        Text("发布前检查")
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: preflightColumns, alignment: .leading, spacing: 8) {
                            ForEach(viewModel.preflightChecks()) { check in
                                Button {
                                    selectedPreflightCheck = check
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: iconName(for: check.level))
                                            .foregroundStyle(color(for: check.level))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(check.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text(statusLabel(for: check.level))
                                                .font(.caption)
                                                .foregroundStyle(color(for: check.level))
                                                .lineLimit(1)
                                            Text("点击查看详情")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: preflightCardHeight, maxHeight: preflightCardHeight, alignment: .topLeading)
                                    .padding(8)
                                    .background(Color.black.opacity(0.03))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        Button("一键发布") {
                            viewModel.runGuidedPublishWorkflow()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .frame(maxWidth: .infinity, alignment: .center)
                        .help("自动执行结构检查、同步远端、workflow/Pages 来源处理、提交推送与部署状态查询。")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("发布执行")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                Button("同步远端") {
                                    viewModel.runSyncWithRemote()
                                }
                                .help("先拉取并 rebase 远端分支，解决 non-fast-forward 推送问题。")

                                Button("提交并推送") {
                                    viewModel.runPublish()
                                }
                                .help("与“一键发布”执行同一流程，保留此按钮用于你的操作习惯。")

                                Button("部署状态") {
                                    viewModel.refreshActionsStatus()
                                }
                                .help("查看最新 GitHub Actions 部署状态和日志入口。")
                                Spacer()
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("部署修复")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                Button("生成或更新 Workflow") {
                                    viewModel.bootstrapGitHubPagesWorkflow()
                                }
                                .help("缺少或异常时重建 Pages workflow，并清理重复项。")

                                Button("检查 Pages 来源") {
                                    viewModel.refreshPagesSourceStatus()
                                }
                                .help("检查仓库 Pages 当前来源是否为 workflow 模式。")

                                Button("修复 Pages 来源") {
                                    viewModel.repairPagesSourceToWorkflow()
                                }
                                .help("将 Pages 来源切换到 GitHub Actions，避免 branch 部署冲突。")
                                Spacer()
                            }
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
                                Text("Pages 来源检查失败（详情已弹窗，不阻断发布）。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                    Text("创建时间（本地）").foregroundStyle(.secondary)
                                    Text(run.createdAtLocalText)
                                }
                                GridRow {
                                    Text("更新时间（本地）").foregroundStyle(.secondary)
                                    Text(run.updatedAtLocalText)
                                }
                            }
                            if let note = run.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let runURL = URL(string: run.htmlURL) {
                                Link("打开运行详情", destination: runURL)
                            } else {
                                Text(run.htmlURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } else if !viewModel.latestWorkflowError.isEmpty {
                            Text("查询失败，请在下方日志查看错误详情与 AI 排障建议。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("点击“部署状态”后显示结果。")
                                .foregroundStyle(.secondary)
                        }

                        if let checked = viewModel.latestWorkflowCheckedAt {
                            Text("状态自动每 30 秒同步。最近同步：\(checked.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("状态自动每 30 秒同步，也可点击“部署状态”手动刷新。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    }
                }

                ModernCard(title: "日志输出", subtitle: "可折叠查看详细日志，支持复制") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("清空日志") {
                                viewModel.clearPublishLogs()
                                expandedLogIDs.removeAll()
                            }
                            Button("刷新日志") {
                                viewModel.refreshPublishLogSnapshot()
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
                            Text("完整原始日志")
                                .font(.subheadline.weight(.semibold))
                            ScrollView([.vertical, .horizontal]) {
                                NumberedLogBlock(text: viewModel.publishLog.isEmpty ? "暂无输出" : viewModel.publishLog)
                                    .frame(minWidth: logRowMinWidth, maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(minHeight: 140, maxHeight: 260)
                            .background(Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text("折叠日志")
                                .font(.subheadline.weight(.semibold))
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(viewModel.publishLogEntries.reversed())) { entry in
                                        DisclosureGroup(isExpanded: bindingForLog(id: entry.id)) {
                                            ScrollView(.horizontal) {
                                                NumberedLogBlock(text: entry.details.isEmpty ? "无详细输出" : entry.details)
                                                    .frame(minWidth: logRowMinWidth, maxWidth: .infinity, alignment: .leading)
                                                    .padding(.trailing, 2)
                                            }
                                            .padding(.top, 6)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: icon(for: entry.level))
                                                    .foregroundStyle(color(for: entry.level))
                                                Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))]")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.blue)
                                                Text(entry.operation)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.orange)
                                                Text(entry.summary)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.03))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .frame(minHeight: 240, maxHeight: 420)
                        }
                    }
                }

                Text("应用会在当前项目目录执行本机的 git/hugo/brew 命令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .sheet(item: $selectedPreflightCheck) { check in
            PreflightCheckDetailSheet(check: check)
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

    private func statusLabel(for level: PublishCheck.Level) -> String {
        switch level {
        case .ok: return "状态：正常"
        case .warning: return "状态：需要关注"
        case .error: return "状态：存在问题"
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

private struct PreflightCheckDetailSheet: View {
    let check: PublishCheck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: iconName(for: check.level))
                    .foregroundStyle(color(for: check.level))
                Text(check.title)
                    .font(.headline)
                Spacer()
                Text(statusLabel(for: check.level))
                    .font(.caption)
                    .foregroundStyle(color(for: check.level))
            }

            ScrollView {
                Text(check.detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 280)
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

    private func statusLabel(for level: PublishCheck.Level) -> String {
        switch level {
        case .ok: return "正常"
        case .warning: return "需要关注"
        case .error: return "存在问题"
        }
    }
}

private struct NumberedLogBlock: View {
    let text: String

    private var lines: [String] {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        return cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                    Text(String(format: "%04d", idx + 1))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if line.hasPrefix("[") {
            return .blue
        }
        if line.hasPrefix("==") {
            return .orange
        }
        if line.contains("失败") || lower.contains("error") || lower.contains("fatal") {
            return .red
        }
        if line.contains("完成") || lower.contains("success") {
            return .green
        }
        return .primary
    }
}

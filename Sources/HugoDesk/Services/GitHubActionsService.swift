import Foundation

enum GitHubActionsError: LocalizedError {
    case invalidRepositoryURL
    case noRunsFound
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            return "无法解析 GitHub 仓库地址。"
        case .noRunsFound:
            return "该仓库还没有任何 workflow 运行记录。"
        case let .httpError(code, body):
            if code == 401 || code == 403 {
                return "GitHub API 鉴权失败（HTTP \(code)）。请检查 Token 权限（建议包含 repo/read:org/workflow 至少可读 workflow）。"
            }
            return "GitHub API 请求失败：HTTP \(code)\n\(body)"
        }
    }
}

struct GitHubActionsService: Sendable {
    func fetchLatestRun(
        remoteURL: String,
        token: String,
        workflowName: String,
        branch: String? = nil
    ) async throws -> WorkflowRunStatus {
        let repo = try parseRepo(from: remoteURL)
        let branchValue = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Prefer querying the managed workflow file directly to avoid stale runs from unrelated workflows.
        if let workflowURL = buildActionsURL(
            "https://api.github.com/repos/\(repo.owner)/\(repo.name)/actions/workflows/hugo.yaml/runs",
            perPage: 20,
            branch: branchValue
        ) {
            do {
                let decoded = try await requestWorkflowRuns(url: workflowURL, token: token)
                if let run = decoded.workflowRuns.first {
                    return makeStatus(from: run, note: branchValue.isEmpty ? nil : "已按分支 \(branchValue) 过滤。")
                }
            } catch GitHubActionsError.httpError(let code, _) where code == 404 {
                // Fallback to generic runs endpoint when workflow file path is unavailable.
            }
        }

        guard let endpoint = buildActionsURL(
            "https://api.github.com/repos/\(repo.owner)/\(repo.name)/actions/runs",
            perPage: 50,
            branch: branchValue
        ) else {
            throw GitHubActionsError.invalidRepositoryURL
        }

        let decoded = try await requestWorkflowRuns(url: endpoint, token: token)
        let picked: WorkflowRunItem?
        var note: String?
        if workflowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            picked = decoded.workflowRuns.first
        } else {
            picked = decoded.workflowRuns.first {
                $0.name.localizedCaseInsensitiveContains(workflowName)
            }
            if picked == nil {
                note = "未匹配到指定 workflow，已回退为最近一次运行。"
            }
        }

        let finalRun = picked ?? decoded.workflowRuns.first
        guard let run = finalRun else {
            throw GitHubActionsError.noRunsFound
        }

        if note == nil, !branchValue.isEmpty {
            note = "已按分支 \(branchValue) 过滤。"
        }
        return makeStatus(from: run, note: note)
    }

    private func requestWorkflowRuns(url: URL, token: String) async throws -> WorkflowRunsResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HugoDesk", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard 200..<300 ~= code else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubActionsError.httpError(code, body)
        }
        return try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
    }

    private func buildActionsURL(_ base: String, perPage: Int, branch: String) -> URL? {
        guard var components = URLComponents(string: base) else {
            return nil
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if !branch.isEmpty {
            queryItems.append(URLQueryItem(name: "branch", value: branch))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func makeStatus(from run: WorkflowRunItem, note: String?) -> WorkflowRunStatus {
        WorkflowRunStatus(
            name: run.name,
            status: run.status,
            conclusion: run.conclusion,
            htmlURL: run.htmlURL,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt,
            branch: run.headBranch,
            sha: run.headSHA,
            note: note
        )
    }

    private func parseRepo(from remoteURL: String) throws -> (owner: String, name: String) {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("git@github.com:") {
            let rest = trimmed.replacingOccurrences(of: "git@github.com:", with: "")
            let parts = rest.split(separator: "/")
            guard parts.count == 2 else {
                throw GitHubActionsError.invalidRepositoryURL
            }
            let owner = String(parts[0])
            let repo = stripGitSuffix(String(parts[1]))
            return (owner, repo)
        }

        guard let url = URL(string: trimmed),
              url.host?.contains("github.com") == true else {
            throw GitHubActionsError.invalidRepositoryURL
        }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else {
            throw GitHubActionsError.invalidRepositoryURL
        }
        let owner = comps[0]
        let repo = stripGitSuffix(comps[1])
        return (owner, repo)
    }

    private func stripGitSuffix(_ name: String) -> String {
        guard name.hasSuffix(".git") else {
            return name
        }
        return String(name.dropLast(4))
    }
}

private struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRunItem]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct WorkflowRunItem: Decodable {
    let name: String
    let status: String
    let conclusion: String?
    let htmlURL: String
    let createdAt: String
    let updatedAt: String
    let headBranch: String
    let headSHA: String

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case conclusion
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case headBranch = "head_branch"
        case headSHA = "head_sha"
    }
}

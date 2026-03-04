import Foundation

enum GitHubPagesServiceError: LocalizedError {
    case invalidRepositoryURL
    case missingTokenForUpdate
    case pagesSiteNotFound(settingsURL: String)
    case httpError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            return "无法解析 GitHub 仓库地址。"
        case .missingTokenForUpdate:
            return "修复 Pages 来源需要 GitHub Token（需具备 Pages/Administration 写权限）。"
        case let .pagesSiteNotFound(settingsURL):
            return """
            GitHub Pages API 请求失败：HTTP 404（Not Found）
            这通常是以下原因之一：
            1) 当前 Token 对该仓库没有 Pages/Administration 权限，或非仓库管理员
            2) 该仓库的 Pages 站点尚未启用

            可先继续“构建/同步/提交并推送”，该告警不应阻断 Git 推送。
            然后到以下页面检查并启用 GitHub Actions 作为来源：
            \(settingsURL)
            """
        case let .httpError(code, body):
            return "GitHub Pages API 请求失败：HTTP \(code)\n\(body)"
        case .invalidResponse:
            return "GitHub Pages API 返回内容无法识别。"
        }
    }
}

struct GitHubPagesSiteStatus {
    var buildType: String
    var sourceBranch: String?
    var sourcePath: String?
    var htmlURL: String

    var sourceDescription: String {
        let branch = sourceBranch ?? "-"
        let path = sourcePath ?? "-"
        return "\(branch) \(path)"
    }
}

struct GitHubPagesService: Sendable {
    func fetchSiteStatus(remoteURL: String, token: String) async throws -> GitHubPagesSiteStatus {
        let repo = try parseRepo(from: remoteURL)
        let endpoint = URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/pages")!
        let settingsURL = pagesSettingsURL(for: repo)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HugoDesk", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard 200..<300 ~= code else {
            if code == 404 {
                throw GitHubPagesServiceError.pagesSiteNotFound(settingsURL: settingsURL)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubPagesServiceError.httpError(code, body)
        }

        let decoded = try JSONDecoder().decode(PagesSiteResponse.self, from: data)
        return GitHubPagesSiteStatus(
            buildType: decoded.buildType ?? "unknown",
            sourceBranch: decoded.source?.branch,
            sourcePath: decoded.source?.path,
            htmlURL: decoded.htmlURL ?? ""
        )
    }

    func switchToWorkflowBuild(remoteURL: String, token: String, branch: String) async throws -> GitHubPagesSiteStatus {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw GitHubPagesServiceError.missingTokenForUpdate
        }

        let repo = try parseRepo(from: remoteURL)
        let endpoint = URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/pages")!
        let settingsURL = pagesSettingsURL(for: repo)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HugoDesk", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "build_type": "workflow",
            "source": [
                "branch": branch,
                "path": "/"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 204 || code == 200 else {
            if code == 404 {
                throw GitHubPagesServiceError.pagesSiteNotFound(settingsURL: settingsURL)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubPagesServiceError.httpError(code, body)
        }

        return try await fetchSiteStatus(remoteURL: remoteURL, token: trimmedToken)
    }

    private func parseRepo(from remoteURL: String) throws -> (owner: String, name: String) {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("git@github.com:") {
            let rest = trimmed.replacingOccurrences(of: "git@github.com:", with: "")
            let parts = rest.split(separator: "/")
            guard parts.count == 2 else {
                throw GitHubPagesServiceError.invalidRepositoryURL
            }
            let owner = String(parts[0])
            let repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
            return (owner, repo)
        }

        guard let url = URL(string: trimmed),
              url.host?.contains("github.com") == true else {
            throw GitHubPagesServiceError.invalidRepositoryURL
        }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else {
            throw GitHubPagesServiceError.invalidRepositoryURL
        }
        let owner = comps[0]
        let repo = comps[1].replacingOccurrences(of: ".git", with: "")
        return (owner, repo)
    }

    private func pagesSettingsURL(for repo: (owner: String, name: String)) -> String {
        "https://github.com/\(repo.owner)/\(repo.name)/settings/pages"
    }
}

private struct PagesSiteResponse: Decodable {
    let buildType: String?
    let htmlURL: String?
    let source: PagesSource?

    enum CodingKeys: String, CodingKey {
        case buildType = "build_type"
        case htmlURL = "html_url"
        case source
    }
}

private struct PagesSource: Decodable {
    let branch: String?
    let path: String?
}

import Foundation

enum PublishDeploymentMode: String, CaseIterable, Codable, Identifiable {
    case githubActions
    case directSourcePush

    var id: String { rawValue }

    var title: String {
        switch self {
        case .githubActions:
            return "GitHub Actions（推荐）"
        case .directSourcePush:
            return "仅推送源码"
        }
    }
}

struct RemoteProfile: Codable {
    var remoteURL: String
    var workflowName: String
    var deploymentMode: PublishDeploymentMode
    var excludeHugoConfigOnPublish: Bool

    init(
        remoteURL: String,
        workflowName: String,
        deploymentMode: PublishDeploymentMode = .githubActions,
        excludeHugoConfigOnPublish: Bool = false
    ) {
        self.remoteURL = remoteURL
        self.workflowName = workflowName
        self.deploymentMode = deploymentMode
        self.excludeHugoConfigOnPublish = excludeHugoConfigOnPublish
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remoteURL = try c.decodeIfPresent(String.self, forKey: .remoteURL) ?? ""
        workflowName = try c.decodeIfPresent(String.self, forKey: .workflowName) ?? ""
        deploymentMode = try c.decodeIfPresent(PublishDeploymentMode.self, forKey: .deploymentMode) ?? .githubActions
        excludeHugoConfigOnPublish = try c.decodeIfPresent(Bool.self, forKey: .excludeHugoConfigOnPublish) ?? false
    }
}

struct WorkflowRunStatus {
    var name: String
    var status: String
    var conclusion: String?
    var htmlURL: String
    var createdAt: String
    var updatedAt: String
    var branch: String
    var sha: String
    var note: String?

    var statusText: String {
        if let conclusion, !conclusion.isEmpty {
            return "\(status) / \(conclusion)"
        }
        return status
    }
}

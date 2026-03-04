import Foundation

struct RemoteProfile: Codable {
    var remoteURL: String
    var workflowName: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remoteURL = try c.decodeIfPresent(String.self, forKey: .remoteURL) ?? ""
        workflowName = try c.decodeIfPresent(String.self, forKey: .workflowName) ?? ""
    }

    init(remoteURL: String, workflowName: String) {
        self.remoteURL = remoteURL
        self.workflowName = workflowName
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

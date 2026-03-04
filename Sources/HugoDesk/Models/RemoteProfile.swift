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

    var createdAtLocalText: String {
        Self.localTimeText(fromISO8601: createdAt)
    }

    var updatedAtLocalText: String {
        Self.localTimeText(fromISO8601: updatedAt)
    }

    private static func localTimeText(fromISO8601 raw: String) -> String {
        guard let date = parseISO8601(raw) else {
            return raw
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: text) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

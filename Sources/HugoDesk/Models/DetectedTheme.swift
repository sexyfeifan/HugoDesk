import Foundation

struct DetectedTheme: Identifiable, Hashable {
    let name: String
    let sourceDescription: String
    let supportsGitalk: Bool
    let supportsSearch: Bool
    let supportsLinks: Bool
    let supportsMath: Bool
    let referencedParamKeys: [String]

    var id: String {
        name.lowercased()
    }

    var hasCapabilitySignals: Bool {
        supportsGitalk || supportsSearch || supportsLinks || supportsMath || !referencedParamKeys.isEmpty
    }

    var capabilitySummary: String {
        var tags: [String] = []
        if supportsGitalk { tags.append("Gitalk") }
        if supportsSearch { tags.append("搜索") }
        if supportsLinks { tags.append("外链") }
        if supportsMath { tags.append("数学公式") }

        if tags.isEmpty {
            return "未检测到明确能力标签"
        }
        return "检测能力：\(tags.joined(separator: " / "))"
    }
}


import Foundation

struct ConfigBackupBundle: Codable {
    var schemaVersion: Int = 1
    var exportedAt: Date
    var project: BlogProject
    var themeConfig: ThemeConfig
    var remoteProfile: RemoteProfile
    var githubTokenClassic: String
    var githubTokenFineGrained: String
    var aiProfile: AIProfile
    var aiAPIKey: String

    init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        project: BlogProject,
        themeConfig: ThemeConfig,
        remoteProfile: RemoteProfile,
        githubTokenClassic: String,
        githubTokenFineGrained: String,
        aiProfile: AIProfile,
        aiAPIKey: String
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.project = project
        self.themeConfig = themeConfig
        self.remoteProfile = remoteProfile
        self.githubTokenClassic = githubTokenClassic
        self.githubTokenFineGrained = githubTokenFineGrained
        self.aiProfile = aiProfile
        self.aiAPIKey = aiAPIKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        project = try container.decode(BlogProject.self, forKey: .project)
        themeConfig = try container.decode(ThemeConfig.self, forKey: .themeConfig)
        remoteProfile = try container.decode(RemoteProfile.self, forKey: .remoteProfile)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyToken = try legacy.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
        githubTokenClassic = try container.decodeIfPresent(String.self, forKey: .githubTokenClassic) ?? ""
        githubTokenFineGrained = try container.decodeIfPresent(String.self, forKey: .githubTokenFineGrained) ?? ""
        if githubTokenClassic.isEmpty && githubTokenFineGrained.isEmpty {
            githubTokenFineGrained = legacyToken
        }
        aiProfile = try container.decodeIfPresent(AIProfile.self, forKey: .aiProfile) ?? .default
        aiAPIKey = try container.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case project
        case themeConfig
        case remoteProfile
        case githubTokenClassic
        case githubTokenFineGrained
        case aiProfile
        case aiAPIKey
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case githubToken
    }
}

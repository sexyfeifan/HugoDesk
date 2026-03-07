import Foundation

enum FrontMatterFormat: String, CaseIterable, Codable, Identifiable {
    case toml = "TOML"
    case yaml = "YAML"
    case json = "JSON"

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    var openingDelimiter: String {
        switch self {
        case .toml:
            return "+++"
        case .yaml:
            return "---"
        case .json:
            return "{"
        }
    }
}

enum FrontMatterEditorMode: String, CaseIterable, Identifiable {
    case structured = "结构化"
    case raw = "原始"

    var id: String { rawValue }
}

enum ContentCreationMode: String, CaseIterable, Identifiable, Codable {
    case singleFile = "单文件"
    case leafBundle = "Leaf Bundle"
    case branchBundle = "Section Bundle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleFile:
            return "单文件"
        case .leafBundle:
            return "页面包（Leaf Bundle）"
        case .branchBundle:
            return "栏目包（Section Bundle）"
        }
    }

    var helpText: String {
        switch self {
        case .singleFile:
            return "适合普通文章，会生成单个 Markdown 文件。"
        case .leafBundle:
            return "适合文章和资源一起管理，会生成 index.md 与同目录资源。"
        case .branchBundle:
            return "适合栏目首页或文档目录，会生成 _index.md。"
        }
    }

    var fileNameHint: String {
        switch self {
        case .singleFile:
            return "hello-world.md"
        case .leafBundle:
            return "hello-world"
        case .branchBundle:
            return "docs-section"
        }
    }

    var createsBundle: Bool {
        switch self {
        case .singleFile:
            return false
        case .leafBundle, .branchBundle:
            return true
        }
    }
}

enum ImageStorageMode: String, CaseIterable, Identifiable {
    case automatic = "自动"
    case pageBundle = "页面资源"
    case staticUploads = "静态目录"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .automatic:
            return "根据当前内容类型自动判断页面资源或静态目录。"
        case .pageBundle:
            return "优先写入当前页面包，适合 Hugo 页面资源工作流。"
        case .staticUploads:
            return "统一写入 static/images/uploads，兼容旧项目。"
        }
    }
}

struct PageResourceItem: Identifiable, Hashable {
    let url: URL
    let relativePath: String
    let mediaKind: String

    var id: String { url.path }
}

enum SummaryHandlingMode: String, CaseIterable, Identifiable {
    case auto = "自动摘要"
    case frontMatter = "Front Matter 摘要"
    case manualDivider = "手动 more 标记"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "自动摘要"
        case .frontMatter:
            return "摘要字段优先"
        case .manualDivider:
            return "手动 more 标记"
        }
    }
}

struct MenuFrontMatter: Codable, Equatable {
    var menuName: String = ""
    var entryName: String = ""
    var identifier: String = ""
    var parent: String = ""
    var weight: Int = 0
    var pre: String = ""
    var post: String = ""

    var isEmpty: Bool {
        menuName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum BuildListMode: String, CaseIterable, Codable, Identifiable {
    case always = "always"
    case never = "never"
    case local = "local"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always:
            return "始终参与列表"
        case .never:
            return "不参与列表"
        case .local:
            return "仅本地构建时参与"
        }
    }
}

enum BuildRenderMode: String, CaseIterable, Codable, Identifiable {
    case always = "always"
    case never = "never"
    case link = "link"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always:
            return "始终渲染"
        case .never:
            return "不直接渲染"
        case .link:
            return "仅保留链接"
        }
    }
}

struct PostBuildOptions: Codable, Equatable {
    var list: BuildListMode = .always
    var render: BuildRenderMode = .always
    var publishResources: Bool = true

    var isDefault: Bool {
        list == .always && render == .always && publishResources
    }
}

struct HugoLanguageProfile: Identifiable, Codable, Equatable {
    var code: String
    var title: String
    var contentDir: String
    var weight: Int

    var id: String { code }
}

struct ShortcodeParameterHint: Identifiable, Hashable {
    let name: String
    let sampleValue: String
    let isPositional: Bool

    var id: String { name }
}

struct ShortcodeDefinition: Identifiable, Hashable {
    let name: String
    let sourcePath: String
    let isProjectLocal: Bool
    let parameterHints: [ShortcodeParameterHint]
    let summary: String

    var id: String { sourcePath }
}

struct PageReferenceCandidate: Identifiable, Hashable {
    let title: String
    let referencePath: String
    let filePath: String

    var id: String { filePath }
}

struct ReferenceDiagnostic: Identifiable, Hashable {
    let postTitle: String
    let filePath: String
    let reference: String
    let linePreview: String

    var id: String { filePath + "|" + reference + "|" + linePreview }
}

struct TranslationDiagnostic: Identifiable, Hashable {
    let translationKey: String
    let sourceTitle: String
    let sourceFilePath: String
    let existingLanguageCodes: [String]
    let existingLanguages: [String]
    let missingLanguageCodes: [String]
    let missingLanguages: [String]

    var id: String { translationKey + "|" + sourceFilePath }
}

struct MenuTreeEntry: Identifiable, Hashable {
    let menuName: String
    let identifier: String
    let title: String
    let parent: String
    let weight: Int
    let filePath: String

    var id: String { menuName + "|" + identifier + "|" + filePath }
}

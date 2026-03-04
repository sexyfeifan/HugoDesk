import Foundation

struct BlogProject: Codable {
    static let lastRootPathDefaultsKey = "hugodesk.lastProjectRootPath"

    var rootPath: String
    var hugoExecutable: String
    var contentSubpath: String
    var gitRemote: String
    var publishBranch: String

    static func bootstrap() -> BlogProject {
        if let cachedRoot = UserDefaults.standard.string(forKey: lastRootPathDefaultsKey),
           !cachedRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cachedURL = URL(fileURLWithPath: cachedRoot, isDirectory: true)
            let cachedConfig = cachedURL.appendingPathComponent("hugo.toml")
            if FileManager.default.fileExists(atPath: cachedConfig.path) {
                return BlogProject(rootPath: cachedURL.path, hugoExecutable: "hugo", contentSubpath: "content/post", gitRemote: "origin", publishBranch: "main")
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let direct = cwd.appendingPathComponent("hugo.toml")
        let parent = cwd.deletingLastPathComponent()
        let parentHugo = parent.appendingPathComponent("hugo.toml")

        if FileManager.default.fileExists(atPath: direct.path) {
            return BlogProject(rootPath: cwd.path, hugoExecutable: "hugo", contentSubpath: "content/post", gitRemote: "origin", publishBranch: "main")
        }

        if FileManager.default.fileExists(atPath: parentHugo.path) {
            return BlogProject(rootPath: parent.path, hugoExecutable: "hugo", contentSubpath: "content/post", gitRemote: "origin", publishBranch: "main")
        }

        return BlogProject(rootPath: cwd.path, hugoExecutable: "hugo", contentSubpath: "content/post", gitRemote: "origin", publishBranch: "main")
    }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    var contentURL: URL {
        rootURL.appendingPathComponent(contentSubpath, isDirectory: true)
    }

    var configURL: URL {
        rootURL.appendingPathComponent("hugo.toml")
    }

    var staticImagesURL: URL {
        rootURL.appendingPathComponent("static/images", isDirectory: true)
    }

    var localConfigBundleURL: URL {
        rootURL.appendingPathComponent(".hugodesk.local.json", isDirectory: false)
    }

    func renderedHTMLCandidates(for postFileURL: URL) -> [URL] {
        let standardizedPost = postFileURL.standardizedFileURL.path
        let standardizedContentRoot = contentURL.standardizedFileURL.path
        guard standardizedPost.hasPrefix(standardizedContentRoot) else {
            return []
        }

        var relative = String(standardizedPost.dropFirst(standardizedContentRoot.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        let noExtension = URL(fileURLWithPath: relative).deletingPathExtension().path
        let cleaned = noExtension.hasPrefix("/") ? String(noExtension.dropFirst()) : noExtension
        guard !cleaned.isEmpty else {
            return []
        }

        return [
            rootURL.appendingPathComponent("public", isDirectory: true)
                .appendingPathComponent(cleaned, isDirectory: true)
                .appendingPathComponent("index.html", isDirectory: false),
            rootURL.appendingPathComponent("public", isDirectory: true)
                .appendingPathComponent(cleaned + ".html", isDirectory: false)
        ]
    }
}

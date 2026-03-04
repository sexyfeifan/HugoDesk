import Foundation

struct BlogProject: Codable {
    static let lastRootPathDefaultsKey = "hugodesk.lastProjectRootPath"
    static let supportedConfigRelativePaths: [String] = [
        "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
        "config.toml", "config.yaml", "config.yml", "config.json",
        "config/_default/hugo.toml", "config/_default/hugo.yaml", "config/_default/hugo.yml", "config/_default/hugo.json",
        "config/_default/config.toml", "config/_default/config.yaml", "config/_default/config.yml", "config/_default/config.json"
    ]

    var rootPath: String
    var hugoExecutable: String
    var contentSubpath: String
    var gitRemote: String
    var publishBranch: String

    static func bootstrap() -> BlogProject {
        if let cachedRoot = UserDefaults.standard.string(forKey: lastRootPathDefaultsKey),
           !cachedRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cachedURL = URL(fileURLWithPath: cachedRoot, isDirectory: true)
            if hasSupportedConfig(in: cachedURL) {
                return BlogProject(
                    rootPath: cachedURL.path,
                    hugoExecutable: "hugo",
                    contentSubpath: preferredContentSubpath(in: cachedURL),
                    gitRemote: "origin",
                    publishBranch: "main"
                )
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let parent = cwd.deletingLastPathComponent()

        if hasSupportedConfig(in: cwd) {
            return BlogProject(
                rootPath: cwd.path,
                hugoExecutable: "hugo",
                contentSubpath: preferredContentSubpath(in: cwd),
                gitRemote: "origin",
                publishBranch: "main"
            )
        }

        if hasSupportedConfig(in: parent) {
            return BlogProject(
                rootPath: parent.path,
                hugoExecutable: "hugo",
                contentSubpath: preferredContentSubpath(in: parent),
                gitRemote: "origin",
                publishBranch: "main"
            )
        }

        return BlogProject(
            rootPath: cwd.path,
            hugoExecutable: "hugo",
            contentSubpath: preferredContentSubpath(in: cwd),
            gitRemote: "origin",
            publishBranch: "main"
        )
    }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    var contentURL: URL {
        rootURL.appendingPathComponent(contentSubpath, isDirectory: true)
    }

    var configURL: URL {
        if let relative = detectedConfigRelativePath {
            return rootURL.appendingPathComponent(relative, isDirectory: false)
        }
        return rootURL.appendingPathComponent("hugo.toml", isDirectory: false)
    }

    var detectedConfigRelativePath: String? {
        let fm = FileManager.default
        for relative in Self.supportedConfigRelativePaths {
            var isDirectory = ObjCBool(false)
            let absolute = rootURL.appendingPathComponent(relative, isDirectory: false).path
            if fm.fileExists(atPath: absolute, isDirectory: &isDirectory), !isDirectory.boolValue {
                return relative
            }
        }
        return nil
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

    private static func hasSupportedConfig(in rootURL: URL) -> Bool {
        let fm = FileManager.default
        for relative in supportedConfigRelativePaths {
            var isDirectory = ObjCBool(false)
            let path = rootURL.appendingPathComponent(relative, isDirectory: false).path
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return true
            }
        }
        return false
    }

    private static func preferredContentSubpath(in rootURL: URL) -> String {
        let fm = FileManager.default
        let posts = rootURL.appendingPathComponent("content/posts", isDirectory: true).path
        var isDirectory = ObjCBool(false)
        if fm.fileExists(atPath: posts, isDirectory: &isDirectory), isDirectory.boolValue {
            return "content/posts"
        }

        let post = rootURL.appendingPathComponent("content/post", isDirectory: true).path
        isDirectory = ObjCBool(false)
        if fm.fileExists(atPath: post, isDirectory: &isDirectory), isDirectory.boolValue {
            return "content/post"
        }

        return "content/posts"
    }
}

import Foundation

final class ImageAssetService {
    private let fm = FileManager.default

    func importImage(from sourceURL: URL, project: BlogProject, subfolder: String) throws -> String {
        let targetDir = project.staticImagesURL.appendingPathComponent(subfolder, isDirectory: true)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let slug = slugify(base)
        let stamp = timestamp()
        let fileName = "\(stamp)-\(slug).\(ext)"
        let targetURL = uniqueFileURL(in: targetDir, preferredName: fileName)

        try fm.copyItem(at: sourceURL, to: targetURL)
        return "/images/\(subfolder)/\(targetURL.lastPathComponent)"
    }

    func importPageResource(from sourceURL: URL, for post: BlogPost, preferredSubfolder: String = "images") throws -> String {
        guard let bundleRoot = post.bundleRootURL else {
            throw NSError(domain: "HugoDesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前页面不是 bundle，不能导入页面资源。"])
        }

        let targetDir = bundleRoot.appendingPathComponent(preferredSubfolder, isDirectory: true)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let slug = slugify(base)
        let stamp = timestamp()
        let fileName = "\(stamp)-\(slug).\(ext)"
        let targetURL = uniqueFileURL(in: targetDir, preferredName: fileName)
        try fm.copyItem(at: sourceURL, to: targetURL)

        let relative = targetURL.path.replacingOccurrences(of: bundleRoot.path + "/", with: "")
        return relative
    }

    func listPageResources(for post: BlogPost) -> [PageResourceItem] {
        guard let bundleRoot = post.bundleRootURL else { return [] }
        let enumerator = fm.enumerator(at: bundleRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var resources: [PageResourceItem] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.path != post.fileURL.path else { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let relativePath = item.path.replacingOccurrences(of: bundleRoot.path + "/", with: "")
            resources.append(PageResourceItem(url: item, relativePath: relativePath, mediaKind: mediaKind(for: item)))
        }
        return resources.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    func movePageResource(_ item: PageResourceItem, to relativePath: String, for post: BlogPost) throws -> PageResourceItem {
        guard let bundleRoot = post.bundleRootURL else {
            throw NSError(domain: "HugoDesk", code: 2, userInfo: [NSLocalizedDescriptionKey: "当前页面不是 bundle，不能移动页面资源。"])
        }

        let cleaned = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else {
            throw NSError(domain: "HugoDesk", code: 3, userInfo: [NSLocalizedDescriptionKey: "目标资源路径不能为空。"])
        }

        let targetURL = bundleRoot.appendingPathComponent(cleaned)
        guard targetURL.standardizedFileURL.path != post.fileURL.standardizedFileURL.path else {
            throw NSError(domain: "HugoDesk", code: 4, userInfo: [NSLocalizedDescriptionKey: "不能覆盖当前正文文件。"])
        }

        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: targetURL.path) {
            throw NSError(domain: "HugoDesk", code: 5, userInfo: [NSLocalizedDescriptionKey: "目标路径已存在同名文件：\(cleaned)"])
        }

        try fm.moveItem(at: item.url, to: targetURL)
        return PageResourceItem(url: targetURL, relativePath: cleaned, mediaKind: mediaKind(for: targetURL))
    }

    func deletePageResource(_ item: PageResourceItem, for post: BlogPost) throws {
        guard post.usesPageBundle else {
            throw NSError(domain: "HugoDesk", code: 6, userInfo: [NSLocalizedDescriptionKey: "当前页面不是 bundle，不能删除页面资源。"])
        }
        guard fm.fileExists(atPath: item.url.path) else { return }
        try fm.removeItem(at: item.url)
    }

    func markdownSnippet(for item: PageResourceItem) -> String {
        let escapedTitle = item.url.deletingPathExtension().lastPathComponent
        switch item.mediaKind {
        case "图片":
            return "![\(escapedTitle)](\(item.relativePath))\n"
        default:
            return "[\(item.relativePath)](\(item.relativePath))\n"
        }
    }

    func normalizePostImageLinks(project: BlogProject) throws -> (changedFiles: Int, changedLinks: Int) {
        var changedFiles = 0
        var changedLinks = 0

        let enumerator = fm.enumerator(at: project.contentURL, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md" else { continue }
            let raw = try String(contentsOf: item, encoding: .utf8)
            let updated = try normalizeMarkdownImages(in: raw, for: item, project: project)
            if updated.changedCount > 0 {
                try updated.text.write(to: item, atomically: true, encoding: .utf8)
                changedFiles += 1
                changedLinks += updated.changedCount
            }
        }

        return (changedFiles, changedLinks)
    }

    private func normalizeMarkdownImages(in markdown: String, for fileURL: URL, project: BlogProject) throws -> (text: String, changedCount: Int) {
        let pattern = #"\!\[([^\]]*)\]\(([^)]+)\)"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let ns = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return (markdown, 0)
        }

        var result = markdown
        var changed = 0
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let alt = ns.substring(with: match.range(at: 1))
            let rawLink = ns.substring(with: match.range(at: 2))
            let cleanLink = rawLink.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))

            guard let localURL = resolveLocalImage(link: cleanLink, relativeTo: fileURL) else { continue }
            guard fm.fileExists(atPath: localURL.path) else { continue }

            let webPath = try importImage(from: localURL, project: project, subfolder: "uploads")
            let replacement = "![\(alt)](\(webPath))"
            let r = Range(match.range, in: result)!
            result.replaceSubrange(r, with: replacement)
            changed += 1
        }

        return (result, changed)
    }

    private func resolveLocalImage(link: String, relativeTo postURL: URL) -> URL? {
        let lower = link.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || lower.hasPrefix("/images/") {
            return nil
        }

        if lower.hasPrefix("file://"), let url = URL(string: link) {
            return url
        }

        if link.hasPrefix("~/") {
            let expanded = NSString(string: link).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }

        if link.hasPrefix("/") {
            return URL(fileURLWithPath: link)
        }

        return postURL.deletingLastPathComponent().appendingPathComponent(link)
    }

    private func uniqueFileURL(in dir: URL, preferredName: String) -> URL {
        var candidate = dir.appendingPathComponent(preferredName)
        var idx = 2
        while fm.fileExists(atPath: candidate.path) {
            let ext = candidate.pathExtension
            let base = candidate.deletingPathExtension().lastPathComponent
            let trimmedBase = base.replacingOccurrences(of: "-\(idx - 1)$", with: "", options: .regularExpression)
            let next = ext.isEmpty ? "\(trimmedBase)-\(idx)" : "\(trimmedBase)-\(idx).\(ext)"
            candidate = dir.appendingPathComponent(next)
            idx += 1
        }
        return candidate
    }

    private func slugify(_ source: String) -> String {
        let lower = source.lowercased()
        let out = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber {
                return ch
            }
            return "-"
        }
        let compact = String(out)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? "image" : compact
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func mediaKind(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "heic":
            return "图片"
        case "pdf":
            return "PDF"
        case "mp3", "wav", "m4a":
            return "音频"
        case "mp4", "mov", "webm":
            return "视频"
        default:
            return url.pathExtension.isEmpty ? "文件" : url.pathExtension.uppercased()
        }
    }
}

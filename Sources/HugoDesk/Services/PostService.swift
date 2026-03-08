import Foundation
import CoreFoundation

final class PostService {
    private let processRunner = ProcessRunner()

    func loadPosts(for project: BlogProject) throws -> [BlogPost] {
        let contentURL = project.contentURL
        try FileManager.default.createDirectory(at: contentURL, withIntermediateDirectories: true)

        let enumerator = FileManager.default.enumerator(
            at: contentURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }

        let posts = try files.map(loadPost)
        return posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.displayFileName.localizedStandardCompare(rhs.displayFileName) == .orderedAscending
            }
            return lhs.date > rhs.date
        }
    }

    func loadPost(at fileURL: URL) throws -> BlogPost {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let split = splitFrontMatter(from: raw)

        var post = BlogPost.empty(in: fileURL.deletingLastPathComponent())
        post.fileURL = fileURL
        post.body = split.body
        post.frontMatterFormat = split.format
        post.rawFrontMatter = split.frontMatter
        post.creationMode = detectCreationMode(for: fileURL)
        post.bundleRootURL = bundleRootURL(for: fileURL)
        post.pageResources = listPageResources(for: fileURL)

        applyFrontMatter(split.frontMatter, format: split.format, to: &post)
        return post
    }

    func availableArchetypes(for project: BlogProject) -> [String] {
        let fm = FileManager.default
        let url = project.archetypesURL
        guard fm.fileExists(atPath: url.path) else { return [] }

        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var kinds = Set<String>()
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md" else { continue }
            let relative = item.path.replacingOccurrences(of: url.path + "/", with: "")
            let kind = URL(fileURLWithPath: relative).deletingPathExtension().path
            if !kind.isEmpty {
                kinds.insert(kind)
            }
        }
        return kinds.sorted()
    }

    func suggestFileName(from title: String) -> String {
        "\(slugify(title.isEmpty ? "new-post" : title)).md"
    }

    func suggestTitle(fromFileName fileName: String) -> String {
        let base = fileName
            .replacingOccurrences(of: ".md", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "未命名文章"
        }
        return base
    }

    func suggestSummary(fromMarkdown markdown: String, maxLength: Int = 140) -> String {
        if let explicit = explicitSummaryMarkerSummary(from: markdown), !explicit.isEmpty {
            return explicit
        }

        let noCode = markdown.replacingOccurrences(
            of: #"```[\s\S]*?```"#,
            with: " ",
            options: .regularExpression
        )
        let noImages = noCode.replacingOccurrences(
            of: #"\!\[[^\]]*\]\([^)]+\)"#,
            with: " ",
            options: .regularExpression
        )
        let noLinks = noImages.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        let stripped = noLinks
            .replacingOccurrences(of: #"(^|\n)\s{0,3}#{1,6}\s*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[>*_`~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n\n", options: .regularExpression)

        let paragraphs = stripped
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = paragraphs.first ?? stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty {
            return ""
        }

        if source.count <= maxLength {
            return source
        }
        return String(source.prefix(maxLength)) + "..."
    }

    func summaryMode(for post: BlogPost) -> SummaryHandlingMode {
        if post.body.contains("<!--more-->") {
            return .manualDivider
        }
        if !post.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .frontMatter
        }
        return .auto
    }

    func ensureSummaryDivider(in body: String) -> String {
        if body.contains("<!--more-->") {
            return body
        }
        if body.isEmpty {
            return "<!--more-->\n"
        }
        if body.hasSuffix("\n") {
            return body + "<!--more-->\n"
        }
        return body + "\n\n<!--more-->\n"
    }

    func createNewPost(
        title: String,
        fileName: String?,
        in project: BlogProject,
        sectionPath: String,
        creationMode: ContentCreationMode,
        frontMatterFormat: FrontMatterFormat,
        archetypeKind: String?
    ) -> BlogPost {
        if let created = tryCreateWithArchetype(
            title: title,
            fileName: fileName,
            in: project,
            sectionPath: sectionPath,
            creationMode: creationMode,
            archetypeKind: archetypeKind
        ), let loaded = try? loadPost(at: created) {
            var post = loaded
            if post.title.isEmpty {
                post.title = title
            }
            post.frontMatterFormat = frontMatterFormat
            if post.rawFrontMatter.isEmpty {
                post.rawFrontMatter = renderFrontMatter(for: post)
            }
            return post
        }

        let desiredStem = sanitizeFileStem(fileName ?? "", fallbackTitle: title)
        let targetDir = project.contentURL(forSectionPath: sectionPath)
        let target = uniqueFileURL(in: targetDir, baseName: desiredStem, creationMode: creationMode)
        var post = BlogPost.empty(in: targetDir)
        post.fileURL = target
        post.title = title
        post.date = Date()
        post.draft = true
        post.frontMatterFormat = frontMatterFormat
        post.creationMode = creationMode
        post.bundleRootURL = bundleRootURL(for: target)
        post.rawFrontMatter = renderFrontMatter(for: post)
        return post
    }

    func previewNewPost(
        title: String,
        fileName: String?,
        in project: BlogProject,
        sectionPath: String,
        creationMode: ContentCreationMode,
        frontMatterFormat: FrontMatterFormat
    ) -> BlogPost {
        let desiredStem = sanitizeFileStem(fileName ?? "", fallbackTitle: title)
        let targetDir = project.contentURL(forSectionPath: sectionPath)
        let target = uniqueFileURL(in: targetDir, baseName: desiredStem, creationMode: creationMode)
        var post = BlogPost.empty(in: targetDir)
        post.fileURL = target
        post.title = title
        post.date = Date()
        post.draft = true
        post.frontMatterFormat = frontMatterFormat
        post.creationMode = creationMode
        post.bundleRootURL = bundleRootURL(for: target)
        post.rawFrontMatter = renderFrontMatter(for: post)
        return post
    }

    func savePost(_ post: BlogPost, preferRawFrontMatter: Bool = false) throws {
        try FileManager.default.createDirectory(at: post.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = renderPost(post, preferRawFrontMatter: preferRawFrontMatter)
        try raw.write(to: post.fileURL, atomically: true, encoding: .utf8)
    }

    func deletePost(at fileURL: URL) throws {
        let fm = FileManager.default
        if ["index.md", "_index.md"].contains(fileURL.lastPathComponent) {
            let bundleRoot = fileURL.deletingLastPathComponent()
            if fm.fileExists(atPath: bundleRoot.path) {
                try fm.removeItem(at: bundleRoot)
                return
            }
        }
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }

    func applyRawFrontMatter(_ rawFrontMatter: String, format: FrontMatterFormat, to post: inout BlogPost) {
        post.frontMatterFormat = format
        post.rawFrontMatter = rawFrontMatter
        resetStructuredFields(on: &post)
        applyFrontMatter(rawFrontMatter, format: format, to: &post)
    }

    func renderFrontMatter(for post: BlogPost) -> String {
        switch post.frontMatterFormat {
        case .toml:
            return renderTOMLFrontMatter(for: post)
        case .yaml:
            return renderYAMLFrontMatter(for: post)
        case .json:
            return renderJSONFrontMatter(for: post)
        }
    }

    private func renderPost(_ post: BlogPost, preferRawFrontMatter: Bool) -> String {
        let frontMatter = preferRawFrontMatter
            ? post.rawFrontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
            : renderFrontMatter(for: post)

        switch post.frontMatterFormat {
        case .toml:
            return renderDelimitedPost(frontMatter: frontMatter, delimiter: "+++", body: post.body)
        case .yaml:
            return renderDelimitedPost(frontMatter: frontMatter, delimiter: "---", body: post.body)
        case .json:
            let trimmed = frontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = post.body.hasPrefix("\n") ? String(post.body.dropFirst()) : post.body
            return trimmed + "\n\n" + body + (body.hasSuffix("\n") ? "" : "\n")
        }
    }

    private func renderDelimitedPost(frontMatter: String, delimiter: String, body: String) -> String {
        var lines: [String] = []
        lines.append(delimiter)
        if !frontMatter.isEmpty {
            lines.append(frontMatter)
        }
        lines.append(delimiter)
        lines.append("")
        lines.append(body)
        if !body.hasSuffix("\n") {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func splitFrontMatter(from raw: String) -> (format: FrontMatterFormat, frontMatter: String, body: String) {
        if let value = splitDelimitedFrontMatter(from: raw, delimiter: "+++", format: .toml) {
            return value
        }
        if let value = splitDelimitedFrontMatter(from: raw, delimiter: "---", format: .yaml) {
            return value
        }
        if let value = splitJSONFrontMatter(from: raw) {
            return value
        }
        return (.toml, "", raw)
    }

    private func splitDelimitedFrontMatter(from raw: String, delimiter: String, format: FrontMatterFormat) -> (format: FrontMatterFormat, frontMatter: String, body: String)? {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == delimiter else {
            return nil
        }

        var endIndex: Int?
        for idx in 1..<lines.count where lines[idx].trimmingCharacters(in: .whitespaces) == delimiter {
            endIndex = idx
            break
        }
        guard let end = endIndex else { return nil }
        let front = lines[1..<end].joined(separator: "\n")
        let body = end + 1 < lines.count ? lines[(end + 1)...].joined(separator: "\n") : ""
        return (format, front, body)
    }

    private func splitJSONFrontMatter(from raw: String) -> (format: FrontMatterFormat, frontMatter: String, body: String)? {
        let trimmed = raw.trimmingCharacters(in: .newlines)
        guard trimmed.first == "{" else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        for (offset, ch) in raw.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            if ch == "\"" {
                inString = true
                continue
            }
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let end = raw.index(raw.startIndex, offsetBy: offset)
                    let front = String(raw[raw.startIndex...end])
                    let bodyStart = raw.index(after: end)
                    let body = bodyStart < raw.endIndex ? String(raw[bodyStart...]).trimmingCharacters(in: .newlines) : ""
                    return (.json, front, body)
                }
            }
        }
        return nil
    }

    private func applyFrontMatter(_ frontMatter: String, format: FrontMatterFormat, to post: inout BlogPost) {
        switch format {
        case .toml:
            let entries = parseTOMLFrontMatter(frontMatter)
            assign(entries: entries, to: &post)
        case .yaml:
            let entries = parseYAMLFrontMatter(frontMatter)
            assign(entries: entries, to: &post)
        case .json:
            let entries = parseJSONFrontMatter(frontMatter)
            assign(entries: entries, to: &post)
        }
    }

    private func assign(entries: [String: Any], to post: inout BlogPost) {
        if let title = stringValue(entries["title"]) { post.title = title }
        if let dateText = stringValue(entries["date"]), let date = parseDate(dateText) { post.date = date }
        if let draft = boolValue(entries["draft"]) { post.draft = draft }
        if let summary = stringValue(entries["summary"]) { post.summary = summary }
        if let tags = stringArrayValue(entries["tags"]) { post.tags = tags }
        if let categories = stringArrayValue(entries["categories"]) { post.categories = categories }
        if let pin = boolValue(entries["pin"]) { post.pin = pin }
        if let math = boolValue(entries["math"]) { post.math = math }
        if let mathJax = boolValue(entries["MathJax"] ?? entries["mathJax"]) { post.mathJax = mathJax }
        if let value = boolValue(entries["private"]) { post.isPrivate = value }
        if let value = boolValue(entries["searchable"]) { post.searchable = value }
        if let cover = stringValue(entries["cover"]) { post.cover = cover }
        if let author = stringValue(entries["author"] ?? entries["Author"]) { post.author = author }
        if let keywords = stringArrayValue(entries["keywords"] ?? entries["Keywords"]) { post.keywords = keywords }
        if let slug = stringValue(entries["slug"]) { post.slug = slug }
        if let url = stringValue(entries["url"]) { post.urlPath = url }
        if let aliases = stringArrayValue(entries["aliases"]) { post.aliases = aliases }
        if let translationKey = stringValue(entries["translationKey"]) { post.translationKey = translationKey }
        if let menu = stringValue(entries["menu"]) {
            post.menuEntry.menuName = menu
        }
        if let build = entries["build"] as? [String: Any] {
            if let list = stringValue(build["list"]), let mode = BuildListMode(rawValue: list) {
                post.buildOptions.list = mode
            }
            if let render = stringValue(build["render"]), let mode = BuildRenderMode(rawValue: render) {
                post.buildOptions.render = mode
            }
            if let publishResources = boolValue(build["publishResources"]) {
                post.buildOptions.publishResources = publishResources
            }
        }
        if let cascade = entries["cascade"] as? [String: Any],
           let build = cascade["build"] as? [String: Any] {
            var options = PostBuildOptions()
            var touched = false
            if let list = stringValue(build["list"]), let mode = BuildListMode(rawValue: list) {
                options.list = mode
                touched = true
            }
            if let render = stringValue(build["render"]), let mode = BuildRenderMode(rawValue: render) {
                options.render = mode
                touched = true
            }
            if let publishResources = boolValue(build["publishResources"]) {
                options.publishResources = publishResources
                touched = true
            }
            post.cascadeBuildOptions = touched ? options : nil
        }
        if let menus = entries["menus"] as? [String: Any],
           let first = menus.sorted(by: { $0.key < $1.key }).first,
           let menuEntries = first.value as? [String: Any] {
            post.menuEntry.menuName = first.key
            post.menuEntry.entryName = stringValue(menuEntries["name"]) ?? ""
            post.menuEntry.identifier = stringValue(menuEntries["identifier"]) ?? ""
            post.menuEntry.parent = stringValue(menuEntries["parent"]) ?? ""
            post.menuEntry.pre = stringValue(menuEntries["pre"]) ?? ""
            post.menuEntry.post = stringValue(menuEntries["post"]) ?? ""
            if let weight = menuEntries["weight"] as? Int {
                post.menuEntry.weight = weight
            } else if let weightText = stringValue(menuEntries["weight"]) {
                post.menuEntry.weight = Int(weightText) ?? 0
            }
        }

        for (key, value) in entries where key.hasSuffix("_weight") {
            let taxonomyKey = String(key.dropLast("_weight".count))
            if let weight = intValue(value) {
                post.taxonomyWeights[taxonomyKey] = weight
            }
        }

        let reservedKeys: Set<String> = [
            "title", "date", "draft", "summary", "tags", "categories", "pin", "math",
            "MathJax", "mathJax", "private", "searchable", "cover", "author", "Author",
            "keywords", "Keywords", "slug", "url", "aliases", "translationKey", "menu",
            "menus", "build", "cascade"
        ]
        for (key, value) in entries where !reservedKeys.contains(key) {
            guard !key.hasSuffix("_weight") else { continue }
            if let terms = stringArrayValue(value), !terms.isEmpty {
                post.customTaxonomies[key] = terms
            } else if let term = stringValue(value), !term.isEmpty {
                post.customTaxonomies[key] = [term]
            }
        }
    }

    private func resetStructuredFields(on post: inout BlogPost) {
        post.title = ""
        post.date = Date()
        post.draft = true
        post.summary = ""
        post.tags = []
        post.categories = []
        post.pin = false
        post.math = false
        post.mathJax = false
        post.isPrivate = false
        post.searchable = true
        post.cover = ""
        post.author = ""
        post.keywords = []
        post.customTaxonomies = [:]
        post.taxonomyWeights = [:]
        post.slug = ""
        post.urlPath = ""
        post.aliases = []
        post.translationKey = ""
        post.menuEntry = MenuFrontMatter()
        post.buildOptions = PostBuildOptions()
        post.cascadeBuildOptions = nil
    }

    private func parseTOMLFrontMatter(_ raw: String) -> [String: Any] {
        var entries: [String: Any] = [:]
        var currentSection = ""
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard let idx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            let parsed = parseScalarOrArray(value)
            if currentSection == "build" {
                var build = entries["build"] as? [String: Any] ?? [:]
                build[key] = parsed
                entries["build"] = build
            } else if currentSection == "cascade.build" {
                var cascade = entries["cascade"] as? [String: Any] ?? [:]
                var build = cascade["build"] as? [String: Any] ?? [:]
                build[key] = parsed
                cascade["build"] = build
                entries["cascade"] = cascade
            } else if currentSection.hasPrefix("menus.") {
                let menuName = String(currentSection.dropFirst("menus.".count))
                var menus = entries["menus"] as? [String: Any] ?? [:]
                var menu = menus[menuName] as? [String: Any] ?? [:]
                menu[key] = parsed
                menus[menuName] = menu
                entries["menus"] = menus
            } else {
                entries[key] = parsed
            }
        }
        return entries
    }

    private func parseYAMLFrontMatter(_ raw: String) -> [String: Any] {
        var entries: [String: Any] = [:]
        var activeArrayKey: String?
        var currentSection = ""
        var currentMenuName = ""
        for line in raw.components(separatedBy: .newlines) {
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let key = activeArrayKey, trimmed.hasPrefix("- ") {
                var current = entries[key] as? [String] ?? []
                current.append(parseString(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                entries[key] = current
                continue
            }
            activeArrayKey = nil
            guard let idx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if indent == 0 {
                currentSection = ""
                currentMenuName = ""
                if value.isEmpty, key == "build" {
                    currentSection = "build"
                    entries["build"] = entries["build"] ?? [String: Any]()
                    continue
                }
                if value.isEmpty, key == "cascade" {
                    currentSection = "cascade"
                    entries["cascade"] = entries["cascade"] ?? [String: Any]()
                    continue
                }
                if value.isEmpty, key == "menus" {
                    currentSection = "menus"
                    entries["menus"] = entries["menus"] ?? [String: Any]()
                    continue
                }
            } else if indent == 2 && currentSection == "menus" && value.isEmpty {
                currentMenuName = key
                var menus = entries["menus"] as? [String: Any] ?? [:]
                menus[currentMenuName] = menus[currentMenuName] ?? [String: Any]()
                entries["menus"] = menus
                continue
            } else if indent == 2 && currentSection == "cascade" && value.isEmpty && key == "build" {
                currentSection = "cascade.build"
                var cascade = entries["cascade"] as? [String: Any] ?? [:]
                cascade["build"] = cascade["build"] ?? [String: Any]()
                entries["cascade"] = cascade
                continue
            }
            if value.isEmpty {
                activeArrayKey = key
                entries[key] = [String]()
            } else {
                let parsed = parseScalarOrArray(value)
                if currentSection == "build" && indent == 2 {
                    var build = entries["build"] as? [String: Any] ?? [:]
                    build[key] = parsed
                    entries["build"] = build
                } else if currentSection == "cascade.build" && indent == 4 {
                    var cascade = entries["cascade"] as? [String: Any] ?? [:]
                    var build = cascade["build"] as? [String: Any] ?? [:]
                    build[key] = parsed
                    cascade["build"] = build
                    entries["cascade"] = cascade
                } else if currentSection == "menus" && indent == 4 && !currentMenuName.isEmpty {
                    var menus = entries["menus"] as? [String: Any] ?? [:]
                    var menu = menus[currentMenuName] as? [String: Any] ?? [:]
                    menu[key] = parsed
                    menus[currentMenuName] = menu
                    entries["menus"] = menus
                } else {
                    entries[key] = parsed
                }
            }
        }
        return entries
    }

    private func parseJSONFrontMatter(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func parseScalarOrArray(_ raw: String) -> Any {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return parseArray(trimmed)
        }
        if trimmed.lowercased() == "true" || trimmed.lowercased() == "false" {
            return parseBool(trimmed)
        }
        return parseString(trimmed)
    }

    private func renderTOMLFrontMatter(for post: BlogPost) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines: [String] = []
        lines.append("title = \(encode(post.title))")
        lines.append("date = \(encode(formatter.string(from: post.date)))")
        lines.append("draft = \(post.draft ? "true" : "false")")
        appendOptionalString(post.summary, key: "summary", to: &lines)
        appendOptionalArray(post.tags, key: "tags", to: &lines)
        appendOptionalArray(post.categories, key: "categories", to: &lines)
        appendOptionalBool(post.pin, key: "pin", to: &lines)
        appendOptionalBool(post.math, key: "math", to: &lines)
        appendOptionalBool(post.mathJax, key: "MathJax", to: &lines)
        appendOptionalBool(post.isPrivate, key: "private", to: &lines)
        if !post.searchable { lines.append("searchable = false") }
        appendOptionalString(post.cover, key: "cover", to: &lines)
        appendOptionalString(post.author, key: "author", to: &lines)
        appendOptionalArray(post.keywords, key: "keywords", to: &lines)
        for key in post.customTaxonomies.keys.sorted() {
            appendOptionalArray(post.customTaxonomies[key] ?? [], key: key, to: &lines)
            if let weight = post.taxonomyWeights[key], weight != 0 {
                lines.append("\(key)_weight = \(weight)")
            }
        }
        if let tagsWeight = post.taxonomyWeights["tags"], !post.tags.isEmpty, tagsWeight != 0 {
            lines.append("tags_weight = \(tagsWeight)")
        }
        if let categoriesWeight = post.taxonomyWeights["categories"], !post.categories.isEmpty, categoriesWeight != 0 {
            lines.append("categories_weight = \(categoriesWeight)")
        }
        appendOptionalString(post.slug, key: "slug", to: &lines)
        appendOptionalString(post.urlPath, key: "url", to: &lines)
        appendOptionalArray(post.aliases, key: "aliases", to: &lines)
        appendOptionalString(post.translationKey, key: "translationKey", to: &lines)
        if !post.menuEntry.isEmpty {
            lines.append("")
            lines.append("[menus.\(post.menuEntry.menuName)]")
            appendOptionalString(post.menuEntry.entryName, key: "name", to: &lines)
            appendOptionalString(post.menuEntry.identifier, key: "identifier", to: &lines)
            appendOptionalString(post.menuEntry.parent, key: "parent", to: &lines)
            if post.menuEntry.weight != 0 {
                lines.append("weight = \(post.menuEntry.weight)")
            }
            appendOptionalString(post.menuEntry.pre, key: "pre", to: &lines)
            appendOptionalString(post.menuEntry.post, key: "post", to: &lines)
        }
        if !post.buildOptions.isDefault {
            lines.append("")
            lines.append("[build]")
            lines.append("list = \(encode(post.buildOptions.list.rawValue))")
            lines.append("render = \(encode(post.buildOptions.render.rawValue))")
            lines.append("publishResources = \(post.buildOptions.publishResources ? "true" : "false")")
        }
        if let cascade = post.cascadeBuildOptions {
            lines.append("")
            lines.append("[cascade.build]")
            lines.append("list = \(encode(cascade.list.rawValue))")
            lines.append("render = \(encode(cascade.render.rawValue))")
            lines.append("publishResources = \(cascade.publishResources ? "true" : "false")")
        }
        return lines.joined(separator: "\n")
    }

    private func renderYAMLFrontMatter(for post: BlogPost) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines: [String] = []
        lines.append("title: \(encodeYAML(post.title))")
        lines.append("date: \(encodeYAML(formatter.string(from: post.date)))")
        lines.append("draft: \(post.draft ? "true" : "false")")
        appendOptionalYAMLString(post.summary, key: "summary", to: &lines)
        appendOptionalYAMLArray(post.tags, key: "tags", to: &lines)
        appendOptionalYAMLArray(post.categories, key: "categories", to: &lines)
        appendOptionalYAMLBool(post.pin, key: "pin", to: &lines)
        appendOptionalYAMLBool(post.math, key: "math", to: &lines)
        appendOptionalYAMLBool(post.mathJax, key: "MathJax", to: &lines)
        appendOptionalYAMLBool(post.isPrivate, key: "private", to: &lines)
        if !post.searchable { lines.append("searchable: false") }
        appendOptionalYAMLString(post.cover, key: "cover", to: &lines)
        appendOptionalYAMLString(post.author, key: "author", to: &lines)
        appendOptionalYAMLArray(post.keywords, key: "keywords", to: &lines)
        for key in post.customTaxonomies.keys.sorted() {
            appendOptionalYAMLArray(post.customTaxonomies[key] ?? [], key: key, to: &lines)
            if let weight = post.taxonomyWeights[key], weight != 0 {
                lines.append("\(key)_weight: \(weight)")
            }
        }
        if let tagsWeight = post.taxonomyWeights["tags"], !post.tags.isEmpty, tagsWeight != 0 {
            lines.append("tags_weight: \(tagsWeight)")
        }
        if let categoriesWeight = post.taxonomyWeights["categories"], !post.categories.isEmpty, categoriesWeight != 0 {
            lines.append("categories_weight: \(categoriesWeight)")
        }
        appendOptionalYAMLString(post.slug, key: "slug", to: &lines)
        appendOptionalYAMLString(post.urlPath, key: "url", to: &lines)
        appendOptionalYAMLArray(post.aliases, key: "aliases", to: &lines)
        appendOptionalYAMLString(post.translationKey, key: "translationKey", to: &lines)
        if !post.menuEntry.isEmpty {
            lines.append("menus:")
            lines.append("  \(post.menuEntry.menuName):")
            if !post.menuEntry.entryName.isEmpty { lines.append("    name: \(encodeYAML(post.menuEntry.entryName))") }
            if !post.menuEntry.identifier.isEmpty { lines.append("    identifier: \(encodeYAML(post.menuEntry.identifier))") }
            if !post.menuEntry.parent.isEmpty { lines.append("    parent: \(encodeYAML(post.menuEntry.parent))") }
            if post.menuEntry.weight != 0 { lines.append("    weight: \(post.menuEntry.weight)") }
            if !post.menuEntry.pre.isEmpty { lines.append("    pre: \(encodeYAML(post.menuEntry.pre))") }
            if !post.menuEntry.post.isEmpty { lines.append("    post: \(encodeYAML(post.menuEntry.post))") }
        }
        if !post.buildOptions.isDefault {
            lines.append("build:")
            lines.append("  list: \(encodeYAML(post.buildOptions.list.rawValue))")
            lines.append("  render: \(encodeYAML(post.buildOptions.render.rawValue))")
            lines.append("  publishResources: \(post.buildOptions.publishResources ? "true" : "false")")
        }
        if let cascade = post.cascadeBuildOptions {
            lines.append("cascade:")
            lines.append("  build:")
            lines.append("    list: \(encodeYAML(cascade.list.rawValue))")
            lines.append("    render: \(encodeYAML(cascade.render.rawValue))")
            lines.append("    publishResources: \(cascade.publishResources ? "true" : "false")")
        }
        return lines.joined(separator: "\n")
    }

    private func renderJSONFrontMatter(for post: BlogPost) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var dict: [String: Any] = [
            "title": post.title,
            "date": formatter.string(from: post.date),
            "draft": post.draft
        ]
        if !post.summary.isEmpty { dict["summary"] = post.summary }
        if !post.tags.isEmpty { dict["tags"] = post.tags }
        if !post.categories.isEmpty { dict["categories"] = post.categories }
        if post.pin { dict["pin"] = true }
        if post.math { dict["math"] = true }
        if post.mathJax { dict["MathJax"] = true }
        if post.isPrivate { dict["private"] = true }
        if !post.searchable { dict["searchable"] = false }
        if !post.cover.isEmpty { dict["cover"] = post.cover }
        if !post.author.isEmpty { dict["author"] = post.author }
        if !post.keywords.isEmpty { dict["keywords"] = post.keywords }
        if !post.customTaxonomies.isEmpty {
            for (key, value) in post.customTaxonomies where !value.isEmpty {
                dict[key] = value
                if let weight = post.taxonomyWeights[key], weight != 0 {
                    dict["\(key)_weight"] = weight
                }
            }
        }
        if let tagsWeight = post.taxonomyWeights["tags"], !post.tags.isEmpty, tagsWeight != 0 {
            dict["tags_weight"] = tagsWeight
        }
        if let categoriesWeight = post.taxonomyWeights["categories"], !post.categories.isEmpty, categoriesWeight != 0 {
            dict["categories_weight"] = categoriesWeight
        }
        if !post.slug.isEmpty { dict["slug"] = post.slug }
        if !post.urlPath.isEmpty { dict["url"] = post.urlPath }
        if !post.aliases.isEmpty { dict["aliases"] = post.aliases }
        if !post.translationKey.isEmpty { dict["translationKey"] = post.translationKey }
        if !post.menuEntry.isEmpty {
            var menu: [String: Any] = [:]
            if !post.menuEntry.entryName.isEmpty { menu["name"] = post.menuEntry.entryName }
            if !post.menuEntry.identifier.isEmpty { menu["identifier"] = post.menuEntry.identifier }
            if !post.menuEntry.parent.isEmpty { menu["parent"] = post.menuEntry.parent }
            if post.menuEntry.weight != 0 { menu["weight"] = post.menuEntry.weight }
            if !post.menuEntry.pre.isEmpty { menu["pre"] = post.menuEntry.pre }
            if !post.menuEntry.post.isEmpty { menu["post"] = post.menuEntry.post }
            dict["menus"] = [post.menuEntry.menuName: menu]
        }
        if !post.buildOptions.isDefault {
            dict["build"] = [
                "list": post.buildOptions.list.rawValue,
                "render": post.buildOptions.render.rawValue,
                "publishResources": post.buildOptions.publishResources
            ]
        }
        if let cascade = post.cascadeBuildOptions {
            dict["cascade"] = [
                "build": [
                    "list": cascade.list.rawValue,
                    "render": cascade.render.rawValue,
                    "publishResources": cascade.publishResources
                ]
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func appendOptionalString(_ value: String, key: String, to lines: inout [String]) {
        guard !value.isEmpty else { return }
        lines.append("\(key) = \(encode(value))")
    }

    private func appendOptionalArray(_ value: [String], key: String, to lines: inout [String]) {
        guard !value.isEmpty else { return }
        lines.append("\(key) = \(encodeArray(value))")
    }

    private func appendOptionalBool(_ value: Bool, key: String, to lines: inout [String]) {
        guard value else { return }
        lines.append("\(key) = true")
    }

    private func appendOptionalYAMLString(_ value: String, key: String, to lines: inout [String]) {
        guard !value.isEmpty else { return }
        lines.append("\(key): \(encodeYAML(value))")
    }

    private func appendOptionalYAMLArray(_ value: [String], key: String, to lines: inout [String]) {
        guard !value.isEmpty else { return }
        lines.append("\(key):")
        for item in value {
            lines.append("  - \(encodeYAML(item))")
        }
    }

    private func appendOptionalYAMLBool(_ value: Bool, key: String, to lines: inout [String]) {
        guard value else { return }
        lines.append("\(key): true")
    }

    private func explicitSummaryMarkerSummary(from markdown: String) -> String? {
        let parts = markdown.components(separatedBy: "<!--more-->")
        guard parts.count > 1 else { return nil }
        return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ raw: String) -> Date? {
        let text = parseString(raw)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: text) {
            return value
        }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return iso2.date(from: text)
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let string = value as? String {
            return parseBool(string)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String {
            return Int(parseString(string))
        }
        return nil
    }

    private func stringArrayValue(_ value: Any?) -> [String]? {
        if let array = value as? [String] { return array }
        if let array = value as? [Any] { return array.compactMap { $0 as? String } }
        if let string = value as? String {
            let parsed = parseArray(string)
            return parsed.isEmpty ? nil : parsed
        }
        return nil
    }

    private func parseString(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var wasQuoted = false
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            wasQuoted = true
        } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        if wasQuoted {
            value = decodeEscapes(value)
        }
        return value
    }

    private func decodeEscapes(_ text: String) -> String {
        var result = ""
        var escaping = false
        for ch in text {
            if escaping {
                switch ch {
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                default:
                    result.append(ch)
                }
                escaping = false
                continue
            }
            if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping {
            result.append("\\")
        }
        return result
    }

    private func parseBool(_ raw: String) -> Bool {
        parseString(raw).lowercased() == "true"
    }

    private func parseArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
            let single = parseString(trimmed)
            return single.isEmpty ? [] : [single]
        }
        let content = String(trimmed.dropFirst().dropLast())
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return content.split(separator: ",")
            .map { parseString(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func encode(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func encodeArray(_ values: [String]) -> String {
        "[" + values.map { encode($0) }.joined(separator: ", ") + "]"
    }

    private func encodeYAML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func sanitizeFileStem(_ raw: String, fallbackTitle: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noExt = trimmed.hasSuffix(".md") ? String(trimmed.dropLast(3)) : trimmed
        let base = noExt.isEmpty ? slugify(fallbackTitle.isEmpty ? "new-post" : fallbackTitle) : slugify(noExt)
        return base.isEmpty ? "post-\(Int(Date().timeIntervalSince1970))" : base
    }

    private func uniqueFileURL(in dir: URL, baseName: String, creationMode: ContentCreationMode) -> URL {
        let fm = FileManager.default
        switch creationMode {
        case .singleFile:
            var attempt = 1
            var candidate = dir.appendingPathComponent("\(baseName).md")
            while fm.fileExists(atPath: candidate.path) {
                attempt += 1
                candidate = dir.appendingPathComponent("\(baseName)-\(attempt).md")
            }
            return candidate
        case .leafBundle, .branchBundle:
            var attempt = 1
            var folderName = baseName
            var folderURL = dir.appendingPathComponent(folderName, isDirectory: true)
            while fm.fileExists(atPath: folderURL.path) {
                attempt += 1
                folderName = "\(baseName)-\(attempt)"
                folderURL = dir.appendingPathComponent(folderName, isDirectory: true)
            }
            let leafName = creationMode == .leafBundle ? "index.md" : "_index.md"
            return folderURL.appendingPathComponent(leafName, isDirectory: false)
        }
    }

    private func slugify(_ source: String) -> String {
        let pinyin = toPinyin(source)
        let lower = pinyin.lowercased()
        let filtered = lower.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "-"
        }
        let compact = String(filtered)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? "post-\(Int(Date().timeIntervalSince1970))" : compact
    }

    private func toPinyin(_ source: String) -> String {
        let mutable = NSMutableString(string: source) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return mutable as String
    }

    private func detectCreationMode(for fileURL: URL) -> ContentCreationMode {
        switch fileURL.lastPathComponent {
        case "index.md":
            return .leafBundle
        case "_index.md":
            return .branchBundle
        default:
            return .singleFile
        }
    }

    private func bundleRootURL(for fileURL: URL) -> URL? {
        switch detectCreationMode(for: fileURL) {
        case .singleFile:
            return nil
        case .leafBundle, .branchBundle:
            return fileURL.deletingLastPathComponent()
        }
    }

    private func listPageResources(for fileURL: URL) -> [PageResourceItem] {
        guard let bundleRoot = bundleRootURL(for: fileURL) else { return [] }
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: bundleRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var resources: [PageResourceItem] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.path != fileURL.path else { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let relativePath = item.path.replacingOccurrences(of: bundleRoot.path + "/", with: "")
            resources.append(PageResourceItem(url: item, relativePath: relativePath, mediaKind: mediaKind(for: item)))
        }
        return resources.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func mediaKind(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "svg":
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

    private func tryCreateWithArchetype(
        title: String,
        fileName: String?,
        in project: BlogProject,
        sectionPath: String,
        creationMode: ContentCreationMode,
        archetypeKind: String?
    ) -> URL? {
        let kind = archetypeKind?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !kind.isEmpty else { return nil }

        let desiredStem = sanitizeFileStem(fileName ?? "", fallbackTitle: title)
        let relativePrefix = normalizedRelativePrefix(sectionPath)
        let relativePath: String
        switch creationMode {
        case .singleFile:
            relativePath = relativePrefix + desiredStem + ".md"
        case .leafBundle:
            relativePath = relativePrefix + desiredStem + "/index.md"
        case .branchBundle:
            relativePath = relativePrefix + desiredStem + "/_index.md"
        }

        do {
            _ = try processRunner.run(
                command: project.hugoExecutable,
                arguments: ["new", "content", "--kind", kind, relativePath],
                in: project.rootURL
            )
            return project.contentURL.appendingPathComponent(relativePath)
        } catch {
            return nil
        }
    }

    private func normalizedRelativePrefix(_ sectionPath: String) -> String {
        let trimmed = sectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "" }
        return trimmed + "/"
    }
}

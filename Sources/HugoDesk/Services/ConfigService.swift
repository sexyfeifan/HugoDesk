import Foundation

final class ConfigService {
    func loadConfig(for project: BlogProject) throws -> ThemeConfig {
        let fileURL = project.configURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ThemeConfig()
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var config = ThemeConfig()
        var section = ""
        var linkIndex: Int?

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                let name = String(trimmed.dropFirst(2).dropLast(2))
                section = name
                if name == "params.links" {
                    config.params.links.append(ThemeLink())
                    linkIndex = config.params.links.count - 1
                }
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                linkIndex = nil
                continue
            }

            guard let (key, valueRaw) = splitKeyValue(trimmed) else {
                continue
            }

            let value = stripInlineComment(valueRaw).trimmingCharacters(in: .whitespaces)

            switch section {
            case "":
                switch key {
                case "baseURL": config.baseURL = parseString(value)
                case "languageCode": config.languageCode = parseString(value)
                case "title": config.title = parseString(value)
                case "theme": config.theme = parseString(value)
                case "pygmentsCodeFences": config.pygmentsCodeFences = parseBool(value)
                case "pygmentsUseClasses": config.pygmentsUseClasses = parseBool(value)
                default: break
                }

            case "params":
                applyParam(key: key, value: value, to: &config)

            case "params.gitalk":
                applyGitalkParam(key: key, value: value, to: &config)

            case "params.links":
                if let idx = linkIndex {
                    switch key {
                    case "title": config.params.links[idx].title = parseString(value)
                    case "href": config.params.links[idx].href = parseString(value)
                    case "icon": config.params.links[idx].icon = parseString(value)
                    default: break
                    }
                }

            case "frontmatter":
                if key == "lastmod" {
                    let normalized = value.replacingOccurrences(of: " ", with: "").lowercased()
                    config.frontmatterTrackLastmod = normalized.contains(":filemodtime")
                }

            case "services.googleAnalytics":
                if key == "ID" {
                    config.googleAnalyticsID = parseString(value)
                }

            case "outputs":
                if key == "home" {
                    config.outputsHome = parseStringArray(value)
                }

            case "outputFormats.json":
                switch key {
                case "mediaType": config.outputFormatJSONMediaType = parseString(value)
                case "baseName": config.outputFormatJSONBaseName = parseString(value)
                case "isPlainText": config.outputFormatJSONIsPlainText = parseBool(value)
                default: break
                }

            default:
                break
            }
        }

        return config
    }

    func saveConfig(_ config: ThemeConfig, for project: BlogProject) throws {
        let fileURL = project.configURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let output = buildManagedConfigLines(config).joined(separator: "\n") + "\n"
            try output.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let existing = try String(contentsOf: fileURL, encoding: .utf8)
        var editor = ConfigLineEditor(raw: existing)
        applyManagedConfig(config, to: &editor)
        let output = editor.rendered()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func applyManagedConfig(_ config: ThemeConfig, to editor: inout ConfigLineEditor) {
        editor.set(
            key: "baseURL",
            value: encodeString(config.baseURL),
            section: nil
        )
        editor.set(
            key: "languageCode",
            value: encodeString(config.languageCode),
            section: nil
        )
        editor.set(
            key: "title",
            value: encodeString(config.title),
            section: nil
        )
        editor.set(
            key: "theme",
            value: encodeString(config.theme),
            section: nil
        )
        editor.set(
            key: "pygmentsCodeFences",
            value: config.pygmentsCodeFences ? "true" : "false",
            section: nil
        )
        editor.set(
            key: "pygmentsUseClasses",
            value: config.pygmentsUseClasses ? "true" : "false",
            section: nil
        )

        editor.set(key: "author", value: encodeString(config.params.author), section: "params")
        editor.set(key: "description", value: encodeString(config.params.description), section: "params", aliases: ["Description"])
        editor.set(key: "tagline", value: encodeString(config.params.tagline), section: "params")
        editor.set(key: "github", value: encodeString(config.params.github), section: "params")
        editor.set(key: "twitter", value: encodeString(config.params.twitter), section: "params")
        editor.set(key: "facebook", value: encodeString(config.params.facebook), section: "params")
        editor.set(key: "linkedin", value: encodeString(config.params.linkedin), section: "params")
        editor.set(key: "instagram", value: encodeString(config.params.instagram), section: "params")
        editor.set(key: "tumblr", value: encodeString(config.params.tumblr), section: "params")
        editor.set(key: "stackoverflow", value: encodeString(config.params.stackoverflow), section: "params")
        editor.set(key: "bluesky", value: encodeString(config.params.bluesky), section: "params")
        editor.set(key: "email", value: encodeString(config.params.email), section: "params", aliases: ["Email"])
        editor.set(key: "url", value: encodeString(config.params.url), section: "params")
        editor.set(key: "keywords", value: encodeString(config.params.keywords), section: "params", aliases: ["Keywords"])
        editor.set(key: "favicon", value: encodeString(config.params.favicon), section: "params")
        editor.set(key: "avatar", value: encodeString(config.params.avatar), section: "params")
        editor.set(key: "headerIcon", value: encodeString(config.params.headerIcon), section: "params")
        editor.set(key: "location", value: encodeString(config.params.location), section: "params")
        editor.set(key: "userStatusEmoji", value: encodeString(config.params.userStatusEmoji), section: "params")
        editor.set(key: "rss", value: config.params.rss ? "true" : "false", section: "params")
        editor.set(key: "lastmod", value: config.params.lastmod ? "true" : "false", section: "params")
        editor.set(key: "enableGitalk", value: config.params.enableGitalk ? "true" : "false", section: "params")
        editor.set(key: "enableSearch", value: config.params.enableSearch ? "true" : "false", section: "params")
        editor.set(key: "math", value: config.params.math ? "true" : "false", section: "params")
        editor.set(key: "MathJax", value: config.params.mathJax ? "true" : "false", section: "params", aliases: ["mathJax"])
        editor.set(key: "custom_css", value: encodeArray(config.params.customCSS), section: "params")
        editor.set(key: "custom_js", value: encodeArray(config.params.customJS), section: "params")

        editor.set(key: "clientID", value: encodeString(config.params.gitalk.clientID), section: "params.gitalk")
        editor.set(key: "clientSecret", value: encodeString(config.params.gitalk.clientSecret), section: "params.gitalk")
        editor.set(key: "repo", value: encodeString(config.params.gitalk.repo), section: "params.gitalk")
        editor.set(key: "owner", value: encodeString(config.params.gitalk.owner), section: "params.gitalk")
        editor.set(key: "admin", value: encodeString(config.params.gitalk.admin), section: "params.gitalk")
        editor.set(key: "id", value: encodeString(config.params.gitalk.id), section: "params.gitalk")
        editor.set(key: "labels", value: encodeString(config.params.gitalk.labels), section: "params.gitalk")
        editor.set(key: "perPage", value: String(config.params.gitalk.perPage), section: "params.gitalk")
        editor.set(key: "pagerDirection", value: encodeString(config.params.gitalk.pagerDirection), section: "params.gitalk")
        editor.set(key: "createIssueManually", value: config.params.gitalk.createIssueManually ? "true" : "false", section: "params.gitalk")
        editor.set(key: "distractionFreeMode", value: config.params.gitalk.distractionFreeMode ? "true" : "false", section: "params.gitalk")
        editor.set(key: "proxy", value: encodeString(config.params.gitalk.proxy), section: "params.gitalk")

        let linkBlocks = config.params.links.map { link in
            var rows: [String] = []
            rows.append("title = \(encodeString(link.title))")
            rows.append("href = \(encodeString(link.href))")
            if !link.icon.isEmpty {
                rows.append("icon = \(encodeString(link.icon))")
            }
            return rows
        }
        editor.replaceArrayTable(name: "params.links", blocks: linkBlocks, preferredAnchorSection: "params.gitalk")

        editor.set(
            key: "lastmod",
            value: config.frontmatterTrackLastmod
                ? "[\"lastmod\", \":fileModTime\", \":default\"]"
                : "[\":default\"]",
            section: "frontmatter"
        )

        editor.set(key: "ID", value: encodeString(config.googleAnalyticsID), section: "services.googleAnalytics")
        editor.set(key: "home", value: encodeArray(config.outputsHome), section: "outputs")
        editor.set(key: "mediaType", value: encodeString(config.outputFormatJSONMediaType), section: "outputFormats.json")
        editor.set(key: "baseName", value: encodeString(config.outputFormatJSONBaseName), section: "outputFormats.json")
        editor.set(key: "isPlainText", value: config.outputFormatJSONIsPlainText ? "true" : "false", section: "outputFormats.json")
    }

    private func buildManagedConfigLines(_ config: ThemeConfig) -> [String] {
        var lines: [String] = []

        lines.append("baseURL = \(encodeString(config.baseURL))")
        lines.append("languageCode = \(encodeString(config.languageCode))")
        lines.append("title = \(encodeString(config.title))")
        lines.append("theme = \(encodeString(config.theme))")
        lines.append("pygmentsCodeFences = \(config.pygmentsCodeFences ? "true" : "false")")
        lines.append("pygmentsUseClasses = \(config.pygmentsUseClasses ? "true" : "false")")
        lines.append("")

        lines.append("[params]")
        lines.append("  author = \(encodeString(config.params.author))")
        lines.append("  description = \(encodeString(config.params.description))")
        lines.append("  tagline = \(encodeString(config.params.tagline))")
        lines.append("  github = \(encodeString(config.params.github))")
        lines.append("  twitter = \(encodeString(config.params.twitter))")
        lines.append("  facebook = \(encodeString(config.params.facebook))")
        lines.append("  linkedin = \(encodeString(config.params.linkedin))")
        lines.append("  instagram = \(encodeString(config.params.instagram))")
        lines.append("  tumblr = \(encodeString(config.params.tumblr))")
        lines.append("  stackoverflow = \(encodeString(config.params.stackoverflow))")
        lines.append("  bluesky = \(encodeString(config.params.bluesky))")
        lines.append("  email = \(encodeString(config.params.email))")
        lines.append("  url = \(encodeString(config.params.url))")
        lines.append("  keywords = \(encodeString(config.params.keywords))")
        lines.append("  favicon = \(encodeString(config.params.favicon))")
        lines.append("  avatar = \(encodeString(config.params.avatar))")
        lines.append("  headerIcon = \(encodeString(config.params.headerIcon))")
        lines.append("  location = \(encodeString(config.params.location))")
        lines.append("  userStatusEmoji = \(encodeString(config.params.userStatusEmoji))")
        lines.append("  rss = \(config.params.rss ? "true" : "false")")
        lines.append("  lastmod = \(config.params.lastmod ? "true" : "false")")
        lines.append("  enableGitalk = \(config.params.enableGitalk ? "true" : "false")")
        lines.append("  enableSearch = \(config.params.enableSearch ? "true" : "false")")
        lines.append("  math = \(config.params.math ? "true" : "false")")
        lines.append("  MathJax = \(config.params.mathJax ? "true" : "false")")
        lines.append("  custom_css = \(encodeArray(config.params.customCSS))")
        lines.append("  custom_js = \(encodeArray(config.params.customJS))")
        lines.append("")

        lines.append("  [params.gitalk]")
        lines.append("    clientID = \(encodeString(config.params.gitalk.clientID))")
        lines.append("    clientSecret = \(encodeString(config.params.gitalk.clientSecret))")
        lines.append("    repo = \(encodeString(config.params.gitalk.repo))")
        lines.append("    owner = \(encodeString(config.params.gitalk.owner))")
        lines.append("    admin = \(encodeString(config.params.gitalk.admin))")
        lines.append("    id = \(encodeString(config.params.gitalk.id))")
        lines.append("    labels = \(encodeString(config.params.gitalk.labels))")
        lines.append("    perPage = \(config.params.gitalk.perPage)")
        lines.append("    pagerDirection = \(encodeString(config.params.gitalk.pagerDirection))")
        lines.append("    createIssueManually = \(config.params.gitalk.createIssueManually ? "true" : "false")")
        lines.append("    distractionFreeMode = \(config.params.gitalk.distractionFreeMode ? "true" : "false")")
        lines.append("    proxy = \(encodeString(config.params.gitalk.proxy))")

        if !config.params.links.isEmpty {
            lines.append("")
            for link in config.params.links {
                lines.append("  [[params.links]]")
                lines.append("    title = \(encodeString(link.title))")
                lines.append("    href = \(encodeString(link.href))")
                if !link.icon.isEmpty {
                    lines.append("    icon = \(encodeString(link.icon))")
                }
            }
        }

        lines.append("")
        lines.append("[frontmatter]")
        if config.frontmatterTrackLastmod {
            lines.append("  lastmod = [\"lastmod\", \":fileModTime\", \":default\"]")
        } else {
            lines.append("  lastmod = [\":default\"]")
        }

        lines.append("")
        lines.append("[services]")
        lines.append("  [services.googleAnalytics]")
        lines.append("    ID = \(encodeString(config.googleAnalyticsID))")

        lines.append("")
        lines.append("[outputs]")
        lines.append("  home = \(encodeArray(config.outputsHome))")

        lines.append("")
        lines.append("[outputFormats.json]")
        lines.append("  mediaType = \(encodeString(config.outputFormatJSONMediaType))")
        lines.append("  baseName = \(encodeString(config.outputFormatJSONBaseName))")
        lines.append("  isPlainText = \(config.outputFormatJSONIsPlainText ? "true" : "false")")
        return lines
    }

    private func applyParam(key: String, value: String, to config: inout ThemeConfig) {
        switch key {
        case "author": config.params.author = parseString(value)
        case "description", "Description": config.params.description = parseString(value)
        case "tagline": config.params.tagline = parseString(value)
        case "github": config.params.github = parseString(value)
        case "twitter": config.params.twitter = parseString(value)
        case "facebook": config.params.facebook = parseString(value)
        case "linkedin": config.params.linkedin = parseString(value)
        case "instagram": config.params.instagram = parseString(value)
        case "tumblr": config.params.tumblr = parseString(value)
        case "stackoverflow": config.params.stackoverflow = parseString(value)
        case "bluesky": config.params.bluesky = parseString(value)
        case "email", "Email": config.params.email = parseString(value)
        case "url": config.params.url = parseString(value)
        case "keywords", "Keywords": config.params.keywords = parseString(value)
        case "favicon": config.params.favicon = parseString(value)
        case "avatar": config.params.avatar = parseString(value)
        case "headerIcon": config.params.headerIcon = parseString(value)
        case "location": config.params.location = parseString(value)
        case "userStatusEmoji": config.params.userStatusEmoji = parseString(value)
        case "rss": config.params.rss = parseBool(value)
        case "lastmod": config.params.lastmod = parseBool(value)
        case "enableGitalk": config.params.enableGitalk = parseBool(value)
        case "enableSearch": config.params.enableSearch = parseBool(value)
        case "math": config.params.math = parseBool(value)
        case "MathJax", "mathJax": config.params.mathJax = parseBool(value)
        case "custom_css": config.params.customCSS = parseStringArray(value)
        case "custom_js": config.params.customJS = parseStringArray(value)
        default: break
        }
    }

    private func applyGitalkParam(key: String, value: String, to config: inout ThemeConfig) {
        switch key {
        case "clientID": config.params.gitalk.clientID = parseString(value)
        case "clientSecret": config.params.gitalk.clientSecret = parseString(value)
        case "repo": config.params.gitalk.repo = parseString(value)
        case "owner": config.params.gitalk.owner = parseString(value)
        case "admin": config.params.gitalk.admin = parseString(value)
        case "id": config.params.gitalk.id = parseString(value)
        case "labels": config.params.gitalk.labels = parseString(value)
        case "perPage": config.params.gitalk.perPage = Int(parseString(value)) ?? 15
        case "pagerDirection": config.params.gitalk.pagerDirection = parseString(value)
        case "createIssueManually": config.params.gitalk.createIssueManually = parseBool(value)
        case "distractionFreeMode": config.params.gitalk.distractionFreeMode = parseBool(value)
        case "proxy": config.params.gitalk.proxy = parseString(value)
        default: break
        }
    }

    private func splitKeyValue(_ line: String) -> (String, String)? {
        guard let idx = line.firstIndex(of: "=") else {
            return nil
        }
        let key = line[..<idx].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return (String(key), String(value))
    }

    private func stripInlineComment(_ value: String) -> String {
        var inSingle = false
        var inDouble = false

        for (idx, ch) in value.enumerated() {
            if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == "#" && !inSingle && !inDouble {
                let cut = value.index(value.startIndex, offsetBy: idx)
                return String(value[..<cut])
            }
        }

        return value
    }

    private func parseString(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    private func parseBool(_ raw: String) -> Bool {
        parseString(raw).lowercased() == "true"
    }

    private func parseStringArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
            return parseString(trimmed).isEmpty ? [] : [parseString(trimmed)]
        }

        let body = String(trimmed.dropFirst().dropLast())
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        return body
            .split(separator: ",")
            .map { parseString(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func encodeString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func encodeArray(_ values: [String]) -> String {
        if values.isEmpty {
            return "[]"
        }
        return "[" + values.map { encodeString($0) }.joined(separator: ", ") + "]"
    }
}

private struct ConfigLineEditor {
    private var lines: [String]

    init(raw: String) {
        var parsed = raw.components(separatedBy: .newlines)
        if parsed.last == "" {
            parsed.removeLast()
        }
        lines = parsed
    }

    mutating func set(key: String, value: String, section: String?, aliases: [String] = []) {
        let keys = Set([key] + aliases)
        if let lineIndex = findKeyLine(section: section, keys: keys) {
            let indent = leadingWhitespace(of: lines[lineIndex])
            lines[lineIndex] = "\(indent)\(key) = \(value)"
            return
        }

        if let section {
            let sectionRef = ensureSection(named: section)
            let indent = indentationForSection(sectionRef: sectionRef)
            let insertAt = insertionIndexForSection(sectionRef: sectionRef)
            lines.insert("\(indent)\(key) = \(value)", at: insertAt)
        } else {
            let insertAt = firstHeaderIndex() ?? lines.count
            lines.insert("\(key) = \(value)", at: insertAt)
        }
    }

    mutating func replaceArrayTable(name: String, blocks: [[String]], preferredAnchorSection: String?) {
        removeArrayTable(named: name)
        guard !blocks.isEmpty else {
            return
        }

        var insertAt: Int
        if let preferredAnchorSection,
           let sectionRef = sectionReference(named: preferredAnchorSection) {
            insertAt = insertionIndexForSection(sectionRef: sectionRef)
        } else if let parent = name.split(separator: ".").dropLast().first, !parent.isEmpty,
                  let sectionRef = sectionReference(named: String(parent)) {
            insertAt = insertionIndexForSection(sectionRef: sectionRef)
        } else {
            insertAt = lines.count
        }

        if insertAt > 0 && !lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.insert("", at: insertAt)
            insertAt += 1
        }

        for (idx, block) in blocks.enumerated() {
            lines.insert("[[\(name)]]", at: insertAt)
            insertAt += 1
            for row in block {
                lines.insert("  \(row)", at: insertAt)
                insertAt += 1
            }
            if idx < blocks.count - 1 {
                lines.insert("", at: insertAt)
                insertAt += 1
            }
        }
    }

    func rendered() -> String {
        var output = lines
        while output.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            output.removeLast()
        }
        return output.joined(separator: "\n") + "\n"
    }

    private mutating func ensureSection(named name: String) -> SectionReference {
        if let existing = sectionReference(named: name) {
            return existing
        }

        if !lines.isEmpty, lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.append("")
        }
        lines.append("[\(name)]")
        return SectionReference(headerIndex: lines.count - 1, endIndex: lines.count)
    }

    private func findKeyLine(section: String?, keys: Set<String>) -> Int? {
        var currentSection: String?
        var currentArraySection: String?

        for index in lines.indices {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if let header = parseHeader(from: trimmed) {
                if header.isArray {
                    currentArraySection = header.name
                    currentSection = nil
                } else {
                    currentSection = header.name
                    currentArraySection = nil
                }
                continue
            }

            if currentArraySection != nil {
                continue
            }

            if section == nil {
                if currentSection != nil {
                    continue
                }
            } else if currentSection != section {
                continue
            }

            guard let assignment = parseAssignment(from: trimmed) else {
                continue
            }
            if keys.contains(assignment.key) {
                return index
            }
        }

        return nil
    }

    private func firstHeaderIndex() -> Int? {
        lines.indices.first(where: { parseHeader(from: lines[$0].trimmingCharacters(in: .whitespaces)) != nil })
    }

    private func sectionReference(named name: String) -> SectionReference? {
        for idx in lines.indices {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard let header = parseHeader(from: trimmed), !header.isArray, header.name == name else {
                continue
            }

            var end = lines.count
            var cursor = idx + 1
            while cursor < lines.count {
                let line = lines[cursor].trimmingCharacters(in: .whitespaces)
                if parseHeader(from: line) != nil {
                    end = cursor
                    break
                }
                cursor += 1
            }
            return SectionReference(headerIndex: idx, endIndex: end)
        }
        return nil
    }

    private func indentationForSection(sectionRef: SectionReference) -> String {
        guard sectionRef.headerIndex < sectionRef.endIndex else {
            return "  "
        }
        for idx in (sectionRef.headerIndex + 1)..<sectionRef.endIndex {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            if parseHeader(from: trimmed) != nil {
                continue
            }
            if parseAssignment(from: trimmed) != nil {
                return leadingWhitespace(of: lines[idx])
            }
        }
        return "  "
    }

    private func insertionIndexForSection(sectionRef: SectionReference) -> Int {
        var insertAt = sectionRef.endIndex
        while insertAt > sectionRef.headerIndex + 1 {
            let previous = lines[insertAt - 1].trimmingCharacters(in: .whitespaces)
            if previous.isEmpty {
                insertAt -= 1
                continue
            }
            break
        }
        return insertAt
    }

    private mutating func removeArrayTable(named name: String) {
        var idx = 0
        while idx < lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if let header = parseHeader(from: trimmed), header.isArray, header.name == name {
                let start = idx
                idx += 1
                while idx < lines.count {
                    let nextTrimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                    if parseHeader(from: nextTrimmed) != nil {
                        break
                    }
                    idx += 1
                }
                lines.removeSubrange(start..<idx)
                idx = start
                while idx > 0 && idx < lines.count
                    && lines[idx - 1].trimmingCharacters(in: .whitespaces).isEmpty
                    && lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.remove(at: idx)
                }
                continue
            }
            idx += 1
        }
    }

    private func parseHeader(from trimmedLine: String) -> (name: String, isArray: Bool)? {
        let headerCandidate = trimmedLine
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? trimmedLine

        if headerCandidate.hasPrefix("[[") && headerCandidate.hasSuffix("]]") {
            let name = String(headerCandidate.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            return (name, true)
        }
        if headerCandidate.hasPrefix("[") && headerCandidate.hasSuffix("]") {
            let name = String(headerCandidate.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            return (name, false)
        }
        return nil
    }

    private func parseAssignment(from trimmedLine: String) -> (key: String, value: String)? {
        guard let idx = trimmedLine.firstIndex(of: "=") else {
            return nil
        }
        let key = trimmedLine[..<idx].trimmingCharacters(in: .whitespaces)
        let value = trimmedLine[trimmedLine.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return (String(key), String(value))
    }

    private func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }
}

private struct SectionReference {
    var headerIndex: Int
    var endIndex: Int
}

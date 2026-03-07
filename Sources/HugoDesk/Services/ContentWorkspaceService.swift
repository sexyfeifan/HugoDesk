import Foundation

final class ContentWorkspaceService {
    private let fm = FileManager.default

    func workspaces(for project: BlogProject, config: ThemeConfig) -> [HugoLanguageProfile] {
        var profiles = config.languageProfiles
        if profiles.isEmpty {
            profiles = [
                HugoLanguageProfile(
                    code: normalizedCode(from: config.languageCode),
                    title: config.languageCode,
                    contentDir: project.contentSubpath,
                    weight: 0
                )
            ]
        }

        if !profiles.contains(where: { $0.contentDir == project.contentSubpath }) {
            profiles.insert(
                HugoLanguageProfile(
                    code: normalizedCode(from: config.languageCode),
                    title: config.languageCode,
                    contentDir: project.contentSubpath,
                    weight: 0
                ),
                at: 0
            )
        }

        return deduplicated(profiles)
    }

    func scanShortcodes(project: BlogProject, activeTheme: String) -> [ShortcodeDefinition] {
        var results: [ShortcodeDefinition] = []
        let projectDir = project.rootURL.appendingPathComponent("layouts/shortcodes", isDirectory: true)
        results.append(contentsOf: scanShortcodes(in: projectDir, projectRoot: project.rootURL, isProjectLocal: true))

        let themeName = activeTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        if !themeName.isEmpty {
            let themeDir = project.rootURL.appendingPathComponent("themes/\(themeName)/layouts/shortcodes", isDirectory: true)
            results.append(contentsOf: scanShortcodes(in: themeDir, projectRoot: project.rootURL, isProjectLocal: false))
        }

        let unique = Dictionary(results.map { ($0.name + "|" + $0.sourcePath, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.values.sorted {
            if $0.isProjectLocal != $1.isProjectLocal {
                return $0.isProjectLocal && !$1.isProjectLocal
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func referenceCandidates(posts: [BlogPost], project: BlogProject) -> [PageReferenceCandidate] {
        posts.map { post in
            PageReferenceCandidate(
                title: post.title.isEmpty ? post.displayFileName : post.title,
                referencePath: referencePath(for: post, project: project),
                filePath: post.fileURL.path
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func anchors(for post: BlogPost) -> [String] {
        let headingPattern = #"(?m)^\s{0,3}#{1,6}\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else { return [] }
        let ns = post.body as NSString
        let range = NSRange(location: 0, length: ns.length)
        var anchors: [String] = []
        regex.enumerateMatches(in: post.body, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let raw = ns.substring(with: match.range(at: 1))
            let cleaned = raw
                .replacingOccurrences(of: #"`+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[(.*?)\]\((.*?)\)"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = slugifyHeading(cleaned)
            if !slug.isEmpty, !anchors.contains(slug) {
                anchors.append(slug)
            }
        }
        return anchors
    }

    func unresolvedReferences(posts: [BlogPost], project: BlogProject) -> [ReferenceDiagnostic] {
        let candidates = referenceCandidates(posts: posts, project: project)
        let validPathSet = Set(candidates.map { normalizedReferencePath($0.referencePath).path })
        let anchorMap = Dictionary(uniqueKeysWithValues: posts.map { post in
            (normalizedReferencePath(referencePath(for: post, project: project)).path, Set(anchors(for: post)))
        })

        guard let regex = try? NSRegularExpression(pattern: #"\{\{<\s*(?:relref|ref)\s+\"([^\"]+)\"\s*>\}\}"#) else {
            return []
        }

        var results: [ReferenceDiagnostic] = []
        for post in posts {
            let body = post.body
            let nsRange = NSRange(body.startIndex..<body.endIndex, in: body)
            regex.enumerateMatches(in: body, options: [], range: nsRange) { match, _, _ in
                guard let match,
                      match.numberOfRanges > 1,
                      let refRange = Range(match.range(at: 1), in: body) else {
                    return
                }

                let reference = String(body[refRange])
                let normalized = normalizedReferencePath(reference)
                guard !normalized.path.isEmpty else { return }

                let invalidPath = !validPathSet.contains(normalized.path)
                let invalidAnchor = !normalized.anchor.isEmpty
                    && !invalidPath
                    && !(anchorMap[normalized.path]?.contains(normalized.anchor) ?? false)
                guard invalidPath || invalidAnchor else { return }

                let reason = invalidPath
                    ? "页面不存在"
                    : "锚点 #\(normalized.anchor) 未找到"
                let preview = linePreview(in: body, for: match.range)
                results.append(
                    ReferenceDiagnostic(
                        postTitle: post.title.isEmpty ? post.displayFileName : post.title,
                        filePath: post.fileURL.path,
                        reference: "\(reference)（\(reason)）",
                        linePreview: preview
                    )
                )
            }
        }

        return results.sorted {
            if $0.postTitle == $1.postTitle {
                return $0.reference < $1.reference
            }
            return $0.postTitle.localizedStandardCompare($1.postTitle) == .orderedAscending
        }
    }

    func translationDiagnostics(
        workspaces: [HugoLanguageProfile],
        postsByWorkspace: [String: [BlogPost]],
        projectRoot: URL
    ) -> [TranslationDiagnostic] {
        guard !workspaces.isEmpty else { return [] }

        struct Entry {
            let workspace: HugoLanguageProfile
            let post: BlogPost
        }

        var grouped: [String: [Entry]] = [:]
        for workspace in workspaces {
            for post in postsByWorkspace[workspace.code, default: []] {
                let identity = translationIdentity(for: post, workspace: workspace, projectRoot: projectRoot)
                grouped[identity, default: []].append(Entry(workspace: workspace, post: post))
            }
        }

        let workspaceTitles = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.code, $0.title.isEmpty ? $0.code : $0.title) })
        return grouped.values.compactMap { group in
            let existingCodes = Set(group.map(\.workspace.code))
            let missingCodes = workspaces.map(\.code).filter { !existingCodes.contains($0) }
            guard !missingCodes.isEmpty else { return nil }

            let source = group.sorted {
                let left = $0.post.title.isEmpty ? $0.post.displayFileName : $0.post.title
                let right = $1.post.title.isEmpty ? $1.post.displayFileName : $1.post.title
                return left.localizedStandardCompare(right) == .orderedAscending
            }.first!

            let key = source.post.translationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? translationIdentity(for: source.post, workspace: source.workspace, projectRoot: projectRoot)
                : source.post.translationKey

            return TranslationDiagnostic(
                translationKey: key,
                sourceTitle: source.post.title.isEmpty ? source.post.displayFileName : source.post.title,
                sourceFilePath: source.post.fileURL.path,
                existingLanguageCodes: Array(existingCodes).sorted(),
                existingLanguages: existingCodes.compactMap { workspaceTitles[$0] }.sorted(),
                missingLanguageCodes: missingCodes.sorted(),
                missingLanguages: missingCodes.compactMap { workspaceTitles[$0] }.sorted()
            )
        }
        .sorted {
            $0.sourceTitle.localizedStandardCompare($1.sourceTitle) == .orderedAscending
        }
    }

    func menuTreeEntries(posts: [BlogPost]) -> [MenuTreeEntry] {
        posts.compactMap { post in
            let menuName = post.menuEntry.menuName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !menuName.isEmpty else { return nil }
            let title = post.menuEntry.entryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (post.title.isEmpty ? post.displayFileName : post.title)
                : post.menuEntry.entryName
            let identifierSeed = post.menuEntry.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? title
                : post.menuEntry.identifier
            return MenuTreeEntry(
                menuName: menuName,
                identifier: slugifyHeading(identifierSeed),
                title: title,
                parent: slugifyHeading(post.menuEntry.parent),
                weight: post.menuEntry.weight,
                filePath: post.fileURL.path
            )
        }
        .sorted {
            if $0.menuName == $1.menuName {
                if $0.weight == $1.weight {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.weight < $1.weight
            }
            return $0.menuName.localizedStandardCompare($1.menuName) == .orderedAscending
        }
    }

    private func scanShortcodes(in directory: URL, projectRoot: URL, isProjectLocal: Bool) -> [ShortcodeDefinition] {
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var items: [ShortcodeDefinition] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension.lowercased() == "html" else { continue }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let relative = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            let name = file.deletingPathExtension().lastPathComponent
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            items.append(
                ShortcodeDefinition(
                    name: name,
                    sourcePath: relative,
                    isProjectLocal: isProjectLocal,
                    parameterHints: shortcodeParameterHints(from: content),
                    summary: summarizeShortcode(content)
                )
            )
        }
        return items
    }

    private func shortcodeParameterHints(from content: String) -> [ShortcodeParameterHint] {
        var hints: [ShortcodeParameterHint] = []
        var seen = Set<String>()

        let namedPatterns = [
            #"\.Get\s+\"([^\"]+)\""#,
            #"\.Param\s+\"([^\"]+)\""#
        ]
        for pattern in namedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = content as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: content, range: range) {
                guard match.numberOfRanges > 1 else { continue }
                let key = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                hints.append(ShortcodeParameterHint(name: key, sampleValue: "value", isPositional: false))
            }
        }

        if let positionalRegex = try? NSRegularExpression(pattern: #"\.Get\s+([0-9]+)"#) {
            let ns = content as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in positionalRegex.matches(in: content, range: range) {
                guard match.numberOfRanges > 1 else { continue }
                let index = ns.substring(with: match.range(at: 1))
                let key = "arg\(index)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                hints.append(ShortcodeParameterHint(name: key, sampleValue: "value\(index)", isPositional: true))
            }
        }

        return hints.sorted {
            if $0.isPositional != $1.isPositional {
                return !$0.isPositional && $1.isPositional
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func summarizeShortcode(_ content: String) -> String {
        let commentPattern = #"(?s)<!--\s*(.*?)\s*-->"#
        if let regex = try? NSRegularExpression(pattern: commentPattern) {
            let ns = content as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: content, range: range), match.numberOfRanges > 1 {
                let summary = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    return summary
                }
            }
        }

        let firstLine = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? ""
        return String(firstLine.prefix(72))
    }

    private func referencePath(for post: BlogPost, project: BlogProject) -> String {
        let standardizedPost = post.fileURL.standardizedFileURL.path
        let standardizedContentRoot = project.contentURL.standardizedFileURL.path
        guard standardizedPost.hasPrefix(standardizedContentRoot) else {
            return post.fileURL.deletingPathExtension().lastPathComponent
        }

        var relative = String(standardizedPost.dropFirst(standardizedContentRoot.count))
        if relative.hasPrefix("/") { relative.removeFirst() }

        switch post.creationMode {
        case .singleFile:
            return URL(fileURLWithPath: relative).deletingPathExtension().path
        case .leafBundle, .branchBundle:
            let bundleRoot = post.fileURL.deletingLastPathComponent().path
            var bundleRelative = bundleRoot.replacingOccurrences(of: standardizedContentRoot + "/", with: "")
            if bundleRelative.hasPrefix("/") { bundleRelative.removeFirst() }
            return bundleRelative
        }
    }

    private func translationIdentity(for post: BlogPost, workspace: HugoLanguageProfile, projectRoot: URL) -> String {
        let translationKey = post.translationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translationKey.isEmpty {
            return translationKey
        }

        let contentRoot = projectRoot.appendingPathComponent(workspace.contentDir, isDirectory: true).standardizedFileURL.path
        let postPath = post.fileURL.standardizedFileURL.path
        guard postPath.hasPrefix(contentRoot) else {
            return post.displayFileName
        }

        var relative = String(postPath.dropFirst(contentRoot.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.hasSuffix("/index.md") {
            relative.removeLast("/index.md".count)
            return relative
        }
        if relative.hasSuffix("/_index.md") {
            relative.removeLast("/_index.md".count)
            return relative
        }
        return URL(fileURLWithPath: relative).deletingPathExtension().path
    }

    private func normalizedReferencePath(_ value: String) -> (path: String, anchor: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = parts.first.map(String.init) ?? trimmed
        let anchorPart = parts.count > 1 ? String(parts[1]) : ""

        var normalized = pathPart
        while normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        let url = URL(fileURLWithPath: normalized)
        if url.pathExtension.lowercased() == "md" {
            normalized = url.deletingPathExtension().path
        }
        if normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        return (normalized, slugifyHeading(anchorPart))
    }

    private func linePreview(in body: String, for range: NSRange) -> String {
        let ns = body as NSString
        let safeLocation = min(max(range.location, 0), max(ns.length - 1, 0))
        let full = ns.substring(with: ns.lineRange(for: NSRange(location: safeLocation, length: 0)))
        return full.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slugifyHeading(_ source: String) -> String {
        let lower = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let filtered = lower.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        return String(filtered)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func normalizedCode(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func deduplicated(_ profiles: [HugoLanguageProfile]) -> [HugoLanguageProfile] {
        var seen = Set<String>()
        return profiles.filter {
            let key = $0.code + "|" + $0.contentDir
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        .sorted {
            if $0.weight == $1.weight { return $0.code < $1.code }
            return $0.weight < $1.weight
        }
    }
}

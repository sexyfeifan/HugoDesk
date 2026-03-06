import Foundation

enum AIServiceError: LocalizedError {
    case missingConfiguration
    case invalidEndpoint
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "请先在 AI 设置中填写 API 地址、API Key 和模型。"
        case .invalidEndpoint:
            return "AI API 地址无效，请检查 base URL。"
        case .invalidResponse:
            return "AI 返回内容为空或格式无法识别。"
        case let .apiError(code, body):
            return "AI 请求失败：HTTP \(code)\n\(body)"
        }
    }
}

struct AIService {
    func formatMarkdown(input: String, profile: AIProfile, apiKey: String) async throws -> String {
        let prompt = """
        请对以下 Markdown 文本执行“排版与语法体检”，输出修正后的 Markdown：
        1. 严格检查并修正 Markdown 符号正确性（标题层级、列表缩进、代码块围栏、链接/图片括号、引用、表格分隔线、转义符）。
        2. 删除无意义字符、乱码、重复标点、孤立符号和明显噪音内容。
        3. 不改变事实，不新增原文没有的信息。
        4. 在不改变原意的前提下优化段落结构与可读性。
        5. 仅输出最终 Markdown 正文，不要解释过程。

        原文如下：
        \(input)
        """

        return try await requestCompletion(
            systemPrompt: "You are a professional markdown editor.",
            userPrompt: prompt,
            profile: profile,
            apiKey: apiKey,
            temperature: 0.2
        )
    }

    func writeMarkdown(input: String, profile: AIProfile, apiKey: String) async throws -> String {
        let references = await loadReferenceContexts(from: input)
        let referencesSection: String
        if references.isEmpty {
            referencesSection = "未检测到可读取的外部链接，或链接内容暂时无法访问。"
        } else {
            referencesSection = references.joined(separator: "\n\n---\n\n")
        }

        let prompt = """
        请根据以下素材执行“二次写作”，输出一段可直接追加到博客正文的 Markdown：
        1. 先识别素材里的文字、链接和关键信息，再组织成结构清晰、可直接发布的中文 Markdown。
        2. 如果素材中包含链接，请优先结合“链接读取结果”提炼重点；无法读取的链接不要编造内容。
        3. 不改变原始事实，不虚构数据，不杜撰来源。
        4. 如果引用了链接信息，尽量在文中保留合适的 Markdown 链接。
        5. 可以根据内容合理使用标题、列表、引用、表格或代码块，但不要输出解释过程。
        6. 仅输出最终 Markdown 正文。

        用户提供的原始素材：
        \(input)

        链接读取结果：
        \(referencesSection)
        """

        return try await requestCompletion(
            systemPrompt: "You are a professional Chinese blog writing assistant.",
            userPrompt: prompt,
            profile: profile,
            apiKey: apiKey,
            temperature: 0.7
        )
    }

    func suggestFix(operation: String, errorLog: String, profile: AIProfile, apiKey: String) async throws -> String {
        let prompt = """
        请根据以下失败日志给出可执行的修复方案。

        操作：\(operation)

        错误日志：
        \(errorLog)

        输出要求：
        1. 先给“最可能原因”（最多 3 条）。
        2. 再给“排查步骤”（按顺序，命令可直接执行）。
        3. 最后给“修复后验证命令”。
        4. 使用中文，输出 Markdown。
        """

        return try await requestCompletion(
            systemPrompt: "You are a senior DevOps and Git troubleshooting assistant.",
            userPrompt: prompt,
            profile: profile,
            apiKey: apiKey,
            temperature: 0.1
        )
    }

    private func requestCompletion(
        systemPrompt: String,
        userPrompt: String,
        profile: AIProfile,
        apiKey: String,
        temperature: Double
    ) async throws -> String {
        let baseURL = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !model.isEmpty, !token.isEmpty else {
            throw AIServiceError.missingConfiguration
        }

        let endpoint = normalizedEndpoint(baseURL)
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidEndpoint
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard 200..<300 ~= code else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.apiError(code, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = extractContent(from: message["content"]),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.invalidResponse
        }

        return content
    }

    private func normalizedEndpoint(_ baseURL: String) -> String {
        if baseURL.hasSuffix("/chat/completions") {
            return baseURL
        }
        if baseURL.hasSuffix("/v1") {
            return baseURL + "/chat/completions"
        }
        return baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions"
    }

    private func extractContent(from raw: Any?) -> String? {
        if let text = raw as? String {
            return text
        }

        if let array = raw as? [[String: Any]] {
            let parts = array.compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                if let type = item["type"] as? String,
                   type == "text",
                   let text = item["text"] as? String {
                    return text
                }
                return nil
            }
            return parts.joined(separator: "\n")
        }

        return nil
    }

    private func loadReferenceContexts(from input: String) async -> [String] {
        let urls = extractURLs(from: input)
        if urls.isEmpty {
            return []
        }

        return await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for url in urls.prefix(3) {
                group.addTask {
                    await fetchReferenceContext(from: url)
                }
            }

            var results: [String] = []
            for await result in group {
                if let result, !result.isEmpty {
                    results.append(result)
                }
            }
            return results
        }
    }

    private func extractURLs(from input: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let ns = input as NSString
        let matches = detector.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var seen: Set<String> = []
        var urls: [URL] = []

        for match in matches {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            let absolute = url.absoluteString
            if seen.insert(absolute).inserted {
                urls.append(url)
            }
        }

        return urls
    }

    private func fetchReferenceContext(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 HugoDesk/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                return nil
            }

            let mimeType = (response.mimeType ?? "").lowercased()
            let text = normalizedReferenceText(from: data, mimeType: mimeType)
            guard !text.isEmpty else { return nil }

            return """
            链接：\(url.absoluteString)
            内容摘录：
            \(text)
            """
        } catch {
            return nil
        }
    }

    private func normalizedReferenceText(from data: Data, mimeType: String) -> String {
        let raw = String(decoding: data.prefix(300_000), as: UTF8.self)
        let text: String

        if mimeType.contains("html") || raw.localizedCaseInsensitiveContains("<html") {
            text = cleanedHTMLText(raw)
        } else {
            text = raw
        }

        return normalizeWhitespace(text).prefix(6_000).description
    }

    private func cleanedHTMLText(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            ("(?is)<script[^>]*>.*?</script>", " "),
            ("(?is)<style[^>]*>.*?</style>", " "),
            ("(?is)<noscript[^>]*>.*?</noscript>", " "),
            ("(?is)<svg[^>]*>.*?</svg>", " "),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|section|article|header|footer|main|aside|li|ul|ol|blockquote|pre|table|tr|td|th|h1|h2|h3|h4|h5|h6)>", "\n"),
            ("(?is)<[^>]+>", " ")
        ]

        for replacement in replacements {
            text = text.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }

        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'")
        ]

        for entity in entities {
            text = text.replacingOccurrences(of: entity.0, with: entity.1)
        }

        return text
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

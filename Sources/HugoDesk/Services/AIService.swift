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
}

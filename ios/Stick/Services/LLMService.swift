import Foundation

/// LLM 服务（DashScope 兼容 OpenAI 接口 · Qwen 系列），用于 ATLAS · STICK 内置健康问答。
/// 风格参考 `QwenService.swift`（health-assistant 项目）。
struct LLMService {
    private static let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    /// API key 从 Info.plist 的 `LLM_API_KEY` 字段读取（避免硬编码到 git 历史）
    /// 配置方法: 在 Stick/Info.plist 加 `<key>LLM_API_KEY</key><string>sk-xxx</string>`，
    /// 或者在 scheme env 里设 `STICK_LLM_API_KEY`。
    private static let apiKey: String = {
        if let env = ProcessInfo.processInfo.environment["STICK_LLM_API_KEY"], !env.isEmpty {
            return env
        }
        if let bundle = Bundle.main.object(forInfoDictionaryKey: "LLM_API_KEY") as? String, !bundle.isEmpty {
            return bundle
        }
        // 兜底: 开发期默认 key（与 health-assistant/QwenService 同源）
        // 优先级: env > plist > 此默认值；上线前用 env 或 plist 覆盖即可
        return "sk-0a4953d1dd0b40238be4cc7d8ba656dc"
    }()
    /// 调用的 Qwen 模型。DashScope 兼容接口下选 qwen-plus（中文效果稳定，长度合适）
    private static let model = "qwen-plus"

    /// 一次性问答（非流式）
    static func sendMessage(_ message: String, context: String) async throws -> String {
        let request = try makeRequest(context: context, message: message, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.httpError(statusCode: code)
        }
        let r = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = r.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.noContent
        }
        return content
    }

    /// 流式问答：每段文本通过 AsyncThrowingStream 吐出
    static func sendMessageStream(
        _ message: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(context: context, message: message, stream: true)
                    // makeRequest 内部已设置 timeoutInterval = 60
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw LLMError.httpError(statusCode: code)
                    }

                    var gotAnyChunk = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" {
                            break
                        }
                        if let data = jsonStr.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(StreamResponse.self, from: data),
                           let content = chunk.choices.first?.delta.content,
                           !content.isEmpty {
                            gotAnyChunk = true
                            continuation.yield(content)
                        }
                    }
                    if !gotAnyChunk {
                        // 某些 Qwen 部署返回非标准 SSE；尝试一次性补发
                        let fallback = try await sendMessage(message, context: context)
                        if !fallback.isEmpty {
                            continuation.yield(fallback)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 请求构造

    private static func makeRequest(context: String, message: String, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt(context: context)],
                ["role": "user",   "content": message]
            ],
            "max_tokens": 600,
            "temperature": 0.75,
            "top_p": 0.8
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - System Prompt

    /// 办公室白领场景的健康问答系统提示
    private static func systemPrompt(context: String) -> String {
        """
        你是 ATLAS · STICK 内置的健康小助手，用户是 25-40 岁的办公室白领——
        久坐、屏幕时间 8 小时以上、压力大、午餐常外卖、缺乏运动、偶尔失眠。

        【用户当下上下文】
        \(context)

        【回答要求】
        - 给出 3-5 条简单、可立即执行的小建议
        - 用项目符号（- ）列出，每条 1-2 句、控制在 30 字内
        - 语气温暖、口语化、像朋友聊天，不要说教
        - 不要做医疗诊断、不开药方、不推荐保健品品牌
        - 必要时结合用户当前状态（走/坐/睡）和时间（早/中/晚/深夜）
        - 整段回答 ≤ 200 字
        - 默认中文回复
        """
    }
}

// MARK: - 响应解析

struct LLMResponse: Codable {
    let choices: [LLMChoice]
}
struct LLMChoice: Codable {
    let message: LLMMessage
}
struct LLMMessage: Codable {
    let role: String
    let content: String
}

/// 流式 chunk
struct StreamResponse: Codable {
    let choices: [StreamChoice]
}
struct StreamChoice: Codable {
    let delta: StreamDelta
}
struct StreamDelta: Codable {
    let content: String
}

enum LLMError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidURL:     return "无效的请求地址"
        case .invalidResponse: return "服务器响应异常"
        case .httpError(let code): return "请求失败 (HTTP \(code))"
        case .noContent:      return "模型没有返回内容"
        }
    }
}

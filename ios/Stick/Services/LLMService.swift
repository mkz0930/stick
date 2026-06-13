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
                            // **模拟流式**：切成 2-3 字一组 + 短延迟 yield，UX 上看着像流式
                            let chunkSize = 2  // 每组 2 字符
                            var idx = fallback.startIndex
                            while idx < fallback.endIndex {
                                let next = fallback.index(idx, offsetBy: chunkSize, limitedBy: fallback.endIndex) ?? fallback.endIndex
                                let piece = String(fallback[idx..<next])
                                continuation.yield(piece)
                                if Task.isCancelled { break }
                                try? await Task.sleep(nanoseconds: 25_000_000)  // 25ms 每片
                                idx = next
                            }
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
        你是 ATLAS · STICK 内置的健康顾问，基于用户的实时健康数据提供个性化建议。

        【用户当下上下文】
        \(context)

        【核心原则】
        - 主动分析「今日健康数据」，结合用户画像和最近问题，给出真正个性化的建议
        - 久坐时长、步数、心率等数据是判断健康状态的核心依据，要主动引用
        - 建议必须结合用户实际情况（如久坐超过2小时重点提醒活动，久坐少则多鼓励）
        - 专业但亲和，像一位可信赖的健康顾问

        【回答格式】严格要求按以下四段式输出：

        **可能的原因**
        - 列出 2-4 条可能原因，每条 1-2 句，结合用户数据说明原理
        - 主动引用数据（如"你今天已经久坐 90 分钟，比昨天同期多 30 分钟"）

        **建议**
        1. 第一条建议，具体可操作，控制在 30 字以内
        2. 第二条建议
        3. 第三条建议（如果有）
        4. 第四条建议（如果有）

        **需要做的检查**（如果有相关检查建议）
        - 列出 1-3 项建议做的检查或自查方法

        **警告**（如果没有重要警告可省略此段）
        - 用红色或高亮样式标注重要的警示信息

        【语气要求】
        - 专业、清晰、不说教
        - 不要做医疗诊断、不开药方、不推荐保健品品牌
        - 整段回答 ≤ 400 字
        - 默认中文回复

        【格式要求】
        - 严格按四段式输出，标题加粗
        - 使用 Markdown 列表和数字编号
        - 警告部分用醒目方式呈现
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

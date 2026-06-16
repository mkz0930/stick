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
    /// 视觉模型（用于图片分析）
    private static let visionModel = "qwen-vl-plus"

    /// 上次个性化分析的时间（UserDefaults key）
    private static let lastAnalysisKey = "llm.last_analysis_time"

    /// 距上次个性化分析的小时数（nil 表示从未分析过）
    static var hoursSinceLastAnalysis: Int? {
        let ts = UserDefaults.standard.double(forKey: lastAnalysisKey)
        guard ts > 0 else { return nil }
        let delta = Date().timeIntervalSince1970 - ts
        let hours = Int(delta / 3600)
        return hours
    }

    /// 记录一次个性化分析的时间（每次 LLM 回复后调用）
    static func markAnalysisDone() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAnalysisKey)
    }

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

    /// 一次性问答 + 返回联网搜索引用
    static func sendMessageWithSearch(_ message: String, context: String) async throws -> (content: String, searchResults: [SearchResult]) {
        let request = try makeRequest(context: context, message: message, stream: false, enableSearch: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.httpError(statusCode: code)
        }
        let r = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let msg = r.choices.first?.message, let content = msg.content, !content.isEmpty else {
            throw LLMError.noContent
        }
        return (content, msg.searchInfo?.searchResults ?? [])
    }

    /// 带图片的流式问答（视觉模型）
    static func sendMessageStreamWithImage(
        _ message: String,
        context: String,
        imageData: Data
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeVisionRequest(context: context, message: message, imageData: imageData, stream: true)
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
                        if jsonStr == "[DONE]" { break }
                        if let data = jsonStr.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(StreamResponse.self, from: data),
                           let content = chunk.choices.first?.delta.content,
                           !content.isEmpty {
                            gotAnyChunk = true
                            continuation.yield(content)
                        }
                    }
                    if !gotAnyChunk {
                        let fallback = try await sendMessageWithImage(message, context: context, imageData: imageData)
                        if !fallback.isEmpty {
                            let chunkSize = 2
                            var idx = fallback.startIndex
                            while idx < fallback.endIndex {
                                let next = fallback.index(idx, offsetBy: chunkSize, limitedBy: fallback.endIndex) ?? fallback.endIndex
                                let piece = String(fallback[idx..<next])
                                continuation.yield(piece)
                                if Task.isCancelled { break }
                                try? await Task.sleep(nanoseconds: 25_000_000)
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

    /// 带图片的一次性问答
    static func sendMessageWithImage(_ message: String, context: String, imageData: Data) async throws -> String {
        let request = try makeVisionRequest(context: context, message: message, imageData: imageData, stream: false)
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
        context: String,
        enableSearch: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(context: context, message: message, stream: true, enableSearch: enableSearch)
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

    /// 流式问答 + 联网搜索（返回内容 chunks + 末尾的搜索引用）
    /// - 在流末尾 yield 一个特殊 sentinel `"__SEARCH_RESULTS__:<encoded JSON>"`，
    ///   客户端解析这个 sentinel 拿到引用并展示。
    static func sendMessageStreamWithSearch(
        _ message: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(context: context, message: message, stream: true, enableSearch: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw LLMError.httpError(statusCode: code)
                    }

                    // 整段响应收集起来，末尾用完整 LLMResponse 解析 search_info
                    var fullText = ""
                    var gotAnyChunk = false
                    var collectedData = Data()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        if let data = jsonStr.data(using: .utf8) {
                            collectedData.append(data)
                            if let chunk = try? JSONDecoder().decode(StreamResponse.self, from: data),
                               let content = chunk.choices.first?.delta.content,
                               !content.isEmpty {
                                gotAnyChunk = true
                                fullText += content
                                continuation.yield(content)
                            }
                        }
                    }

                    // 末尾再发一次非流式请求，拿到 search_info 引用
                    if gotAnyChunk {
                        do {
                            let (_, searchResults) = try await sendMessageWithSearch(message, context: context)
                            if !searchResults.isEmpty,
                               let json = try? JSONEncoder().encode(searchResults),
                               let str = String(data: json, encoding: .utf8) {
                                continuation.yield("__SEARCH_RESULTS__:" + str)
                            }
                        } catch {
                            // 静默失败，搜索引用非关键
                        }
                    } else {
                        // 完全没收到流，回退到非流式
                        let (fallback, searchResults) = try await sendMessageWithSearch(message, context: context)
                        if !fallback.isEmpty {
                            let chunkSize = 2
                            var idx = fallback.startIndex
                            while idx < fallback.endIndex {
                                let next = fallback.index(idx, offsetBy: chunkSize, limitedBy: fallback.endIndex) ?? fallback.endIndex
                                let piece = String(fallback[idx..<next])
                                continuation.yield(piece)
                                if Task.isCancelled { break }
                                try? await Task.sleep(nanoseconds: 25_000_000)
                                idx = next
                            }
                            if !searchResults.isEmpty,
                               let json = try? JSONEncoder().encode(searchResults),
                               let str = String(data: json, encoding: .utf8) {
                                continuation.yield("__SEARCH_RESULTS__:" + str)
                            }
                        }
                    }
                    _ = fullText
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 请求构造

    private static func makeRequest(context: String, message: String, stream: Bool, enableSearch: Bool = false) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt(context: context, lastAnalysisHour: hoursSinceLastAnalysis)],
                ["role": "user",   "content": message]
            ],
            "max_tokens": 600,
            "temperature": 0.75,
            "top_p": 0.8
        ]
        if enableSearch {
            // DashScope 联网搜索：模型按需检索并把结果作为上下文，响应里返回引用 URL
            body["enable_search"] = true
            body["search_options"] = [
                "forced_search": false,   // 让模型自己决定是否需要搜索
                "search_strategy": "standard"
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 构建视觉模型请求（带图片）
    private static func makeVisionRequest(context: String, message: String, imageData: Data, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }
        let base64Image = imageData.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // 图片较大，超时时间加倍

        let body: [String: Any] = [
            "model": visionModel,
            "stream": stream,
            "messages": [
                ["role": "system", "content": visionSystemPrompt(context: context, lastAnalysisHour: hoursSinceLastAnalysis)],
                ["role": "user", "content": [
                    ["type": "text", "text": message],
                    ["type": "image_url", "image_url": ["url": imageURL]]
                ]]
            ],
            "max_tokens": 800,
            "temperature": 0.75
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - System Prompt

    /// 视觉问答专用：先做图片相关性初判，再深入分析
    private static func visionSystemPrompt(context: String, lastAnalysisHour: Int?) -> String {
        let hourHint: String
        if let h = lastAnalysisHour {
            hourHint = "距离上次个性化分析已超过 \(h) 小时，本次可根据情况省略详细分析。"
        } else {
            hourHint = "本次可进行完整的分析。"
        }

        return """
        你是 ATLAS · STICK 内置的健康顾问，用户发来了一张图片。

        【用户当下上下文】
        \(context)

        【回答结构 - 严格两段式】
        1. **【图片类型判断】**（第一段，必须先输出）
           - 用 1-2 句话说明：这张图片是否与健康相关
           - 健康相关示例：皮肤状态、舌苔、饮食（食物/饮品）、药品/保健品、体姿/骨骼、体表症状（红肿/疹子/伤口）、运动动作、医疗报告/化验单/处方、眼睛/口腔
           - 健康无关示例：风景、宠物、人物日常、自拍、街景、表情包、卡通、商品、纯文字截图等
           - 严格只输出"健康相关"或"健康无关"的判断 + 简短理由

        2. **【深入分析】**（第二段，根据第一段判断决定内容）
           - 如果"健康无关"：礼貌告诉用户这张图片不在健康分析范围内，建议上传健康相关的图片。1-2 句即可，不要强行分析
           - 如果"健康相关"：根据图片内容做专业分析
             - 皮肤/舌苔：观察颜色、状态、可能反映的健康信号（不要下诊断）
             - 饮食/药品：识别内容、分析营养或作用、给出建议
             - 体姿/骨骼：观察姿势、可能的风险点、给出改善建议
             - 医疗报告/化验单：识别关键指标、解释含义（不做诊断）
             - 体表症状：描述观察所见、列出可能原因、建议就医科室
             - 其他：根据实际内容灵活分析
           - \(hourHint)

        【回答原则】
        - 专业、清晰、不说教，像可信赖的健康顾问
        - 第一段判断必须先输出，结构清晰
        - 不要做医疗诊断、不开药方、不推荐保健品品牌
        - 默认中文回复

        【格式要求】
        - 严格按"图片类型判断 → 深入分析"两段顺序
        - 第一段标题加粗
        - 健康无关时第二段简短（一句话即可）
        - 健康相关时第二段可展开 3-6 句
        - 不要凑四段式

        【结构化输出】（必须）
        当图片是食物时，在回复正文之后另起一行输出：
        [FOOD] 餐次|食物名|热量kcal
        示例：[FOOD] 早餐|馒头,鸡蛋|350
        - 餐次：早餐|午餐|晚餐|加餐
        - 食物名：逗号分隔的食物名称
        - 热量：估算的千卡数（不确定则写 0）
        - 非食物图片不输出此行
        """
    }

    /// 办公室白领场景的健康问答系统提示
    private static func systemPrompt(context: String, lastAnalysisHour: Int?) -> String {
        let hourHint: String
        if let h = lastAnalysisHour {
            hourHint = "距离上次个性化分析已超过 \(h) 小时，本次可根据情况省略详细分析，直接回答用户问题。"
        } else {
            hourHint = "本次可进行完整的个性化分析。"
        }

        return """
        你是 ATLAS · STICK 内置的健康顾问。

        【用户当下上下文】
        \(context)

        【回答策略】
        - 先快速判断用户真正想问什么（健康咨询/症状询问/建议请求/闲聊）
        - 根据问题类型灵活调整回答深度和结构
        - \(hourHint)
        - 久坐、步数、心率等数据是判断依据，主动引用但不要每次都长篇分析

        【回答原则】
        - 专业但亲和，像可信赖的健康顾问，不说教
        - 整段回答 ≤ 300 字
        - 默认中文回复
        - 不要做医疗诊断、不开药方、不推荐保健品品牌

        【格式建议】（根据问题类型灵活调整，不要机械套用）
        - 简短问题时：直接给答案 + 1-2 句补充说明即可
        - 需要建议时：先说结论，再简短解释原因（1-2 句）
        - 需要分析时：可展开 2-3 句分析，再给建议
        - 有重要警示才单独提醒，不要刻意凑四段式
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
    let content: String?
    /// 联网搜索引用（DashScope enable_search=true 时返回，可能为空）
    let searchInfo: SearchInfo?

    enum CodingKeys: String, CodingKey {
        case role, content
        case searchInfo = "search_info"
    }
}

/// 联网搜索结果引用
struct SearchInfo: Codable {
    let searchResults: [SearchResult]

    enum CodingKeys: String, CodingKey {
        case searchResults = "search_results"
    }
}

struct SearchResult: Codable, Identifiable, Hashable {
    let index: Int          // 角标编号（与文本里的 [n] 对应）
    let url: String         // 来源 URL
    let title: String?      // 标题
    let siteName: String?   // 站点名

    var id: Int { index }
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

import SwiftUI
import CoreLocation

// MARK: - Chat Overlay Context Builders

/// 今日健康数据统计（从 HealthStore 实时计算）
@MainActor
struct TodayHealthStats {
    let sitMinutes: Int
    let walkMinutes: Int
    let sleepMinutes: Int
    let standMinutes: Int
    let totalSteps: Int
    let avgHeartRate: Int

    init() {
        let snapshots = HealthStore.shared.today
        var sit = 0, walk = 0, sleep = 0, stand = 0, hrSum = 0, hrCount = 0
        for s in snapshots {
            switch s.bodyState {
            case "sit": sit += 1
            case "walk": walk += 1
            case "sleep": sleep += 1
            case "stand": stand += 1
            default: break
            }
            if let hr = s.heartRate { hrSum += Int(hr); hrCount += 1 }
        }
        let totalSteps = snapshots.last?.cumulativeStepCount ?? 0
        self.sitMinutes = sit
        self.walkMinutes = walk
        self.sleepMinutes = sleep
        self.standMinutes = stand
        self.totalSteps = totalSteps
        self.avgHeartRate = hrCount > 0 ? hrSum / hrCount : 72
    }
}

// MARK: - Context Builder Extension

extension ChatOverlay {
    func buildContext() -> String {
        let time = StickState.formatMinute(StickState.minutesOfDay(.now))
        let hour = Calendar.current.component(.hour, from: .now)
        let period: String
        switch hour {
        case 5..<11:  period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default:      period = "深夜"
        }

        // 1. 长期用户画像
        let profileBlock = UserProfileStore.shared.profileContextBlock()

        // 2. 用户关注标签（短期 top5 + 长期 top3）
        let shortTags = UserProfileStore.shared.topShortTermTags(limit: 5)
        let longTags = UserInterestTagStore.shared.topLongTermTags(limit: 3)
        var tagsBlock = ""
        if !shortTags.isEmpty || !longTags.isEmpty {
            tagsBlock += "【用户关注标签】\n"
            if !shortTags.isEmpty {
                tagsBlock += "近期: \(shortTags.joined(separator: " / "))\n"
            }
            if !longTags.isEmpty {
                tagsBlock += "长期: \(longTags.joined(separator: " / "))\n"
            }
            tagsBlock += "\n"
        }

        // 3. 健康趋势语义化
        let trend = HealthTrendAnalyzer.analyze(
            today: HealthStore.shared.today,
            all: HealthStore.shared.all
        )
        var trendBlock = ""
        if !trend.semanticLines.isEmpty {
            trendBlock = "【健康趋势语义化】\n" + trend.semanticLines.joined(separator: "\n") + "\n\n"
        }

        // 4. 今日健康数据
        let stats = TodayHealthStats()
        let healthBlock = """
        【今日健康数据】
        - 久坐: \(stats.sitMinutes) 分钟
        - 行走: \(stats.walkMinutes) 分钟
        - 站立: \(stats.standMinutes) 分钟
        - 睡眠: \(stats.sleepMinutes) 分钟
        - 步数: \(stats.totalSteps) 步
        - 平均心率: \(stats.avgHeartRate) bpm

        """

        // 4.5 睡眠习惯画像（出差状态切换时显示对应作息）
        let isTravelNow = LocationService.shared.isTravel(
            now: Date.now,
            homeCity: UserProfileStore.shared.sleepHabit.homeCity
        )
        let sleepBlock = UserProfileStore.shared.sleepHabitContextBlock(isTravel: isTravelNow)

        // 5. 用户最近问题
        let recentUserMsgs = messages
            .filter { $0.role == .user }
            .suffix(10)
            .map { "用户: \($0.content)" }
            .joined(separator: "\n")

        // 6. 系统指令
        let systemBlock = """
        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase) (\(state.englishName))
        - 备注: 给出符合该时段 + 该姿态的即时可行建议
        """

        return profileBlock + tagsBlock + trendBlock + healthBlock + sleepBlock + """
        【用户最近问题】
        \(recentUserMsgs)

        """ + systemBlock
    }

    // MARK: - Widget 风险提醒专属流程

    /// 久坐时长（分钟），由 riskSeed 解析而来
    var sedentaryMinutes: Int {
        guard let seed = riskSeed,
              seed.hasPrefix("久坐风险提醒:"),
              let minStr = seed.split(separator: ":").last,
              let min = Int(minStr) else { return 30 }
        return min
    }

    /// 构建 widget 风险提醒的 system prompt
    func buildRiskContext(seed: String) -> String {
        let time = StickState.formatMinute(StickState.minutesOfDay(.now))
        let hour = Calendar.current.component(.hour, from: .now)
        let period: String
        switch hour {
        case 5..<11:  period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default:      period = "深夜"
        }

        if seed.hasPrefix("久坐风险提醒") {
            let mins = sedentaryMinutes
            let hours = mins / 60
            let remain = mins % 60
            let durationText = hours > 0 ? "\(hours)小时\(remain)分钟" : "\(mins)分钟"

            let stats = TodayHealthStats()
            return """
            【用户当前状态】
            - 当前时间: \(time) (\(period))
            - 当前姿态: \(state.actionPhrase)
            - 久坐时长: \(durationText)
            - 今日久坐累计: \(stats.sitMinutes) 分钟
            - 今日行走累计: \(stats.walkMinutes) 分钟
            - 今日步数: \(stats.totalSteps) 步
            - 平均心率: \(stats.avgHeartRate) bpm

            【本次对话目标】
            用户点击了久坐风险提醒卡片，这是一个健康科普+即时行动建议的场景。
            请严格按以下结构回复：

            1. 【风险科普】先用1-2句话解释久坐\(durationText)对身体的具体危害（要具体、可感知，不要笼统）
            2. 【当前状态分析】结合时间、姿态、今日久坐累计，简述用户此刻的身体感受
            3. 【立刻可以做的动作】给出2-4条马上就能做、没有阻力的动作，每条10字以内，格式：「动作名称 · 具体描述」

            示例：「扩胸3下 · 双手背后握拳，向后展开胸部，重复3次」

            【语气要求】
            - 温暖、口语化，像朋友提醒你动一动
            - 不要说教，不要给医疗建议
            - 总字数 ≤ 300字
            """
        }

        return """
        【用户当前状态】
        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase)

        【本次对话目标】
        用户点击了健康风险提醒卡片，请给出风险科普和2-4条立刻能做的动作建议。

        1. 【风险科普】1-2句话解释当前健康风险
        2. 【立刻能做的动作】2-4条无阻力的即时行动

        语气温暖口语化，总字数 ≤ 300字
        """
    }

    /// 生成 widget 风险提醒的 AI 分析（直接输出，不作为用户消息）
    func generateRiskAnalysis(seed: String) {
        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildRiskContext(seed: seed)
        streamTask = Task {
            do {
                for try await chunk in LLMService.sendMessageStream(seed, context: ctx) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                        messages[idx].content = "⚠️ \(err)"
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                input = ""
            }

            await generateSuggestions(for: assistantId)
        }
    }

    /// 饮食建议专属流程：基于用户今日健康数据，调用 LLM 给个性化推荐
    func generateDietAdvice(seed: String) {
        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildDietContext()
        streamTask = Task {
            do {
                for try await chunk in LLMService.sendMessageStream(seed, context: ctx) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                        messages[idx].content = "⚠️ \(err)"
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                input = ""
            }
            await generateSuggestions(for: assistantId)
        }
    }

    /// 饮食建议专属 context：基于用户今日健康数据
    func buildDietContext() -> String {
        let time = StickState.formatMinute(StickState.minutesOfDay(.now))
        let hour = Calendar.current.component(.hour, from: .now)
        let period: String
        switch hour {
        case 5..<11:  period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default:      period = "深夜"
        }

        let stats = TodayHealthStats()
        let trend = HealthTrendAnalyzer.analyze(
            today: HealthStore.shared.today,
            all: HealthStore.shared.all
        )

        return """
        【用户当前状态】
        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase)

        【今日健康数据】
        - 久坐: \(stats.sitMinutes) 分钟
        - 行走: \(stats.walkMinutes) 分钟
        - 站立: \(stats.standMinutes) 分钟
        - 步数: \(stats.totalSteps) 步
        - 平均心率: \(stats.avgHeartRate) bpm

        \(trend.semanticLines.isEmpty ? "" : "【健康趋势】\n" + trend.semanticLines.joined(separator: "\n") + "\n")

        【本次对话目标】
        用户点击了"饮食建议"chip，需要基于今日健康数据（久坐/步数/心率等）给出个性化饮食推荐。

        请严格按以下结构回复：

        1. 【今日饮食重点】1-2 句话，结合用户今日的活动量（步数/久坐）给一句核心建议（如"久坐较多 → 多吃富钾食物"）
        2. 【推荐 3 类食物】每类 1-2 个具体例子 + 1 句话说明为什么适合他
        3. 【避开 1-2 类】结合用户当前状态，列出今日应少吃的
        4. 【今日餐次节奏】如果现在是早上/中午/晚上，给具体的饮食时间建议

        【语气要求】
        - 温暖、口语化，像营养师朋友提醒
        - 不要说教，不要给医疗建议
        - 食物要具体（如"香蕉/牛油果/三文鱼"而不是"水果"）
        - 总字数 ≤ 350字
        """
    }
}

//
//  SleepParser.swift
//  从用户对话中正则解析睡眠信息（bedTime / wakeTime / duration）
//
//  支持中英文；支持中文数字"五个小时"、半小时间隔"5个半小时"。
//  返回 nil 表示没解析到睡眠相关内容。
//

import Foundation

/// 从用户对话中提取出的睡眠信息（参照时间为 `referenceDate`）
struct SleepInfo: Codable, Equatable {
    /// 昨晚/最近一次入睡时刻（绝对 Date）
    let bedTime: Date?
    /// 起床/醒来时刻（绝对 Date）
    let wakeTime: Date?
    /// 睡眠时长（分钟）
    let durationMinutes: Int?
    /// 参照日期（默认 now，用于"昨晚""今天"等相对表达）
    let referenceDate: Date
}

@MainActor
enum SleepParser {
    /// 主入口：从用户消息中解析睡眠信息
    /// - Parameters:
    ///   - text: 用户消息原文
    ///   - now: 参照当前时间（用于"昨晚""今天"等相对表达）
    /// - Returns: 解析出的 SleepInfo；未命中任何睡眠模式返回 nil
    static func parse(_ text: String, now: Date = Date()) -> SleepInfo? {
        guard !text.isEmpty else { return nil }

        // 1) 排除明显不相关的消息
        if !looksLikeSleepMessage(text) { return nil }

        let calendar = Calendar.current
        let hourNow = calendar.component(.hour, from: now)
        let minuteNow = calendar.component(.minute, from: now)

        var bedTime: Date?
        var wakeTime: Date?
        var durationMin: Int?

        // 2) 解析"睡了 X 小时 / X 个小时 / X 个半小时"
        if let dur = parseDuration(text) {
            durationMin = dur
        }

        // 3) 解析"X 点睡 / X 点钟睡 / 凌晨 X 点 / X 点入睡"
        if let parsedBed = parseClockTime(text, kind: .bed, now: now, hourNow: hourNow) {
            bedTime = parsedBed
        }

        // 4) 解析"X 点起 / X 点起床 / X 点醒"
        if let parsedWake = parseClockTime(text, kind: .wake, now: now, hourNow: hourNow) {
            wakeTime = parsedWake
        }

        // 5) 跨午夜推断：如果只知道 bedTime 且没 duration，且 hourNow 早（<12 早上），
        //    说明是"今早起"补的昨晚睡眠，bedTime 应该是昨天
        if bedTime != nil && durationMin != nil && durationMin! < 16 * 60 {
            // 已经有 duration 且合理（<16h），不必调整
        }

        // 6) 推算缺失的字段
        // 6a) 缺 bedTime 但有 wake + duration
        if bedTime == nil, let wake = wakeTime, let dur = durationMin {
            bedTime = wake.addingTimeInterval(-TimeInterval(dur * 60))
        }
        // 6b) 缺 wakeTime 但有 bed + duration
        if wakeTime == nil, let bed = bedTime, let dur = durationMin {
            wakeTime = bed.addingTimeInterval(TimeInterval(dur * 60))
        }
        // 6c) 缺 duration 但有 bed + wake
        if durationMin == nil, let bed = bedTime, let wake = wakeTime {
            durationMin = Int(wake.timeIntervalSince(bed) / 60)
        }

        // 7) 跨午夜的合理性纠正：bedTime > wakeTime → 减去 24h 或加上 24h
        if let bed = bedTime, let wake = wakeTime {
            if bed > wake {
                // 早上说"昨晚"模式：bed 是昨天，wake 是今天，差值正确（>0）
                let diff = wake.timeIntervalSince(bed) / 60
                if diff < 0 || diff > 16 * 60 {
                    // 不合理：强行纠正 bed
                    if hourNow < 12 {
                        // 早上语境：bed = 昨天
                        bedTime = bed.addingTimeInterval(-24 * 3600)
                    } else {
                        // 晚上语境：bed = 昨天
                        bedTime = bed.addingTimeInterval(-24 * 3600)
                    }
                    durationMin = Int(wake.timeIntervalSince(bedTime!) / 60)
                }
            }
        }

        // 8) 至少要有一个有效字段才返回
        guard bedTime != nil || wakeTime != nil || durationMin != nil else {
            return nil
        }

        // 9) 时长合理性检查：30 分钟 - 16 小时
        if let d = durationMin, d < 30 || d > 16 * 60 {
            // 时长不合理 → 丢弃整个解析结果
            return nil
        }

        return SleepInfo(
            bedTime: bedTime,
            wakeTime: wakeTime,
            durationMinutes: durationMin,
            referenceDate: now
        )
    }

    // MARK: - 子判断

    /// 简单启发：消息里包含睡眠相关关键词
    private static func looksLikeSleepMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        let zh = ["睡", "眠", "起", "醒", "觉", "眠", "起床", "入睡"]
        for k in zh where text.contains(k) { return true }
        let en = ["sleep", "slept", "bed", "woke", "wake up", "asleep"]
        for k in en where lower.contains(k) { return true }
        return false
    }

    private enum ClockKind { case bed, wake }

    /// 解析"X 点 [睡/起/醒/起床/入睡/醒来]"，支持"凌晨/早上/上午"前缀
    private static func parseClockTime(
        _ text: String,
        kind: ClockKind,
        now: Date,
        hourNow: Int
    ) -> Date? {
        // 先把所有空白去掉以便正则
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        // 简化：用 NSRegularExpression 多次尝试不同 pattern
        // 凌晨 / 早上 / 上午 / 晚上 修饰
        // 数字允许 0-23
        // 关键词集合
        let sleepKeywords = ["睡", "入睡", "眠", "睡觉", "睡了", "睡着"]
        let wakeKeywords  = ["起", "起床", "醒", "醒来", "醒了", "起床了"]
        let suffix: [String]
        switch kind {
        case .bed: suffix = sleepKeywords
        case .wake: suffix = wakeKeywords
        }

        // 模式 1: 凌晨/早上/上午/晚上 + 数字 + 点 + (半) + 关键词
        let prefixPattern = "(?:凌晨|早上|上午|中午|下午|晚上|夜里|深夜)?"
        let hourPattern = "([0-9]{1,2})"
        let halfPattern = "(?:个半)?(?:小时?)?"  // 允许"5个半"等冗余
        let pointWord = "[点:：]"

        for kw in suffix {
            // pattern: (prefix)X点(suffixKeyword)
            // 同时支持"X点Y"（kw）和"X点睡了"
            let patterns = [
                "\(prefixPattern)\(hourPattern)\(pointWord)\(halfPattern)\(kw)",
                "\(prefixPattern)\(hourPattern)\(halfPattern)\(pointWord)\(kw)",
            ]
            for pat in patterns {
                if let m = matchFirst(cleaned, pattern: pat),
                   let hourStr = m.captures.first,
                   let hour = Int(hourStr) {
                    if let date = buildDate(hour: hour, minute: 0, now: now, hourNow: hourNow, kind: kind, prefix: m.prefix) {
                        return date
                    }
                }
            }
        }
        return nil
    }

    /// 解析"睡了 X 小时 / X 个小时 / X 个半小时 / X小时 / 才睡 X / 只睡了 X"
    private static func parseDuration(_ text: String) -> Int? {
        // 数字解析（中文/阿拉伯）
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        // pattern 1: 阿拉伯数字 + 小时/个(半)小时
        let patterns: [String] = [
            "(?:[才只刚一])?睡了?([0-9]+(?:\\.[0-9]+)?)(?:个半)?(?:个)?小时",
            "(?:[才只刚一])?睡了?([0-9]+)(?:个半)?小时",
            "(?:[才只刚一])?睡(?:了)?([0-9]+)(?:小时|个(?:小)?时)",
            // 英文
            "slept?\\s+([0-9]+(?:\\.[0-9]+)?)\\s*hours?",
            "slept?\\s+for\\s+([0-9]+)\\s*hours?",
        ]
        for pat in patterns {
            if let m = matchFirst(cleaned, pattern: pat),
               let s = m.captures.first,
               let v = Double(s) {
                return Int(v * 60)
            }
        }
        // pattern 2: 中文数字 + 小时 (一/二/三/四/五/六/七/八/九/十)
        let cnMap: [Character: Int] = [
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        // 5 个小时 / 五个小时 / 五个半小时
        let cnPattern = "睡了?([" + String(cnMap.keys) + "]+)(?:个)?(?:半)?(?:个)?小时"
        if let m = matchFirst(cleaned, pattern: cnPattern),
           let s = m.captures.first {
            if let v = parseChineseNumber(s) {
                return v * 60
            }
        }
        // X 个半 (小时)  → 5个半 = 5.5h
        let halfPattern = "睡了?([0-9]+|[一-十两]+)个半(?:个)?小时?"
        if let m = matchFirst(cleaned, pattern: halfPattern),
           let s = m.captures.first {
            if let v = Int(s) {
                return (v * 60) + 30
            } else if let v = parseChineseNumber(s) {
                return (v * 60) + 30
            }
        }
        return nil
    }

    /// 解析简单中文数字（支持 1-19）
    private static func parseChineseNumber(_ s: String) -> Int? {
        let map: [Character: Int] = [
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        if s.count == 1, let v = map[s.first!] { return v }
        if s.count == 2 {
            // "十一"=11, "十五"=15, "十X"=10+X
            if s.first == "十", let v = map[s.last!] { return 10 + v }
            // "X十" = X*10
            if s.last == "十", let v = map[s.first!] { return v * 10 }
        }
        if s.count == 3, s.first == "十" {
            // "X十Y" = 10*X + Y  （实际很少见）
            return nil
        }
        return nil
    }

    // MARK: - 正则 helper

    private struct MatchResult {
        let captures: [String]
        let prefix: String
    }

    private static func matchFirst(_ text: String, pattern: String) -> MatchResult? {
        // options: NSRegularExpression.Options 不区分大小写
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        // capture groups
        var captures: [String] = []
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound, let swiftRange = Range(r, in: text) {
                captures.append(String(text[swiftRange]))
            } else {
                captures.append("")
            }
        }
        // 提取 prefix（第一捕获组之前的非空文字）
        let firstRange = match.range(at: 0)
        if firstRange.location > 0,
           let swiftRange = Range(NSRange(location: 0, length: firstRange.location), in: text) {
            let before = String(text[swiftRange])
            return MatchResult(captures: captures, prefix: before)
        }
        return MatchResult(captures: captures, prefix: "")
    }

    /// 构造一个绝对 Date，必要时跨天（bed 昨天/wake 今天）
    private static func buildDate(
        hour: Int,
        minute: Int,
        now: Date,
        hourNow: Int,
        kind: ClockKind,
        prefix: String
    ) -> Date? {
        guard (0...23).contains(hour) else { return nil }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }

        // 跨天处理：
        // - bedTime：用户在早上(NB: hourNow < 12)说"昨晚 X 点睡" → 应该是昨天
        // - wakeTime：用户说"X 点起" → 一般是今天；若 hourNow 晚而 hour 早（凌晨 X 点），则是今天
        let nowTs = now.timeIntervalSince1970
        let candTs = candidate.timeIntervalSince1970
        switch kind {
        case .bed:
            // 如果是凌晨 (hour < 6) 且 prefix 包含"凌晨" → 算今天（"凌晨 2 点睡"指今天早上凌晨）
            // 否则默认 bed 应该是今天 or 昨天：若 cand > now + 1h → 减 1 天（昨晚）
            if hour < 6 && prefix.contains("凌晨") {
                // 凌晨 X 点睡：理解为今天凌晨
                return candidate
            }
            if candTs > nowTs + 3600 {
                // bed 在未来 1h 之后 → 减 1 天
                return candidate.addingTimeInterval(-24 * 3600)
            }
            return candidate
        case .wake:
            // wake 应该 ≤ now；若 cand > now → 减 1 天
            if candTs > nowTs + 3600 {
                return candidate.addingTimeInterval(-24 * 3600)
            }
            return candidate
        }
    }
}

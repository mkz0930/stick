//
//  TopicExtractor.swift
//  零延迟规则匹配，从用户输入中提取关注标签
//

import Foundation

enum TopicExtractor {
    /// 标签分类体系：标签名 -> 关键词列表
    static let taxonomy: [String: [String]] = [
        "眼部健康": ["眼睛", "眼干", "眼涩", "视力", "屏幕", "蓝光", "眼疲劳", "干眼"],
        "骨骼健康": ["腰", "颈椎", "背", "肩", "骨头", "关节", "腰疼", "腰痛", "肩酸", "脖子"],
        "睡眠问题": ["睡不着", "失眠", "困", "睡眠", "早醒", "深睡", "熬夜", "入睡", "睡眠质量"],
        "心血管": ["心率", "血压", "胸闷", "心脏", "心慌", "心跳"],
        "消化系统": ["胃", "便秘", "消化", "腹胀", "午饭", "午饭", "肠胃", "拉肚子"],
        "运动健身": ["跑步", "走路", "步数", "运动", "拉伸", "锻炼", "健身", "久坐"],
        "情绪压力": ["焦虑", "压力", "烦躁", "心情", "低落", "情绪", "抑郁", "疲惫"],
        "饮食营养": ["咖啡", "茶", "水", "吃饭", "蔬菜", "维生素", "饮食", "外卖"],
    ]

    /// 从文本提取匹配到的标签数组（去重、保留出现顺序）
    /// - Parameter text: 用户输入文本
    /// - Returns: 按首次匹配顺序排列的标签数组
    static func extract(from text: String) -> [String] {
        let lowercased = text.lowercased()
        var found: [(index: Int, tag: String)] = []

        for (tag, keywords) in taxonomy {
            for keyword in keywords {
                if lowercased.contains(keyword.lowercased()) {
                    // 已收录则跳过；未收录则追加
                    if !found.contains(where: { $0.tag == tag }) {
                        found.append((found.count, tag))
                    }
                    break
                }
            }
        }

        // 按原始出现顺序排序
        found.sort { $0.index < $1.index }
        return found.map { $0.tag }
    }
}

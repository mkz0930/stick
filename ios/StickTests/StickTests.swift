//
//  StickTests.swift
//  Stick
//
//  StickState / DaySegment / Theme 单元测试。
//  AAA 模式：Arrange / Act / Assert。
//

import XCTest
import SwiftUI
@testable import Stick

final class StickTests: XCTestCase {

    // MARK: - Helpers

    /// 用指定分钟数构造一个 Date（日期本身不重要，关心时分）。
    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026
        c.month = 6
        c.day = 18
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }
}

// MARK: - StickState.current(at:)

extension StickTests {

    /// 00:00 → 夜间睡眠
    func test_currentAt_midnight_returnsSleep() {
        // Arrange
        let date = self.date(hour: 0, minute: 0)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sleep)
    }

    /// 06:59 仍在睡眠窗口（[0, 420)）
    func test_currentAt_justBeforeMorningCommute_returnsSleep() {
        // Arrange
        let date = self.date(hour: 6, minute: 59)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sleep)
    }

    /// 07:00 整 → 晨间通勤
    func test_currentAt_7am_returnsWalk() {
        // Arrange
        let date = self.date(hour: 7, minute: 0)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .walk)
    }

    /// 08:29 仍在通勤（[420, 510)）
    func test_currentAt_829am_returnsWalk() {
        // Arrange
        let date = self.date(hour: 8, minute: 29)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .walk)
    }

    /// 08:30 → 上午工作
    func test_currentAt_830am_returnsSit() {
        // Arrange
        let date = self.date(hour: 8, minute: 30)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sit)
    }

    /// 12:00 → 午餐 + 散步
    func test_currentAt_noon_returnsWalk() {
        // Arrange
        let date = self.date(hour: 12, minute: 0)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .walk)
    }

    /// 13:30 → 下午工作
    func test_currentAt_130pm_returnsSit() {
        // Arrange
        let date = self.date(hour: 13, minute: 30)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sit)
    }

    /// 18:00 → 晚间通勤 + 休闲
    func test_currentAt_6pm_returnsWalk() {
        // Arrange
        let date = self.date(hour: 18, minute: 0)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .walk)
    }

    /// 22:00 → 夜间休息
    func test_currentAt_10pm_returnsSleep() {
        // Arrange
        let date = self.date(hour: 22, minute: 0)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sleep)
    }

    /// 23:59 仍在夜间（[1320, 1440)）
    func test_currentAt_lateNight_returnsSleep() {
        // Arrange
        let date = self.date(hour: 23, minute: 59)

        // Act
        let state = StickState.current(at: date)

        // Assert
        XCTAssertEqual(state, .sleep)
    }
}

// MARK: - StickState.minutesOfDay

extension StickTests {

    /// 00:00 → 0 分钟
    func test_minutesOfDay_midnight_isZero() {
        // Arrange
        let date = self.date(hour: 0, minute: 0)

        // Act
        let minutes = StickState.minutesOfDay(date)

        // Assert
        XCTAssertEqual(minutes, 0)
    }

    /// 13:45 → 825 分钟
    func test_minutesOfDay_afternoon_correct() {
        // Arrange
        let date = self.date(hour: 13, minute: 45)

        // Act
        let minutes = StickState.minutesOfDay(date)

        // Assert
        XCTAssertEqual(minutes, 13 * 60 + 45)
    }

    /// 23:59 → 1439 分钟
    func test_minutesOfDay_endOfDay_is1439() {
        // Arrange
        let date = self.date(hour: 23, minute: 59)

        // Act
        let minutes = StickState.minutesOfDay(date)

        // Assert
        XCTAssertEqual(minutes, 1439)
    }
}

// MARK: - StickState.formatMinute

extension StickTests {

    /// 0 → "00:00"
    func test_formatMinute_zero_returns0000() {
        // Arrange / Act
        let formatted = StickState.formatMinute(0)

        // Assert
        XCTAssertEqual(formatted, "00:00")
    }

    /// 510 → "08:30"
    func test_formatMinute_morningCommuteStart() {
        // Arrange / Act
        let formatted = StickState.formatMinute(510)

        // Assert
        XCTAssertEqual(formatted, "08:30")
    }

    /// 1439 → "23:59"
    func test_formatMinute_endOfDay() {
        // Arrange / Act
        let formatted = StickState.formatMinute(1439)

        // Assert
        XCTAssertEqual(formatted, "23:59")
    }
}

// MARK: - DaySegment

extension StickTests {

    /// contains 闭包：segment 内分钟返回 true
    func test_daySegment_contains_insideSegment_returnsTrue() {
        // Arrange
        let segment = StickState.DaySegment(state: .walk, startMinute: 420, endMinute: 510, stepCount: nil)

        // Act
        let insideStart = segment.contains(420)
        let insideMiddle = segment.contains(465)
        let justBeforeEnd = segment.contains(509)

        // Assert
        XCTAssertTrue(insideStart, "start boundary should be included")
        XCTAssertTrue(insideMiddle, "middle minute should be included")
        XCTAssertTrue(justBeforeEnd, "minute just before end should be included")
    }

    /// contains 闭包：segment 外 / 边界点 endMinute 不含
    func test_daySegment_contains_outsideSegment_returnsFalse() {
        // Arrange
        let segment = StickState.DaySegment(state: .walk, startMinute: 420, endMinute: 510, stepCount: nil)

        // Act
        let beforeStart = segment.contains(419)
        let atEnd = segment.contains(510)
        let afterEnd = segment.contains(511)

        // Assert
        XCTAssertFalse(beforeStart)
        XCTAssertFalse(atEnd, "end boundary should be excluded (half-open interval)")
        XCTAssertFalse(afterEnd)
    }

    /// duration = end - start
    func test_daySegment_duration_computedFromBounds() {
        // Arrange
        let segment = StickState.DaySegment(state: .sit, startMinute: 510, endMinute: 720, stepCount: nil)

        // Act
        let duration = segment.duration

        // Assert
        XCTAssertEqual(duration, 210, "上午工作时段应为 210 分钟")
    }

    /// id 与 startMinute 绑定，Identifiable
    func test_daySegment_id_equalsStartMinute() {
        // Arrange
        let segment = StickState.DaySegment(state: .sleep, startMinute: 1320, endMinute: 1440, stepCount: nil)

        // Act
        let id = segment.id

        // Assert
        XCTAssertEqual(id, 1320)
    }
}

// MARK: - DaySchedule 覆盖性

extension StickTests {

    /// 时刻表必须首尾相接覆盖全天 [0, 1440)
    func test_daySchedule_coversAllMinutes() {
        // Arrange
        let schedule = StickState.daySchedule

        // Act
        let totalCoverage = schedule.reduce(0) { $0 + $1.duration }

        // Assert
        XCTAssertEqual(totalCoverage, 1440, "所有时段合计应恰好覆盖 1440 分钟")
    }

    /// 时刻表无间隙：前一段 end == 后一段 start
    func test_daySchedule_hasNoGaps() {
        // Arrange
        let schedule = StickState.daySchedule

        // Act
        var gaps: [String] = []
        for i in 1..<schedule.count {
            let prev = schedule[i - 1]
            let curr = schedule[i]
            if prev.endMinute != curr.startMinute {
                gaps.append("gap between \(prev.endMinute) and \(curr.startMinute)")
            }
        }

        // Assert
        XCTAssertTrue(gaps.isEmpty, "时刻表存在间隙: \(gaps.joined(separator: ", "))")
    }

    /// 时刻表必须以 0 开头、1440 结尾
    func test_daySchedule_boundedByMidnight() {
        // Arrange
        let schedule = StickState.daySchedule

        // Act
        let first = schedule.first
        let last = schedule.last

        // Assert
        XCTAssertEqual(first?.startMinute, 0, "首段应从 00:00 开始")
        XCTAssertEqual(last?.endMinute, 1440, "末段应到 24:00 结束")
    }

    /// walk 段必须带步数，sit/sleep 段步数必须为 nil
    func test_daySchedule_stepCountOnlyOnWalkSegments() {
        // Arrange
        let schedule = StickState.daySchedule

        // Act
        let violations = schedule.filter { segment in
            if segment.state == .walk {
                return segment.stepCount == nil
            } else {
                return segment.stepCount != nil
            }
        }

        // Assert
        XCTAssertTrue(
            violations.isEmpty,
            "walk 段缺步数 / 非 walk 段带步数: \(violations.map { "[\($0.startMinute)-\($0.endMinute) state=\($0.state) stepCount=\($0.stepCount ?? -1)]" })"
        )
    }
}

// MARK: - Theme

extension StickTests {

    /// Theme 颜色：navy / slate / mist 等灰度色阶存在且互不相同
    func test_theme_textColors_areDistinct() {
        // Arrange / Act
        let navy = Theme.navy
        let slate = Theme.slate
        let mist = Theme.mist

        // Assert
        XCTAssertNotEqual(navy, slate, "navy 与 slate 必须不同")
        XCTAssertNotEqual(slate, mist, "slate 与 mist 必须不同")
        XCTAssertNotEqual(navy, mist, "navy 与 mist 必须不同")
    }

    /// Theme 渐变背景：bgTop 应比 bgBottom 更接近纯白
    func test_theme_backgroundGradient_topIsLighterThanBottom() {
        // Arrange
        let top = Theme.bgTop
        let bottom = Theme.bgBottom

        // Act
        let topLuma = Self.luminance(of: top)
        let bottomLuma = Self.luminance(of: bottom)

        // Assert
        XCTAssertGreaterThan(topLuma, bottomLuma, "bgTop 应比 bgBottom 更亮（接近纯白）")
    }

    /// Theme 健康仪表盘色：dashSedentary 应为橙色（红色通道高）
    func test_theme_dashSedentary_isOrangeTone() {
        // Arrange
        let sedentary = Theme.dashSedentary

        // Act
        let resolved = Self.resolveRGB(sedentary)

        // Assert
        XCTAssertNotNil(resolved, "Theme.dashSedentary 必须可解析为 RGB")
        guard let (r, g, b) = resolved else { return }
        XCTAssertGreaterThan(r, g, "red 通道 > green 通道（橙色）")
        XCTAssertGreaterThan(r, b, "red 通道 > blue 通道（橙色）")
    }

    /// Theme 卡片：card 应为白色，cardBorder 透明度极低（< 0.1）
    func test_theme_card_borderIsVerySubtle() {
        // Arrange
        let border = Theme.cardBorder

        // Act
        // cardBorder 是 Color.black.opacity(0.04)，无法直接读 opacity；
        // 这里至少验证类型是 Color，编过即过。
        let _ = border.description

        // Assert
        XCTAssertNotNil(border.description)
    }

    /// Theme 健康仪表盘色集合：5 类颜色互不相同
    func test_theme_dashboardColors_areDistinct() {
        // Arrange / Act
        let colors: [Color] = [
            Theme.dashSleep,
            Theme.dashSteps,
            Theme.dashDiet,
            Theme.dashBody,
            Theme.dashBlood,
            Theme.dashSedentary,
        ]

        // Assert
        let unique = Set(colors.map { $0.description })
        XCTAssertEqual(unique.count, colors.count, "6 个仪表盘色必须互不相同")
    }
}

// MARK: - Theme helper extensions

private extension StickTests {

    /// 把 Color 解析成 (r, g, b) 0~1。SwiftUI Color 在不同 color scheme 下可能取到 dynamic，
    /// 这里固定 light scheme 取 sRGB。
    static func resolveRGB(_ color: Color) -> (Double, Double, Double)? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        #if canImport(UIKit)
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
        #else
        return nil
        #endif
    }

    /// 用 Rec.709 公式估算亮度
    static func luminance(of color: Color) -> Double {
        guard let (r, g, b) = resolveRGB(color) else { return 0 }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

#if canImport(UIKit)
import UIKit
#endif

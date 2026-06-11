//
//  PersonalView.swift
//  个人面板 (浅色) — 跟主页一致的极浅色主题
//
//  新增：数据能力矩阵 (设备划分)
//  - 已连接的设备亮，对应 metric 解锁
//  - 未连接的设备灰，旁边提示"连接 XX 解锁 N 项"
//  - 点击设备行可切换 connected / disconnected（模拟连接）
//

import SwiftUI

struct PersonalView: View {
    var onClose: () -> Void
    @Binding var openSpecialists: Bool
    @Binding var openDataRecord: Bool
    @Binding var openWidgetPreview: Bool
    @Binding var deviceSet: Set<DeviceID>

    @State private var showSpecialists: Bool = false
    @State private var showDataRecord: Bool = false
    @State private var showWidgetPreview: Bool = false

    private let menus: [MenuItem] = [
        MenuItem(icon: "clock.arrow.circlepath", title: "数据记录"),
        MenuItem(icon: "person.2",  title: "专科专家"),
        MenuItem(icon: "macwindow",  title: "Widget 预览"),
    ]

    // 已配置的设备 (iPhone 永远在线) — 可点击切换连接状态
    private var allDevices: [Device] {
        DeviceID.allCases.map { id in
            Device(
                id: id.rawValue,
                icon: id.icon,
                name: id.displayName,
                isConnected: deviceSet.contains(id),
                color: id.color
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topUserBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                devicesSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                // 数据能力矩阵 (新增)
                capabilitySection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                VStack(spacing: 0) {
                    ForEach(menus) { item in
                        Button {
                            switch item.title {
                            case "专科专家":
                                withAnimation(.easeInOut(duration: 0.25)) { showSpecialists = true }
                            case "数据记录":
                                withAnimation(.easeInOut(duration: 0.25)) { showDataRecord = true }
                            case "Widget 预览":
                                withAnimation(.easeInOut(duration: 0.25)) { showWidgetPreview = true }
                            default: break
                            }
                        } label: {
                            MenuRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 24)

                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                taskSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .sheet(isPresented: $showSpecialists) {
            SpecialistsView(onClose: { showSpecialists = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDataRecord) {
            DataRecordView(onClose: { showDataRecord = false }, deviceSet: deviceSet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWidgetPreview) {
            WidgetPreviewView(onClose: { showWidgetPreview = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: openSpecialists) { _, newValue in
            if newValue { showSpecialists = true; openSpecialists = false }
        }
        .onChange(of: openDataRecord) { _, newValue in
            if newValue { showDataRecord = true; openDataRecord = false }
        }
        .onChange(of: openWidgetPreview) { _, newValue in
            if newValue { showWidgetPreview = true; openWidgetPreview = false }
        }
    }

    // MARK: - 顶部用户栏

    private var topUserBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
                Text("马")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(StickState.walk.accent)
            }
            .frame(width: 48, height: 48)

            Text("xxx")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.navy)

            Spacer()

            // 六边形 (设置)
            Button {} label: {
                Image(systemName: "hexagon")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(Theme.navy)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }

            // 三横线 (关闭)
            Button(action: onClose) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.navy)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    // MARK: - 智能设备

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 副操作
            HStack {
                Text("连接智能设备")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text("\(deviceSet.count) / \(DeviceID.allCases.count) 在线")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.slate)
            }

            VStack(spacing: 0) {
                ForEach(Array(allDevices.enumerated()), id: \.offset) { idx, dev in
                    DeviceRow(device: dev) {
                        toggleDevice(dev.idEnum)
                    }
                    if idx < allDevices.count - 1 {
                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.leading, 54)
                    }
                }
            }
        }
    }

    /// 切换设备连接状态 (iPhone 永远在)
    private func toggleDevice(_ id: DeviceID) {
        if id == .iPhone { return }   // iPhone 不可断开
        withAnimation(.easeInOut(duration: 0.25)) {
            if deviceSet.contains(id) {
                deviceSet.remove(id)
            } else {
                deviceSet.insert(id)
            }
        }
    }

    // MARK: - 数据能力矩阵 (新增)

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("数据能力")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text(capabilityStatusText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(capabilityStatusColor)
            }

            // 已解锁 / 已锁定两组
            VStack(alignment: .leading, spacing: 8) {
                ForEach(MetricCategory.allCases.sorted { $0.order < $1.order }) { cat in
                    capabilityRow(for: cat)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )

            // 推荐解锁
            if !DeviceCapabilities.unlockSuggestions(deviceSet).isEmpty {
                unlockHint
            }
        }
    }

    private func capabilityRow(for cat: MetricCategory) -> some View {
        let metricsInCat = MetricID.allCases.filter { $0.category == cat }
        let unlockedCount = metricsInCat.filter { DeviceCapabilities.unlocked($0, deviceSet: deviceSet) }.count
        let total = metricsInCat.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cat.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Theme.slate)
                Spacer()
                Text("\(unlockedCount)/\(total)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(unlockedCount == total ? StickState.walk.accent : Theme.mist)
            }
            // 类别下的所有 metric
            HStack(spacing: 6) {
                ForEach(metricsInCat) { m in
                    let on = DeviceCapabilities.unlocked(m, deviceSet: deviceSet)
                    CapabilityChip(metric: m, unlocked: on)
                }
            }
        }
    }

    private var unlockHint: some View {
        let suggestions = DeviceCapabilities.unlockSuggestions(deviceSet)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(StickState.walk.accent)
                Text("连接更多设备解锁")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.navy)
            }
            ForEach(Array(suggestions.keys), id: \.self) { dev in
                let metrics = suggestions[dev] ?? []
                Button {
                    toggleDevice(dev)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(dev.color.opacity(0.14))
                            Image(systemName: dev.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(dev.color)
                        }
                        .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dev.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.navy)
                            Text(metrics.map { $0.rawValue }.joined(separator: " · "))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Theme.slate)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("+ \(metrics.count) 项")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(dev.color)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(dev.color)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(dev.color.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var capabilityStatusText: String {
        let summary = DeviceCapabilities.summary(deviceSet: deviceSet)
        let totalOn = summary.reduce(0) { $0 + $1.unlocked }
        let totalAll = summary.reduce(0) { $0 + $1.total }
        return "\(totalOn) / \(totalAll) 项数据"
    }

    private var capabilityStatusColor: Color {
        let summary = DeviceCapabilities.summary(deviceSet: deviceSet)
        let totalOn = summary.reduce(0) { $0 + $1.unlocked }
        let totalAll = summary.reduce(0) { $0 + $1.total }
        if totalOn == totalAll { return StickState.walk.accent }
        if totalOn < totalAll / 2 { return StickState.sleep.accent }
        return StickState.sit.accent
    }

    // MARK: - 健康建议

    private let suggestions: [Suggestion] = [
        Suggestion(icon: "figure.walk",     color: Color(red: 0.30, green: 0.85, blue: 0.50), title: "起身活动",   desc: "已连续坐 2 小时, 建议站起走动 5 分钟"),
        Suggestion(icon: "drop.fill",       color: Color(red: 0.40, green: 0.65, blue: 0.95), title: "补充水分",   desc: "今日饮水量不足 1L, 目标 2L"),
        Suggestion(icon: "moon.zzz.fill",   color: Color(red: 0.55, green: 0.50, blue: 0.85), title: "早睡",       desc: "最佳入睡时间为 22:30"),
    ]

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("健康建议")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.slate)
                Spacer()
                Button {} label: {
                    Text("编辑")
                        .font(.system(size: 14))
                        .foregroundColor(StickState.walk.accent)
                }
            }
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    SuggestionRow(suggestion: s)
                    if idx < suggestions.count - 1 {
                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }
            }

            // 新建
            Button {} label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Theme.slate)
                    Text("新建任务")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.slate)
                }
            }
            .padding(.top, 18)
        }
    }
}

// MARK: - 菜单行

struct MenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}

struct MenuRow: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: item.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Theme.navy)
                .frame(width: 32)
            Text(item.title)
                .font(.system(size: 17))
                .foregroundColor(Theme.navy)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.mist)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - 智能设备

struct Device: Identifiable {
    let id: String
    let icon: String
    let name: String
    let isConnected: Bool
    let color: Color

    var idEnum: DeviceID {
        DeviceID(rawValue: name) ?? .iPhone
    }
}

struct DeviceRow: View {
    let device: Device
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(device.color.opacity(device.isConnected ? 0.14 : 0.05))
                    Image(systemName: device.icon)
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(device.isConnected ? device.color : Theme.mist)
                }
                .frame(width: 32, height: 32)

                // 名称
                Text(device.name)
                    .font(.system(size: 16))
                    .foregroundColor(device.isConnected ? Theme.navy : Theme.mist)

                Spacer()

                // 状态指示 (灰显时还显示 "未连接")
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.isConnected ? device.color : Theme.mist)
                        .frame(width: 6, height: 6)
                    Text(device.isConnected ? "已连接" : "未连接")
                        .font(.system(size: 12))
                        .foregroundColor(device.isConnected ? Theme.slate : Theme.mist)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(device.name == DeviceID.iPhone.rawValue)   // iPhone 不可断开
        .opacity(device.name == DeviceID.iPhone.rawValue ? 0.6 : 1.0)
    }
}

// MARK: - 能力矩阵 chip

private struct CapabilityChip: View {
    let metric: MetricID
    let unlocked: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: unlocked ? metric.icon : "lock.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(metric.rawValue)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(unlocked ? StickState.walk.accentSoft : Theme.mist.opacity(0.12))
        )
        .foregroundColor(unlocked ? Theme.navy : Theme.mist)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(unlocked ? Color.clear : Theme.mist.opacity(0.35),
                        style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        )
    }
}

#Preview {
    PersonalView(
        onClose: {},
        openSpecialists: .constant(false),
        openDataRecord: .constant(false),
        openWidgetPreview: .constant(false),
        deviceSet: .constant([.iPhone])
    )
}

// MARK: - 专科专家列表

struct Specialist: Identifiable {
    let id = UUID()
    let name: String        // 姓氏
    let title: String       // 职称
    let dept: String        // 科室
    let hospital: String    // 医院
    let avatarColor: Color  // 头像背景色
    let avatarChar: String  // 头像文字
}

struct SpecialistsView: View {
    var onClose: () -> Void

    // 各专科名医 (假数据)
    private let specialists: [Specialist] = [
        Specialist(name: "李",  title: "主任医师",  dept: "心血管内科",   hospital: "北京协和医院",   avatarColor: Color(red: 0.30, green: 0.55, blue: 0.85), avatarChar: "李"),
        Specialist(name: "王",  title: "副主任医师", dept: "神经内科",     hospital: "北京天坛医院",   avatarColor: Color(red: 0.85, green: 0.45, blue: 0.55), avatarChar: "王"),
        Specialist(name: "张",  title: "主任医师",  dept: "骨科",         hospital: "北京积水潭医院", avatarColor: Color(red: 0.45, green: 0.65, blue: 0.50), avatarChar: "张"),
        Specialist(name: "陈",  title: "副主任医师", dept: "消化内科",     hospital: "上海瑞金医院",   avatarColor: Color(red: 0.85, green: 0.65, blue: 0.30), avatarChar: "陈"),
        Specialist(name: "刘",  title: "主任医师",  dept: "呼吸内科",     hospital: "广州呼吸健康研究院", avatarColor: Color(red: 0.60, green: 0.45, blue: 0.75), avatarChar: "刘"),
        Specialist(name: "赵",  title: "主任医师",  dept: "内分泌科",     hospital: "北京 301 医院",   avatarColor: Color(red: 0.40, green: 0.65, blue: 0.70), avatarChar: "赵"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(specialists) { s in
                            SpecialistRow(specialist: s)
                            Rectangle()
                                .fill(Theme.borderSoft)
                                .frame(height: 0.5)
                                .padding(.leading, 76)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("专科专家")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.navy)
                Text("\(specialists.count) 位名医 · 点击查看详情")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
            }
        }
    }
}

struct SpecialistRow: View {
    let specialist: Specialist

    var body: some View {
        Button {} label: {
            HStack(spacing: 16) {
                // 头像 (圆形 + 姓氏 + 彩色背景)
                ZStack {
                    Circle().fill(specialist.avatarColor)
                    Text(specialist.avatarChar)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 52, height: 52)

                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(specialist.name + "医生")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.navy)
                        Text("·")
                            .foregroundColor(Theme.mist)
                        Text(specialist.title)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.slate)
                    }
                    Text(specialist.dept)
                        .font(.system(size: 14))
                        .foregroundColor(StickState.walk.accent)
                    Text(specialist.hospital)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.slate)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.mist)
            }
            .frame(minHeight: 72)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 健康建议

struct Suggestion: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let desc: String
}

struct SuggestionRow: View {
    let suggestion: Suggestion

    var body: some View {
        Button {} label: {
            HStack(spacing: 14) {
                // 图标 (圆角方块 + 彩色淡底)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(suggestion.color.opacity(0.12))
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(suggestion.color)
                }
                .frame(width: 38, height: 38)

                // 文字
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Text(suggestion.desc)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.slate)
                        .lineLimit(2)
                }

                Spacer()
            }
            .frame(minHeight: 56)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

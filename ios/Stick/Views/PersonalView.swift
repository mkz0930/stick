//
//  PersonalView.swift
//  个人面板 (深色) — 复刻参考图
//

import SwiftUI

struct PersonalView: View {
    var onClose: () -> Void
    @Binding var openSpecialists: Bool
    @State private var showSpecialists: Bool = false

    private let menus: [MenuItem] = [
        MenuItem(icon: "clock.arrow.circlepath", title: "数据记录"),
        MenuItem(icon: "person.2",  title: "专科专家"),
    ]

    // 智能设备 (假数据 — 后续接 HealthKit / Bluetooth)
    private let devices: [Device] = [
        Device(icon: "applewatch",   name: "Apple Watch",  status: .connected,  meta: "电量 78%"),
        Device(icon: "earbuds",      name: "AirPods Pro",  status: .connected,  meta: "电量 56%"),
        Device(icon: "scalemass",    name: "小米体重秤",   status: .disconnected, meta: "未连接"),
        Device(icon: "circle.dotted", name: "Oura Ring",  status: .disconnected, meta: "未连接"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topUserBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                devicesSection
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                VStack(spacing: 0) {
                    ForEach(menus) { item in
                        Button {
                            if item.title == "专科专家" {
                                withAnimation(.easeInOut(duration: 0.25)) { showSpecialists = true }
                            }
                        } label: {
                            MenuRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 28)

                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                taskSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSpecialists) {
            SpecialistsView(onClose: { showSpecialists = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: openSpecialists) { _, newValue in
            if newValue { showSpecialists = true; openSpecialists = false }
        }
    }

    // MARK: - 顶部用户栏

    private var topUserBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(white: 0.13))
                Text("马")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.50))
            }
            .frame(width: 48, height: 48)

            Text("马振坤")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // 六边形 (设置)
            Button {} label: {
                Image(systemName: "hexagon")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Color(white: 0.25), lineWidth: 1))
            }

            // 三横线 (关闭)
            Button(action: onClose) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Color(white: 0.25), lineWidth: 1))
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
                    .foregroundColor(.white)
                Spacer()
                Button {} label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.50))
                }
            }

            // 设备列表
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.offset) { idx, dev in
                    DeviceRow(device: dev)
                    if idx < devices.count - 1 {
                        Rectangle()
                            .fill(Color(white: 0.10))
                            .frame(height: 0.5)
                            .padding(.leading, 54)
                    }
                }
            }
        }
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
                    .foregroundColor(Color(white: 0.45))
                Spacer()
                Button {} label: {
                    Text("编辑")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.50))
                }
            }
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    SuggestionRow(suggestion: s)
                    if idx < suggestions.count - 1 {
                        Rectangle()
                            .fill(Color(white: 0.10))
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
                        .foregroundColor(Color(white: 0.55))
                    Text("新建任务")
                        .font(.system(size: 15))
                        .foregroundColor(Color(white: 0.55))
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
                .foregroundColor(.white)
                .frame(width: 32)
            Text(item.title)
                .font(.system(size: 17))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(white: 0.35))
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - 智能设备

struct Device: Identifiable {
    enum Status { case connected, disconnected }

    let id = UUID()
    let icon: String
    let name: String
    let status: Status
    let meta: String
}

struct DeviceRow: View {
    let device: Device

    var body: some View {
        Button {} label: {
            HStack(spacing: 16) {
                // 图标
                Image(systemName: device.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white)
                    .frame(width: 32)

                // 名称
                Text(device.name)
                    .font(.system(size: 16))
                    .foregroundColor(.white)

                Spacer()

                // 状态指示
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(device.meta)
                        .font(.system(size: 12))
                        .foregroundColor(statusMetaColor)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch device.status {
        case .connected:    return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .disconnected: return Color(white: 0.35)
        }
    }

    private var statusMetaColor: Color {
        switch device.status {
        case .connected:    return Color(white: 0.55)
        case .disconnected: return Color(white: 0.40)
        }
    }
}

#Preview {
    PersonalView(onClose: {}, openSpecialists: .constant(false))
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
            Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(specialists) { s in
                            SpecialistRow(specialist: s)
                            Rectangle()
                                .fill(Color(white: 0.10))
                                .frame(height: 0.5)
                                .padding(.leading, 76)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("专科专家")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("\(specialists.count) 位名医 · 点击查看详情")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(white: 0.15)))
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
                            .foregroundColor(.white)
                        Text("·")
                            .foregroundColor(Color(white: 0.35))
                        Text(specialist.title)
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.55))
                    }
                    Text(specialist.dept)
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.50))
                    Text(specialist.hospital)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.45))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(white: 0.35))
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
                // 图标 (圆角方块 + 彩色)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(suggestion.color.opacity(0.18))
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(suggestion.color)
                }
                .frame(width: 38, height: 38)

                // 文字
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(suggestion.desc)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.50))
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

import SwiftUI

@main
struct StickApp: App {
    @State private var deepLinkDestination: DeepLinkDestination?

    var body: some Scene {
        WindowGroup {
            DeepLinkHandler(destination: $deepLinkDestination)
                .onOpenURL { url in
                    if let dest = DeepLinkDestination(url: url) {
                        deepLinkDestination = dest
                    }
                }
        }
    }
}

enum DeepLinkDestination {
    case sedentary           // 久坐风险
    case sedentaryHook      // 腿私信 / 腰演出 钩子卡
    case postWorkoutIceWater // 运动后冰水
    case walking            // WALK 状态卡
    case sitting            // SIT 状态卡
    case sedentaryMood      // 4x2 久坐心情

    init?(url: URL) {
        guard url.scheme == "stick",
              url.host == "science" else {
            return nil
        }
        let key = url.path.replacingOccurrences(of: "/", with: "")
        switch key {
        case "sedentary":      self = .sedentary
        case "sedentaryhook":  self = .sedentaryHook
        case "icewater":      self = .postWorkoutIceWater
        case "walking":        self = .walking
        case "sitting":        self = .sitting
        case "sedentarymood":  self = .sedentaryMood
        default:               return nil
        }
    }
}

struct DeepLinkHandler: View {
    @Binding var destination: DeepLinkDestination?
    @State private var showSheet = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()
            if let dest = destination {
                ScienceView(destination: dest, onDismiss: { destination = nil })
            } else {
                ContentView()
            }
        }
        .onChange(of: destination) { _, newValue in
            showSheet = (newValue != nil)
        }
    }
}

struct ScienceView: View {
    let destination: DeepLinkDestination
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch destination {
            case .sedentary:
                SedentaryScienceView()
            case .sedentaryHook:
                SedentaryScienceView()
            case .postWorkoutIceWater:
                PostWorkoutIceWaterScienceView()
            case .walking:
                WalkingScienceView()
            case .sitting:
                SittingScienceView()
            case .sedentaryMood:
                SedentaryMoodScienceView()
            }
        }
        .preferredColorScheme(.light)
        .statusBarHidden(false)
        .overlay(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .padding(16)
        }
    }
}

import SwiftUI

@main
struct StickApp: App {
    @State private var pendingChatSeed: String? = nil

    var body: some Scene {
        WindowGroup {
            ContentView(pendingChatSeed: $pendingChatSeed)
                .onOpenURL { url in
                    StickWidgetURLRouter.route(url, setChatSeed: { pendingChatSeed = $0 })
                }
        }
    }
}

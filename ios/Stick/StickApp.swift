import SwiftUI

@main
struct StickApp: App {
    var body: some Scene {
        WindowGroup {
            // Debug: launch with `-widget-gallery 1` to open widget gallery directly
            // Debug: launch with `-sedentary-science 1` to open science view
            // Debug: launch with `-chat-history-demo 1` to preview expandable history
            if CommandLine.arguments.contains("-chat-history-demo") {
                ChatHistoryDemoView()
                    .preferredColorScheme(.light)
                    .statusBarHidden(false)
            } else if CommandLine.arguments.contains("-sedentary-science") {
                SedentaryScienceView()
                    .preferredColorScheme(.light)
                    .statusBarHidden(false)
            } else if CommandLine.arguments.contains("-widget-gallery") {
                AnyView(Text("Widget Gallery (disabled)"))
                    .preferredColorScheme(.light)
                    .statusBarHidden(false)
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
                    .statusBarHidden(false)
            }
        }
    }
}

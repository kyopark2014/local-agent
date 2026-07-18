import SwiftUI

@main
struct LocalAgentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Seyeon") {
            GeometryReader { proxy in
                let scale = appState.uiScale
                RootView()
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
                    .frame(
                        width: proxy.size.width / scale,
                        height: proxy.size.height / scale
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    Task { await appState.createTask() }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Button("Zoom In") {
                    appState.zoomIn()
                }
                .keyboardShortcut("=", modifiers: [.command])
                Button("Zoom In ") {
                    appState.zoomIn()
                }
                .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") {
                    appState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") {
                    appState.resetZoom()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(appState)
                .frame(width: 420, height: 280)
        }
    }
}

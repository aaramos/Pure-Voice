import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PureVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        } label: {
            Label("Pure Voice", systemImage: state.stageIconName)
        }

        WindowGroup("Pure Voice") {
            MainWindowView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        }
        .defaultSize(width: 620, height: 640)

        Window("Pure Voice HUD", id: "hud") {
            HUDView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        }
        .defaultSize(width: 360, height: 220)

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 560, height: 520)
                .task { await state.loadIfNeeded() }
        }
    }
}

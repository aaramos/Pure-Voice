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
    @StateObject private var state: AppState

    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        Task { @MainActor in
            await appState.loadIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        } label: {
            if state.stage == .recording {
                MenuBarIconView(isRecording: true)
            } else {
                Label("Pure Voice", systemImage: "mic.fill")
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Pure Voice")
            }
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
                .frame(
                    minWidth: 560,
                    idealWidth: 820,
                    maxWidth: .infinity,
                    minHeight: 520,
                    idealHeight: 760,
                    maxHeight: .infinity
                )
                .task { await state.loadIfNeeded() }
        }
    }
}

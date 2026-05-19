import AppKit
import SwiftUI

@MainActor
private enum AppModel {
    static let state = AppState()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [weak self] in
            _ = self
            let appState = AppModel.state
            appState.openOnboardingIfNeeded()
            await appState.loadIfNeeded()
            appState.openOnboardingIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AppModel.state.openOnboardingIfNeeded()
        }
    }
}

@main
struct PureVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    init() {
        AppState.migrateOnboardingSentinelIfNeeded()
        let appState = AppModel.state
        _state = StateObject(wrappedValue: appState)
        Task { @MainActor in
            appState.openOnboardingIfNeeded()
            await appState.loadIfNeeded()
            appState.openOnboardingIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup("Pure Voice") {
            MainWindowView()
                .environmentObject(state)
                .task {
                    state.openOnboardingIfNeeded()
                    await state.loadIfNeeded()
                    state.openOnboardingIfNeeded()
                }
        }
        .defaultSize(width: 620, height: 640)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    state.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

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

        Window("Pure Voice HUD", id: "hud") {
            HUDView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        }
        .defaultSize(width: 360, height: 220)
    }
}

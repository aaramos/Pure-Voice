import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.demoteIfNoUserFacingWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }

    static func promoteForUserFacingWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func demoteIfNoUserFacingWindows() {
        let hasVisibleUserFacingWindow = NSApp.windows.contains { window in
            window.isVisible
                && !(window is NSPanel)
                && window.canBecomeMain
                && !window.className.contains("NSStatus")
        }

        if !hasVisibleUserFacingWindow {
            NSApp.setActivationPolicy(.accessory)
        }
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
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Pure Voice HUD", id: "hud") {
            HUDView()
                .environmentObject(state)
                .task { await state.loadIfNeeded() }
        }
        .defaultSize(width: 360, height: 220)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 560, height: 520)
                .task { await state.loadIfNeeded() }
        }
    }
}

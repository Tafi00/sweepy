import AppKit
import SwiftUI
import UserNotifications

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--auto") || args.contains("--scan") || args.contains("--check-path") {
            CLI.run(args)
            exit(0)
        }
        SweepyApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by views that can open the main window (SwiftUI's openWindow isn't reachable from here).
    static var openMainWindow: (() -> Void)?
    /// True once the user picked "Thoát Sweepy" (or an update restarts the app).
    static var reallyQuit = false

    static func quit() {
        reallyQuit = true
        NSApp.terminate(nil)
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    static var hasVisibleMainWindow: Bool {
        NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Logout, shutdown, `osascript quit`, Dock → Quit arrive as a quit Apple event: always honour those.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let fromAppleEvent = event?.eventClass == kCoreEventClass && event?.eventID == kAEQuitApplication
        guard !AppDelegate.reallyQuit, !fromAppleEvent, Store.loadConfig().keepInMenuBar else { return .terminateNow }
        // ⌘Q: keep running in the menu bar.
        for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain { window.close() }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.showMainWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Last window closed → drop the Dock icon, stay in the menu bar.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, !(window is NSPanel), window.canBecomeMain else { return }
            DispatchQueue.main.async {
                if !AppDelegate.hasVisibleMainWindow && Store.loadConfig().keepInMenuBar {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = self
            Notifier.requestAuthorization()
        }
        // Opened at login: stay quietly in the menu bar.
        let atLogin = LoginItem.launchedAtLogin
        let afterUpdate = CommandLine.arguments.contains("--updated-in-background")
        if afterUpdate || (atLogin && Store.loadConfig().hideWindowAtLogin && LoginItem.isEnabled) {
            DispatchQueue.main.async {
                for window in NSApp.windows where !(window is NSPanel) { window.close() }
            }
        }
        if let dir = ProcessInfo.processInfo.environment["SWEEPY_SNAPSHOT_DIR"] {
            Snapshotter.run(into: dir)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct SweepyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Sweepy", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quét lại") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.busy)
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

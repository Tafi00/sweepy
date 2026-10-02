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
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = self
            Notifier.requestAuthorization()
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

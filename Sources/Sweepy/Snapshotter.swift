import AppKit

/// Debug aid: SWEEPY_SNAPSHOT_DIR=/path renders each screen of the main window to PNG, then quits.
@MainActor
enum Snapshotter {
    static let screens: [(String, SidebarItem)] = [
        ("overview", .overview), ("projects", .category(.projects)), ("apps", .category(.apps)),
        ("browsers", .category(.browsers)), ("settings", .settings),
    ]

    static func run(into dir: String) {
        Task { @MainActor in
            while AppModel.shared?.isScanning != false || AppModel.shared?.scans.isEmpty == true {
                try? await Task.sleep(for: .seconds(1))
            }
            try? await Task.sleep(for: .seconds(1))
            for (name, item) in screens {
                AppModel.shared?.sidebar = item
                try? await Task.sleep(for: .seconds(1.5))
                capture(to: "\(dir)/\(name).png")
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.frame.width > 500 }),
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                  [.boundsIgnoreFraming, .bestResolution]) else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }
}

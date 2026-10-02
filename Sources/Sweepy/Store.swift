import Foundation
import UserNotifications

enum Store {
    /// SWEEPY_CONFIG_DIR lets tests use a throwaway config.
    static let directory: URL = {
        if let custom = ProcessInfo.processInfo.environment["SWEEPY_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: PathUtil.expand(custom))
        }
        return URL(fileURLWithPath: PathUtil.expand("~/Library/Application Support/Sweepy"))
    }()

    static var configURL: URL { directory.appendingPathComponent("config.json") }
    static var historyURL: URL { directory.appendingPathComponent("history.json") }
    static var logURL: URL {
        if ProcessInfo.processInfo.environment["SWEEPY_CONFIG_DIR"] != nil { return directory.appendingPathComponent("auto.log") }
        return URL(fileURLWithPath: PathUtil.expand("~/Library/Logs/Sweepy/auto.log"))
    }

    static func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        return config
    }

    static func save(_ config: AppConfig) {
        write(config, to: configURL)
    }

    static func loadHistory() -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: historyURL),
              let entries = try? decoder.decode([HistoryEntry].self, from: data) else { return [] }
        return entries
    }

    static func append(_ entry: HistoryEntry) {
        var entries = loadHistory()
        entries.append(entry)
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
        write(entries, to: historyURL)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log("Không ghi được \(url.path): \(error.localizedDescription)")
        }
    }

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// Installs a per-user LaunchAgent that runs `Sweepy --auto` on the chosen schedule.
enum Scheduler {
    static let label = "local.sweepy.autoclean"
    static var plistURL: URL { URL(fileURLWithPath: PathUtil.expand("~/Library/LaunchAgents/\(label).plist")) }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static var executablePath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    /// The LaunchAgent stores an absolute path, so the app must live somewhere permanent.
    static var appLocationWarning: String? {
        let bundle = Bundle.main.bundlePath
        guard bundle.hasSuffix(".app") else { return "Đang chạy ngoài gói .app – hãy chạy bản Sweepy.app đã build." }
        if bundle.hasPrefix("/Applications/") || bundle.hasPrefix(PathUtil.expand("~/Applications") + "/") { return nil }
        return "Sweepy đang chạy từ \(PathUtil.abbreviate(bundle)). Hãy chuyển app vào thư mục Applications trước khi bật lịch, nếu không lịch sẽ hỏng khi bạn di chuyển hoặc xoá thư mục này."
    }

    static func plist(for schedule: Schedule) -> [String: Any] {
        var interval: [String: Int] = ["Hour": schedule.hour, "Minute": schedule.minute]
        switch schedule.frequency {
        case .weekly: interval["Weekday"] = schedule.weekday
        case .monthly: interval["Day"] = schedule.dayOfMonth
        default: break
        }
        return [
            "Label": label,
            "ProgramArguments": [executablePath, "--auto"],
            "StartCalendarInterval": interval,
            "StandardOutPath": Store.logURL.path,
            "StandardErrorPath": Store.logURL.path,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
        ]
    }

    /// Installs, updates or removes the LaunchAgent. Returns an error message on failure.
    @discardableResult
    static func apply(_ schedule: Schedule) -> String? {
        let domain = "gui/\(getuid())"
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        if schedule.frequency == .off {
            try? FileManager.default.removeItem(at: plistURL)
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist(for: schedule), format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return "Không ghi được LaunchAgent: \(error.localizedDescription)"
        }
        let res = Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path], mergeStderr: true)
        return res.status == 0 ? nil : "launchctl bootstrap lỗi (\(res.status)): \(res.output)"
    }
}

enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a notification and waits briefly so a short-lived `--auto` process can deliver it.
    static func post(title: String, body: String, wait: Bool = false) {
        guard available else { print("\(title): \(body)"); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in done.signal() }
        if wait { _ = done.wait(timeout: .now() + 5) }
    }
}

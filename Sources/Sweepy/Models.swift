import Foundation
import SwiftUI

// MARK: - Rule

enum RuleCategory: String, Codable, CaseIterable, Identifiable {
    case projects, devTools, browsers, apps, system, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Dự án lập trình"
        case .devTools: return "Công cụ dev"
        case .browsers: return "Trình duyệt"
        case .apps: return "Ứng dụng & chat"
        case .system: return "Hệ thống & Tải về"
        case .custom: return "Tuỳ chỉnh"
        }
    }

    var subtitle: String {
        switch self {
        case .projects: return "Thư mục build và thư viện có thể tạo lại trong các dự án code."
        case .devTools: return "Cache của Xcode, npm, Gradle, Homebrew… tự tải lại khi cần."
        case .browsers: return "Cache trang web. Không đụng tới mật khẩu, lịch sử hay cookie."
        case .apps: return "Cache và media đã tải của Zalo, Telegram, Discord và các app Electron."
        case .system: return "Log cũ, cache ứng dụng bỏ không, file cài đặt trong Downloads, Thùng rác."
        case .custom: return "Quy tắc do bạn tự tạo."
        }
    }

    var symbol: String {
        switch self {
        case .projects: return "hammer"
        case .devTools: return "shippingbox"
        case .browsers: return "globe"
        case .apps: return "bubble.left.and.bubble.right"
        case .system: return "gearshape.2"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum Safety: String, Codable, CaseIterable {
    case safe, moderate, review

    var title: String {
        switch self {
        case .safe: return "An toàn"
        case .moderate: return "Cần tải lại"
        case .review: return "Nên xem trước"
        }
    }

    var help: String {
        switch self {
        case .safe: return "Cache tự tạo lại, xoá không mất dữ liệu."
        case .moderate: return "Xoá được, nhưng lần sau phải cài/tải/biên dịch lại nên sẽ chậm hơn."
        case .review: return "Có thể chứa file của bạn. Hãy xem danh sách trước khi xoá."
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .moderate: return .orange
        case .review: return .red
        }
    }
}

enum RuleKind: String, Codable, CaseIterable, Identifiable {
    /// Each child of the matched directories is one item.
    case contents
    /// Each matched path (glob) is one item.
    case paths
    /// Folders with a given name found inside the project roots.
    case projectFolders
    /// A shell command (e.g. `brew cleanup`).
    case command
    /// Big files not opened for a long time, inside the project roots and `paths`.
    case largeFiles
    /// Containers / data left behind by apps that are no longer installed.
    case orphanData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contents: return "Nội dung bên trong thư mục"
        case .paths: return "Đường dẫn cụ thể (hỗ trợ *)"
        case .projectFolders: return "Thư mục tên X trong dự án"
        case .command: return "Chạy lệnh shell"
        case .largeFiles: return "File lớn lâu không mở"
        case .orphanData: return "Dữ liệu của app đã gỡ"
        }
    }
}

enum DeleteMode: String, Codable, CaseIterable, Identifiable {
    case permanent, trash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .permanent: return "Xoá vĩnh viễn"
        case .trash: return "Chuyển vào Thùng rác"
        }
    }
}

enum AgeBasis: String, Codable {
    /// Newest modification time found inside the item.
    case modified
    /// Date the item was added to its folder (download date, date trashed).
    case added
    /// Last opened (access time, or modification if later).
    case accessed
}

struct Rule: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var detail: String = ""
    var category: RuleCategory
    var safety: Safety = .safe
    var kind: RuleKind
    var paths: [String] = []
    var folderNames: [String] = []
    /// projectFolders: the parent folder must contain one of these (fnmatch patterns).
    var markers: [String] = []
    /// projectFolders: the matched folder must contain one of these.
    var markersInside: [String] = []
    /// Child names to ignore (fnmatch patterns).
    var excludeNames: [String] = []
    /// Only items with these extensions (lowercase, no dot). Empty = everything.
    var extensions: [String] = []
    /// projectFolders: the project must be untouched for this many days.
    var minIdleDays: Int = 0
    /// Only items older than this many days. 0 = everything.
    var olderThanDays: Int = 0
    var ageBasis: AgeBasis = .modified
    var command: String = ""
    /// Bundle IDs (contain a dot) or process names that must not be running.
    var skipIfRunning: [String] = []
    var onlyWhenAppClosed: Bool = true
    /// projectFolders: skip a project while a process is running from it (dev server…).
    var skipIfProjectRunning: Bool = false
    var deleteMode: DeleteMode = .permanent
    var autoClean: Bool = false
    var builtIn: Bool = true
    /// projectFolders: clean this path inside the matched folder instead (e.g. node_modules/.cache).
    var subpath: String = ""
    /// Keep the N most recent items of each folder (old app/tool versions).
    var keepNewest: Int = 0
    /// largeFiles: minimum size in MB.
    var minSizeMB: Int = 0
    /// Skip items a running process was launched from.
    var skipIfInUse: Bool = false
    /// contents/paths: only items whose name matches one of these (fnmatch, Unicode-normalized).
    var includeNames: [String] = []
}

extension Rule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        category = try c.decodeIfPresent(RuleCategory.self, forKey: .category) ?? .custom
        safety = try c.decodeIfPresent(Safety.self, forKey: .safety) ?? .safe
        kind = try c.decodeIfPresent(RuleKind.self, forKey: .kind) ?? .contents
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? []
        folderNames = try c.decodeIfPresent([String].self, forKey: .folderNames) ?? []
        markers = try c.decodeIfPresent([String].self, forKey: .markers) ?? []
        markersInside = try c.decodeIfPresent([String].self, forKey: .markersInside) ?? []
        excludeNames = try c.decodeIfPresent([String].self, forKey: .excludeNames) ?? []
        extensions = try c.decodeIfPresent([String].self, forKey: .extensions) ?? []
        minIdleDays = try c.decodeIfPresent(Int.self, forKey: .minIdleDays) ?? 0
        olderThanDays = try c.decodeIfPresent(Int.self, forKey: .olderThanDays) ?? 0
        ageBasis = try c.decodeIfPresent(AgeBasis.self, forKey: .ageBasis) ?? .modified
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        skipIfRunning = try c.decodeIfPresent([String].self, forKey: .skipIfRunning) ?? []
        onlyWhenAppClosed = try c.decodeIfPresent(Bool.self, forKey: .onlyWhenAppClosed) ?? true
        skipIfProjectRunning = try c.decodeIfPresent(Bool.self, forKey: .skipIfProjectRunning) ?? false
        deleteMode = try c.decodeIfPresent(DeleteMode.self, forKey: .deleteMode) ?? .permanent
        autoClean = try c.decodeIfPresent(Bool.self, forKey: .autoClean) ?? false
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
        subpath = try c.decodeIfPresent(String.self, forKey: .subpath) ?? ""
        keepNewest = try c.decodeIfPresent(Int.self, forKey: .keepNewest) ?? 0
        minSizeMB = try c.decodeIfPresent(Int.self, forKey: .minSizeMB) ?? 0
        skipIfInUse = try c.decodeIfPresent(Bool.self, forKey: .skipIfInUse) ?? false
        includeNames = try c.decodeIfPresent([String].self, forKey: .includeNames) ?? []
    }
}

/// User changes to a built-in rule. Built-in definitions live in code so they can improve over time.
struct RuleOverride: Codable, Hashable {
    var autoClean: Bool?
    var deleteMode: DeleteMode?
    var olderThanDays: Int?
    var minIdleDays: Int?
    var onlyWhenAppClosed: Bool?
    var keepNewest: Int?
    var minSizeMB: Int?

    var isEmpty: Bool {
        autoClean == nil && deleteMode == nil && olderThanDays == nil && minIdleDays == nil && onlyWhenAppClosed == nil
            && keepNewest == nil && minSizeMB == nil
    }

    func apply(to rule: Rule) -> Rule {
        var r = rule
        if let v = autoClean { r.autoClean = v }
        if let v = deleteMode { r.deleteMode = v }
        if let v = olderThanDays { r.olderThanDays = v }
        if let v = minIdleDays { r.minIdleDays = v }
        if let v = onlyWhenAppClosed { r.onlyWhenAppClosed = v }
        if let v = keepNewest { r.keepNewest = v }
        if let v = minSizeMB { r.minSizeMB = v }
        return r
    }

    static func diff(base: Rule, edited: Rule) -> RuleOverride {
        RuleOverride(
            autoClean: base.autoClean == edited.autoClean ? nil : edited.autoClean,
            deleteMode: base.deleteMode == edited.deleteMode ? nil : edited.deleteMode,
            olderThanDays: base.olderThanDays == edited.olderThanDays ? nil : edited.olderThanDays,
            minIdleDays: base.minIdleDays == edited.minIdleDays ? nil : edited.minIdleDays,
            onlyWhenAppClosed: base.onlyWhenAppClosed == edited.onlyWhenAppClosed ? nil : edited.onlyWhenAppClosed,
            keepNewest: base.keepNewest == edited.keepNewest ? nil : edited.keepNewest,
            minSizeMB: base.minSizeMB == edited.minSizeMB ? nil : edited.minSizeMB
        )
    }
}

// MARK: - Config

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case off, hourly, daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Tắt"
        case .hourly: return "Mỗi vài giờ"
        case .daily: return "Hằng ngày"
        case .weekly: return "Hằng tuần"
        case .monthly: return "Hằng tháng"
        }
    }
}

struct Schedule: Codable, Hashable {
    var frequency: Frequency = .off
    var hour: Int = 12
    var minute: Int = 30
    /// launchd weekday: 0 = Sunday … 6 = Saturday.
    var weekday: Int = 1
    var dayOfMonth: Int = 1
    /// hourly: run every N hours.
    var intervalHours: Int = 2

    static let intervalChoices = [1, 2, 3, 4, 6, 8, 12]

    static let weekdayNames = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch frequency {
        case .off: return "Chưa bật"
        case .hourly: return intervalHours == 1 ? "Mỗi giờ" : "Mỗi \(intervalHours) giờ"
        case .daily: return "Mỗi ngày lúc \(time)"
        case .weekly: return "\(Schedule.weekdayNames[max(0, min(6, weekday))]) hằng tuần lúc \(time)"
        case .monthly: return "Ngày \(dayOfMonth) hằng tháng lúc \(time)"
        }
    }
}

extension Schedule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try c.decodeIfPresent(Frequency.self, forKey: .frequency) ?? .off
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 12
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 30
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1
        dayOfMonth = try c.decodeIfPresent(Int.self, forKey: .dayOfMonth) ?? 1
        intervalHours = try c.decodeIfPresent(Int.self, forKey: .intervalHours) ?? 2
    }
}

struct AppConfig: Codable {
    var projectRoots: [String] = AppConfig.defaultProjectRoots()
    var exclusions: [String] = []
    var schedule = Schedule()
    /// Auto runs only clean when free space is below this many GB. 0 = always.
    var minFreeGB: Int = 0
    var notify: Bool = true
    /// When macOS opens Sweepy at login, stay in the menu bar instead of showing the window.
    var hideWindowAtLogin: Bool = true
    var overrides: [String: RuleOverride] = [:]
    var customRules: [Rule] = []

    static func defaultProjectRoots() -> [String] {
        let fm = FileManager.default
        // SDK/toolchain folders hold packages too, but are not projects to clean.
        let skip: Set<String> = ["Library", "Applications", "Music", "Movies", "Pictures", "Public", "Sites",
                                 "fvm", "flutter", "go", "sdk", "Android", "android-sdk", "anaconda3", "miniconda3",
                                 "miniforge3", "opt", "bin"]
        var roots = ["~/Desktop", "~/Documents", "~/Downloads", "~/Developer", "~/Projects", "~/Code", "~/dev"]
        // Also any top-level home folder that holds code (a git repo or package within two levels).
        let markers = [".git", "package.json", "pubspec.yaml", "Package.swift", "build.gradle", "Cargo.toml", "pyproject.toml"]
        for name in (try? fm.contentsOfDirectory(atPath: PathUtil.home)) ?? [] where !name.hasPrefix(".") && !skip.contains(name) {
            let dir = PathUtil.home + "/" + name
            guard PathUtil.isDirectory(dir), !roots.contains("~/" + name) else { continue }
            let level1 = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            let hasCode = level1.contains { child in
                markers.contains(child) || markers.contains { fm.fileExists(atPath: "\(dir)/\(child)/\($0)") }
                    || ((try? fm.contentsOfDirectory(atPath: "\(dir)/\(child)")) ?? []).contains { grand in
                        markers.contains { fm.fileExists(atPath: "\(dir)/\(child)/\(grand)/\($0)") }
                    }
            }
            if hasCode { roots.append("~/" + name) }
        }
        var seen = Set<String>()
        return roots.filter { path in
            let expanded = PathUtil.expand(path)
            guard PathUtil.isDirectory(expanded) else { return false }
            // ~/code and ~/Code are the same folder on a case-insensitive volume.
            return seen.insert(expanded.lowercased()).inserted
        }
    }

    func effectiveRules() -> [Rule] {
        let builtIns = DefaultRules.all.map { rule in overrides[rule.id]?.apply(to: rule) ?? rule }
        return builtIns + customRules
    }
}

extension AppConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectRoots = try c.decodeIfPresent([String].self, forKey: .projectRoots) ?? AppConfig.defaultProjectRoots()
        exclusions = try c.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
        minFreeGB = try c.decodeIfPresent(Int.self, forKey: .minFreeGB) ?? 0
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        hideWindowAtLogin = try c.decodeIfPresent(Bool.self, forKey: .hideWindowAtLogin) ?? true
        overrides = try c.decodeIfPresent([String: RuleOverride].self, forKey: .overrides) ?? [:]
        customRules = try c.decodeIfPresent([Rule].self, forKey: .customRules) ?? []
    }
}

// MARK: - Scan & history

struct ScanItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let date: Date?
    var note: String?
}

struct RuleScan: Identifiable {
    var id: String { ruleID }
    let ruleID: String
    var items: [ScanItem] = []
    var blockedBy: String?
    var notes: [String] = []
    /// False when none of the rule's paths exist on this Mac (the app isn't installed…).
    var applicable = false
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum Trigger: String, Codable {
    case manual, auto
    var title: String { self == .auto ? "Tự động" : "Thủ công" }
}

struct RuleOutcome: Codable, Hashable, Identifiable {
    var id: String { ruleID }
    var ruleID: String
    var ruleName: String
    var freed: Int64 = 0
    var itemCount: Int = 0
    var errors: [String] = []
    var skipped: String?
    var output: String?
}

struct HistoryEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var trigger: Trigger
    var freed: Int64
    var freeBefore: Int64
    var freeAfter: Int64
    var outcomes: [RuleOutcome]
    var note: String?
}

struct DiskStatus {
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskStatus {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let important = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values?.volumeAvailableCapacity ?? 0)
        return DiskStatus(total: total, available: important > 0 ? important : plain)
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        n <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func age(_ date: Date?) -> String {
        guard let date else { return "" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days <= 0 { return "hôm nay" }
        if days < 60 { return "\(days) ngày" }
        if days < 730 { return "\(days / 30) tháng" }
        return "\(days / 365) năm"
    }

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()
}

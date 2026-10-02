import AppKit
import Foundation
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case category(RuleCategory)
    case history
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig
    @Published var scans: [String: RuleScan] = [:]
    @Published var history: [HistoryEntry]
    @Published var disk = DiskStatus.current()
    @Published var sidebar: SidebarItem? = .overview

    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var lastScan: Date?

    /// Rules ticked for the next manual clean.
    @Published var selected: Set<String> = []
    /// Individual items unticked for the next manual clean.
    @Published var unticked: Set<String> = []
    @Published var pendingClean: [String]?
    @Published var lastResult: HistoryEntry?
    @Published var scheduleError: String?
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var loginItemMessage: String?

    let updater = Updater()

    static weak var shared: AppModel?

    init() {
        config = Store.loadConfig()
        history = Store.loadHistory()
        selected = Set(config.effectiveRules().filter(\.autoClean).map(\.id))
        AppModel.shared = self
        updater.start(enabled: config.autoUpdate)
        Scheduler.repairIfMoved(config.schedule)
        // Quitting Xcode/Chrome should unlock its rules without a full rescan.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared?.refreshBlocked() }
            }
        }
        // Command-line tools (gradle daemons…) don't post workspace notifications; recheck when the window comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared?.refreshBlocked() }
        }
    }

    func refreshBlocked() {
        let rules = self.rules.filter(\.onlyWhenAppClosed)
        Task.detached(priority: .utility) {
            let processes = ProcessSnapshot.capture(includeProjectInfo: false)
            let blocked = rules.map { ($0.id, processes.runningName(among: $0.skipIfRunning)) }
            await MainActor.run {
                for (id, name) in blocked where self.scans[id] != nil && self.scans[id]?.blockedBy != name {
                    self.scans[id]?.blockedBy = name
                }
            }
        }
    }

    var busy: Bool { isScanning || isCleaning }
    var rules: [Rule] { config.effectiveRules() }

    func rules(in category: RuleCategory) -> [Rule] {
        rules.filter { rule in
            guard rule.category == category else { return false }
            // Hide built-in rules for apps/tools that don't exist on this Mac.
            guard rule.builtIn, let scan = scans[rule.id] else { return true }
            return scan.applicable || !scan.items.isEmpty
        }
    }

    func hiddenCount(in category: RuleCategory) -> Int {
        rules.filter { $0.category == category && $0.builtIn }.count - rules(in: category).filter(\.builtIn).count
    }

    func size(of ruleID: String) -> Int64 {
        guard let scan = scans[ruleID] else { return 0 }
        return scan.items.filter { !unticked.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    func size(of category: RuleCategory) -> Int64 {
        uniqueTotal(rules.filter { $0.category == category }.map(\.id))
    }

    /// Items of several rules with overlaps removed (a folder counts once even if a broader rule covers it too).
    func uniqueItems(_ ruleIDs: [String], respectUnticked: Bool = false) -> [(ruleID: String, item: ScanItem)] {
        let all = ruleIDs.flatMap { id in (scans[id]?.items ?? []).map { (ruleID: id, item: $0) } }
            .filter { !respectUnticked || !unticked.contains($0.item.path) }
            .sorted { $0.item.path < $1.item.path }
        var out: [(ruleID: String, item: ScanItem)] = []
        for entry in all {
            if let last = out.last, PathUtil.isUnder(entry.item.path, last.item.path) { continue }
            out.append(entry)
        }
        return out
    }

    private func uniqueTotal(_ ids: [String], respectUnticked: Bool = false) -> Int64 {
        uniqueItems(ids, respectUnticked: respectUnticked).reduce(0) { $0 + $1.item.size }
    }

    /// Rules whose app is open right now; cleaning skips them, so they must not count as cleanable.
    func isBlocked(_ ruleID: String) -> Bool { scans[ruleID]?.blockedBy != nil }

    /// What cleaning `ids` would actually free right now.
    func cleanableTotal(_ ids: [String]) -> Int64 {
        uniqueTotal(ids.filter { !isBlocked($0) }, respectUnticked: true)
    }

    var totalFound: Int64 { uniqueTotal(rules.map(\.id)) }
    var selectedTotal: Int64 { cleanableTotal(Array(selected)) }
    var autoTotal: Int64 { uniqueTotal(rules.filter { $0.autoClean && !isBlocked($0.id) }.map(\.id)) }

    /// Selected size held back by running apps, and which apps.
    var waitingTotal: Int64 { uniqueTotal(selected.filter(isBlocked), respectUnticked: true) }
    var waitingApps: [String] {
        Set(selected.compactMap { id in size(of: id) > 0 ? scans[id]?.blockedBy : nil }).sorted()
    }

    /// Everything found that is neither cleanable now nor waiting on an app, so the three parts add up to `totalFound`.
    var unselectedTotal: Int64 { max(0, totalFound - selectedTotal - waitingTotal) }

    // MARK: Quitting apps that hold files open

    /// Apps never quit on the user's behalf: Sweepy itself, and Finder (relaunches, owns the desktop).
    static let neverQuit: Set<String> = ["local.sweepy.app", "com.apple.finder"]

    /// Running GUI apps that keep the given rules from being cleaned.
    func blockingApps(_ ids: [String]) -> [NSRunningApplication] {
        let wanted = Set(rules.filter { ids.contains($0.id) && isBlocked($0.id) && size(of: $0.id) > 0 }
            .flatMap(\.skipIfRunning).filter { $0.contains(".") })
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return wanted.contains(id) && !AppModel.neverQuit.contains(id)
        }
    }

    /// Blocked rules held back only by command-line processes, which Sweepy does not kill.
    func blockedByProcesses(_ ids: [String]) -> [String] {
        let apps = Set(blockingApps(ids).compactMap(\.localizedName))
        return Set(ids.compactMap { scans[$0]?.blockedBy }).subtracting(apps).sorted()
    }

    /// Rule IDs waiting for the user to confirm quitting their apps.
    @Published var quitRequest: [String]?
    @Published var lastError: String?

    /// Asks the blocking apps to quit normally (they may prompt to save), then cleans the rules.
    func quitAppsAndClean(_ ids: [String]) {
        guard !busy else { return }
        let apps = blockingApps(ids)
        let names = apps.compactMap(\.localizedName).joined(separator: ", ")
        apps.forEach { $0.terminate() }
        isCleaning = true
        status = "Đang chờ \(names) thoát…"
        let rules = self.rules.filter { ids.contains($0.id) }
        Task {
            for _ in 0..<40 where !apps.allSatisfy(\.isTerminated) {
                try? await Task.sleep(for: .milliseconds(500))
            }
            // Re-read what is still running before deciding what can go.
            let processes = await Task.detached { ProcessSnapshot.capture(includeProjectInfo: false) }.value
            for rule in rules where rule.onlyWhenAppClosed {
                self.scans[rule.id]?.blockedBy = processes.runningName(among: rule.skipIfRunning)
            }
            self.isCleaning = false
            let still = apps.filter { !$0.isTerminated }.compactMap(\.localizedName)
            if !still.isEmpty {
                self.status = ""
                self.lastError = "\(still.joined(separator: ", ")) chưa thoát (có thể đang chờ bạn lưu dữ liệu). Các mục của app đó được giữ lại."
            }
            self.clean(ids)
        }
    }

    var lastAutoRun: HistoryEntry? { history.last { $0.trigger == .auto } }

    // MARK: Scan & clean

    func refreshDisk() { disk = DiskStatus.current() }

    func scan(_ only: [Rule]? = nil) {
        guard !busy else { return }
        let rules = only ?? self.rules
        let config = self.config
        isScanning = true
        progress = 0
        status = "Đang tìm thư mục dự án…"
        let total = Double(max(rules.count, 1))
        Task.detached(priority: .userInitiated) {
            let results = Engine.scan(rules: rules, config: config) { result, done in
                Task { @MainActor in
                    self.scans[result.ruleID] = result
                    self.progress = Double(done) / total
                    self.status = "Đã quét \(done)/\(Int(total)) quy tắc"
                }
            }
            await MainActor.run {
                for (id, r) in results { self.scans[id] = r }
                self.unticked = self.unticked.filter { path in results.values.contains { $0.items.contains { $0.path == path } } }
                self.isScanning = false
                self.lastScan = Date()
                self.status = ""
                self.refreshDisk()
            }
        }
    }

    /// Asks for confirmation (via `pendingClean`) before deleting.
    func requestClean(_ ids: [String]) {
        let ids = ids.filter { id in
            guard let rule = rules.first(where: { $0.id == id }) else { return false }
            return rule.kind == .command || size(of: id) > 0
        }
        guard !ids.isEmpty else { return }
        pendingClean = ids
    }

    func clean(_ ids: [String], trigger: Trigger = .manual) {
        guard !busy else { return }
        let rules = self.rules.filter { ids.contains($0.id) }
        let scans = self.scans
        let unticked = self.unticked
        let config = self.config
        isCleaning = true
        status = "Đang dọn…"
        Task.detached(priority: .userInitiated) {
            let entry = Engine.clean(rules: rules, scans: scans, excludedItems: unticked, config: config, trigger: trigger) { name in
                Task { @MainActor in self.status = "Đang dọn: \(name)" }
            }
            Store.append(entry)
            await MainActor.run {
                self.history.append(entry)
                self.lastResult = entry
                self.isCleaning = false
                self.status = ""
                self.refreshDisk()
                if config.notify && trigger == .auto {
                    Notifier.post(title: "Sweepy đã dọn \(Fmt.bytes(entry.freed))", body: "Ổ đĩa còn trống \(Fmt.bytes(entry.freeAfter)).")
                }
                // Rescan what we touched so sizes reflect reality.
                self.scan(rules)
            }
        }
    }

    /// Same as the scheduled run: scan the auto rules, then clean them.
    func runAutoNow() {
        guard !busy else { return }
        let rules = self.rules.filter(\.autoClean)
        let config = self.config
        isCleaning = true
        status = "Đang quét các mục tự động…"
        Task.detached(priority: .userInitiated) {
            let scans = Engine.scan(rules: rules, config: config)
            let entry = Engine.clean(rules: rules, scans: scans, excludedItems: [], config: config, trigger: .manual) { name in
                Task { @MainActor in self.status = "Đang dọn: \(name)" }
            }
            Store.append(entry)
            await MainActor.run {
                self.history.append(entry)
                self.lastResult = entry
                self.isCleaning = false
                self.status = ""
                self.refreshDisk()
                if config.notify {
                    Notifier.post(title: "Sweepy đã dọn \(Fmt.bytes(entry.freed))", body: "Ổ đĩa còn trống \(Fmt.bytes(entry.freeAfter)).")
                }
                self.scan()
            }
        }
    }

    // MARK: Editing

    func update(_ id: String, _ mutate: (inout Rule) -> Void) {
        if let i = config.customRules.firstIndex(where: { $0.id == id }) {
            mutate(&config.customRules[i])
        } else if let base = DefaultRules.all.first(where: { $0.id == id }) {
            var edited = config.overrides[id]?.apply(to: base) ?? base
            mutate(&edited)
            let diff = RuleOverride.diff(base: base, edited: edited)
            config.overrides[id] = diff.isEmpty ? nil : diff
        }
        save()
    }

    func binding<T>(_ id: String, _ keyPath: WritableKeyPath<Rule, T>, default value: T) -> Binding<T> {
        Binding(
            get: { self.rules.first { $0.id == id }?[keyPath: keyPath] ?? value },
            set: { newValue in self.update(id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.selected.contains(id) },
                set: { on in if on { self.selected.insert(id) } else { self.selected.remove(id) } })
    }

    func itemBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { !self.unticked.contains(path) },
                set: { on in if on { self.unticked.remove(path) } else { self.unticked.insert(path) } })
    }

    func addExclusion(_ path: String) {
        let short = PathUtil.abbreviate(path)
        guard !config.exclusions.contains(short) else { return }
        config.exclusions.append(short)
        save()
        for (id, var scan) in scans {
            scan.items.removeAll { PathUtil.isUnder($0.path, path) }
            scans[id] = scan
        }
    }

    func saveCustomRule(_ rule: Rule) {
        if let i = config.customRules.firstIndex(where: { $0.id == rule.id }) {
            config.customRules[i] = rule
        } else {
            config.customRules.append(rule)
        }
        if rule.autoClean { selected.insert(rule.id) }
        save()
        scan([rule])
    }

    func deleteCustomRule(_ id: String) {
        config.customRules.removeAll { $0.id == id }
        scans[id] = nil
        selected.remove(id)
        save()
    }

    func applySchedule(_ schedule: Schedule) {
        config.schedule = schedule
        save()
        scheduleError = Scheduler.apply(schedule)
    }

    func save() { Store.save(config) }

    func setLaunchAtLogin(_ on: Bool) {
        loginItemMessage = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: Finder helpers

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

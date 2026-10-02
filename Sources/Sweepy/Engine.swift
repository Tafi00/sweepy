import Foundation

/// Hard limits that apply to every rule, including custom ones.
enum SafetyGuard {
    static let protectedPrefixes = [
        "~/.ssh", "~/.gnupg", "~/Library/Keychains", "~/Library/Mobile Documents", "~/Library/Mail",
        "~/Library/Messages", "~/Library/Photos", "~/Library/CloudStorage", "~/Pictures/Photos Library.photoslibrary",
    ].map(PathUtil.expand)

    static let protectedExact = [
        "~", "~/Library", "~/Library/Application Support", "~/Library/Caches", "~/Library/Containers",
        "~/Library/Group Containers", "~/Library/Developer", "~/Library/Preferences", "~/Library/Logs",
        "~/Desktop", "~/Documents", "~/Downloads", "~/Pictures", "~/Movies", "~/Music", "~/Public",
        "~/Applications", "~/.Trash", "~/.config", "~/.local", "~/.cache", "~/.npm", "~/.gradle",
    ].map(PathUtil.expand)

    /// Returns a reason when `path` must not be deleted.
    static func refusal(for path: String, config: AppConfig) -> String? {
        if path.contains("/../") || path.contains("/./") || path.hasSuffix("/..") { return "đường dẫn không hợp lệ" }
        let home = PathUtil.home
        let inHome = path.hasPrefix(home + "/")
        let inTmp = path.hasPrefix(PathUtil.tmpDir + "/")
        guard inHome || inTmp else { return "nằm ngoài thư mục người dùng" }
        if inHome {
            let depth = path.dropFirst(home.count + 1).split(separator: "/").count
            if depth < 2 { return "quá gần thư mục gốc" }
        }
        if protectedExact.contains(path) || config.projectRoots.map(PathUtil.expand).contains(path) {
            return "thư mục được bảo vệ"
        }
        if protectedPrefixes.contains(where: { PathUtil.isUnder(path, $0) }) { return "dữ liệu cá nhân được bảo vệ" }
        if isExcluded(path, config: config) { return "nằm trong danh sách loại trừ" }
        return nil
    }

    static func isExcluded(_ path: String, config: AppConfig) -> Bool {
        config.exclusions.map(PathUtil.expand).contains { PathUtil.isUnder(path, $0) }
    }
}

struct Scanner {
    let config: AppConfig
    let processes: ProcessSnapshot
    let projectCandidates: [String]

    static let generatedNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular", ".expo",
        "DerivedData", "build", ".gradle", ".cxx", ".dart_tool", "__pycache__", ".venv", "venv", "Pods", "target",
        "dist", ".cache", "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    ]

    /// Item names never touched inside cache folders.
    static let keepNames: Set<String> = [".DS_Store", ".localized", "CACHEDIR.TAG"]

    init(config: AppConfig, rules: [Rule], processes: ProcessSnapshot) {
        self.config = config
        self.processes = processes
        let names = Set(rules.filter { $0.kind == .projectFolders }.flatMap(\.folderNames))
        let roots = config.projectRoots.map(PathUtil.expand)
        let found = FileScan.findDirectories(named: names, under: roots, maxDepth: 10) { path in
            SafetyGuard.isExcluded(path, config: config)
        }
        // Overlapping roots (~/Desktop and ~/Desktop/Code) would otherwise report a folder twice.
        projectCandidates = Array(Set(found)).sorted()
    }

    func scan(_ rule: Rule) -> RuleScan {
        var result = RuleScan(ruleID: rule.id)
        if rule.onlyWhenAppClosed, let name = processes.runningName(among: rule.skipIfRunning) {
            result.blockedBy = name
        }

        var candidates: [(path: String, note: String?)] = []
        switch rule.kind {
        case .command:
            result.applicable = !rule.command.isEmpty && Shell.commandExists(rule.command)
            return result

        case .contents:
            let roots = rule.paths.flatMap(PathUtil.glob).filter { root in
                PathUtil.isDirectory(root) && !PathUtil.matches(PathUtil.name(root), any: rule.excludeNames)
            }
            let rootSet = Set(roots)
            result.applicable = !roots.isEmpty
            for root in roots {
                let children: [String]
                do {
                    children = try FileManager.default.contentsOfDirectory(atPath: root)
                } catch {
                    result.notes.append("Không đọc được \(PathUtil.abbreviate(root)) – cần cấp quyền Full Disk Access.")
                    continue
                }
                for name in children {
                    let path = root + "/" + name
                    // A child that is itself one of the rule's roots is handled at its own level.
                    if rootSet.contains(path) || Scanner.keepNames.contains(name) { continue }
                    // Version folders only: never count marker files like .sdk-version as a "version".
                    if rule.keepNewest > 0 && (name.hasPrefix(".") || !PathUtil.isDirectory(path)) { continue }
                    if PathUtil.matches(name, any: rule.excludeNames) { continue }
                    if !rule.includeNames.isEmpty && !PathUtil.matches(name, any: rule.includeNames) { continue }
                    if !rule.extensions.isEmpty {
                        let ext = (name as NSString).pathExtension.lowercased()
                        if !rule.extensions.contains(ext) { continue }
                    }
                    candidates.append((path, nil))
                }
            }

        case .paths:
            let matched = rule.paths.flatMap(PathUtil.glob)
            result.applicable = !matched.isEmpty
            for path in matched {
                let name = PathUtil.name(path)
                if PathUtil.matches(name, any: rule.excludeNames) { continue }
                if rule.keepNewest > 0 && !PathUtil.isDirectory(path) { continue }
                if !rule.includeNames.isEmpty && !PathUtil.matches(name, any: rule.includeNames) { continue }
                if !rule.extensions.isEmpty && !rule.extensions.contains((name as NSString).pathExtension.lowercased()) { continue }
                candidates.append((path, nil))
            }

        case .projectFolders:
            let names = Set(rule.folderNames)
            var recentlyUsed = 0
            var busy = Set<String>()
            let cutoff = Date().addingTimeInterval(-Double(rule.minIdleDays) * 86_400)
            var idleCache: [String: Date?] = [:]
            for dir in projectCandidates where names.contains(PathUtil.name(dir)) {
                let project = PathUtil.parent(dir)
                if !rule.markers.isEmpty && !Scanner.hasChild(project, matching: rule.markers) { continue }
                if !rule.markersInside.isEmpty && !Scanner.hasChild(dir, matching: rule.markersInside) { continue }
                // A folder that is itself a git repo is never a build artifact.
                if PathUtil.exists(dir + "/.git") { continue }
                result.applicable = true
                if rule.skipIfProjectRunning && processes.isProjectBusy(project) {
                    busy.insert(PathUtil.name(project))
                    continue
                }
                if rule.minIdleDays > 0 {
                    let last: Date?
                    if let cached = idleCache[project] { last = cached } else {
                        last = FileScan.lastActivity(in: project, ignoring: Scanner.generatedNames)
                        idleCache[project] = last
                    }
                    if let last, last > cutoff { recentlyUsed += 1; continue }
                }
                if rule.subpath.isEmpty {
                    candidates.append((dir, Scanner.projectLabel(project)))
                } else if PathUtil.exists(dir + "/" + rule.subpath) {
                    candidates.append((dir + "/" + rule.subpath, Scanner.projectLabel(project)))
                }
            }
            if !busy.isEmpty {
                result.notes.append("Bỏ qua dự án đang chạy: " + busy.sorted().joined(separator: ", "))
            }
            if recentlyUsed > 0 {
                result.notes.append("Bỏ qua \(recentlyUsed) thư mục thuộc dự án mới sửa trong \(rule.minIdleDays) ngày qua.")
            }

        case .largeFiles:
            let roots = Array(Set(rule.paths.flatMap(PathUtil.glob) + config.projectRoots.map(PathUtil.expand)))
            result.applicable = !roots.isEmpty
            let cutoff = Date().addingTimeInterval(-Double(rule.olderThanDays) * 86_400)
            let minBytes = Int64(max(rule.minSizeMB, 1)) * 1_048_576
            let found = FileScan.findLargeFiles(under: roots, minBytes: minBytes) { SafetyGuard.isExcluded($0, config: config) }
            var recent = 0
            for f in found {
                if rule.olderThanDays > 0 && f.date > cutoff { recent += 1; continue }
                if !rule.extensions.isEmpty && !rule.extensions.contains((f.path as NSString).pathExtension.lowercased()) { continue }
                if SafetyGuard.refusal(for: f.path, config: config) != nil { continue }
                result.items.append(ScanItem(path: f.path, size: f.size, date: f.date))
            }
            if recent > 0 { result.notes.append("Giữ lại \(recent) file lớn đã mở trong \(rule.olderThanDays) ngày qua.") }
            result.items.sort { $0.size > $1.size }
            return result

        case .orphanData:
            let roots = rule.paths.flatMap(PathUtil.glob).filter(PathUtil.isDirectory)
            result.applicable = !roots.isEmpty
            for root in roots {
                guard let children = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                    result.notes.append("Không đọc được \(PathUtil.abbreviate(root)) – cần cấp quyền Full Disk Access.")
                    continue
                }
                for name in children {
                    if root.hasSuffix("Application Support"), InstalledApps.isOrphanFolder(name, running: processes.appNames) {
                        candidates.append((root + "/" + name, "không thấy app \(name) trên máy"))
                        continue
                    }
                    var id = name.replacingOccurrences(of: ".savedState", with: "")
                    // Group containers are "TEAMID.vendor.app", "group.vendor.app" or "TEAMID.group.vendor.app".
                    if root.hasSuffix("Group Containers") {
                        var parts = id.split(separator: ".").map(String.init)
                        if let first = parts.first, first.count == 10,
                           first.allSatisfy({ $0.isUppercase || $0.isNumber }) { parts.removeFirst() }
                        if parts.first == "group" || parts.first == "groups" { parts.removeFirst() }
                        id = parts.joined(separator: ".")
                    }
                    guard InstalledApps.looksLikeBundleID(id), InstalledApps.isOrphan(id, running: processes.appNames) else { continue }
                    candidates.append((root + "/" + name, "không thấy app \(InstalledApps.vendor(id)).* nào trên máy"))
                }
            }
        }

        // Exclusions and hard safety limits.
        candidates.removeAll { SafetyGuard.refusal(for: $0.path, config: config) != nil }

        // Something a running process was started from (e.g. an older Claude Code build) stays.
        if rule.skipIfInUse {
            let before = candidates.count
            candidates.removeAll { processes.isInUse($0.path) }
            if candidates.count < before { result.notes.append("Giữ lại \(before - candidates.count) mục đang được dùng.") }
        }

        // Measure.
        var measured: [ScanItem] = []
        for c in candidates {
            let m = FileScan.measure(c.path)
            if m.size == 0 && m.files == 0 { continue }
            let date: Date? = rule.ageBasis == .added ? PathUtil.addedDate(c.path) : m.newest
            measured.append(ScanItem(path: c.path, size: m.size, date: date, note: c.note))
        }

        // Keep the newest N per folder (current version of an app/tool).
        if rule.keepNewest > 0 {
            let groups = Dictionary(grouping: measured) { PathUtil.parent($0.path) }
            measured = groups.values.flatMap { group in
                group.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.dropFirst(rule.keepNewest)
            }
        }

        // Age filter.
        let cutoff = Date().addingTimeInterval(-Double(rule.olderThanDays) * 86_400)
        var items: [ScanItem] = []
        var tooNew = 0
        for item in measured {
            if rule.olderThanDays > 0, let date = item.date, date > cutoff { tooNew += 1; continue }
            items.append(item)
        }
        if tooNew > 0 && rule.olderThanDays > 0 {
            result.notes.append("Giữ lại \(tooNew) mục mới hơn \(rule.olderThanDays) ngày.")
        }

        // Never list both a folder and something inside it.
        items.sort { $0.path < $1.path }
        var deduped: [ScanItem] = []
        for item in items {
            if let last = deduped.last, PathUtil.isUnder(item.path, last.path) { continue }
            deduped.append(item)
        }
        result.items = deduped.sorted { $0.size > $1.size }
        return result
    }

    static func hasChild(_ dir: String, matching patterns: [String]) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return false }
        return names.contains { PathUtil.matches($0, any: patterns) }
    }

    static func projectLabel(_ project: String) -> String {
        let parts = PathUtil.abbreviate(project).split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }
}

enum Engine {
    static func scan(rules: [Rule], config: AppConfig, progress: ((RuleScan, Int) -> Void)? = nil) -> [String: RuleScan] {
        let needsProjects = rules.contains { $0.kind == .projectFolders || $0.skipIfInUse }
        let processes = ProcessSnapshot.capture(includeProjectInfo: needsProjects)
        let scanner = Scanner(config: config, rules: rules, processes: processes)
        var results: [String: RuleScan] = [:]
        let lock = NSLock()
        var done = 0
        DispatchQueue.concurrentPerform(iterations: rules.count) { i in
            let r = scanner.scan(rules[i])
            lock.lock()
            results[r.ruleID] = r
            done += 1
            let n = done
            lock.unlock()
            progress?(r, n)
        }
        return results
    }

    /// Deletes the scanned items of `rules`. Re-checks running apps right before deleting.
    static func clean(rules: [Rule], scans: [String: RuleScan], excludedItems: Set<String>, config: AppConfig,
                      trigger: Trigger, progress: ((String) -> Void)? = nil) -> HistoryEntry {
        let freeBefore = DiskStatus.current().available
        let processes = ProcessSnapshot.capture(includeProjectInfo: rules.contains { $0.kind == .projectFolders || $0.skipIfInUse })
        var outcomes: [RuleOutcome] = []

        for rule in rules {
            var outcome = RuleOutcome(ruleID: rule.id, ruleName: rule.name)
            progress?(rule.name)
            if rule.onlyWhenAppClosed, let name = processes.runningName(among: rule.skipIfRunning) {
                outcome.skipped = "\(name) đang chạy"
                outcomes.append(outcome)
                continue
            }

            if rule.kind == .command {
                guard Shell.commandExists(rule.command) else {
                    outcome.skipped = "không tìm thấy lệnh"
                    outcomes.append(outcome)
                    continue
                }
                let before = DiskStatus.current().available
                let res = Shell.runUserCommand(rule.command)
                outcome.freed = max(0, DiskStatus.current().available - before)
                outcome.output = String(res.output.suffix(2000))
                if res.status != 0 { outcome.errors.append("Lệnh kết thúc với mã \(res.status)") }
                outcomes.append(outcome)
                continue
            }

            guard let scan = scans[rule.id] else { continue }
            for item in scan.items where !excludedItems.contains(item.path) {
                if let reason = SafetyGuard.refusal(for: item.path, config: config) {
                    outcome.errors.append("Từ chối \(PathUtil.abbreviate(item.path)): \(reason)")
                    continue
                }
                if rule.kind == .projectFolders && rule.skipIfProjectRunning
                    && processes.isProjectBusy(PathUtil.parent(item.path)) {
                    outcome.errors.append("Bỏ qua \(PathUtil.abbreviate(item.path)): dự án vừa được khởi chạy")
                    continue
                }
                if rule.skipIfInUse && processes.isInUse(item.path) {
                    outcome.errors.append("Bỏ qua \(PathUtil.abbreviate(item.path)): đang được dùng")
                    continue
                }
                guard PathUtil.exists(item.path) else { continue }
                do {
                    try remove(item.path, mode: rule.deleteMode)
                    outcome.freed += item.size
                    outcome.itemCount += 1
                } catch {
                    if outcome.errors.count < 20 {
                        outcome.errors.append("\(PathUtil.abbreviate(item.path)): \(error.localizedDescription)")
                    }
                }
            }
            outcomes.append(outcome)
        }

        let freeAfter = DiskStatus.current().available
        let freed = outcomes.reduce(0) { $0 + $1.freed }
        return HistoryEntry(date: Date(), trigger: trigger, freed: freed, freeBefore: freeBefore,
                            freeAfter: freeAfter, outcomes: outcomes)
    }

    static func remove(_ path: String, mode: DeleteMode) throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        if mode == .trash {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return
        }
        do {
            try fm.removeItem(at: url)
        } catch {
            // Read-only folders (Go module cache, some npm packages) need write permission first.
            Shell.run("/bin/chmod", ["-R", "u+w", path])
            try fm.removeItem(at: url)
        }
    }
}

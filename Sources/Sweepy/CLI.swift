import Foundation

/// Headless entry points:
///   Sweepy --auto            scheduled run (what the LaunchAgent calls)
///   Sweepy --auto --dry-run  show what a scheduled run would delete
///   Sweepy --scan            report every rule, deletes nothing
///   --only id1,id2           limit to some rules
enum CLI {
    static func run(_ args: [String]) {
        let config = Store.loadConfig()
        if let i = args.firstIndex(of: "--check-path"), i + 1 < args.count {
            let path = PathUtil.expand(args[i + 1])
            print("\(path): \(SafetyGuard.refusal(for: path, config: config) ?? "cho phép xoá")")
            return
        }
        let dryRun = args.contains("--dry-run") || args.contains("--scan")
        var rules = config.effectiveRules()
        if let i = args.firstIndex(of: "--only"), i + 1 < args.count {
            let ids = Set(args[i + 1].split(separator: ",").map(String.init))
            rules = rules.filter { ids.contains($0.id) }
        } else if args.contains("--auto") {
            rules = rules.filter(\.autoClean)
        }

        let disk = DiskStatus.current()
        if args.contains("--auto") && !dryRun {
            Store.log("Bắt đầu dọn tự động – còn trống \(Fmt.bytes(disk.available))")
            if config.minFreeGB > 0 && disk.available > Int64(config.minFreeGB) * 1_000_000_000 {
                Store.log("Bỏ qua: dung lượng trống vẫn trên \(config.minFreeGB) GB")
                return
            }
        }

        let started = Date()
        let scans = Engine.scan(rules: rules, config: config)
        if dryRun {
            printReport(rules: rules, scans: scans, disk: disk, seconds: Date().timeIntervalSince(started))
            return
        }

        let entry = Engine.clean(rules: rules, scans: scans, excludedItems: [], config: config, trigger: .auto)
        Store.append(entry)
        for o in entry.outcomes where o.freed > 0 || o.skipped != nil || !o.errors.isEmpty {
            var line = "  \(o.ruleName): \(Fmt.bytes(o.freed)) (\(o.itemCount) mục)"
            if let s = o.skipped { line += " – bỏ qua: \(s)" }
            if !o.errors.isEmpty { line += " – \(o.errors.count) lỗi: \(o.errors.prefix(3).joined(separator: "; "))" }
            Store.log(line)
        }
        Store.log("Xong: giải phóng \(Fmt.bytes(entry.freed)), còn trống \(Fmt.bytes(entry.freeAfter))")
        if config.notify && entry.freed > 0 {
            Notifier.post(title: "Sweepy đã dọn \(Fmt.bytes(entry.freed))",
                          body: "Ổ đĩa còn trống \(Fmt.bytes(entry.freeAfter)).", wait: true)
        }
    }

    static func printReport(rules: [Rule], scans: [String: RuleScan], disk: DiskStatus, seconds: Double) {
        print("Ổ đĩa: còn trống \(Fmt.bytes(disk.available)) / \(Fmt.bytes(disk.total))")
        print(String(format: "Quét %d quy tắc trong %.1fs\n", rules.count, seconds))
        var total: Int64 = 0
        var autoTotal: Int64 = 0
        for category in RuleCategory.allCases {
            let inCat = rules.filter { $0.category == category }
            guard !inCat.isEmpty else { continue }
            print("== \(category.title) ==")
            for rule in inCat {
                guard let s = scans[rule.id] else { continue }
                if !s.applicable && s.items.isEmpty { continue }
                total += s.total
                if rule.autoClean { autoTotal += s.total }
                let flag = rule.autoClean ? "[auto]" : "[    ]"
                let size = rule.kind == .command ? "lệnh" : Fmt.bytes(s.total)
                print("\(flag) \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(rule.name) (\(s.items.count) mục)")
                if let b = s.blockedBy { print("         ⚠︎ \(b) đang chạy – sẽ bỏ qua khi dọn") }
                for n in s.notes { print("         · \(n)") }
                let limit = CommandLine.arguments.contains("--all") ? Int.max : 4
                for item in s.items.prefix(limit) {
                    let note = item.note.map { " [\($0)]" } ?? ""
                    print("           \(Fmt.bytes(item.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(PathUtil.abbreviate(item.path))\(note)")
                }
                if s.items.count > limit { print("           … và \(s.items.count - limit) mục khác") }
            }
            print("")
        }
        print("Tổng có thể dọn: \(Fmt.bytes(total)) — trong đó quy tắc tự động: \(Fmt.bytes(autoTotal))")
    }
}

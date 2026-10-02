import Foundation

enum PathUtil {
    static let home: String = NSHomeDirectory()

    static let tmpDir: String = {
        var t = NSTemporaryDirectory()
        while t.count > 1 && t.hasSuffix("/") { t.removeLast() }
        return t
    }()

    /// Where macOS saves screenshots (System Settings can move it away from the Desktop).
    static let screenshotDir: String = {
        if let loc = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !loc.isEmpty {
            var p = loc.hasPrefix("~") ? home + loc.dropFirst() : loc
            while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            return p
        }
        return home + "/Desktop"
    }()

    static func expand(_ path: String) -> String {
        var s = path.trimmingCharacters(in: .whitespaces)
        if s == "~" { return home }
        if s.hasPrefix("~/") { s = home + s.dropFirst() }
        s = s.replacingOccurrences(of: "$TMPDIR", with: tmpDir)
        s = s.replacingOccurrences(of: "$SCREENSHOTS", with: screenshotDir)
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        if s.hasPrefix("/") && (s.contains("/../") || s.contains("/./") || s.hasSuffix("/..") || s.contains("//")) {
            s = (s as NSString).standardizingPath
        }
        return s
    }

    static func abbreviate(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        if path.hasPrefix(tmpDir + "/") { return "$TMPDIR" + path.dropFirst(tmpDir.count) }
        return path
    }

    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    static func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    /// Expands `~`, `$TMPDIR`, `*`, `?`, `[…]` and `{a,b}`. Only returns paths that exist.
    static func glob(_ pattern: String) -> [String] {
        let expanded = expand(pattern)
        guard expanded.contains(where: { "*?[{".contains($0) }) else {
            return exists(expanded) ? [expanded] : []
        }
        var gt = glob_t()
        defer { globfree(&gt) }
        guard Darwin.glob(expanded, GLOB_BRACE, nil, &gt) == 0 else { return [] }
        var out: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let p = gt.gl_pathv[i] {
                let s = String(cString: p)
                if exists(s) { out.append(s) }
            }
        }
        return out
    }

    static func matches(_ name: String, any patterns: [String]) -> Bool {
        // File names may be stored decomposed (NFD); compare both sides precomposed.
        let n = name.precomposedStringWithCanonicalMapping
        return patterns.contains { fnmatch($0.precomposedStringWithCanonicalMapping, n, FNM_CASEFOLD) == 0 }
    }

    static func isUnder(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func addedDate(_ path: String) -> Date? {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        return v?.addedToDirectoryDate ?? v?.contentModificationDate
    }
}

struct Measure {
    var size: Int64 = 0
    var newest: Date?
    var files: Int = 0
}

enum FileScan {
    /// Allocated size (like `du`) and newest modification date of a file or folder tree.
    /// Does not follow symlinks or cross into other volumes.
    static func measure(_ path: String) -> Measure {
        var total: Int64 = 0
        var newest = 0
        var count = 0
        guard let cpath = strdup(path) else { return Measure() }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return Measure() }
        defer { fts_close(fts) }
        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            switch info {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_D:
                guard let st = ent.pointee.fts_statp else { continue }
                total += Int64(st.pointee.st_blocks) * 512
                newest = max(newest, st.pointee.st_mtimespec.tv_sec)
                if info != FTS_D { count += 1 }
            default:
                continue
            }
        }
        return Measure(size: total,
                       newest: newest > 0 ? Date(timeIntervalSince1970: TimeInterval(newest)) : nil,
                       files: count)
    }

    /// Finds directories whose name is in `names` under `roots`. Does not descend into matches.
    static func findDirectories(named names: Set<String>, under roots: [String], maxDepth: Int,
                                skip: (String) -> Bool) -> [String] {
        guard !names.isEmpty else { return [] }
        let neverDescend: Set<String> = [".git", ".hg", ".svn", ".Trash", "Library", ".npm", ".pnpm-store"]
        var results: [String] = []
        for root in roots where PathUtil.isDirectory(root) {
            guard let cpath = strdup(root) else { continue }
            defer { free(cpath) }
            var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
            guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_NOSTAT, nil) else { continue }
            defer { fts_close(fts) }
            while let ent = fts_read(fts) {
                guard Int32(ent.pointee.fts_info) == FTS_D else { continue }
                let level = Int(ent.pointee.fts_level)
                if level == 0 { continue }
                let path = String(cString: ent.pointee.fts_path)
                let name = PathUtil.name(path)
                if names.contains(name) {
                    if !skip(path) { results.append(path) }
                    fts_set(fts, ent, FTS_SKIP)
                } else if level >= maxDepth || neverDescend.contains(name) || name.hasSuffix(".app")
                            || name.hasSuffix(".photoslibrary") || skip(path) {
                    fts_set(fts, ent, FTS_SKIP)
                }
            }
        }
        return results
    }

    /// Most recent modification of a regular file in a project, ignoring generated folders.
    static func lastActivity(in project: String, ignoring ignored: Set<String>, maxDepth: Int = 6,
                             maxEntries: Int = 40_000) -> Date? {
        var newest = 0
        var seen = 0
        guard let cpath = strdup(project) else { return nil }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }
        while let ent = fts_read(fts) {
            seen += 1
            if seen > maxEntries { break }
            let info = Int32(ent.pointee.fts_info)
            let level = Int(ent.pointee.fts_level)
            if info == FTS_D {
                if level == 0 { continue }
                let name = PathUtil.name(String(cString: ent.pointee.fts_path))
                if level >= maxDepth || ignored.contains(name) || name == ".git" || name == ".DS_Store" {
                    fts_set(fts, ent, FTS_SKIP)
                }
            } else if info == FTS_F, let st = ent.pointee.fts_statp {
                let name = PathUtil.name(String(cString: ent.pointee.fts_path))
                if name == ".DS_Store" { continue }
                newest = max(newest, st.pointee.st_mtimespec.tv_sec)
            }
        }
        return newest > 0 ? Date(timeIntervalSince1970: TimeInterval(newest)) : nil
    }
}

enum Shell {
    struct Result {
        var status: Int32
        var output: String
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String], mergeStderr: Bool = false) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = mergeStderr ? out : FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Result(status: -1, output: error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a command through a login zsh so the user's PATH (Homebrew, nvm…) is available.
    static func runUserCommand(_ command: String) -> Result {
        let script = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; " + command
        return run("/bin/zsh", ["-lc", script], mergeStderr: true)
    }

    static func commandExists(_ command: String) -> Bool {
        guard let first = command.split(separator: " ").first.map(String.init) else { return false }
        if first.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: first) }
        return runUserCommand("command -v \(first) >/dev/null 2>&1").status == 0
    }
}

extension FileScan {
    /// Regular files of at least `minBytes` under `roots`; date = last access or modification, whichever is later.
    static func findLargeFiles(under roots: [String], minBytes: Int64, skip: (String) -> Bool) -> [(path: String, size: Int64, date: Date)] {
        let neverDescend: Set<String> = [".git", ".Trash", "Library", "node_modules", ".next", "DerivedData", "Pods",
                                         ".gradle", "build", ".venv", "venv", ".npm", ".cache"]
        var seen = Set<String>()
        var out: [(String, Int64, Date)] = []
        for root in roots where PathUtil.isDirectory(root) {
            guard let cpath = strdup(root) else { continue }
            defer { free(cpath) }
            var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
            guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(fts) }
            while let ent = fts_read(fts) {
                let info = Int32(ent.pointee.fts_info)
                if info == FTS_D {
                    guard ent.pointee.fts_level > 0 else { continue }
                    let path = String(cString: ent.pointee.fts_path)
                    let name = PathUtil.name(path)
                    // Bundles (.app, .photoslibrary, .fcpbundle…) are managed by their apps.
                    if neverDescend.contains(name) || (name as NSString).pathExtension.count > 1 || skip(path) {
                        fts_set(fts, ent, FTS_SKIP)
                    }
                } else if info == FTS_F, let st = ent.pointee.fts_statp {
                    let size = Int64(st.pointee.st_blocks) * 512
                    guard size >= minBytes else { continue }
                    let path = String(cString: ent.pointee.fts_path)
                    guard seen.insert(path).inserted, !skip(path) else { continue }
                    let t = max(st.pointee.st_atimespec.tv_sec, st.pointee.st_mtimespec.tv_sec)
                    out.append((path, size, Date(timeIntervalSince1970: TimeInterval(t))))
                }
            }
        }
        return out
    }
}

/// Bundle IDs of apps installed on this Mac, used to spot data left by uninstalled apps.
enum InstalledApps {
    static let bundleIDs: Set<String> = {
        var ids = Set<String>()
        let roots = ["/Applications", "/Applications/Utilities", PathUtil.expand("~/Applications"),
                     "/System/Applications", "/System/Applications/Utilities",
                     "/System/Cryptexes/App/System/Applications", "/Library/Application Support"]
        func add(_ app: String) {
            if let id = Bundle(path: app)?.bundleIdentifier { ids.insert(id.lowercased()) }
        }
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = root + "/" + name
                if name.hasSuffix(".app") { add(path); continue }
                // Suites like "Adobe Illustrator 2026/" or vendor folders keep apps one level down.
                if let inner = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    for n in inner where n.hasSuffix(".app") { add(path + "/" + n) }
                }
            }
        }
        return ids
    }()

    /// Vendor prefixes ("com.microsoft", "net.whatsapp") of installed apps.
    static let vendors: Set<String> = Set(bundleIDs.map(vendor))

    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Application Support folders named after the app rather than its bundle ID.
    /// Values are bundle IDs or vendor prefixes; the folder is orphaned when none of them is installed.
    static let knownFolders: [String: [String]] = [
        "LarkInternational": ["com.larksuite", "com.electron.lark", "com.bytedance.lark"],
        "Lark": ["com.larksuite", "com.electron.lark"], "Feishu": ["com.bytedance.feishu", "com.electron.lark"],
        "discord": ["com.hnc.Discord"], "Slack": ["com.tinyspeck.slackmacgap"], "ZaloData": ["com.vng.zalo"],
        "Code": ["com.microsoft.VSCode"], "Cursor": ["com.todesktop.230313mzl4w4u92"], "Windsurf": ["com.exafunction.windsurf"],
        "Figma": ["com.figma.Desktop"], "Spotify": ["com.spotify.client"], "zoom.us": ["us.zoom.xos"],
        "Telegram Desktop": ["com.tdesktop.Telegram"], "Notion": ["notion.id"], "Postman": ["com.postmanlabs.mac"],
        "obs-studio": ["com.obsproject.obs-studio"], "Microsoft Teams": ["com.microsoft.teams", "com.microsoft.teams2"],
        "Skype": ["com.skype.skype"], "Signal": ["org.whispersystems.signal-desktop"], "Messenger": ["com.facebook.archon"],
        "Antigravity": ["com.google.antigravity"], "Claude": ["com.anthropic.claudefordesktop"],
        "CapCut": ["com.lemon.lvoverseas"], "TeamViewer": ["com.teamviewer.TeamViewer"], "AnyDesk": ["com.philandro.anydesk"],
        "BraveSoftware": ["com.brave.Browser"], "Microsoft Edge": ["com.microsoft.edgemac"], "Firefox": ["org.mozilla.firefox"],
        "Arc": ["company.thebrowser.Browser"], "Opera": ["com.operasoftware.Opera"],
    ]

    static func isOrphanFolder(_ name: String, running: [String: String]) -> Bool {
        guard let ids = knownFolders[name] else { return false }
        let runningIDs = running.keys.map { $0.lowercased() }
        return !ids.contains { id in
            let id = id.lowercased()
            let installed = id.split(separator: ".").count == 2
                ? bundleIDs.contains { $0.hasPrefix(id + ".") } || runningIDs.contains { $0.hasPrefix(id + ".") }
                : bundleIDs.contains(id) || runningIDs.contains(id)
            return installed
        }
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
    }

    /// Conservative: anything from a vendor that still has an app installed counts as in use.
    static func isOrphan(_ id: String, running: [String: String]) -> Bool {
        let lower = id.lowercased()
        // Apple, Shortcuts (is.workflow) and command-line tools have no .app to look for.
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("is.workflow.") || lower.hasSuffix(".cli") { return false }
        // Vendors that share data across differently-named apps.
        let aliases: [String: [String]] = ["com.facebook": ["net.whatsapp", "com.facebook"], "com.ddg": ["com.duckduckgo"]]
        if let others = aliases[vendor(lower)], others.contains(where: vendors.contains) { return false }
        if running.keys.contains(where: { InstalledApps.vendor($0) == vendor(lower) }) { return false }
        return !vendors.contains(vendor(lower))
    }
}

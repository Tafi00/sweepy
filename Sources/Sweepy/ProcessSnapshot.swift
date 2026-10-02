import AppKit
import Foundation

/// What is running right now, so we never pull files out from under a live app or dev server.
struct ProcessSnapshot {
    var appNames: [String: String] = [:]   // bundle ID -> display name
    var processNames: Set<String> = []     // lowercased executable names
    var commandLines: [String] = []
    var workingDirs: [(command: String, cwd: String)] = []

    /// Processes that merely sit in a project folder (terminals, editors, AI agents) don't make it busy.
    /// A dev server they start still shows up through its command line.
    static let passive: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux", "screen", "-zsh", "-bash", "nu",
                                       "claude", "disclaimer", "codex", "vim", "nvim", "nano", "less", "man", "git",
                                       "ssh", "caffeinate", "sleep", "tail", "watch"]

    static func capture(includeProjectInfo: Bool) -> ProcessSnapshot {
        var snap = ProcessSnapshot()
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier {
                snap.appNames[id] = app.localizedName ?? id
            }
        }
        let comm = Shell.run("/bin/ps", ["-axo", "comm="])
        for line in comm.output.split(separator: "\n") {
            let name = PathUtil.name(line.trimmingCharacters(in: .whitespaces)).lowercased()
            if !name.isEmpty { snap.processNames.insert(name) }
        }
        if includeProjectInfo {
            let args = Shell.run("/bin/ps", ["-axww", "-o", "command="])
            snap.commandLines = args.output.split(separator: "\n").map(String.init)
            // -Fcn: "c<command>" then "n<cwd>" for every process.
            let lsof = Shell.run("/usr/sbin/lsof", ["-w", "-a", "-d", "cwd", "-Fcn"])
            var current = ""
            for line in lsof.output.split(separator: "\n") {
                guard let tag = line.first else { continue }
                let value = String(line.dropFirst())
                if tag == "c" { current = value }
                else if tag == "n" { snap.workingDirs.append((current, value)) }
            }
        }
        return snap
    }

    /// Display name of the first running entry, or nil.
    func runningName(among ids: [String]) -> String? {
        for id in ids {
            if id.contains(".") {
                if let name = appNames[id] { return name }
            } else if processNames.contains(id.lowercased()) {
                return id
            }
        }
        return nil
    }

    /// True when a running process was launched from inside `path`.
    func isInUse(_ path: String) -> Bool {
        commandLines.contains { $0.contains(path + "/") || $0.hasPrefix(path + " ") || $0 == path }
    }

    /// True when a dev server / build tool is running from inside `project`.
    func isProjectBusy(_ project: String) -> Bool {
        let prefix = project.hasSuffix("/") ? project : project + "/"
        if commandLines.contains(where: { $0.contains(prefix) }) { return true }
        return workingDirs.contains { entry in
            PathUtil.isUnder(entry.cwd, project) && !ProcessSnapshot.passive.contains(entry.command.lowercased())
        }
    }
}

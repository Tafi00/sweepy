import AppKit
import SwiftUI
import Foundation

/// Self-update from GitHub Releases. A download is only installed when it is signed by the same
/// Developer ID team and bundle ID as the running app, so a tampered zip can never replace Sweepy.
@MainActor
final class Updater: ObservableObject {
    nonisolated static let repo = "Tafi00/sweepy"
    nonisolated static let assetName = "Sweepy.zip"
    nonisolated static let teamID = "3JD7L6FN23"
    static let checkInterval: TimeInterval = 6 * 3600

    struct Release {
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL?
    }

    enum State: Equatable {
        case idle, checking, upToDate, downloading
        case ready(version: String)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var available: Release?
    @Published var lastCheck: Date?

    /// Verified new app bundle waiting to be swapped in.
    private var staged: URL?
    private var timer: Timer?

    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let parse = { (v: String) in v.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = parse(a), y = parse(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    func start(enabled: Bool) {
        timer?.invalidate()
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check(auto: true) }
        timer = Timer.scheduledTimer(withTimeInterval: Updater.checkInterval, repeats: true) { _ in
            Task { @MainActor in AppModel.shared?.updater.check(auto: true) }
        }
    }

    /// `auto` checks download in the background and stay quiet when nothing is new or the network is down.
    func check(auto: Bool = false) {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        state = .checking
        Task {
            do {
                let release = try await Updater.fetchLatest()
                lastCheck = Date()
                guard let release, Updater.isNewer(release.version, than: Updater.currentVersion) else {
                    available = nil
                    state = auto ? .idle : .upToDate
                    return
                }
                available = release
                if auto { await download(release) } else { state = .idle }
            } catch {
                state = auto ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func downloadAvailable() {
        guard let release = available else { return }
        Task { await download(release) }
    }

    private func download(_ release: Release) async {
        state = .downloading
        do {
            staged = try await Task.detached(priority: .utility) { try Updater.fetchAndVerify(release) }.value
            state = .ready(version: release.version)
            // Nobody is looking (menu bar only): update right away and come back hidden.
            if let model = AppModel.shared, !model.busy, !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) }) {
                installAndRelaunch(background: true)
                return
            }
            if let model = AppModel.shared, model.config.notify {
                Notifier.post(title: "Sweepy \(release.version) đã sẵn sàng", body: "Mở Sweepy và bấm \"Khởi động lại để cập nhật\".")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Swaps the bundle once this process has exited, then reopens it.
    func installAndRelaunch(background: Bool = false) {
        guard let staged else { return }
        let target = Bundle.main.bundleURL.standardizedFileURL
        let parent = target.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            state = .failed("Không ghi được vào \(parent). Hãy kéo Sweepy vào /Applications rồi thử lại.")
            return
        }
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let backup = target.path + ".old"
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(backup))
        mv \(q(target.path)) \(q(backup)) || exit 1
        if mv \(q(staged.path)) \(q(target.path)); then rm -rf \(q(backup)); else mv \(q(backup)) \(q(target.path)); fi
        open \(q(target.path))\(background ? " --args --updated-in-background" : "")
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        do { try p.run() } catch {
            state = .failed(error.localizedDescription)
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: Network & verification (off the main actor)

    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated static func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError(message: "GitHub trả về mã \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.draft != true, payload.prerelease != true,
              let asset = payload.assets.first(where: { $0.name == assetName }) else { return nil }
        return Release(version: payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                       notes: payload.body ?? "", downloadURL: asset.browser_download_url, pageURL: payload.html_url)
    }

    nonisolated static func fetchAndVerify(_ release: Release) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("sweepy-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(assetName)
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        URLSession.shared.downloadTask(with: release.downloadURL) { url, response, error in
            defer { semaphore.signal() }
            if let error { failure = error; return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let url else {
                failure = UpdateError(message: "Tải bản cập nhật thất bại"); return
            }
            do { try FileManager.default.moveItem(at: url, to: zip) } catch { failure = error }
        }.resume()
        semaphore.wait()
        if let failure { throw failure }

        let unzip = Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path], mergeStderr: true)
        guard unzip.status == 0 else { throw UpdateError(message: "Giải nén thất bại: \(unzip.output)") }
        let app = work.appendingPathComponent("Sweepy.app")
        guard fm.fileExists(atPath: app.path) else { throw UpdateError(message: "File tải về không chứa Sweepy.app") }

        let bundleID = Bundle.main.bundleIdentifier ?? "local.sweepy.app"
        let requirement = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(teamID)\""
        let verify = Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", app.path], mergeStderr: true)
        guard verify.status == 0 else { throw UpdateError(message: "Chữ ký bản cập nhật không hợp lệ") }

        let version = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String ?? "0"
        guard isNewer(version, than: currentVersion) else { throw UpdateError(message: "Bản tải về không mới hơn bản đang dùng") }
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }
}

/// Settings section: version, auto-update switch and manual check.
struct UpdateSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some View {
        Section {
            LabeledContent("Phiên bản", value: Updater.currentVersion)
            Toggle("Tự động cập nhật", isOn: $model.config.autoUpdate)
                .onChange(of: model.config.autoUpdate) {
                    model.save()
                    updater.start(enabled: model.config.autoUpdate)
                }
            HStack {
                switch updater.state {
                case .checking:
                    ProgressView().controlSize(.small); Text("Đang kiểm tra…").foregroundStyle(.secondary)
                case .downloading:
                    ProgressView().controlSize(.small); Text("Đang tải bản \(updater.available?.version ?? "")…").foregroundStyle(.secondary)
                case .ready(let version):
                    Text("Bản \(version) đã tải xong.")
                    Spacer()
                    Button("Khởi động lại để cập nhật") { updater.installAndRelaunch() }.buttonStyle(.borderedProminent)
                case .upToDate:
                    Label("Đang dùng bản mới nhất", systemImage: "checkmark.circle").foregroundStyle(.green)
                case .failed(let message):
                    Text(message).foregroundStyle(.orange).lineLimit(2)
                case .idle:
                    if let release = updater.available {
                        Text("Có bản \(release.version)")
                        Spacer()
                        Button("Tải về") { updater.downloadAvailable() }
                    }
                }
                if !isBusy {
                    Spacer()
                    Button("Kiểm tra cập nhật") { updater.check() }
                }
            }
            if let notes = updater.available?.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(6)
            }
        } header: {
            Text("Cập nhật")
        } footer: {
            Text("Sweepy kiểm tra GitHub Releases mỗi 6 giờ, chỉ cài bản được ký bằng cùng chứng chỉ Developer ID. Khi app chỉ đang nằm trên menu bar, bản mới được cài ngay; khi cửa sổ đang mở, Sweepy chờ bạn bấm khởi động lại.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .ready: return true
        default: return false
        }
    }
}

/// Toolbar / menu bar button shown once an update is downloaded.
struct UpdateReadyButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if case .ready(let version) = updater.state {
            Button { updater.installAndRelaunch() } label: {
                Label("Cập nhật \(version)", systemImage: "arrow.down.circle.fill").labelStyle(.titleAndIcon)
            }
            .help("Khởi động lại Sweepy để dùng bản \(version)")
        }
    }
}

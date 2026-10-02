import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = Schedule()
    @State private var loaded = false

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = c.hour ?? 12
                draft.minute = c.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Tần suất", selection: $draft.frequency) {
                    ForEach(Frequency.allCases) { Text($0.title).tag($0) }
                }
                if draft.frequency == .hourly {
                    Picker("Chạy", selection: $draft.intervalHours) {
                        ForEach(Schedule.intervalChoices, id: \.self) { h in
                            Text(h == 1 ? "Mỗi giờ" : "Mỗi \(h) giờ").tag(h)
                        }
                    }
                    Text("Mẹo: với lịch dày, nên đặt \"Chỉ dọn khi dung lượng trống dưới X GB\" để app chỉ dọn lúc cần, và chỉ báo khi dọn được từ 50 MB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if draft.frequency != .off && draft.frequency != .hourly {
                    DatePicker("Giờ chạy", selection: timeBinding, displayedComponents: .hourAndMinute)
                    if draft.frequency == .weekly {
                        Picker("Vào", selection: $draft.weekday) {
                            ForEach(0..<7, id: \.self) { Text(Schedule.weekdayNames[$0]).tag($0) }
                        }
                    }
                    if draft.frequency == .monthly {
                        Stepper("Ngày \(draft.dayOfMonth) hằng tháng", value: $draft.dayOfMonth, in: 1...28)
                    }
                }
                Stepper(value: $model.config.minFreeGB, in: 0...500, step: 5) {
                    Text(model.config.minFreeGB == 0
                         ? "Luôn dọn khi tới lịch"
                         : "Chỉ dọn khi dung lượng trống dưới \(model.config.minFreeGB) GB")
                }
                .onChange(of: model.config.minFreeGB) { model.save() }
                Toggle("Gửi thông báo sau khi dọn", isOn: $model.config.notify)
                    .onChange(of: model.config.notify) { model.save() }

                HStack {
                    if Scheduler.isInstalled && model.config.schedule.frequency != .off {
                        Label("Đang bật: \(model.config.schedule.summary)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Lịch tự động chưa bật", systemImage: "pause.circle").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(draft.frequency == .off ? "Tắt lịch" : "Lưu & bật lịch") {
                        model.applySchedule(draft)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == model.config.schedule && (Scheduler.isInstalled || draft.frequency == .off))
                }
                if let warning = Scheduler.appLocationWarning, draft.frequency != .off {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                if let error = model.scheduleError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Lịch dọn tự động")
            } footer: {
                Text("Sweepy cài một LaunchAgent (~/Library/LaunchAgents/\(Scheduler.label).plist) để tự chạy theo lịch kể cả khi app đang đóng. Nếu máy đang ngủ đúng giờ đó, macOS sẽ chạy bù khi máy thức dậy. Chỉ các quy tắc bật \"Tự động\" mới được dọn.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Mở Sweepy khi đăng nhập macOS", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Khi tự mở lúc đăng nhập, chỉ hiện trên menu bar", isOn: $model.config.hideWindowAtLogin)
                    .disabled(!model.launchAtLogin)
                    .onChange(of: model.config.hideWindowAtLogin) { model.save() }
                if let message = model.loginItemMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Khởi động")
            } footer: {
                Text("Sweepy sẽ nằm trên menu bar (biểu tượng ✨) để bạn xem dung lượng trống và dọn nhanh. Lịch dọn tự động vẫn chạy kể cả khi tắt tuỳ chọn này.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(model.config.projectRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder")
                        Text(root)
                        Spacer()
                        Button(role: .destructive) {
                            model.config.projectRoots.removeAll { $0 == root }
                            model.save()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Thêm thư mục…") {
                    if let path = pickFolder() {
                        model.config.projectRoots.append(PathUtil.abbreviate(path))
                        model.save()
                    }
                }
            } header: {
                Text("Thư mục chứa dự án code")
            } footer: {
                Text("Sweepy tìm node_modules, .next, build… bên trong các thư mục này.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if model.config.exclusions.isEmpty {
                    Text("Chưa có. Chuột phải vào một mục bất kỳ → \"Luôn bỏ qua đường dẫn này\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.config.exclusions, id: \.self) { path in
                    HStack {
                        Image(systemName: "nosign")
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            model.config.exclusions.removeAll { $0 == path }
                            model.save()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Thêm thư mục loại trừ…") {
                    if let path = pickFolder() {
                        model.addExclusion(path)
                    }
                }
            } header: {
                Text("Không bao giờ xoá")
            }

            Section("Quyền truy cập") {
                Text("Để dọn Thùng rác, cache Safari và một số dữ liệu app khác, hãy cấp quyền Full Disk Access cho Sweepy (System Settings → Privacy & Security → Full Disk Access → thêm Sweepy.app).")
                    .font(.callout)
                Button("Mở cài đặt Full Disk Access") { model.openFullDiskAccessSettings() }
            }

            UpdateSection(updater: model.updater)

            Section("Dữ liệu") {
                LabeledContent("Cấu hình & lịch sử", value: PathUtil.abbreviate(Store.directory.path))
                LabeledContent("Log tự động", value: PathUtil.abbreviate(Store.logURL.path))
                HStack {
                    Button("Mở thư mục cấu hình") { NSWorkspace.shared.open(Store.directory) }
                    Button("Mở log") { NSWorkspace.shared.open(Store.logURL) }
                        .disabled(!FileManager.default.fileExists(atPath: Store.logURL.path))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cài đặt & lịch")
        .onAppear {
            if !loaded { draft = model.config.schedule; loaded = true }
            model.launchAtLogin = LoginItem.isEnabled
        }
    }

    private func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: PathUtil.home)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let entries = model.history.reversed()
        List {
            Section {
                HStack(spacing: 30) {
                    VStack(alignment: .leading) {
                        Text("Tổng đã giải phóng").foregroundStyle(.secondary)
                        Text(Fmt.bytes(model.history.reduce(0) { $0 + $1.freed })).font(.title.bold())
                    }
                    VStack(alignment: .leading) {
                        Text("Số lần dọn").foregroundStyle(.secondary)
                        Text("\(model.history.count)").font(.title.bold())
                    }
                }
                .padding(.vertical, 6)
            }
            if entries.isEmpty {
                Text("Chưa có lần dọn nào.").foregroundStyle(.secondary)
            }
            ForEach(Array(entries)) { entry in
                DisclosureGroup {
                    OutcomeList(outcomes: entry.outcomes.filter { $0.freed > 0 || $0.skipped != nil || !$0.errors.isEmpty })
                        .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text(Fmt.dateTime.string(from: entry.date)).monospacedDigit()
                        Tag(text: entry.trigger.title, symbol: entry.trigger == .auto ? "clock" : "hand.tap")
                        Spacer()
                        Text(Fmt.bytes(entry.freed)).bold().monospacedDigit()
                        Text("→ còn trống \(Fmt.bytes(entry.freeAfter))").foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
        }
        .navigationTitle("Lịch sử")
        .onAppear { model.history = Store.loadHistory() }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "internaldrive")
                Text("Còn trống \(Fmt.bytes(model.disk.available))").font(.headline)
            }
            ProgressView(value: model.disk.usedFraction).tint(model.disk.usedFraction > 0.9 ? .red : .accentColor)
            if !model.scans.isEmpty {
                Text("Có thể dọn \(Fmt.bytes(model.totalFound)) · tự động \(Fmt.bytes(model.autoTotal))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Lịch: \(model.config.schedule.summary)").font(.caption).foregroundStyle(.secondary)
            if model.busy {
                HStack { ProgressView().controlSize(.small); Text(model.status).font(.caption).lineLimit(1) }
            }
            Divider()
            Button { model.runAutoNow() } label: { Label("Dọn các mục tự động ngay", systemImage: "sparkles") }
                .disabled(model.busy)
            Button { model.scan() } label: { Label("Quét lại", systemImage: "arrow.clockwise") }
                .disabled(model.busy)
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label("Mở Sweepy", systemImage: "macwindow") }
            UpdateReadyButton(updater: model.updater)
            Divider()
            Button("Thoát Sweepy") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 280)
        .onAppear { model.refreshDisk() }
    }
}

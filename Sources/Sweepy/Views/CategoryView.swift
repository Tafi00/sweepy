import SwiftUI

struct CategoryView: View {
    @EnvironmentObject var model: AppModel
    let category: RuleCategory
    @State private var editing: Rule?

    var body: some View {
        let rules = model.rules(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.subtitle).foregroundStyle(.secondary)
                    Spacer()
                    if category == .custom {
                        Button { editing = RuleEditor.newRule() } label: { Label("Thêm quy tắc", systemImage: "plus") }
                    }
                    Button("Chọn tất cả") { rules.forEach { model.selected.insert($0.id) } }
                    Button("Bỏ chọn") { rules.forEach { model.selected.remove($0.id) } }
                }
                if rules.isEmpty {
                    Text(category == .custom
                         ? "Chưa có quy tắc tuỳ chỉnh. Ví dụ: dọn thư mục ~/Movies/Recordings cũ hơn 30 ngày."
                         : "Không tìm thấy gì để dọn trong nhóm này.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                }
                ForEach(rules) { rule in
                    RuleCard(rule: rule, onEdit: { editing = rule })
                }
                let hidden = model.hiddenCount(in: category)
                if hidden > 0 {
                    Text("\(hidden) quy tắc khác bị ẩn vì ứng dụng/công cụ tương ứng không có trên máy này.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle(category.title)
        .navigationSubtitle(Fmt.bytes(model.size(of: category)))
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule)
        }
    }
}

struct RuleCard: View {
    @EnvironmentObject var model: AppModel
    let rule: Rule
    var onEdit: () -> Void
    @State private var expanded = false

    var scan: RuleScan? { model.scans[rule.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: model.selectionBinding(rule.id))
                    .toggleStyle(.checkbox).labelsHidden()
                    .help("Tick để dọn khi bấm \"Dọn\"")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.name).font(.headline)
                        SafetyBadge(safety: rule.safety)
                        if rule.deleteMode == .trash { Tag(text: "Thùng rác", symbol: "trash") }
                        if rule.olderThanDays > 0 { Tag(text: "> \(rule.olderThanDays) ngày", symbol: "calendar") }
                        if rule.minIdleDays > 0 { Tag(text: "dự án nghỉ ≥ \(rule.minIdleDays) ngày", symbol: "moon.zzz") }
                        if rule.keepNewest > 0 { Tag(text: "giữ \(rule.keepNewest) bản mới", symbol: "square.stack") }
                        if rule.kind == .largeFiles { Tag(text: "≥ \(rule.minSizeMB) MB", symbol: "doc.zipper") }
                    }
                    Text(rule.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blocked = scan?.blockedBy {
                        HStack(spacing: 8) {
                            Label("\(blocked) đang mở – mục này bị bỏ qua khi dọn.", systemImage: "lock.fill")
                                .font(.caption).foregroundStyle(.orange)
                            if !model.blockingApps([rule.id]).isEmpty {
                                Button("Thoát \(blocked) & dọn") { model.quitRequest = [rule.id] }
                                    .controlSize(.mini).disabled(model.busy)
                            } else {
                                Text("(tiến trình dòng lệnh – hãy tự tắt)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(scan?.notes ?? [], id: \.self) { note in
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    if rule.kind == .command {
                        Text("Lệnh").font(.title3.bold()).foregroundStyle(.secondary)
                    } else if scan == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(Fmt.bytes(model.size(of: rule.id))).font(.title3.bold()).monospacedDigit()
                        Text("\(scan?.items.count ?? 0) mục").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Tự động", isOn: model.binding(rule.id, \.autoClean, default: false))
                        .toggleStyle(.switch).controlSize(.mini)
                        .help("Dọn quy tắc này trong các lần chạy theo lịch")
                }
            }
            DisclosureGroup(isExpanded: $expanded) {
                RuleDetail(rule: rule, onEdit: onEdit).padding(.top, 6)
            } label: {
                Text("Chi tiết & tuỳ chỉnh").font(.callout)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }
}

struct RuleDetail: View {
    @EnvironmentObject var model: AppModel
    let rule: Rule
    var onEdit: () -> Void
    @State private var showAll = false

    var items: [ScanItem] { model.scans[rule.id]?.items ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            settings
            Divider()
            if rule.kind == .command {
                Text("Lệnh: \(rule.command)").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            } else if rule.kind == .projectFolders {
                Text("Tìm thư mục: \(rule.folderNames.joined(separator: ", "))"
                     + (rule.subpath.isEmpty ? "" : " → \(rule.subpath)")
                     + (rule.markers.isEmpty ? "" : " — cạnh file \(rule.markers.joined(separator: " / "))"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if rule.kind == .largeFiles {
                Text("Tìm trong: thư mục dự án, " + rule.paths.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Vị trí: " + rule.paths.joined(separator: "  ·  "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if items.isEmpty && rule.kind != .command {
                Text("Không có mục nào cần dọn.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(showAll ? items : Array(items.prefix(12))) { item in
                ItemRow(item: item)
            }
            if items.count > 12 {
                Button(showAll ? "Thu gọn" : "Xem tất cả \(items.count) mục") { showAll.toggle() }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder private var settings: some View {
        HStack(spacing: 18) {
            if rule.kind == .largeFiles {
                Stepper(value: model.binding(rule.id, \.minSizeMB, default: 500), in: 50...10_000, step: 50) {
                    Text("File từ \(rule.minSizeMB) MB")
                }
            }
            if DefaultRules.all.first(where: { $0.id == rule.id })?.keepNewest ?? 0 > 0 || rule.keepNewest > 0 {
                Stepper(value: model.binding(rule.id, \.keepNewest, default: 1), in: 1...10) {
                    Text("Giữ \(rule.keepNewest) bản mới nhất")
                }
            }
            if [.contents, .paths, .largeFiles, .orphanData].contains(rule.kind) {
                Stepper(value: model.binding(rule.id, \.olderThanDays, default: 0), in: 0...3650, step: rule.olderThanDays >= 30 ? 30 : 1) {
                    Text(rule.olderThanDays == 0 ? "Xoá mọi mục" : "Chỉ mục cũ hơn \(rule.olderThanDays) ngày")
                }
            }
            if rule.kind == .projectFolders {
                Stepper(value: model.binding(rule.id, \.minIdleDays, default: 0), in: 0...3650, step: rule.minIdleDays >= 30 ? 30 : 1) {
                    Text(rule.minIdleDays == 0 ? "Mọi dự án" : "Dự án không sửa ≥ \(rule.minIdleDays) ngày")
                }
            }
            if rule.kind != .command {
                Picker("", selection: model.binding(rule.id, \.deleteMode, default: .permanent)) {
                    ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 190)
            }
            if !rule.skipIfRunning.isEmpty {
                Toggle("Chỉ dọn khi app đã đóng", isOn: model.binding(rule.id, \.onlyWhenAppClosed, default: true))
            }
            Spacer()
            if !rule.builtIn {
                Button("Sửa…", action: onEdit)
                Button("Xoá quy tắc", role: .destructive) { model.deleteCustomRule(rule.id) }
            }
            Button("Quét lại") { model.scan([rule]) }.disabled(model.busy)
            Button("Dọn quy tắc này") { model.requestClean([rule.id]) }
                .disabled(model.busy || (rule.kind != .command && model.size(of: rule.id) == 0))
        }
        .controlSize(.small)
    }
}

struct ItemRow: View {
    @EnvironmentObject var model: AppModel
    let item: ScanItem

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: model.itemBinding(item.path)).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(PathUtil.abbreviate(item.path)).lineLimit(1).truncationMode(.middle)
                if let note = item.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.age(item.date)).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            Text(Fmt.bytes(item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { model.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Hiện trong Finder")
        }
        .font(.callout)
        .contextMenu {
            Button("Hiện trong Finder") { model.reveal(item.path) }
            Button("Luôn bỏ qua đường dẫn này") { model.addExclusion(item.path) }
        }
    }
}

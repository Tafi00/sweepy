import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.sidebar) {
                Section {
                    Label("Tổng quan", systemImage: "gauge.with.dots.needle.67percent")
                        .tag(SidebarItem.overview)
                }
                Section("Nhóm rác") {
                    ForEach(RuleCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol)
                            .badge(badge(for: category))
                            .tag(SidebarItem.category(category))
                    }
                }
                Section {
                    Label("Lịch sử", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                    Label("Cài đặt & lịch", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { DiskFooter().padding(12) }
        } detail: {
            switch model.sidebar ?? .overview {
            case .overview: OverviewView()
            case .category(let c): CategoryView(category: c)
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: 280)
                }
                Button { model.scan() } label: { Label("Quét lại", systemImage: "arrow.clockwise") }
                    .disabled(model.busy)
                    .help("Quét lại toàn bộ (⌘R)")
                Button { model.requestClean(Array(model.selected)) } label: {
                    Label("Dọn \(Fmt.bytes(model.selectedTotal))", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(model.busy || model.selectedTotal == 0)
                .help("Dọn các quy tắc đang được tick")
            }
        }
        .sheet(item: Binding(get: { model.pendingClean.map(PendingClean.init) }, set: { model.pendingClean = $0?.ids })) { pending in
            ConfirmCleanSheet(ids: pending.ids)
        }
        .sheet(item: $model.lastResult) { entry in
            ResultSheet(entry: entry)
        }
        .task {
            if model.scans.isEmpty { model.scan() }
        }
    }

    private func badge(for category: RuleCategory) -> Text? {
        let size = model.size(of: category)
        return size > 0 ? Text(Fmt.bytes(size)) : nil
    }
}

struct PendingClean: Identifiable {
    let ids: [String]
    var id: String { ids.joined(separator: ",") }
}

struct DiskFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive")
                Text("Còn trống \(Fmt.bytes(model.disk.available))").font(.callout.weight(.medium))
            }
            ProgressView(value: model.disk.usedFraction)
                .tint(model.disk.usedFraction > 0.9 ? .red : .accentColor)
            Text("\(Fmt.bytes(model.disk.used)) / \(Fmt.bytes(model.disk.total)) đã dùng")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SafetyBadge: View {
    let safety: Safety
    var body: some View {
        Text(safety.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(safety.color.opacity(0.15), in: Capsule())
            .foregroundStyle(safety.color)
            .help(safety.help)
    }
}

struct Tag: View {
    let text: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
    }
}

struct ConfirmCleanSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ids: [String]

    var rules: [Rule] { model.rules.filter { ids.contains($0.id) } }
    var total: Int64 { model.uniqueItems(ids, respectUnticked: true).reduce(0) { $0 + $1.item.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dọn \(Fmt.bytes(total))?").font(.title2.bold())
            Text("Các quy tắc sau sẽ được chạy. Mục \"Xoá vĩnh viễn\" không khôi phục được.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rules) { rule in
                        HStack {
                            Text(rule.name)
                            SafetyBadge(safety: rule.safety)
                            if let blocked = model.scans[rule.id]?.blockedBy {
                                Tag(text: "\(blocked) đang chạy – sẽ bỏ qua", symbol: "exclamationmark.triangle")
                            }
                            Spacer()
                            Text(rule.kind == .command ? "lệnh" : Fmt.bytes(model.size(of: rule.id)))
                                .monospacedDigit()
                            Tag(text: rule.deleteMode.title, symbol: rule.deleteMode == .trash ? "trash" : "xmark.bin")
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Dọn ngay") {
                    let ids = self.ids
                    dismiss()
                    model.clean(ids)
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct ResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Đã giải phóng \(Fmt.bytes(entry.freed))").font(.title2.bold())
                    Text("Ổ đĩa còn trống \(Fmt.bytes(entry.freeAfter)) (trước đó \(Fmt.bytes(entry.freeBefore)))")
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView { OutcomeList(outcomes: entry.outcomes) }.frame(maxHeight: 320)
            HStack { Spacer(); Button("Đóng") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct OutcomeList: View {
    let outcomes: [RuleOutcome]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(outcomes) { o in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(o.ruleName)
                        Spacer()
                        if let s = o.skipped {
                            Text("Bỏ qua: \(s)").foregroundStyle(.orange).font(.callout)
                        } else {
                            Text("\(Fmt.bytes(o.freed)) · \(o.itemCount) mục").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    ForEach(o.errors.prefix(5), id: \.self) { e in
                        Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
            }
        }
    }
}

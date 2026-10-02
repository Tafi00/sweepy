import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var topItems: [(rule: Rule, item: ScanItem)] {
        let rules = Dictionary(uniqueKeysWithValues: model.rules.map { ($0.id, $0) })
        // Attribute items to specific rules rather than the catch-all cache rule.
        return model.uniqueItems(model.rules.map(\.id).filter { $0 != "sys.caches-all" })
            .compactMap { entry in rules[entry.ruleID].map { (rule: $0, item: entry.item) } }
            .sorted { $0.item.size > $1.item.size }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    diskCard
                    reclaimCard
                }
                categoryCard
                if !topItems.isEmpty { topItemsCard }
                scheduleCard
            }
            .padding(24)
        }
        .navigationTitle("Tổng quan")
    }

    private var diskCard: some View {
        Card {
            Label("Ổ đĩa", systemImage: "internaldrive").font(.headline)
            Text(Fmt.bytes(model.disk.available))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(model.disk.usedFraction > 0.9 ? .red : .primary)
            Text("còn trống trên \(Fmt.bytes(model.disk.total))").foregroundStyle(.secondary)
            ProgressView(value: model.disk.usedFraction)
                .tint(model.disk.usedFraction > 0.9 ? .red : .accentColor)
            Text(String(format: "Đã dùng %.0f%%", model.disk.usedFraction * 100))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var reclaimCard: some View {
        Card {
            Label("Có thể dọn", systemImage: "sparkles").font(.headline)
            if model.isScanning && model.scans.isEmpty {
                ProgressView(value: model.progress)
                Text("Đang quét…").foregroundStyle(.secondary)
            } else {
                Text(Fmt.bytes(model.totalFound))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text("Đã chọn \(Fmt.bytes(model.selectedTotal)) · tự động \(Fmt.bytes(model.autoTotal))")
                    .foregroundStyle(.secondary)
                if model.waitingTotal > 0 {
                    Label("\(Fmt.bytes(model.waitingTotal)) chờ đóng \(model.waitingApps.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .help("Các mục này chỉ được dọn khi app đã thoát hẳn (⌘Q).")
                }
                HStack {
                    Button {
                        model.requestClean(Array(model.selected))
                    } label: {
                        Label("Dọn mục đã chọn", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.selectedTotal == 0)
                    if let date = model.lastScan {
                        Text("Quét lúc \(Fmt.dateTime.string(from: date))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var categoryCard: some View {
        Card {
            Text("Theo nhóm").font(.headline)
            let maxSize = max(1, RuleCategory.allCases.map { model.size(of: $0) }.max() ?? 1)
            ForEach(RuleCategory.allCases) { category in
                let size = model.size(of: category)
                Button {
                    model.sidebar = .category(category)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.symbol).frame(width: 20).foregroundStyle(.tint)
                        Text(category.title).frame(width: 170, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: size == 0 ? 0 : max(2, geo.size.width * CGFloat(Double(size) / Double(maxSize))))
                        }
                        .frame(height: 8)
                        Text(Fmt.bytes(size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topItemsCard: some View {
        Card {
            Text("Mục lớn nhất").font(.headline)
            ForEach(topItems, id: \.item.path) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PathUtil.abbreviate(entry.item.path)).lineLimit(1).truncationMode(.middle)
                        Text(entry.rule.name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let blocked = model.scans[entry.rule.id]?.blockedBy {
                        Tag(text: "\(blocked) đang chạy", symbol: "exclamationmark.triangle", color: .orange)
                    } else if entry.rule.autoClean {
                        Tag(text: "tự động", symbol: "clock")
                    }
                    Text(Fmt.bytes(entry.item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                }
                .contextMenu {
                    Button("Hiện trong Finder") { model.reveal(entry.item.path) }
                    Button("Luôn bỏ qua đường dẫn này") { model.addExclusion(entry.item.path) }
                }
            }
        }
    }

    private var scheduleCard: some View {
        Card {
            HStack {
                Label("Dọn tự động", systemImage: "calendar.badge.clock").font(.headline)
                Spacer()
                Button("Thiết lập lịch") { model.sidebar = .settings }
                Button("Chạy các mục tự động ngay") { model.runAutoNow() }.disabled(model.busy)
            }
            Text(model.config.schedule.summary
                 + (model.config.minFreeGB > 0 ? " · chỉ khi còn trống dưới \(model.config.minFreeGB) GB" : ""))
                .foregroundStyle(model.config.schedule.frequency == .off ? .orange : .primary)
            if let last = model.lastAutoRun {
                Text("Lần tự động gần nhất: \(Fmt.dateTime.string(from: last.date)) – giải phóng \(Fmt.bytes(last.freed))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("\(model.rules.filter(\.autoClean).count) quy tắc đang bật chế độ tự động. Bật/tắt bằng công tắc \"Tự động\" ở từng quy tắc.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
    }
}

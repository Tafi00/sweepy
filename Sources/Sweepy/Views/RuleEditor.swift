import SwiftUI

struct RuleEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    @State private var pathsText = ""
    @State private var extensionsText = ""
    @State private var appsText = ""

    static func newRule() -> Rule {
        Rule(id: "custom." + UUID().uuidString.prefix(8).lowercased(), name: "", category: .custom,
             safety: .review, kind: .contents, builtIn: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Tên", text: $rule.name, prompt: Text("VD: Video quay màn hình cũ"))
                TextField("Mô tả", text: $rule.detail)
                Picker("Kiểu", selection: $rule.kind) {
                    Text(RuleKind.contents.title).tag(RuleKind.contents)
                    Text(RuleKind.paths.title).tag(RuleKind.paths)
                    Text(RuleKind.command.title).tag(RuleKind.command)
                }
                if rule.kind == .command {
                    TextField("Lệnh", text: $rule.command, prompt: Text("VD: docker system prune -f"))
                        .font(.system(.body, design: .monospaced))
                } else {
                    VStack(alignment: .leading) {
                        Text(rule.kind == .contents
                             ? "Thư mục (mỗi dòng một đường dẫn). Mọi thứ BÊN TRONG sẽ bị dọn."
                             : "Đường dẫn cần xoá (mỗi dòng một dòng, hỗ trợ ~ và *).")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $pathsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    }
                    Stepper(value: $rule.olderThanDays, in: 0...3650) {
                        Text(rule.olderThanDays == 0 ? "Xoá mọi mục" : "Chỉ mục cũ hơn \(rule.olderThanDays) ngày")
                    }
                    Picker("Tính tuổi theo", selection: $rule.ageBasis) {
                        Text("Lần sửa cuối").tag(AgeBasis.modified)
                        Text("Ngày được thêm vào thư mục").tag(AgeBasis.added)
                    }
                    TextField("Chỉ đuôi file", text: $extensionsText, prompt: Text("VD: mov, mp4 (để trống = tất cả)"))
                    Picker("Cách xoá", selection: $rule.deleteMode) {
                        ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                TextField("Bỏ qua khi app đang chạy", text: $appsText, prompt: Text("Bundle ID, VD: com.apple.Music"))
                Picker("Mức an toàn", selection: $rule.safety) {
                    ForEach(Safety.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Dọn tự động theo lịch", isOn: $rule.autoClean)
            }
            .formStyle(.grouped)

            HStack {
                Text("Sweepy không bao giờ xoá ngoài thư mục người dùng, hay ~/Desktop, ~/Documents… ở cấp gốc.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lưu") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (rule.kind == .command ? rule.command.isEmpty : lines(pathsText).isEmpty))
            }
            .padding(16)
        }
        .frame(width: 600, height: 620)
        .onAppear {
            pathsText = rule.paths.joined(separator: "\n")
            extensionsText = rule.extensions.joined(separator: ", ")
            appsText = rule.skipIfRunning.joined(separator: ", ")
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        rule.paths = lines(pathsText)
        rule.extensions = list(extensionsText).map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        rule.skipIfRunning = list(appsText)
        rule.category = .custom
        rule.builtIn = false
        model.saveCustomRule(rule)
        dismiss()
    }
}

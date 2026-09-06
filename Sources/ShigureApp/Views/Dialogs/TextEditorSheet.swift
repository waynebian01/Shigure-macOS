import SwiftUI

/// 多行文本编辑（规则注释 / 公式）。
struct TextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringResource
    @State var text: String
    var confirmTitle: LocalizedStringResource = "确定"
    var monospaced = false
    var hint: LocalizedStringResource?
    let onConfirm: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.title3.bold()).padding(12)
            Divider()
            TextEditor(text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .padding(8)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 6) }
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { onConfirm(text); dismiss() } label: { Text(confirmTitle) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 320)
    }
}

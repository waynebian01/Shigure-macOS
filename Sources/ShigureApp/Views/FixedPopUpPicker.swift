import AppKit
import SwiftUI

// MARK: - 固定宽度下拉（NSPopUpButton）

/// macOS 的 SwiftUI Picker 按最长菜单项自适应宽度、忽略 frame 提议的宽度，
/// 同一列的下拉因此参差不齐；直接包 NSPopUpButton 让控件吃满列宽。
struct PopUpOption<Tag: Hashable> {
    let tag: Tag
    let title: String
    var image: NSImage?
    var titleColor: NSColor?

    init(_ tag: Tag, _ title: String, image: NSImage? = nil, titleColor: NSColor? = nil) {
        self.tag = tag
        self.title = title
        self.image = image
        self.titleColor = titleColor
    }
}

struct FixedPopUpPicker<Tag: Hashable>: NSViewRepresentable {
    let options: [PopUpOption<Tag>]
    @Binding var selection: Tag

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let signature = options.map { option in
            "\(option.tag)|\(option.title)|\(option.image.map { ObjectIdentifier($0).hashValue } ?? 0)|\(option.titleColor != nil)"
        }
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            let menu = NSMenu()
            for option in options {
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                item.image = option.image
                if let color = option.titleColor {
                    item.attributedTitle = NSAttributedString(string: option.title, attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 0)])
                }
                menu.addItem(item)
            }
            button.menu = menu
        }
        button.selectItem(at: options.firstIndex { $0.tag == selection } ?? -1)
        button.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        if let width = proposal.width, width.isFinite { return CGSize(width: width, height: intrinsic.height) }
        return intrinsic
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FixedPopUpPicker
        var signature: [String] = []

        init(_ parent: FixedPopUpPicker) { self.parent = parent }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].tag
        }
    }
}

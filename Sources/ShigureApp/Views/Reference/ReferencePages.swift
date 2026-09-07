import SwiftUI
import ShigureCore

struct BossNumbersPage: View {
    var body: some View {
        List {
            ForEach(ReferenceData.seasonBossGroups) { group in
                Section(localizedReferenceText(group.title)) {
                    ForEach(group.dungeons) { dungeon in
                        DisclosureGroup {
                            ForEach(dungeon.bosses) { boss in
                                HStack {
                                    Text("\(boss.sequence)").foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                    Text(boss.name)
                                    Spacer().frame(width: 12)
                                    Text("\(boss.number)")
                                        .foregroundStyle(.tint)
                                        .monospacedDigit()
                                        .frame(width: 36, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            Label(dungeon.name, systemImage: "list.number")
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct CommonFieldsPage: View {
    var body: some View {
        List {
            ForEach(ReferenceData.commonFieldCards, id: \.title) { card in
                Section(localizedReferenceText(card.title)) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ], alignment: .leading, spacing: 0) {
                        ForEach(card.names, id: \.self) { name in
                            Text(name)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct AboutPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ReferenceData.productName).font(.largeTitle.bold())
                        Text(localizedReferenceText(ReferenceData.productTagline)).foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            row("产品", ReferenceData.productName)
                            row("公司", AppInfo.company)
                            row("版本", AppInfo.version)
                            row("类型", String(localized: "冲锋枪"))
                            row("数据目录", model.paths.root.path)
                            row("模块目录", model.paths.moduleDirectory.path)
                            row("配置目录", model.paths.configDirectory.path)
                            row("插件源", model.paths.fuyutsuiDirectory.path)
                            row("游戏插件目录", model.addOnsDirectory?.path ?? String(localized: "未检测到游戏"))
                        }
                        HStack {
                            Button("在 Finder 中显示数据目录") { model.revealInFinder(model.paths.root) }
                            Button("打开模块目录") { model.openModuleDirectory() }
                        }
                    }
                    Spacer()
                    if let url = Bundle.main.url(forResource: "arasaka-logo-transparent", withExtension: "png", subdirectory: "Icons"),
                       let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 160).opacity(0.55)
                    }
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

                article("免责声明", ReferenceData.disclaimer)
                article("许可证", ReferenceData.mitLicense)
                ForEach(ReferenceData.attributions, id: \.title) { item in
                    article(LocalizedStringResource(String.LocalizationValue(item.title)), item.body)
                }
            }
            .padding(16)
        }
    }

    private func row(_ label: LocalizedStringResource, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }

    private func article(_ title: LocalizedStringResource, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(title) } icon: { Image(systemName: "scalemass") }.font(.headline)
            Text(localizedReferenceText(body)).font(.callout).textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

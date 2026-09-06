import SwiftUI
import ShigureCore

/// 通用页「下载数据包」：状态 + 检查/下载 + 进度/取消。
struct IconPackCard: View {
    @Environment(AppModel.self) private var model
    @State private var progressMessage: String?
    @State private var percentage: Int?
    @State private var task: Task<Void, Never>?
    @State private var resultMessage: String?
    @State private var failed = false

    var body: some View {
        LabeledContent("下载数据包") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(progressMessage ?? resultMessage ?? statusText)
                        .font(.callout)
                        .foregroundStyle(failed ? .orange : .secondary)
                        .lineLimit(2)
                    Spacer()
                    if task != nil {
                        if let percentage { ProgressView(value: Double(percentage), total: 100).frame(width: 120) } else { ProgressView().controlSize(.small) }
                        Button("取消") { task?.cancel() }
                    } else {
                        Button(buttonTitle) { start() }
                    }
                }
                if failed {
                    Link("到 GitHub 发布页手动下载 SpellIcons.shgpack", destination: IconPackDownloader.releasesPageURL).font(.caption)
                    Text("保存到: \(model.paths.iconPackFile.path)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        let catalog = model.iconCatalog
        if catalog.isPackageAvailable {
            let size = String(format: "%.2f MiB", catalog.packageSizeMiB)
            return catalog.isItemDatabaseAvailable
                ? "已安装完整包：\(size)。点击检查 GitHub 更新。"
                : "已安装仅技能旧包：\(size)。物品搜索库不可用，可检查更新以获取完整包。"
        }
        if catalog.loadError != nil { return "本地数据包损坏或格式不受支持；技能/物品图标与添加联想不可用。" }
        return "未安装；技能/物品图标与添加技能、物品联想不可用。"
    }

    private var buttonTitle: String {
        if model.iconCatalog.isPackageAvailable { return "检查更新" }
        return model.iconCatalog.loadError != nil ? "重新下载" : "下载数据包"
    }

    private func start() {
        failed = false
        resultMessage = nil
        let downloader = IconPackDownloader(targetURL: model.paths.iconPackFile)
        let localAvailable = model.iconCatalog.isPackageAvailable
        task = Task {
            do {
                let outcome = try await downloader.update(localAvailable: localAvailable) { progress in
                    Task { @MainActor in
                        progressMessage = progress.message
                        percentage = progress.percentage
                    }
                }
                model.iconCatalog.reload()
                let kind = model.iconCatalog.isItemDatabaseAvailable ? "完整包" : "仅技能旧包"
                let size = String(format: "%.2f MiB", Double(outcome.size) / 1024 / 1024)
                resultMessage = (outcome.upToDate ? "已是最新" : "安装完成") + "（\(kind)）：\(size)，SHA-256 \(outcome.sha256.prefix(12))…"
                model.log.append(outcome.upToDate ? "技能/物品图标数据包已是最新" : "技能/物品图标数据包已下载、校验并热加载")
            } catch is CancellationError {
                resultMessage = "下载已取消；原数据包未修改。"
            } catch let error as URLError where error.code == .cancelled {
                resultMessage = "下载已取消；原数据包未修改。"
            } catch {
                failed = true
                resultMessage = "下载失败：\(error.localizedDescription)"
                model.log.append("数据包下载失败: \(error)")
            }
            progressMessage = nil
            percentage = nil
            task = nil
        }
    }
}

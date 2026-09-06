import Foundation
import Testing
@testable import ShigureCore

/// 联网的端到端下载验证：默认跳过，需要显式开启（会下载约 300 MiB）。
///     SHIGURE_NETWORK_TEST=1 swift test --filter 图标包联网下载
@Suite("图标包联网下载", .enabled(if: ProcessInfo.processInfo.environment["SHIGURE_NETWORK_TEST"] == "1"))
struct IconPackNetworkTests {
    @Test("下载、校验、验包、安装全流程")
    func fullDownload() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shigure-packtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("SpellIcons.shgpack")

        let percents = Mutex<[Int]>([])
        let started = Date()
        let outcome = try await IconPackDownloader(targetURL: target).update(localAvailable: false) { progress in
            if let p = progress.percentage { percents.withLock { $0.append(p) } }
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(outcome.changed)
        #expect(!outcome.upToDate)
        #expect(outcome.size > 100 << 20)
        #expect(outcome.sha256.count == 64)

        let onDisk = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? 0
        #expect(onDisk == outcome.size)
        #expect(try IconPackDownloader.sha256(of: target) == outcome.sha256)

        // 进度必须真的在跳，否则说明 delegate 回调没接上。
        let ticks = percents.withLock { $0 }
        #expect(ticks.count > 20, "只收到 \(ticks.count) 次进度回调")
        #expect(ticks == ticks.sorted())

        // 装好的包必须能被目录读取器打开。
        let catalog = try ShgPackReader(url: target)
        #expect(!catalog.allSpellIds.isEmpty)
        #expect(catalog.hasItemDatabase)

        let mib = Double(outcome.size) / 1024 / 1024
        print(String(format: "下载 %.1f MiB 用时 %.0fs（%.2f MiB/s），进度回调 %d 次", mib, elapsed, mib / elapsed, ticks.count))
    }
}

/// 测试用的最小互斥容器。
private final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

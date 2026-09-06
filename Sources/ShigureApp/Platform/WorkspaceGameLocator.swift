import AppKit
import CoreGraphics
import ShigureCore

/// 定位游戏进程与其最前的可见窗口（对应 C# WowProcessLocator）。
/// 候选进程按 bundle identifier 或进程名匹配；窗口取 CGWindowList 前→后 Z 序中第一个属于候选进程的普通层窗口。
final class WorkspaceGameLocator: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String]
    private var cache: (target: GameTarget?, at: ContinuousClock.Instant)?
    private let cacheTTL: Duration = .milliseconds(200)

    init(identifiers: [String]) {
        self.identifiers = identifiers
    }

    func setIdentifiers(_ values: [String]) {
        lock.withLock {
            identifiers = values
            cache = nil
        }
    }

    var configuredIdentifiers: [String] { lock.withLock { identifiers } }

    func describeConfigured() -> String {
        let ids = configuredIdentifiers.filter { !$0.isEmpty }
        return ids.isEmpty ? String(localized: "未配置") : ids.joined(separator: String(localized: "、"))
    }

    private func matches(_ app: NSRunningApplication, _ ids: [String]) -> Bool {
        for id in ids where !id.isEmpty {
            if let bundleId = app.bundleIdentifier, bundleId.caseInsensitiveCompare(id) == .orderedSame { return true }
            if let name = app.localizedName, name.caseInsensitiveCompare(id) == .orderedSame { return true }
            if let exe = app.executableURL?.lastPathComponent, exe.caseInsensitiveCompare(id) == .orderedSame { return true }
        }
        return false
    }

    func runningGameApplications() -> [NSRunningApplication] {
        let ids = configuredIdentifiers
        return NSWorkspace.shared.runningApplications.filter { matches($0, ids) }
    }

    /// 最前的候选窗口；结果缓存 200ms（发送与扫描每 tick 都会调用）。
    func currentTarget() -> GameTarget? {
        let now = ContinuousClock.now
        if let cache = lock.withLock({ cache }), now - cache.at < cacheTTL {
            return cache.target
        }
        let target = locate()
        lock.withLock { cache = (target, now) }
        return target
    }

    func invalidate() {
        lock.withLock { cache = nil }
    }

    private func locate() -> GameTarget? {
        let apps = runningGameApplications()
        guard !apps.isEmpty else { return nil }
        let pids = Set(apps.map(\.processIdentifier))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(pid) else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            guard bounds.width >= 64, bounds.height >= 64 else { continue }
            let app = apps.first { $0.processIdentifier == pid }
            return GameTarget(pid: pid, windowID: number, bounds: bounds, bundleURL: app?.bundleURL)
        }
        return nil
    }

    /// 用户显式指定的游戏 .app（设置中选择）；为空时自动定位。
    var preferredGameAppURL: URL? {
        get { lock.withLock { preferredApp } }
        set { lock.withLock { preferredApp = newValue } }
    }
    private var preferredApp: URL?

    /// 游戏 .app 位置：运行中的进程 → 用户指定 → 已安装应用中优先正式服（_retail_）。
    /// 正式服/怀旧服共用同一 bundle identifier，不能只取 LaunchServices 返回的第一个。
    func gameBundleURL() -> URL? {
        if let running = runningGameApplications().first?.bundleURL { return running }
        if let preferred = preferredGameAppURL, FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        var candidates: [URL] = []
        for id in configuredIdentifiers where id.contains(".") {
            candidates.append(contentsOf: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id))
        }
        if let retail = candidates.first(where: { $0.path.contains("_retail_") }) { return retail }
        return candidates.first
    }

    /// 所有已安装的候选游戏 .app（供设置页选择）。
    func installedGameApps() -> [URL] {
        var result: [URL] = []
        for id in configuredIdentifiers where id.contains(".") {
            for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) where !result.contains(url) {
                result.append(url)
            }
        }
        return result.sorted { ($0.path.contains("_retail_") ? 0 : 1, $0.path) < ($1.path.contains("_retail_") ? 0 : 1, $1.path) }
    }

    /// 部署目标 AddOns 目录（找不到游戏返回 nil）。
    func addOnsDirectory() -> URL? {
        gameBundleURL().map { WowAddonLocator.findAddOnsDirectory(bundleURL: $0) }
    }
}

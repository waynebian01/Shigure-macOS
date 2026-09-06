import Foundation
import CryptoKit

/// 从 GitHub Release 下载 SpellIcons.shgpack（四级回退），校验 SHA-256 后原子安装。
public struct IconPackDownloader: Sendable {
    public static let latestReleaseApiURL = URL(string: "https://api.github.com/repos/waynebian01/Shigure/releases/latest")!
    public static let releasesApiURL = URL(string: "https://api.github.com/repos/waynebian01/Shigure/releases?per_page=20")!
    public static let latestBrowserDownloadURL = URL(string: "https://github.com/waynebian01/Shigure/releases/latest/download/SpellIcons.shgpack")!
    public static let releasesPageURL = ReferenceData.releasesPageURL
    public static let assetName = "SpellIcons.shgpack"

    public struct Progress: Sendable {
        public let message: String
        public let percentage: Int?
    }

    public struct Outcome: Sendable {
        public let changed: Bool
        public let upToDate: Bool
        public let size: Int64
        public let sha256: String
    }

    struct ReleaseAsset: Sendable {
        let downloadURL: URL
        let size: Int64?
        let sha256: String?
    }

    public struct DownloadError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    public let targetURL: URL
    public let currentVersionTag: String

    public init(targetURL: URL, currentVersionTag: String = AppInfo.version) {
        self.targetURL = targetURL
        self.currentVersionTag = currentVersionTag
    }

    private var sessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": "Shigure/1.0", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 3600
        return config
    }

    private var session: URLSession { URLSession(configuration: sessionConfiguration) }

    /// 检查并更新；`localAvailable` 表示当前本地包可打开。
    public func update(localAvailable: Bool, progress: @escaping @Sendable (Progress) -> Void) async throws -> Outcome {
        let asset = try await resolveLatestAsset(progress: progress)
        let fm = FileManager.default
        if fm.fileExists(atPath: targetURL.path), localAvailable {
            let localSize = (try? fm.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
            if let remoteHash = asset.sha256 {
                progress(Progress(message: "正在比较本地与远端 SHA-256……", percentage: nil))
                let localHash = try Self.sha256(of: targetURL)
                if localHash.caseInsensitiveCompare(remoteHash) == .orderedSame {
                    return Outcome(changed: false, upToDate: true, size: asset.size ?? localSize, sha256: localHash)
                }
            } else if let remoteSize = asset.size, remoteSize == localSize {
                progress(Progress(message: "正在比较本地与远端文件大小……", percentage: nil))
                return Outcome(changed: false, upToDate: true, size: remoteSize, sha256: try Self.sha256(of: targetURL))
            }
        }
        let dataDirectory = targetURL.deletingLastPathComponent()
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let temporary = dataDirectory.appendingPathComponent(".\(Self.assetName).\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).download")
        defer { try? fm.removeItem(at: temporary) }
        let (hash, size) = try await download(asset, to: temporary, progress: progress)
        if let expected = asset.sha256, hash.caseInsensitiveCompare(expected) != .orderedSame {
            throw DownloadError(message: "数据包 SHA-256 校验失败：远端 \(expected)，下载结果 \(hash)。")
        }
        progress(Progress(message: "正在验证并安装数据包……", percentage: 100))
        try ShgPackReader.validate(temporary)
        try install(from: temporary)
        return Outcome(changed: true, upToDate: false, size: size, sha256: hash)
    }

    /// 原子替换目标文件；失败时恢复备份。
    func install(from downloaded: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: targetURL.path) {
            _ = try fm.replaceItemAt(targetURL, withItemAt: downloaded, backupItemName: "\(Self.assetName).backup", options: [.usingNewMetadataOnly])
        } else {
            try fm.moveItem(at: downloaded, to: targetURL)
        }
    }

    private func resolveLatestAsset(progress: @escaping @Sendable (Progress) -> Void) async throws -> ReleaseAsset {
        var errors: [String] = []
        progress(Progress(message: "正在读取 GitHub 最新正式版本……", percentage: nil))
        if let asset = await attempt({ try await assetFromRelease(url: Self.latestReleaseApiURL) }, &errors) { return asset }
        progress(Progress(message: "正在改用 GitHub 发布列表……", percentage: nil))
        if let asset = await attempt({ try await assetFromReleaseList() }, &errors) { return asset }
        progress(Progress(message: "正在改用 GitHub 发布页直链……", percentage: nil))
        if let asset = await attempt({ try await assetFromDirectLink(Self.latestBrowserDownloadURL) }, &errors) { return asset }
        progress(Progress(message: "正在改用当前版本 \(currentVersionTag) 发布页……", percentage: nil))
        let versioned = URL(string: "https://github.com/waynebian01/Shigure/releases/download/\(currentVersionTag)/\(Self.assetName)")!
        if let asset = await attempt({ try await assetFromDirectLink(versioned) }, &errors) { return asset }
        throw DownloadError(message: "无法获取数据包下载地址：" + errors.joined(separator: "；"))
    }

    private func attempt(_ operation: () async throws -> ReleaseAsset?, _ errors: inout [String]) async -> ReleaseAsset? {
        do {
            return try await operation()
        } catch {
            errors.append(error.localizedDescription)
            return nil
        }
    }

    private func assetFromRelease(url: URL) async throws -> ReleaseAsset? {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError(message: "GitHub API 返回 \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard case .object(let release) = try JSONParser.parse(data: data) else { return nil }
        return Self.readAsset(release)
    }

    private func assetFromReleaseList() async throws -> ReleaseAsset? {
        let (data, response) = try await session.data(from: Self.releasesApiURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError(message: "GitHub API 返回 \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard case .array(let releases) = try JSONParser.parse(data: data) else { return nil }
        let candidates = releases.compactMap(\.objectValue).filter { JSONHelpers.getBool($0["draft"]) != true }
        if let stable = candidates.first(where: { JSONHelpers.getBool($0["prerelease"]) != true }), let asset = Self.readAsset(stable) { return asset }
        if let pre = candidates.first, let asset = Self.readAsset(pre) { return asset }
        return nil
    }

    static func readAsset(_ release: JSONObject) -> ReleaseAsset? {
        guard let assets = release.array("assets") else { return nil }
        for node in assets {
            guard let asset = node.objectValue, asset["name"]?.stringValue == assetName, asset["state"]?.stringValue == "uploaded",
                  let size = JSONHelpers.getLong(asset["size"]), size > 0,
                  let urlText = asset["browser_download_url"]?.stringValue, let url = URL(string: urlText), url.scheme == "https" else { continue }
            var sha: String?
            if let digest = asset["digest"]?.stringValue, digest.lowercased().hasPrefix("sha256:") {
                let hex = String(digest.dropFirst(7))
                if hex.count == 64 { sha = hex.uppercased() }
            }
            return ReleaseAsset(downloadURL: url, size: size, sha256: sha)
        }
        return nil
    }

    private func assetFromDirectLink(_ url: URL) async throws -> ReleaseAsset? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    let size = http.expectedContentLength > 0 ? http.expectedContentLength : nil
                    return ReleaseAsset(downloadURL: url, size: size, sha256: nil)
                }
                if http.statusCode == 405 || http.statusCode == 403 { return ReleaseAsset(downloadURL: url, size: nil, sha256: nil) }
                throw DownloadError(message: "直链返回 \(http.statusCode)")
            }
        } catch let error as URLError where error.code == .timedOut {
            return ReleaseAsset(downloadURL: url, size: nil, sha256: nil)
        }
        return ReleaseAsset(downloadURL: url, size: nil, sha256: nil)
    }

    /// 用 `URLSessionDownloadTask` 落盘：逐字节迭代 `AsyncBytes` 只有约 0.2 MiB/s，对 300 MiB 的包不可用。
    /// 必须走纯 delegate（不带 completionHandler），否则 `didWriteData` 不回调、进度条是死的。
    private func download(_ asset: ReleaseAsset, to destination: URL, progress: @escaping @Sendable (Progress) -> Void) async throws -> (String, Int64) {
        let observer = DownloadProgressObserver(destination: destination, declaredSize: asset.size, progress: progress)
        let session = URLSession(configuration: sessionConfiguration, delegate: observer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    observer.start(session: session, url: asset.downloadURL, continuation: continuation)
                }
            } onCancel: {
                observer.cancel()
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        let total = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        if let expected = asset.size, total != expected {
            throw DownloadError(message: "下载的数据大小 \(total) 与声明的 \(expected) 不一致")
        }
        progress(Progress(message: "正在校验 SHA-256……", percentage: 100))
        return (try Self.sha256(of: destination), total)
    }

    /// 分块读取，避免把整包读进内存（图标包约 300 MiB）。
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }
}

/// 下载任务的会话级 delegate：负责进度、落盘与结果回传。
private final class DownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let declaredSize: Int64?
    private let progress: @Sendable (IconPackDownloader.Progress) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionTask?
    private var moveError: Error?
    private var cancelled = false
    private var lastPercent = -1

    init(destination: URL, declaredSize: Int64?, progress: @escaping @Sendable (IconPackDownloader.Progress) -> Void) {
        self.destination = destination
        self.declaredSize = declaredSize
        self.progress = progress
    }

    func start(session: URLSession, url: URL, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let task = session.downloadTask(with: url)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = declaredSize ?? (totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        guard let expected, expected > 0 else {
            progress(IconPackDownloader.Progress(message: "正在下载 \(totalBytesWritten / 1024 / 1024) MiB……", percentage: nil))
            return
        }
        let percent = Int(min(totalBytesWritten, expected) * 100 / expected)
        lock.lock()
        let changed = percent != lastPercent
        if changed { lastPercent = percent }
        lock.unlock()
        if changed { progress(IconPackDownloader.Progress(message: "正在下载 \(percent)%", percentage: percent)) }
    }

    /// 回调返回后临时文件即被删除，必须在此同步搬走。
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
        } catch {
            lock.lock()
            moveError = error
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let moveError = self.moveError
        lock.unlock()
        if let error { finish(.failure(error)) }
        else if let moveError { finish(.failure(moveError)) }
        else if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(IconPackDownloader.DownloadError(message: "下载失败，HTTP \(http.statusCode)")))
        } else {
            finish(.success(()))
        }
    }
}

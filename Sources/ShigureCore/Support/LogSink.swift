import Foundation
import os

public struct LogEntry: Sendable, Identifiable, Equatable {
    public let id: UInt64
    public let time: Date
    public let message: String

    public var formatted: String {
        "\(LogEntry.timeFormatter.string(from: time))  \(message)"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// 有界日志环形缓冲 + 文件落盘（~/Library/Logs/Shigure/）。线程安全。
public final class LogSink: @unchecked Sendable {
    public let capacity: Int
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private var nextId: UInt64 = 1
    private var fileHandle: FileHandle?
    private let logger = Logger(subsystem: "club.shigure.Shigure", category: "runtime")
    private var listeners: [UUID: @Sendable (LogEntry) -> Void] = [:]

    public init(capacity: Int = 2000, fileDirectory: URL? = nil) {
        self.capacity = capacity
        if let fileDirectory {
            try? FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let url = fileDirectory.appendingPathComponent("shigure-\(formatter.string(from: Date())).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: url)
            _ = try? fileHandle?.seekToEnd()
        }
    }

    public func append(_ message: String) {
        let entry: LogEntry = lock.withLock {
            let e = LogEntry(id: nextId, time: Date(), message: message)
            nextId += 1
            entries.append(e)
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
            return e
        }
        logger.info("\(message, privacy: .public)")
        if let data = (entry.formatted + "\n").data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }
        let currentListeners = lock.withLock { Array(listeners.values) }
        for listener in currentListeners { listener(entry) }
    }

    public var all: [LogEntry] { lock.withLock { entries } }

    public func clear() { lock.withLock { entries.removeAll() } }

    @discardableResult
    public func addListener(_ listener: @escaping @Sendable (LogEntry) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { listeners[id] = listener }
        return id
    }

    public func removeListener(_ id: UUID) {
        lock.withLock { _ = listeners.removeValue(forKey: id) }
    }

    public var fileDirectoryURL: URL? {
        nil
    }
}

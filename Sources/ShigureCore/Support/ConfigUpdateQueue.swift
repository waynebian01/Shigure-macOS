import Foundation

/// 配置更新尾队列：所有生成 config/keymap、依赖导入、插件部署的操作串行执行（对应 C# MainForm._configUpdateTail）。
/// 运行时启动/重启前先 `waitUntilIdle()`。
public actor ConfigUpdateQueue {
    private var tail: Task<Void, Never>?
    private var pending = 0

    public init() {}

    public var isIdle: Bool { pending == 0 }

    /// 追加一个操作；返回该操作自身的 Task（错误由调用方处理）。
    @discardableResult
    public func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) -> Task<T, Error> {
        pending += 1
        let previous = tail
        let task = Task<T, Error> {
            if let previous { await previous.value }
            do {
                let result = try await operation()
                self.finishOne()
                return result
            } catch {
                self.finishOne()
                throw error
            }
        }
        tail = Task { _ = try? await task.value }
        return task
    }

    private func finishOne() {
        pending = max(0, pending - 1)
    }

    /// 等待队列稳定（期间新入队的操作也会被等待）。
    public func waitUntilIdle() async {
        while pending > 0, let current = tail {
            await current.value
            if tail == current { break }
        }
    }
}

import Foundation

public enum RuntimeEvent: Sendable {
    case snapshot(RenderSnapshot)
    case failed(sessionId: UInt64, message: String)
    case stopped(sessionId: UInt64)
}

/// 串行管理运行时的启动/重启/停止（对应 C# RuntimeSessionCoordinator）。
/// 请求带版本号，过期请求被丢弃；快照带 sessionId，UI 丢弃非当前会话的快照。
public actor RuntimeCoordinator {
    public typealias Factory = @Sendable (AppOptions, UInt64, @escaping @Sendable (RenderSnapshot) -> Void) -> ShigureRuntime

    private struct Session {
        let id: UInt64
        let options: AppOptions
        let runtime: ShigureRuntime
        let task: Task<Void, Never>
    }

    private let factory: Factory
    private var session: Session?
    private var nextSessionId: UInt64 = 1
    private var latestRequestVersion: UInt64 = 0
    private var continuations: [UUID: AsyncStream<RuntimeEvent>.Continuation] = [:]

    public init(factory: @escaping Factory) {
        self.factory = factory
    }

    public var isRunning: Bool { session != nil }
    public var currentSessionId: UInt64? { session?.id }
    public var currentOptions: AppOptions? { session?.options }

    /// 订阅事件流（多个订阅者各自独立）。
    public func events() -> AsyncStream<RuntimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit(_ event: RuntimeEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    nonisolated private func emitFromRuntime(_ event: RuntimeEvent) {
        Task { await self.emit(event) }
    }

    public func start(_ options: AppOptions) async {
        await restart(options)
    }

    /// 停止当前会话并以新选项启动；重入时最新请求胜出。
    public func restart(_ options: AppOptions) async {
        latestRequestVersion &+= 1
        let version = latestRequestVersion
        await stopCurrentSession()
        guard version == latestRequestVersion else { return }
        let id = nextSessionId
        nextSessionId += 1
        let runtime = factory(options, id) { [weak self] snapshot in
            self?.emitFromRuntime(.snapshot(snapshot))
        }
        let task = Task { [weak self] in
            await runtime.run()
            await self?.sessionFinished(id)
        }
        session = Session(id: id, options: options, runtime: runtime, task: task)
    }

    public func stop() async {
        latestRequestVersion &+= 1
        await stopCurrentSession()
    }

    private func stopCurrentSession() async {
        guard let current = session else { return }
        session = nil
        current.task.cancel()
        await current.task.value
        emit(.stopped(sessionId: current.id))
    }

    private func sessionFinished(_ id: UInt64) {
        if session?.id == id {
            session = nil
            emit(.stopped(sessionId: id))
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        await session?.runtime.setEnabled(enabled)
    }

    public func toggleEnabled() async {
        await session?.runtime.toggleEnabled()
    }

    public func isEnabled() async -> Bool {
        guard let runtime = session?.runtime else { return false }
        return await runtime.isEnabled
    }
}

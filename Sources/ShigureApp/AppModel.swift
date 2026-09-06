import AppKit
import Observation
import ShigureCore

/// 组合根 + 界面状态（@MainActor）。持有所有核心服务，界面只读它的属性并调用方法。
@MainActor
@Observable
final class AppModel {
    // MARK: 服务
    let paths: AppPaths
    let log: LogSink
    let moduleStore: ModuleStore
    let locator: WorkspaceGameLocator
    let keyInjector: CGEventKeyInjector
    let trigger: CGTriggerKeyMonitor
    let scanner: ScreenCaptureKitScanner
    let coordinator: RuntimeCoordinator
    let configQueue = ConfigUpdateQueue()
    let iconCatalog: IconCatalogStore
    let keyRecorder = KeyRecorder()

    // MARK: 设置
    var settings: AppSettings {
        didSet { persistSettings() }
    }

    // MARK: 运行状态
    private(set) var snapshot: RenderSnapshot = .idle()
    private(set) var isRunning = false
    private(set) var runtimeError: String?
    private(set) var logEntries: [LogEntry] = []
    private(set) var configStatus = "项目目录是唯一配置源；尚未执行手动更新"
    private(set) var configStatusIsError = false
    private(set) var isUpdatingConfig = false
    private(set) var isRecordingKey = false
    var recordingHint: String?

    // MARK: 权限
    private(set) var hasScreenRecording = Permissions.screenRecording
    private(set) var hasAccessibility = Permissions.accessibility
    private(set) var hasInputMonitoring = Permissions.inputMonitoring

    // MARK: 游戏
    private(set) var gameTarget: GameTarget?
    private(set) var addOnsDirectory: URL?

    private var eventTask: Task<Void, Never>?
    private var lastLoggedStep: String?
    private var lastLoggedFailure: String?
    private var lastLoggedClass: String?
    private var lastLoggedEnabled: Bool?
    private var lastLoggedModule: String?
    private var lastLoggedDetails: String?
    private var logListener: UUID?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        let paths = AppPaths.defaultUserData()
        self.paths = paths
        log = LogSink(capacity: 2000, fileDirectory: paths.logDirectory)
        if let resources = Bundle.main.resourceURL {
            do {
                try paths.seed(fromBundleResources: resources)
            } catch {
                log.append("初始化用户数据目录失败: \(error.localizedDescription)")
            }
        }
        let settings = AppSettings.load(from: paths.settingsFile)
        self.settings = settings
        moduleStore = ModuleStore(moduleDirectory: paths.moduleDirectory)
        locator = WorkspaceGameLocator(identifiers: settings.gameBundleIdentifiers)
        locator.preferredGameAppURL = settings.gameAppPath.map { URL(fileURLWithPath: $0) }
        keyInjector = CGEventKeyInjector(locator: locator, mode: settings.keyInjectionMode)
        trigger = CGTriggerKeyMonitor()
        scanner = ScreenCaptureKitScanner(locator: locator)
        iconCatalog = IconCatalogStore(packageURL: paths.iconPackFile)

        let scanner = self.scanner
        let keyInjector = self.keyInjector
        let trigger = self.trigger
        let moduleStore = self.moduleStore
        let store = SettingsSnapshotBox()
        coordinator = RuntimeCoordinator { options, sessionId, publish in
            let config = try? ConfigService.load(configDirectory: paths.configDirectory)
            let snapshotSettings = store.value
            let logic = LogicRegistry(keymapService: KeymapService(paths: paths, config: config ?? ConfigService(root: JSONObject())),
                                      moduleStore: moduleStore,
                                      selectedModuleId: options.moduleId,
                                      defaultModules: snapshotSettings.defaultModules)
            return ShigureRuntime(options: options, sessionId: sessionId, scanner: scanner,
                                  stateBuilder: StateBuilder(config: config ?? ConfigService(root: JSONObject())),
                                  keyOutput: keyInjector, trigger: trigger, logic: logic, onSnapshot: publish)
        }
        settingsBox = store
        store.value = settings
        logEntries = log.all
        logListener = log.addListener { [weak self] entry in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logEntries.append(entry)
                if self.logEntries.count > 2000 { self.logEntries.removeFirst(self.logEntries.count - 2000) }
            }
        }
        observeWorkspace()
        startEventLoop()
        refreshGameTarget()
        trigger.startLatchIfPossible()
        log.append("Shigure 已启动，数据目录: \(paths.root.path)")
    }

    private let settingsBox: SettingsSnapshotBox

    /// 供运行时工厂读取的设置快照（工厂闭包不能触碰 MainActor）。
    final class SettingsSnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = AppSettings()
        var value: AppSettings {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private func persistSettings() {
        settingsBox.value = settings
        locator.setIdentifiers(settings.gameBundleIdentifiers)
        locator.preferredGameAppURL = settings.gameAppPath.map { URL(fileURLWithPath: $0) }
        keyInjector.setMode(settings.keyInjectionMode)
        do {
            try settings.save(to: paths.settingsFile)
        } catch {
            log.append("保存设置失败: \(error.localizedDescription)")
        }
    }

    // MARK: 事件循环

    private func startEventLoop() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await coordinator.events()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.handle(event) }
            }
        }
    }

    private func handle(_ event: RuntimeEvent) {
        switch event {
        case .snapshot(let snapshot):
            Task { [weak self] in
                guard let self, let current = await self.coordinator.currentSessionId else { return }
                guard snapshot.sessionId == current else { return }
                self.apply(snapshot)
            }
        case .failed(_, let message):
            runtimeError = message
            log.append("运行时错误: \(message)")
        case .stopped:
            Task { [weak self] in
                guard let self else { return }
                let running = await self.coordinator.isRunning
                self.isRunning = running
            }
        }
    }

    private func apply(_ snapshot: RenderSnapshot) {
        self.snapshot = snapshot
        isRunning = true
        if let target = snapshot.target, target != gameTarget {
            gameTarget = target
            addOnsDirectory = locator.addOnsDirectory()
        }
        writeSnapshotLog(snapshot)
    }

    private func writeSnapshotLog(_ s: RenderSnapshot) {
        if let failure = s.scanFailureReason {
            if failure != lastLoggedFailure {
                log.append("扫描失败: \(failure)")
                lastLoggedFailure = failure
            }
        } else if lastLoggedFailure != nil {
            log.append("扫描已恢复")
            lastLoggedFailure = nil
        }
        if let className = s.className {
            let text = "\(className) / \(s.specName ?? "-")"
            if text != lastLoggedClass {
                log.append("识别职业: \(text)")
                lastLoggedClass = text
            }
        }
        if s.enabled != lastLoggedEnabled {
            log.append(s.enabled ? "逻辑已开启" : "逻辑已关闭")
            lastLoggedEnabled = s.enabled
        }
        if let module = s.moduleName, module != lastLoggedModule {
            log.append("匹配模块: \(module)")
            lastLoggedModule = module
        }
        var details: [String] = []
        if let v = s.unitInfo["动作单位"] { details.append("目标 \(v.displayText)") }
        if let v = s.unitInfo["动作按键"], v.displayText != "-" { details.append("按键 \(v.displayText)") }
        if let v = s.unitInfo["动作延迟"], v.displayText != "-" { details.append("动作延迟 \(v.displayText)") }
        if let v = s.unitInfo["逻辑延迟"], v.displayText != "-" { details.append("逻辑延迟 \(v.displayText)") }
        if let v = s.unitInfo["规则编号"] { details.append("规则 \(v.displayText)") }
        if let v = s.unitInfo["发送失败"] { details.append("发送失败 \(v.displayText)") }
        let line = details.isEmpty ? s.currentStep : "\(s.currentStep)（\(details.joined(separator: "，"))）"
        if line != lastLoggedDetails {
            log.append(line)
            lastLoggedDetails = line
        }
    }

    // MARK: 工作区观察

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let launchedPid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let isLaunch = name == NSWorkspace.didLaunchApplicationNotification
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let wasPresent = self.gameTarget != nil
                    self.locator.invalidate()
                    self.refreshGameTarget()
                    if isLaunch, let launchedPid,
                       self.locator.runningGameApplications().contains(where: { $0.processIdentifier == launchedPid }),
                       !wasPresent {
                        self.log.append("检测到目标游戏进程已打开，正在自动更新配置")
                        self.updateConfigFromProject(showFeedback: false)
                    }
                }
            }
            workspaceObservers.append(observer)
        }
        let activation = NSApplication.didBecomeActiveNotification
        let observer = NotificationCenter.default.addObserver(forName: activation, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissions() }
        }
        workspaceObservers.append(observer)
    }

    func refreshGameTarget() {
        gameTarget = locator.currentTarget()
        addOnsDirectory = locator.addOnsDirectory()
    }

    func refreshPermissions() {
        hasScreenRecording = Permissions.screenRecording
        hasAccessibility = Permissions.accessibility
        hasInputMonitoring = Permissions.inputMonitoring
        if hasInputMonitoring { trigger.startLatchIfPossible() }
    }

    var missingPermissions: [String] {
        var list: [String] = []
        if !hasScreenRecording { list.append("屏幕录制") }
        if !hasAccessibility { list.append("辅助功能") }
        return list
    }

    // MARK: 运行时控制

    func startRuntime() {
        guard validateRuntimeOptions() else { return }
        Task {
            await configQueue.waitUntilIdle()
            await coordinator.start(settings.options)
            isRunning = await coordinator.isRunning
            log.append("运行会话已启动（触发键 \(settings.toggleKey)，模式 \(settings.sendMode.displayName)）")
        }
    }

    func restartRuntime(reason: String? = nil) {
        guard validateRuntimeOptions() else { return }
        Task {
            await configQueue.waitUntilIdle()
            let wasRunning = await coordinator.isRunning
            await coordinator.restart(settings.options)
            isRunning = await coordinator.isRunning
            if let reason, wasRunning { log.append("\(reason), 重新启动运行") }
        }
    }

    func stopRuntime() {
        Task {
            await coordinator.stop()
            isRunning = await coordinator.isRunning
            snapshot = .idle(step: "已停止")
            log.append("运行会话已停止")
        }
    }

    func toggleEnabled() {
        Task { await coordinator.toggleEnabled() }
    }

    func setEnabled(_ value: Bool) {
        Task { await coordinator.setEnabled(value) }
    }

    private func validateRuntimeOptions() -> Bool {
        if MacKeyCodes.isUnsupportedToggleKey(settings.toggleKey) {
            runtimeError = "触发键不支持 Option(ALT) 或单独的修饰键，请选择其他按键。"
            return false
        }
        if trigger.resolve(keyName: settings.toggleKey) == nil {
            runtimeError = "无法识别触发键: \(settings.toggleKey)"
            return false
        }
        runtimeError = nil
        return true
    }

    /// 通用页「测试发送」：直接向游戏发送一个热键，验证注入方式是否有效。
    func testSend(hotkey: String) -> String {
        let result = keyInjector.send(hotkey: hotkey, expectedTarget: nil)
        let message = result.succeeded ? "已向游戏发送 \(hotkey)" : "发送失败: \(result.failureReason ?? "未知原因")"
        log.append("测试发送: \(message)")
        return message
    }

    // MARK: 触发键录制

    func beginRecordingToggleKey() {
        isRecordingKey = true
        recordingHint = "请按任意键..."
        keyRecorder.begin { [weak self] outcome in
            guard let self else { return }
            self.isRecordingKey = false
            switch outcome {
            case .cancelled:
                self.recordingHint = nil
                self.log.append("已取消按键录入")
            case .unsupported(let reason):
                self.recordingHint = reason
                self.log.append("触发键录入失败: \(reason)")
                Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { self.recordingHint = nil } }
            case .captured(let name):
                self.recordingHint = nil
                self.settings.toggleKey = name
                self.log.append("已录入触发键: \(name)")
                self.restartRuntime(reason: "触发键已变更")
            }
        }
    }

    func cancelRecordingToggleKey() {
        keyRecorder.end()
        isRecordingKey = false
        recordingHint = nil
    }

    // MARK: 模块

    var liveModuleMatches: [ModuleDefinition] {
        guard let state = snapshot.state, state.getBool("有效性") else {
            return moduleStore.getModules()
        }
        return moduleStore.findMatches(classId: snapshot.classId, specId: snapshot.specId,
                                       partyType: state.getInt("队伍类型"), heroTalent: state.getInt("英雄天赋"))
    }

    var moduleFilterCaption: String {
        guard let state = snapshot.state, state.getBool("有效性") else { return "筛选: 等待游戏状态" }
        let cls = snapshot.className.map { "\($0) (\(snapshot.classId ?? 0))" } ?? "-"
        let spec = snapshot.specName.map { "\($0) (\(snapshot.specId ?? 0))" } ?? "-"
        return "筛选: \(cls) / \(spec) / 队伍类型 \(state.getInt("队伍类型")) / 英雄天赋 \(state.getInt("英雄天赋"))"
    }

    func selectModule(_ id: String?) {
        settings.selectedModuleId = id
        log.append("模块选择: \(id.flatMap { mid in moduleStore.getModulesForDisplay().first { $0.id == mid }?.name } ?? "自动选择")")
        restartRuntime(reason: "模块选择已变更")
    }

    func setDefaultModule(_ selection: DefaultModuleSelection) {
        settings.defaultModules.removeAll { $0.hasSameFilter(classId: selection.classId, specId: selection.specId, partyType: selection.partyType, heroTalent: selection.heroTalent) }
        settings.defaultModules.append(selection)
        let name = moduleStore.getModulesForDisplay().first { $0.id == selection.moduleId }?.name ?? selection.moduleId
        log.append("默认模块: \(name)")
        restartRuntime(reason: "默认模块已变更")
    }

    func removeDefaultModule(_ selection: DefaultModuleSelection) {
        settings.defaultModules.removeAll { $0 == selection }
        restartRuntime(reason: "默认模块已变更")
    }

    var moduleReloadVersion = 0

    /// 刷新模块：重新加载目录，导入依赖，重启运行时。
    func reloadModules(reason: String = "刷新模块") {
        enqueueConfigWork(label: reason) { [self] in
            self.moduleStore.reload()
            let importResult = try await self.importModuleDependencies()
            self.moduleReloadVersion += 1
            return importResult
        } completion: { [self] result in
            switch result {
            case .success(let imported):
                if let imported, imported.hasChanges {
                    self.log.append("模块依赖已导入: 配置新增 \(imported.configAdded) 项、更新 \(imported.configUpdated) 项、宏新增 \(imported.macrosAdded) 项")
                }
                self.restartRuntime(reason: reason)
            case .failure(let error):
                self.log.append("\(reason)失败: \(error.localizedDescription)")
            }
        }
    }

    /// 启动/刷新时把模块携带的依赖合并到本地 Lua；超容量模块被拒绝并标红。
    func importModuleDependencies() async throws -> ModuleDependencyService.ImportResult? {
        let service = ModuleDependencyService(paths: paths)
        let result = try service.importAll(moduleStore.getModulesForImport())
        moduleStore.setImportIssues(rejected: result.rejected.map(\.moduleId), conflicted: Array(result.conflictedModuleIds))
        for module in result.sanitizedModules {
            _ = try? moduleStore.saveDependenciesInPlace(module)
        }
        for rejected in result.rejected { log.append("模块「\(rejected.moduleName)」被拒绝: \(rejected.reason)") }
        for conflict in result.conflicts.prefix(20) { log.append("依赖冲突: \(conflict)") }
        if result.hasChanges {
            try regenerateConfigAndKeymap()
            _ = deployAddon()
        }
        return result
    }

    // MARK: 配置生成与部署

    private func enqueueConfigWork<T: Sendable>(label: String, _ work: @escaping @MainActor () async throws -> T, completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        Task {
            let task = await configQueue.enqueue { @MainActor in try await work() }
            do {
                let value = try await task.value
                completion(.success(value))
            } catch {
                completion(.failure(error))
            }
        }
    }

    struct ConfigUpdateOutcome: Sendable {
        var configFiles = 0
        var keymapFiles = 0
        var warnings: [String] = []
        var sync: AddonSyncResult?
    }

    func regenerateConfigAndKeymap() throws -> ConfigUpdateOutcome {
        var outcome = ConfigUpdateOutcome()
        let configResult = try FuyutsuiConfigConverter.updateFromClassDirectory(paths.fuyutsuiClassDirectory, configDirectory: paths.configDirectory)
        outcome.configFiles = configResult.updatedFiles.count
        outcome.warnings.append(contentsOf: configResult.warnings)
        if FileManager.default.fileExists(atPath: paths.classMacrosFile.path) {
            let keymapResult = try FuyutsuiKeymapConverter.updateFromClassMacros(paths.classMacrosFile, keymapDirectory: paths.keymapDirectory)
            outcome.keymapFiles = keymapResult.updatedFiles.count
            outcome.warnings.append(contentsOf: keymapResult.warnings)
        } else {
            log.append("项目 Fuyutsui 中未找到 core/classmacros.lua，已跳过 keymap 更新")
        }
        catalogVersion += 1
        return outcome
    }

    var catalogVersion = 0

    func deployAddon(singleFile relativePath: String? = nil) -> AddonSyncResult? {
        let target = locator.addOnsDirectory().map { $0.appendingPathComponent("Fuyutsui", isDirectory: true) }
        do {
            let result: AddonSyncResult
            if let relativePath {
                result = try FuyutsuiAddonSync.synchronizeFile(sourceRoot: paths.fuyutsuiDirectory, targetRoot: target, relativePath: relativePath)
            } else {
                result = try FuyutsuiAddonSync.synchronizeAll(sourceRoot: paths.fuyutsuiDirectory, targetRoot: target)
            }
            log.append("插件同步: \(result.summary)")
            return result
        } catch {
            log.append("插件同步失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 通用页「更新配置」：生成 config/keymap → 全量部署 → 重启运行时。
    func updateConfigFromProject(showFeedback: Bool) {
        isUpdatingConfig = true
        configStatus = "正在生成配置并同步游戏插件…"
        configStatusIsError = false
        enqueueConfigWork(label: "更新配置") { [self] in
            var outcome = try self.regenerateConfigAndKeymap()
            outcome.sync = self.deployAddon()
            return outcome
        } completion: { [self] result in
            self.isUpdatingConfig = false
            switch result {
            case .success(let outcome):
                let syncOK = outcome.sync?.completedSuccessfully ?? false
                if syncOK && outcome.warnings.isEmpty {
                    self.configStatus = "已更新 \(outcome.configFiles) 个配置文件，并完成游戏同步"
                    self.configStatusIsError = false
                } else {
                    var issues: [String] = []
                    if !syncOK { issues.append(outcome.sync?.summary ?? "游戏同步未完成") }
                    if !outcome.warnings.isEmpty { issues.append("存在 \(outcome.warnings.count) 条转换警告") }
                    self.configStatus = "配置已更新；" + issues.joined(separator: "；")
                    self.configStatusIsError = !syncOK
                }
                self.log.append("已从项目 Fuyutsui 更新配置: \(outcome.configFiles) 个 config、\(outcome.keymapFiles) 个 keymap")
                for warning in outcome.warnings.prefix(20) { self.log.append("转换警告: \(warning)") }
                self.restartRuntime(reason: "配置已更新")
            case .failure(let error):
                self.configStatus = "更新失败: \(error.localizedDescription)"
                self.configStatusIsError = true
                self.log.append("更新配置失败: \(error.localizedDescription)")
            }
        }
    }

    /// 编辑器保存 Lua 后的流程：重捕获该职业模块依赖 → 重新生成 → 单文件部署 → 重启。
    func afterLuaSaved(relativePath: String, classId: Int?) async -> String {
        let task = await configQueue.enqueue { @MainActor [self] in
            var notes: [String] = []
            if let classId {
                let (saved, failed, missing) = self.recaptureDependencies(classId: classId)
                notes.append("已一并保存该职业的 \(saved) 个模块" + (missing > 0 ? "（\(missing) 个模块未携带依赖）" : ""))
                if failed > 0 { notes.append("\(failed) 个模块保存失败，详情见日志") }
            }
            _ = try self.regenerateConfigAndKeymap()
            let sync = self.deployAddon(singleFile: relativePath)
            if let sync, !sync.completedSuccessfully {
                notes.append("游戏插件同步未完成：\(sync.summary)")
            } else {
                notes.append("请在游戏内重载界面 (/reload)")
            }
            self.restartRuntime(reason: "配置已更新")
            return notes.joined(separator: "\n")
        }
        do {
            return try await task.value
        } catch {
            log.append("保存后的更新失败: \(error.localizedDescription)")
            return "本地 Lua 已保存，但后续更新失败：\(error.localizedDescription)"
        }
    }

    private func recaptureDependencies(classId: Int) -> (saved: Int, failed: Int, missing: Int) {
        let service = ModuleDependencyService(paths: paths)
        var saved = 0, failed = 0, missing = 0
        for var module in moduleStore.getModulesForImport() where module.match.classId == classId {
            do {
                if let warning = try service.capture(&module) {
                    missing += 1
                    log.append("模块「\(module.name)」: \(warning)")
                }
                _ = try moduleStore.saveDependenciesInPlace(module)
                saved += 1
            } catch {
                failed += 1
                log.append("模块「\(module.name)」依赖更新失败: \(error.localizedDescription)")
            }
        }
        return (saved, failed, missing)
    }

    /// 启动时：补齐缺失的 config/keymap → 导入模块依赖 → 部署插件 → 自动启动。
    func performStartupSequence() {
        enqueueConfigWork(label: "启动") { [self] in
            var didWork = false
            let missing = !FileManager.default.fileExists(atPath: paths.configDirectory.appendingPathComponent("common.json").path)
                || ClassNames.allClasses.contains { !FileManager.default.fileExists(atPath: paths.configDirectory.appendingPathComponent("\(ClassNames.configFileName($0.id)).json").path) }
                || ClassNames.allClasses.contains { !FileManager.default.fileExists(atPath: paths.keymapDirectory.appendingPathComponent("\(ClassNames.configFileName($0.id).lowercased()).json").path) }
            if missing {
                log.append("检测到 config 或 keymap 缺失或不完整，正在从项目 Fuyutsui 自动生成")
                _ = try regenerateConfigAndKeymap()
                didWork = true
            }
            if let imported = try await importModuleDependencies(), imported.hasChanges { didWork = true }
            if !didWork { _ = deployAddon() }
        } completion: { [self] result in
            if case .failure(let error) = result {
                log.append("启动初始化失败: \(error.localizedDescription)")
            }
            if settings.autoStartRuntime { startRuntime() }
        }
    }

    // MARK: 退出

    func shutdown() async {
        keyRecorder.end()
        await coordinator.stop()
        await configQueue.waitUntilIdle()
        eventTask?.cancel()
    }

    // MARK: 辅助

    func openModuleDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.moduleDirectory])
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearLog() {
        log.clear()
        logEntries.removeAll()
    }

    var logText: String {
        logEntries.map(\.formatted).joined(separator: "\n")
    }
}

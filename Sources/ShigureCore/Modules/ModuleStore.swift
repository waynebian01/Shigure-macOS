import Foundation

public struct ModuleStoreError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// 模块目录（{root}/module/*.json）的内存快照与文件事务。线程安全（锁保护），运行时每 tick 同步查询。
public final class ModuleStore: @unchecked Sendable {
    public let moduleDirectory: URL
    private let lock = NSLock()
    private var modules: [ModuleDefinition] = []
    private var incompatibleVersionModuleIds = Set<String>()
    private var rejectedModuleIds = Set<String>()
    private var importIssueModuleIds = Set<String>()

    public init(moduleDirectory: URL) {
        self.moduleDirectory = moduleDirectory
        try? FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
        reload()
    }

    // MARK: 查询

    /// 参与匹配/运行的模块（排除版本不兼容与被拒绝）。
    public func getModules() -> [ModuleDefinition] {
        lock.withLock { modules.filter { !incompatibleVersionModuleIds.contains(lower($0.id)) && !rejectedModuleIds.contains(lower($0.id)) } }
    }

    /// 依赖导入用：包含版本过期模块，仍排除上次导入被拒绝的模块。
    public func getModulesForImport() -> [ModuleDefinition] {
        lock.withLock { modules.filter { !rejectedModuleIds.contains(lower($0.id)) } }
    }

    public func getModulesForDisplay() -> [ModuleDefinition] {
        lock.withLock { modules }
    }

    public func setImportIssues(rejected: [String], conflicted: [String]) {
        lock.withLock {
            rejectedModuleIds = Set(rejected.map(lower))
            importIssueModuleIds = rejectedModuleIds.union(conflicted.map(lower))
        }
    }

    public func hasImportIssue(_ moduleId: String) -> Bool {
        lock.withLock { incompatibleVersionModuleIds.contains(lower(moduleId)) || importIssueModuleIds.contains(lower(moduleId)) }
    }

    public func isVersionIncompatible(_ moduleId: String) -> Bool {
        lock.withLock { incompatibleVersionModuleIds.contains(lower(moduleId)) }
    }

    public func reload() {
        lock.withLock {
            try? FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
            var loaded: [ModuleDefinition] = []
            incompatibleVersionModuleIds.removeAll()
            let files = Self.enumerateJSONFiles(in: moduleDirectory)
            for file in files {
                guard let text = try? TextFile.read(file), var module = try? ModuleJSON.decode(text: text) else { continue } // 单个模块损坏时跳过
                ModuleNormalizer.normalize(&module)
                module.fileURL = file
                loaded.append(module)
                if !module.hasCompatibleVersion { incompatibleVersionModuleIds.insert(lower(module.id)) }
            }
            modules = Self.sortModules(loaded)
            rejectedModuleIds.removeAll()
            importIssueModuleIds.removeAll()
        }
    }

    static func enumerateJSONFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    public func findSelectedOrBestMatch(selectedModuleId: String?, classId: Int?, specId: Int?, partyType: Int?, heroTalent: Int?) -> ModuleDefinition? {
        lock.withLock {
            let matches = Self.sortMatches(eligibleLocked(), classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent)
            if let selected = selectedModuleId, !selected.isBlank,
               let found = matches.first(where: { $0.id.equalsIgnoringCase(selected) }) {
                return found
            }
            return matches.first
        }
    }

    public func findMatches(classId: Int?, specId: Int?, partyType: Int?, heroTalent: Int?) -> [ModuleDefinition] {
        lock.withLock { Self.sortMatches(eligibleLocked(), classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent) }
    }

    private func eligibleLocked() -> [ModuleDefinition] {
        modules.filter { !incompatibleVersionModuleIds.contains(lower($0.id)) && !rejectedModuleIds.contains(lower($0.id)) }
    }

    // MARK: 写入

    @discardableResult
    public func save(_ input: ModuleDefinition) throws -> ModuleDefinition {
        var module = input
        ModuleNormalizer.normalize(&module)
        let oldURL = module.fileURL
        let url = buildModulePath(module)
        return try lock.withLock {
            if modules.contains(where: { !$0.id.equalsIgnoringCase(module.id) && $0.name.caseInsensitiveCompare(module.name) == .orderedSame }) {
                throw ModuleStoreError("模块名称“\(module.name)”已存在。")
            }
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path), oldURL == nil || !Self.pathsEqual(oldURL!, url) {
                throw ModuleStoreError("模块文件“\(url.lastPathComponent)”已存在，请使用其他名称。")
            }
            try AtomicFile.write(ModuleJSON.encodeText(module), to: url)
            if let oldURL, isInsideModuleDirectory(oldURL), !Self.pathsEqual(oldURL, url), fm.fileExists(atPath: oldURL.path) {
                do {
                    try fm.removeItem(at: oldURL)
                } catch {
                    do { try fm.removeItem(at: url) } catch let rollbackError {
                        throw ModuleStoreError("模块已写入新文件，但旧文件删除失败，且无法回滚新文件。\(error) / \(rollbackError)")
                    }
                    throw error
                }
            }
            module.fileURL = url
            modules.removeAll { $0.id.equalsIgnoringCase(module.id) || ($0.fileURL.map { Self.pathsEqual($0, url) } ?? false) }
            modules.append(module)
            modules = Self.sortModules(modules)
            updateVersionCompatibilityLocked(module)
            rejectedModuleIds.remove(lower(module.id))
            importIssueModuleIds.remove(lower(module.id))
            return module
        }
    }

    /// 回写已更新的模块依赖快照，并保留模块原有文件位置。
    @discardableResult
    public func saveDependenciesInPlace(_ input: ModuleDefinition) throws -> ModuleDefinition {
        var module = input
        ModuleNormalizer.normalize(&module)
        return try lock.withLock {
            guard let existing = modules.first(where: { $0.id.equalsIgnoringCase(module.id) }), let url = existing.fileURL else {
                throw ModuleStoreError("找不到要清理的模块“\(module.name)”。")
            }
            guard isInsideModuleDirectory(url), FileManager.default.fileExists(atPath: url.path) else {
                throw ModuleStoreError("模块文件不在模块目录中或已不存在: \(url.path)")
            }
            module.fileURL = url
            try AtomicFile.write(ModuleJSON.encodeText(module), to: url)
            modules.removeAll { $0.id.equalsIgnoringCase(existing.id) }
            modules.append(module)
            modules = Self.sortModules(modules)
            updateVersionCompatibilityLocked(module)
            rejectedModuleIds.remove(lower(module.id))
            importIssueModuleIds.remove(lower(module.id))
            return module
        }
    }

    public func delete(_ module: ModuleDefinition) throws {
        try lock.withLock {
            if let url = module.fileURL, isInsideModuleDirectory(url), FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            modules.removeAll { $0.id.equalsIgnoringCase(module.id) || ($0.fileURL != nil && module.fileURL != nil && Self.pathsEqual($0.fileURL!, module.fileURL!)) }
            incompatibleVersionModuleIds.remove(lower(module.id))
            rejectedModuleIds.remove(lower(module.id))
            importIssueModuleIds.remove(lower(module.id))
        }
    }

    private func updateVersionCompatibilityLocked(_ module: ModuleDefinition) {
        if module.hasCompatibleVersion {
            incompatibleVersionModuleIds.remove(lower(module.id))
        } else {
            incompatibleVersionModuleIds.insert(lower(module.id))
        }
    }

    public static func createModuleId(_ name: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return "\(sanitizeFileName(name))-\(formatter.string(from: Date()))"
    }

    public func createNextModuleName() -> String {
        lock.withLock {
            var index = 1
            while true {
                let name = "新模块\(index)"
                if !modules.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return name }
                index += 1
            }
        }
    }

    // MARK: 排序 / 路径

    static func sortModules(_ modules: [ModuleDefinition]) -> [ModuleDefinition] {
        modules.sorted { a, b in
            let ka = (a.match.classId ?? Int.max, a.match.specId ?? Int.max, ModuleMatch.partyTypeSortKey(a.match.partyType), a.match.heroTalent ?? Int.max)
            let kb = (b.match.classId ?? Int.max, b.match.specId ?? Int.max, ModuleMatch.partyTypeSortKey(b.match.partyType), b.match.heroTalent ?? Int.max)
            if ka != kb { return ka < kb }
            return a.name.caseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func sortMatches(_ modules: [ModuleDefinition], classId: Int?, specId: Int?, partyType: Int?, heroTalent: Int?) -> [ModuleDefinition] {
        modules.filter { $0.match.matches(classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent) }
            .sorted { a, b in
                if a.match.specificity != b.match.specificity { return a.match.specificity > b.match.specificity }
                return a.name.caseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    func buildModulePath(_ module: ModuleDefinition) -> URL {
        moduleDirectory.appendingPathComponent("\(Self.sanitizeFileName(module.name)).json")
    }

    static func pathsEqual(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.path.caseInsensitiveCompare(right.standardizedFileURL.path) == .orderedSame
    }

    func isInsideModuleDirectory(_ url: URL) -> Bool {
        let dir = moduleDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.lowercased().hasPrefix((dir + "/").lowercased())
    }

    /// 使用 Windows 的非法文件名字符集，保证与 Windows 版生成相同的文件名。
    public static func sanitizeFileName(_ value: String) -> String {
        var text = value.isBlank ? "module" : value.trimmed()
        let invalid: Set<Character> = ["\"", "<", ">", "|", ":", "*", "?", "\\", "/"]
        text = String(text.map { ch -> Character in
            if invalid.contains(ch) { return "-" }
            if let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1, scalar.value < 32 { return "-" }
            return ch
        })
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        if text.count > 64 { text = String(text.prefix(64)) }
        return text
    }

    private func lower(_ s: String) -> String { s.lowercased() }
}

/// 模块加载/保存时的规范化与版本迁移（对应 C# ModuleStore.Normalize）。
public enum ModuleNormalizer {
    public static func normalize(_ module: inout ModuleDefinition) {
        if module.name.isBlank { module.name = "新模块" }
        if module.id.isBlank { module.id = ModuleStore.createModuleId(module.name) }
        module.match.partyType = ModuleMatch.normalizePartyType(module.match.partyType)
        module.units.removeAll { $0.name.isBlank }
        module.counts.removeAll { $0.name.isBlank }
        module.valueAdjustments.removeAll { $0.field.isBlank }
        for i in module.units.indices {
            module.units[i].name = module.units[i].name.trimmed()
            module.units[i].healthName = module.units[i].healthName.isNilOrBlank ? nil : module.units[i].healthName!.trimmed()
            module.units[i].healthThresholdField = module.units[i].healthThresholdField.isNilOrBlank ? nil : module.units[i].healthThresholdField!.trimmed()
        }
        for i in module.counts.indices {
            module.counts[i].name = module.counts[i].name.trimmed()
            module.counts[i].healthThresholdField = module.counts[i].healthThresholdField.isNilOrBlank ? nil : module.counts[i].healthThresholdField!.trimmed()
        }
        for i in module.valueAdjustments.indices {
            module.valueAdjustments[i].field = module.valueAdjustments[i].field.trimmed()
            module.valueAdjustments[i].condition = module.valueAdjustments[i].condition.trimmed()
            module.valueAdjustments[i].formula = module.valueAdjustments[i].formula.trimmed()
        }

        let mappingVersion = module.unitMappingVersion ?? 0
        if mappingVersion < 2 {
            for i in module.rules.indices {
                switch module.rules[i].unit {
                case 31: module.rules[i].unit = ReservedUnit.cursor
                case 34: module.rules[i].unit = ReservedUnit.player
                default: break
                }
            }
        }
        if mappingVersion < 3 {
            for i in module.rules.indices where module.rules[i].unit == 36 || module.rules[i].unit == 37 {
                let normalized = MacroConditionText.normalizeLegacyUnit(module.rules[i].unit!, module.rules[i].macroCondition)
                module.rules[i].unit = normalized.unit
                module.rules[i].macroCondition = normalized.condition
            }
        }
        module.unitMappingVersion = ModuleDefinition.currentUnitMappingVersion

        for i in module.rules.indices {
            module.rules[i].comment = module.rules[i].comment.trimmed()
            module.rules[i].spell = ModuleSpecialActions.normalizeSpellAction(module.rules[i].spell)
            if let mc = module.rules[i].macroCondition {
                module.rules[i].macroCondition = MacroConditionText.normalize(mc)
            }
            module.rules[i].delayMs = (module.rules[i].delayMs ?? 0) > 0 ? module.rules[i].delayMs : nil
            module.rules[i].logicDelayMs = (module.rules[i].logicDelayMs ?? 0) > 0 ? module.rules[i].logicDelayMs : nil
            module.rules[i].continueLogic = module.rules[i].continueLogic == true ? true : nil
            if let subs = module.rules[i].subConditions {
                let cleaned = subs.map { $0.trimmed() }.filter { !$0.isEmpty }
                module.rules[i].subConditions = cleaned.isEmpty ? nil : cleaned
            }
        }
    }
}

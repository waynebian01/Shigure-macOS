import Foundation
import Testing
@testable import ShigureCore

/// 用本机 Application Support 中的真实模块做 round-trip 与依赖校验（目录不存在时跳过）。
@Suite("真实模块（本机数据目录）")
struct RealModuleTests {
    static let moduleDirectory = AppPaths.defaultUserData().moduleDirectory

    static var moduleFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: moduleDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    @Test("解码 → 规范化 → 编码 → 解码 语义一致；Hotkey/Step 保留", arguments: moduleFiles)
    func roundTrip(file: URL) throws {
        let text = try TextFile.read(file)
        var module = try ModuleJSON.decode(text: text)
        let original = module
        ModuleNormalizer.normalize(&module)
        let encoded = ModuleJSON.encodeText(module)
        var reparsed = try ModuleJSON.decode(text: encoded)
        ModuleNormalizer.normalize(&reparsed)
        #expect(reparsed == module, Comment(rawValue: file.lastPathComponent))
        #expect(module.rules.map(\.hotkey) == original.rules.map(\.hotkey))
        #expect(module.rules.map(\.step) == original.rules.map(\.step))
        #expect(module.rules.count == original.rules.count)
        // 每条规则的条件都能被解析器接受（文本⇄可视化 round-trip 后再解析一致）
        for rule in module.rules {
            let terms = ConditionExpression.parse(rule.condition)
            let rebuilt = ConditionExpression.build(terms)
            #expect(ConditionExpression.parse(rebuilt) == terms, Comment(rawValue: "\(file.lastPathComponent): \(rule.condition)"))
        }
        // 依赖快照可通过校验（不写盘）
        if var snapshot = module.dependencies {
            #expect(throws: Never.self) { try ModuleDependencyService.validateSnapshot(module, &snapshot) }
        }
    }

    @Test("真实模块的规则可在合成状态下求值而不报错")
    func evaluateAgainstSyntheticState() throws {
        try Fixtures.withTempDirectory { dir in
            let paths = try Fixtures.makePaths(dir)
            let config = try ConfigService.load(configDirectory: paths.configDirectory)
            for file in Self.moduleFiles {
                var module = try ModuleJSON.decode(text: TextFile.read(file))
                ModuleNormalizer.normalize(&module)
                guard let classId = module.match.classId, let specId = module.match.specId else { continue }
                let keymap = KeymapSelection.load(paths: paths, config: config, classId: classId, specId: specId)
                var state = StateBuilder(config: config).build(rowData: [1: 1, 2: classId, 3: specId, 6: 1], barData: [:], healAbsorbData: [:])
                let decisions = RuleEngine.run(module: module, state: &state, keymap: keymap)
                #expect(!decisions.isEmpty, Comment(rawValue: file.lastPathComponent))
                #expect(!decisions.contains { $0.step.hasSuffix("条件错误") }, Comment(rawValue: "\(file.lastPathComponent): \(decisions.last?.unitInfo["条件错误"]?.displayText ?? "")"))
            }
        }
    }
}

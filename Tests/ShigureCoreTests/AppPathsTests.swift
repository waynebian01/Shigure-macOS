import Foundation
import Testing
@testable import ShigureCore

@Suite("用户数据目录种子与框架升级")
struct AppPathsTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shigure-apppaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("框架文件升级：覆盖过期框架、补齐新增、保护用户编辑文件")
    func upgradeFrameworkFiles() throws {
        let fm = FileManager.default
        let resources = try makeTempDir()
        let root = try makeTempDir()
        defer {
            try? fm.removeItem(at: resources)
            try? fm.removeItem(at: root)
        }
        let bundleAddon = resources.appendingPathComponent("Fuyutsui", isDirectory: true)
        try write("new macro pool", to: bundleAddon.appendingPathComponent("core/macro.lua"))
        try write("new main", to: bundleAddon.appendingPathComponent("main.lua"))
        try write("brand new file", to: bundleAddon.appendingPathComponent("core/added.lua"))
        try write("bundle classmacros", to: bundleAddon.appendingPathComponent("core/classmacros.lua"))
        try write("bundle priest", to: bundleAddon.appendingPathComponent("class/Priest.lua"))

        let paths = AppPaths(root: root)
        let userAddon = paths.fuyutsuiDirectory
        try write("old macro pool", to: userAddon.appendingPathComponent("core/macro.lua"))
        try write("new main", to: userAddon.appendingPathComponent("main.lua")) // 已一致，应跳过
        try write("user classmacros", to: userAddon.appendingPathComponent("core/classmacros.lua"))
        try write("user priest", to: userAddon.appendingPathComponent("class/Priest.lua"))
        try write("user extra", to: userAddon.appendingPathComponent("core/extra.lua")) // 多余文件不删除

        let updated = try paths.upgradeFrameworkFiles(fromBundleResources: resources)
        #expect(updated == ["core/added.lua", "core/macro.lua"])
        #expect(try String(contentsOf: userAddon.appendingPathComponent("core/macro.lua"), encoding: .utf8) == "new macro pool")
        #expect(try String(contentsOf: userAddon.appendingPathComponent("core/added.lua"), encoding: .utf8) == "brand new file")
        // 用户编辑的文件保持原样
        #expect(try String(contentsOf: userAddon.appendingPathComponent("core/classmacros.lua"), encoding: .utf8) == "user classmacros")
        #expect(try String(contentsOf: userAddon.appendingPathComponent("class/Priest.lua"), encoding: .utf8) == "user priest")
        #expect(fm.fileExists(atPath: userAddon.appendingPathComponent("core/extra.lua").path))

        // 再跑一次：全部一致，无更新
        #expect(try paths.upgradeFrameworkFiles(fromBundleResources: resources).isEmpty)
    }

    @Test("用户目录尚未播种时不做任何事")
    func upgradeSkipsWhenNotSeeded() throws {
        let resources = try makeTempDir()
        let root = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: resources)
            try? FileManager.default.removeItem(at: root)
        }
        try write("x", to: resources.appendingPathComponent("Fuyutsui/main.lua"))
        let paths = AppPaths(root: root)
        #expect(try paths.upgradeFrameworkFiles(fromBundleResources: resources).isEmpty)
    }

    @Test("用户可编辑文件判定")
    func userEditablePaths() {
        #expect(AppPaths.isUserEditableAddonFile("core/classmacros.lua"))
        #expect(AppPaths.isUserEditableAddonFile("class/Priest.lua"))
        #expect(!AppPaths.isUserEditableAddonFile("core/macro.lua"))
        #expect(!AppPaths.isUserEditableAddonFile("main.lua"))
        #expect(!AppPaths.isUserEditableAddonFile("core/block.lua"))
    }
}

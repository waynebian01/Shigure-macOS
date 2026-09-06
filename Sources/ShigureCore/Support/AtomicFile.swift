import Foundation

public enum AtomicFile {
    /// 同目录临时文件 + rename 提交；失败时删除临时文件并抛出原始错误。
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).tmp")
        do {
            try data.write(to: tempURL, options: [.atomic])
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    public static func write(_ text: String, to url: URL, withBOM: Bool = false) throws {
        var data = Data()
        if withBOM { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        data.append(text.data(using: .utf8)!)
        try write(data, to: url)
    }
}

public enum TextFile {
    /// 读取 UTF-8 文本并去掉 BOM。
    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return decode(data)
    }

    public static func decode(_ data: Data) -> String {
        var slice = data[...]
        if slice.count >= 3, slice[slice.startIndex] == 0xEF, slice[slice.startIndex + 1] == 0xBB, slice[slice.startIndex + 2] == 0xBF {
            slice = slice.dropFirst(3)
        }
        return String(decoding: slice, as: UTF8.self)
    }
}

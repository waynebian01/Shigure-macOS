import Foundation

/// 技能/物品图标数据包 `.shgpack` 只读访问（格式与 Windows 版 SpellIconPackage 一致）。
///
/// 头 56 字节：magic "SHGICN1\0"、version=1、spellCount、iconCount、nameCount、spellMapOffset(=56)、
/// iconIndexOffset、nameIndexOffset、dataOffset。技能表按 spellId 升序（二分查找）。
/// 可选物品扩展：文件末尾 48 字节 footer "SHGITM1\0"。
public final class ShgPackReader: @unchecked Sendable {
    public struct PackError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    static let magic: [UInt8] = Array("SHGICN1\0".utf8)
    static let itemFooterMagic: [UInt8] = Array("SHGITM1\0".utf8)
    static let headerSize = 56
    static let recordSize = 12
    static let itemFooterSize = 48

    public let url: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let spellIds: [Int64]
    private let spellIconIndices: [Int32]
    private let itemIds: [Int64]
    private let itemIconIndices: [Int32]
    private let iconOffsets: [Int64]
    private let iconLengths: [Int32]
    public let spellIdsByName: [String: Int64]
    public let spellNamesById: [Int64: String]
    public let itemIdsByName: [String: Int64]
    public let itemNamesById: [Int64: String]

    public var hasItemDatabase: Bool { !itemIds.isEmpty }
    public var allSpellIds: [Int64] { spellIds }
    public var allItemIds: [Int64] { itemIds }
    public var fileSize: Int64 { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0 }

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        self.handle = handle
        let length = Int64(try handle.seekToEnd())
        func read(_ offset: Int64, _ count: Int) throws -> Data {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: count), data.count == count else { throw PackError(message: "数据包意外结束") }
            return data
        }
        let header = try read(0, Self.headerSize)
        guard Array(header[0..<8]) == Self.magic, header.int32(at: 8) == 1 else { throw PackError(message: "Unsupported spell icon package.") }
        let spellCount = Int(header.int32(at: 12))
        let iconCount = Int(header.int32(at: 16))
        let nameCount = Int(header.int32(at: 20))
        let spellMapOffset = header.int64(at: 24)
        let iconIndexOffset = header.int64(at: 32)
        let nameIndexOffset = header.int64(at: 40)
        let dataOffset = header.int64(at: 48)
        guard (1...2_000_000).contains(spellCount), (1...100_000).contains(iconCount), (0...2_000_000).contains(nameCount),
              spellMapOffset == Int64(Self.headerSize),
              iconIndexOffset == spellMapOffset + Int64(spellCount * Self.recordSize),
              nameIndexOffset == iconIndexOffset + Int64(iconCount * Self.recordSize),
              dataOffset >= nameIndexOffset, dataOffset <= length else {
            throw PackError(message: "Invalid spell icon package header.")
        }

        let spellMap = try read(spellMapOffset, spellCount * Self.recordSize)
        var ids = [Int64](repeating: 0, count: spellCount)
        var idx = [Int32](repeating: 0, count: spellCount)
        for i in 0..<spellCount {
            let id = spellMap.int64(at: i * Self.recordSize)
            let icon = spellMap.int32(at: i * Self.recordSize + 8)
            guard id > 0, i == 0 || id > ids[i - 1], icon >= 0, Int(icon) < iconCount else { throw PackError(message: "Invalid spell map in icon package.") }
            ids[i] = id
            idx[i] = icon
        }
        spellIds = ids
        spellIconIndices = idx

        let iconIndex = try read(iconIndexOffset, iconCount * Self.recordSize)
        var offsets = [Int64](repeating: 0, count: iconCount)
        var lengths = [Int32](repeating: 0, count: iconCount)
        for i in 0..<iconCount {
            let offset = iconIndex.int64(at: i * Self.recordSize)
            let len = iconIndex.int32(at: i * Self.recordSize + 8)
            guard offset >= dataOffset, (512...(10 * 1024 * 1024)).contains(len), offset <= length - Int64(len) else { throw PackError(message: "Invalid image index in icon package.") }
            offsets[i] = offset
            lengths[i] = len
        }
        iconOffsets = offsets
        iconLengths = lengths

        var namesById: [Int64: String] = [:]
        var idsByName: [String: Int64] = [:]
        let nameTable = try read(nameIndexOffset, Int(dataOffset - nameIndexOffset))
        var pos = 0
        for _ in 0..<nameCount {
            guard pos + 12 <= nameTable.count else { throw PackError(message: "Invalid name index in icon package.") }
            let id = nameTable.int64(at: pos)
            let byteLength = Int(nameTable.int32(at: pos + 8))
            pos += 12
            guard id > 0, (1...4096).contains(byteLength), pos + byteLength <= nameTable.count else { throw PackError(message: "Invalid name index in icon package.") }
            let name = String(decoding: nameTable[(nameTable.startIndex + pos)..<(nameTable.startIndex + pos + byteLength)], as: UTF8.self)
            pos += byteLength
            if !name.isBlank {
                if idsByName[name] == nil { idsByName[name] = id }
                if namesById[id] == nil { namesById[id] = name }
            }
        }
        guard pos == nameTable.count else { throw PackError(message: "Spell icon package index size mismatch.") }
        spellIdsByName = idsByName
        spellNamesById = namesById

        var itemIdList: [Int64] = []
        var itemIconList: [Int32] = []
        var itemNames: [Int64: String] = [:]
        var itemIdsByNameMap: [String: Int64] = [:]
        if length >= dataOffset + Int64(Self.itemFooterSize) {
            let footerOffset = length - Int64(Self.itemFooterSize)
            let footer = try read(footerOffset, Self.itemFooterSize)
            if Array(footer[0..<8]) == Self.itemFooterMagic {
                let itemCount = Int(footer.int32(at: 8))
                let itemNameCount = Int(footer.int32(at: 12))
                let itemMapOffset = footer.int64(at: 16)
                let itemNameOffset = footer.int64(at: 24)
                guard (1...2_000_000).contains(itemCount), (0...2_000_000).contains(itemNameCount), itemMapOffset >= dataOffset,
                      itemNameOffset == itemMapOffset + Int64(itemCount * Self.recordSize), itemNameOffset <= footerOffset else {
                    throw PackError(message: "Invalid item extension footer in icon package.")
                }
                let itemMap = try read(itemMapOffset, itemCount * Self.recordSize)
                itemIdList = [Int64](repeating: 0, count: itemCount)
                itemIconList = [Int32](repeating: 0, count: itemCount)
                for i in 0..<itemCount {
                    let id = itemMap.int64(at: i * Self.recordSize)
                    let icon = itemMap.int32(at: i * Self.recordSize + 8)
                    guard id > 0, i == 0 || id > itemIdList[i - 1], icon >= 0, Int(icon) < iconCount else { throw PackError(message: "Invalid item map in icon package.") }
                    itemIdList[i] = id
                    itemIconList[i] = icon
                }
                let itemNameTable = try read(itemNameOffset, Int(footerOffset - itemNameOffset))
                var p = 0
                for _ in 0..<itemNameCount {
                    guard p + 12 <= itemNameTable.count else { throw PackError(message: "Invalid item name index in icon package.") }
                    let id = itemNameTable.int64(at: p)
                    let byteLength = Int(itemNameTable.int32(at: p + 8))
                    p += 12
                    guard id > 0, (1...4096).contains(byteLength), p + byteLength <= itemNameTable.count else { throw PackError(message: "Invalid item name index in icon package.") }
                    let name = String(decoding: itemNameTable[(itemNameTable.startIndex + p)..<(itemNameTable.startIndex + p + byteLength)], as: UTF8.self)
                    p += byteLength
                    if !name.isBlank {
                        if itemIdsByNameMap[name] == nil { itemIdsByNameMap[name] = id }
                        if itemNames[id] == nil { itemNames[id] = name }
                    }
                }
                guard p == itemNameTable.count else { throw PackError(message: "Item name table size mismatch in icon package.") }
            }
        }
        itemIds = itemIdList
        itemIconIndices = itemIconList
        itemNamesById = itemNames
        itemIdsByName = itemIdsByNameMap
    }

    deinit {
        try? handle.close()
    }

    public func spellIconData(_ spellId: Int64) -> Data? {
        guard let index = Self.binarySearch(spellIds, spellId) else { return nil }
        return iconBlob(Int(spellIconIndices[index]))
    }

    public func itemIconData(_ itemId: Int64) -> Data? {
        guard let index = Self.binarySearch(itemIds, itemId) else { return nil }
        return iconBlob(Int(itemIconIndices[index]))
    }

    private func iconBlob(_ iconIndex: Int) -> Data? {
        lock.withLock {
            do {
                try handle.seek(toOffset: UInt64(iconOffsets[iconIndex]))
                let data = try handle.read(upToCount: Int(iconLengths[iconIndex]))
                return data?.count == Int(iconLengths[iconIndex]) ? data : nil
            } catch {
                return nil
            }
        }
    }

    static func binarySearch(_ array: [Int64], _ value: Int64) -> Int? {
        var low = 0
        var high = array.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if array[mid] == value { return mid }
            if array[mid] < value { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// 校验文件可打开（下载后安装前）。
    public static func validate(_ url: URL) throws {
        _ = try ShgPackReader(url: url)
    }
}

extension Data {
    func int32(at offset: Int) -> Int32 {
        var value: Int32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + 4)) }
        return Int32(littleEndian: value)
    }

    func int64(at offset: Int) -> Int64 {
        var value: Int64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + 8)) }
        return Int64(littleEndian: value)
    }
}

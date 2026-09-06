import Foundation

/// BGRA 像素缓冲（物理像素）。
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bgra: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int, bgra: [UInt8]) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bgra = bgra
    }

    @inline(__always)
    public func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let offset = y * bytesPerRow + x * 4
        return (bgra[offset + 2], bgra[offset + 1], bgra[offset])
    }

    /// 测试辅助：由 RGB 三元组网格构造。
    public static func make(rows: [[(UInt8, UInt8, UInt8)]]) -> PixelBuffer {
        let height = rows.count
        let width = rows.first?.count ?? 0
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in rows.enumerated() {
            for (x, px) in row.enumerated() {
                let o = (y * width + x) * 4
                bytes[o] = px.2
                bytes[o + 1] = px.1
                bytes[o + 2] = px.0
                bytes[o + 3] = 255
            }
        }
        return PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bgra: bytes)
    }
}

/// Fuyutsui 像素协议解码（纯函数，与截屏实现解耦）。
public enum PixelDecoder {
    public static let topRowBlockCount = 510
    public static let topRowFirstSchemeMax = 255
    public static let healAbsorbMaxRows = 6
    public static let healAbsorbMaxUnits = 30
    /// 锚点行搜索范围（物理像素行）；Retina 下 1 个 UI 单位可能是 2 个物理像素。
    public static let anchorSearchRows = 8

    public struct Decoded: Sendable, Equatable {
        public var rowData: [Int: Int]
        public var barData: [Int: Int]
        public var healAbsorbData: [Int: Int]
        public var anchorRow: Int?
        public var markerRow: Int?
        public var failureReason: String?
    }

    /// 完整解码：顶行（锚点搜索）→ CountBars 标记列 → 段值 → 治疗吸收网格。
    public static func decode(_ buffer: PixelBuffer) -> Decoded {
        var result = Decoded(rowData: [:], barData: [:], healAbsorbData: [:], anchorRow: nil, markerRow: nil, failureReason: nil)
        guard buffer.width > 0, buffer.height > 0 else {
            result.failureReason = "目标窗口客户区尺寸无效"
            return result
        }
        // 1. 顶行：在前几行中寻找 step==1 的锚点
        for y in 0..<min(anchorSearchRows, buffer.height) {
            let row = scanTopRow(buffer, y: y)
            if !row.isEmpty {
                result.rowData = row
                result.anchorRow = y
                break
            }
        }
        if result.rowData.isEmpty {
            result.failureReason = "未找到有效的状态像素起始标记"
            return result
        }
        // 2. CountBars 红色标记（客户区 x=0 向下）
        guard let markerY = findCountBarsMarkerY(buffer, startRow: (result.anchorRow ?? 0) + 1) else {
            result.failureReason = "未找到 CountBars 标记, 层数条和治疗吸收数据未采集"
            return result
        }
        result.markerRow = markerY
        result.barData = scanLeftMarkerRow(buffer, y: markerY)
        result.healAbsorbData = scanHealAbsorbGrid(buffer, markerY: markerY)
        return result
    }

    /// 索引 1..255: (0, i, b)；256..510: (1, i-255, b)。
    @inline(__always)
    static func decodeTopRowBlock(_ px: (r: UInt8, g: UInt8, b: UInt8)) -> (step: Int, value: Int)? {
        guard px.g >= 1 else { return nil }
        let step: Int
        switch px.r {
        case 0: step = Int(px.g)
        case 1: step = 255 + Int(px.g)
        default: return nil
        }
        guard step >= 1, step <= topRowBlockCount else { return nil }
        return (step, Int(px.b))
    }

    public static func scanTopRow(_ buffer: PixelBuffer, y: Int) -> [Int: Int] {
        var rowData: [Int: Int] = [:]
        var startX = -1
        for x in 0..<min(topRowBlockCount * 2, buffer.width) {
            if let decoded = decodeTopRowBlock(buffer.rgb(x: x, y: y)), decoded.step == 1 {
                startX = x
                break
            }
        }
        if startX < 0 { return rowData }
        for x in startX..<buffer.width {
            if let decoded = decodeTopRowBlock(buffer.rgb(x: x, y: y)) {
                rowData[decoded.step] = decoded.value
                if decoded.step == topRowBlockCount { break }
            }
        }
        return rowData
    }

    @inline(__always) static func isRedMarker(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { c.r == 1 && c.g == 0 && c.b == 0 }
    @inline(__always) static func isRedGreenMarker(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { c.r == 1 && c.g == 1 && c.b == 0 }
    @inline(__always) static func isWhite(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { c.r == 255 && c.g == 255 && c.b == 255 }
    @inline(__always) static func isGrayEndMarker(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { c.r == 200 && c.g == 200 && c.b == 200 }

    public static func findCountBarsMarkerY(_ buffer: PixelBuffer, startRow: Int = 0) -> Int? {
        for y in startRow..<buffer.height where isRedMarker(buffer.rgb(x: 0, y: y)) {
            return y
        }
        return nil
    }

    /// 段值 = 白条右侧首个非白像素 G−1；红后接 (1,1,0) 也算段起点；灰 (200,200,200) 终止。
    public static func scanLeftMarkerRow(_ buffer: PixelBuffer, y: Int) -> [Int: Int] {
        var barData: [Int: Int] = [:]
        var segIndex = 0
        var x = 0
        var pendingRed = false
        let width = buffer.width
        while x < width {
            let color = buffer.rgb(x: x, y: y)
            if isGrayEndMarker(color) { break }
            if pendingRed && isRedGreenMarker(color) {
                pendingRed = false
                segIndex += 1
                let (value, nextX) = consumeValueFrom(buffer, y: y, fromX: x + 1, alreadySawWhite: false)
                barData[segIndex] = max(0, value - 1)
                x = nextX
                continue
            }
            if isRedMarker(color) {
                pendingRed = true
                x += 1
                continue
            }
            if isWhite(color) {
                let prevWhite = x > 0 && isWhite(buffer.rgb(x: x - 1, y: y))
                if !prevWhite {
                    pendingRed = false
                    segIndex += 1
                    let (value, nextX) = consumeValueFrom(buffer, y: y, fromX: x + 1, alreadySawWhite: true)
                    barData[segIndex] = max(0, value - 1)
                    x = nextX
                    continue
                }
            }
            x += 1
        }
        return barData
    }

    private static func consumeValueFrom(_ buffer: PixelBuffer, y: Int, fromX: Int, alreadySawWhite: Bool) -> (Int, Int) {
        var sx = fromX
        var needWhite = !alreadySawWhite
        while sx < buffer.width {
            let c = buffer.rgb(x: sx, y: y)
            if isGrayEndMarker(c) { return (0, buffer.width) }
            if isRedMarker(c) { return (0, sx) }
            if needWhite {
                if isWhite(c) { needWhite = false }
                sx += 1
                continue
            }
            if isWhite(c) {
                sx += 1
                continue
            }
            return (Int(c.g), sx + 1)
        }
        return (0, buffer.width)
    }

    /// 治疗吸收网格：CountBars 下方最多 6 逻辑行。行位置按像素内容判定（白条右侧首个非白像素 R=行号），
    /// 因此 Retina/UI 缩放下每行占多个物理像素也能正确覆盖 30 个槽位。
    public static func scanHealAbsorbGrid(_ buffer: PixelBuffer, markerY: Int) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var rowsSeen = Set<Int>()
        var y = markerY + 1
        // 扫描到高度用尽或已收集满 6 个逻辑行后连续多行无数据为止
        var emptyStreak = 0
        while y < buffer.height, emptyStreak < 4 {
            var foundAny = false
            var x = 0
            while x < buffer.width {
                let color = buffer.rgb(x: x, y: y)
                if !isWhite(color) { x += 1; continue }
                if x > 0 && isWhite(buffer.rgb(x: x - 1, y: y)) { x += 1; continue }
                let (px, nextX) = consumeHealAbsorbPixel(buffer, y: y, fromX: x + 1)
                if let px {
                    let unit = Int(px.b)
                    let logicalRow = Int(px.r)
                    if unit >= 1 && unit <= healAbsorbMaxUnits && logicalRow < healAbsorbMaxRows {
                        result[unit] = max(0, Int(px.g) - 1)
                        rowsSeen.insert(logicalRow)
                        foundAny = true
                    }
                }
                x = nextX
            }
            emptyStreak = foundAny ? 0 : emptyStreak + 1
            if rowsSeen.count >= healAbsorbMaxRows && !foundAny { break }
            y += 1
        }
        return result
    }

    private static func consumeHealAbsorbPixel(_ buffer: PixelBuffer, y: Int, fromX: Int) -> ((r: UInt8, g: UInt8, b: UInt8)?, Int) {
        var sx = fromX
        while sx < buffer.width {
            let c = buffer.rgb(x: sx, y: y)
            if isWhite(c) { sx += 1; continue }
            return (c, sx + 1)
        }
        return (nil, buffer.width)
    }
}

import AppKit
import CoreGraphics
import ScreenCaptureKit
import ShigureCore

/// 用 ScreenCaptureKit 截取游戏窗口顶部区域并解码 Fuyutsui 像素协议（对应 C# PixelScanner）。
/// - 只截取窗口顶部若干点高（含标题栏），按物理像素采样，sRGB 不做色彩管理；
/// - 窗口被遮挡也能截到（desktopIndependentWindow）；
/// - 需要「屏幕录制」权限。
final class ScreenCaptureKitScanner: ScreenScanner, @unchecked Sendable {
    /// 截取高度（点）。ColorBars + CountBars + 6 行治疗吸收约 15 个 UI 单位，加标题栏留足余量。
    static let captureHeightPoints: CGFloat = 96

    private let locator: WorkspaceGameLocator
    private let lock = NSLock()
    private var cachedWindow: (id: UInt32, window: SCWindow)?
    private var lastContentRefresh: ContinuousClock.Instant?

    init(locator: WorkspaceGameLocator) {
        self.locator = locator
    }

    func scan() async -> ScreenScanResult {
        guard let target = locator.currentTarget() else {
            return .failure(String(localized: "未找到目标进程的可见窗口（\(locator.describeConfigured())）"))
        }
        guard Permissions.screenRecording else {
            return .failure(String(localized: "未授予「屏幕录制」权限，无法读取游戏画面"), target: target)
        }
        do {
            let window = try await resolveWindow(target)
            let scale = Self.backingScale(for: target.bounds)
            let heightPoints = min(target.bounds.height, Self.captureHeightPoints)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(target.bounds.width * scale))
            config.height = max(1, Int(heightPoints * scale))
            config.sourceRect = CGRect(x: 0, y: 0, width: target.bounds.width, height: heightPoints)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.scalesToFit = false
            config.captureResolution = .best
            config.shouldBeOpaque = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let buffer = Self.pixelBuffer(from: image)
            let decoded = PixelDecoder.decode(buffer)
            return ScreenScanResult(rowData: decoded.rowData.isEmpty ? nil : decoded.rowData,
                                    barData: decoded.barData,
                                    healAbsorbData: decoded.healAbsorbData,
                                    target: target,
                                    failureReason: decoded.failureReason)
        } catch {
            lock.withLock { cachedWindow = nil }
            return .failure(String(localized: "截屏失败: \(error.localizedDescription)"), target: target)
        }
    }

    private func resolveWindow(_ target: GameTarget) async throws -> SCWindow {
        if let cached = lock.withLock({ cachedWindow }), cached.id == target.windowID {
            return cached.window
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw ScanError.windowNotShareable
        }
        lock.withLock { cachedWindow = (target.windowID, window) }
        return window
    }

    enum ScanError: LocalizedError {
        case windowNotShareable
        var errorDescription: String? { String(localized: "游戏窗口不可截取（可能已关闭或正在切换）") }
    }

    static func backingScale(for bounds: CGRect) -> CGFloat {
        // CGWindow 坐标为左上原点；NSScreen 为左下原点，用主屏高度换算后取相交面积最大的屏幕。
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        var best: (area: CGFloat, scale: CGFloat) = (0, NSScreen.main?.backingScaleFactor ?? 2)
        for screen in NSScreen.screens {
            let inter = screen.frame.intersection(flipped)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > best.area { best = (area, screen.backingScaleFactor) }
        }
        return best.scale
    }

    /// CGImage → BGRA 缓冲。用 sRGB 绘制到自有上下文，源图同为 sRGB 时不发生颜色转换。
    static func pixelBuffer(from image: CGImage) -> PixelBuffer {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return }
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return PixelBuffer(width: width, height: height, bytesPerRow: bytesPerRow, bgra: bytes)
    }
}

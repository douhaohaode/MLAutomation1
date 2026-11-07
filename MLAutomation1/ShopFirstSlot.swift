//
//  ShopFirstSlot.swift
//  MLAutomation1
//
//  购买窗物品栏第一格。宝图固定在这一格，被抢光时格子是空的。
//  格子范围按 1024×769 的购买截图标定。空格内部颜色几乎不变，有图标时明暗差很大。
//

import AppKit

struct ShopFirstSlotReport {
    /// 第一格里没有物品。
    let empty: Bool
    /// 第一格中心，相对整张画面的比例坐标，可直接点击。
    let center: CGPoint
    /// 格子内部亮度的最大最小差。空格很小，有图标会大很多。
    let spread: Double
}

enum ShopFirstSlot {
    /// 5 列 × 4 行物品栏的左上第一格。
    static let cell = CGRect(x: 0.3662, y: 0.2523, width: 0.0518, height: 0.0702)
    static var center: CGPoint { CGPoint(x: cell.midX, y: cell.midY) }
    /// 低于这个差值视为空格。有图标的格子差值通常在 150 以上。
    static let emptySpread: Double = 60

    static func inspect(_ image: CGImage) -> ShopFirstSlotReport {
        let fullW = image.width
        let fullH = image.height
        let inner = cell.insetBy(dx: cell.width * 0.28, dy: cell.height * 0.28)
        let x = max(0, Int((inner.minX * CGFloat(fullW)).rounded(.down)))
        let y = max(0, Int((inner.minY * CGFloat(fullH)).rounded(.down)))
        let w = min(fullW - x, max(1, Int((inner.width * CGFloat(fullW)).rounded())))
        let h = min(fullH - y, max(1, Int((inner.height * CGFloat(fullH)).rounded())))
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return ShopFirstSlotReport(empty: false, center: center, spread: -1)
        }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return ShopFirstSlotReport(empty: false, center: center, spread: -1)
        }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minL = 255.0
        var maxL = 0.0
        for i in 0..<(w * h) {
            let o = i * 4
            let l = 0.299 * Double(pixels[o]) + 0.587 * Double(pixels[o + 1]) + 0.114 * Double(pixels[o + 2])
            if l < minL { minL = l }
            if l > maxL { maxL = l }
        }
        let spread = maxL - minL
        return ShopFirstSlotReport(empty: spread < emptySpread, center: center, spread: spread)
    }
}


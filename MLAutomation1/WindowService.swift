//
//  WindowService.swift
//  MLAutomation
//

import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

class WindowService {

    static let gameProcessKeywords = ["mhmain.exe","Simulator"]

    // MARK: - 发现游戏窗口（正式）
    static func discoverGameWindows() -> [GameWindow] {
//        discoverWindows { owner, title in
//            gameProcessKeywords.contains {
//                owner.localizedCaseInsensitiveContains($0) ||
//                title.localizedCaseInsensitiveContains($0)
//            }
//        }
        
        let allMatched = discoverWindows { owner, title in
                gameProcessKeywords.contains {
                    owner.localizedCaseInsensitiveContains($0) ||
                    title.localizedCaseInsensitiveContains($0)
                }
            }

            // ── 同一个 PID 只保留最合适的窗口 ──
            // 优先级 1：kCGWindowLayer == 0（标准应用窗口）
            //           layer < 0 是 Wine 虚拟桌面根窗口（会导致坐标偏移至屏幕左上角）
            //           layer > 0 是悬浮面板 / 工具窗
            // 优先级 2：同 layer 时取面积最大（内容窗口 > 装饰边框）
            var bestByPID: [Int32: GameWindow] = [:]
            for win in allMatched {
                let area = win.frame.width * win.frame.height
                if let existing = bestByPID[win.pid] {
                    let existingArea = existing.frame.width * existing.frame.height
                    // 新窗口 layer 更优（接近 0 更好），或 layer 相同但面积更大
                    let newLayerBetter = abs(win.layer) < abs(existing.layer)
                    let sameLevelBigger = win.layer == existing.layer && area > existingArea
                    if newLayerBetter || sameLevelBigger {
                        print("[WindowService] ⚠️ PID:\(win.pid) 替换窗口 layer:\(existing.layer) \(Int(existing.frame.width))×\(Int(existing.frame.height)) → layer:\(win.layer) \(Int(win.frame.width))×\(Int(win.frame.height))")
                        bestByPID[win.pid] = win
                    } else {
                        print("[WindowService] ⚠️ PID:\(win.pid) 忽略窗口 layer:\(win.layer) \(Int(win.frame.width))×\(Int(win.frame.height))")
                    }
                } else {
                    bestByPID[win.pid] = win
                }
            }

            // 按 instanceIndex 排序保持稳定顺序
            return bestByPID.values.sorted { $0.instanceIndex < $1.instanceIndex }
        
    }

    // MARK: - 发现所有窗口（调试）
    static func discoverAllWindows() -> [GameWindow] {
        discoverWindows { _, _ in true }
    }

    // MARK: - 通用枚举
    private static func discoverWindows(filter: (String, String) -> Bool) -> [GameWindow] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            print("[WindowService] CGWindowListCopyWindowInfo 返回 nil，请检查屏幕录制权限")
            return []
        }
        print("[WindowService] 原始窗口总数: \(rawList.count)")

        var results: [GameWindow] = []
        var idx = 0

        for info in rawList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let windowID  = info[kCGWindowNumber    as String] as? Int,
                  let pid       = info[kCGWindowOwnerPID  as String] as? Int32,
                  let bounds    = info[kCGWindowBounds    as String] as? [String: CGFloat]
            else { continue }

            let title = info[kCGWindowName as String] as? String ?? ownerName
            let w = bounds["Width"] ?? 0, h = bounds["Height"] ?? 0
            guard w > 200 && h > 150 else { continue }
            guard filter(ownerName, title) else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            print("[WindowService] ✅ \(ownerName) | \(title) | \(Int(w))×\(Int(h)) | PID:\(pid) | Layer:\(layer)")
            results.append(GameWindow(
                id: windowID, pid: pid,
                title: title.isEmpty ? ownerName : title,
                frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h),
                instanceIndex: idx,
                layer: layer
            ))
            idx += 1
        }
        return results
    }
    
    
    // WindowService 里加这个方法
//    static func getWindowFrameByPID(_ pid: Int32) -> CGRect? {
//        guard let rawList = CGWindowListCopyWindowInfo(
//            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
//        ) as? [[String: Any]] else { return nil }
//
//        return rawList
//            .filter { info in
//                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
//                      ownerPID == pid,
//                      let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
//                      let w = bounds["Width"], let h = bounds["Height"]
//                else { return false }
//                return w > 200 && h > 150  // 过滤掉小窗口/工具窗口
//            }
//            .compactMap { info -> CGRect? in
//                guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
//                return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
//                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
//            }
//            .max(by: { $0.width * $0.height < $1.width * $1.height }) // 取最大窗口
//    }


    // MARK: - 截图（ScreenCaptureKit）
    // SCWindow 缓存：首次查询后缓存，避免每帧都调用 excludingDesktopWindows 触发 TCC
    private static var scWindowCache: [Int: SCWindow] = [:]

    static func captureWindow(_ window: GameWindow,
                               completion: @escaping (NSImage?) -> Void) {
        Task { completion(await captureWindowAsync(window)) }
    }

    // 连续失败计数（避免 TCC 未授权时刷屏报错）
    private static var captureFailCount: [Int: Int] = [:]

    static func captureWindowAsync(_ window: GameWindow) async -> NSImage? {
            do {
                let scWin: SCWindow
                if let cached = scWindowCache[window.id] {
                    scWin = cached
                } else {
                    let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: true)
                    guard let found = shareableContent.windows.first(where: {
                        $0.windowID == CGWindowID(window.id)
                    }) else {
                        print("[截图] 未找到 SCWindow id=\(window.id)")
                        return nil
                    }
                    scWindowCache[window.id] = found
                    scWin = found
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWin)
                let config = SCStreamConfiguration()
                // ⚠️ SCStreamConfiguration.width/height 单位是物理像素（px），
                //    scWin.frame.width/height 是逻辑点（pt）。
                //    Retina 2x 屏幕 1pt = 2px，必须乘以 backingScaleFactor。
                //    否则截图尺寸只有窗口物理尺寸的一半，Vision OCR normY 换算到
                //    window.frame 时会出现 2x 的系统性偏移。
                let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
                config.width       = max(1, Int(scWin.frame.width)  * scale)
                config.height      = max(1, Int(scWin.frame.height) * scale)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                let cg = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                captureFailCount[window.id] = 0   // 成功，重置计数
                // autoreleasepool 确保 NSImage 初始化产生的中间对象及时释放
                let result: NSImage = autoreleasepool {
                    NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                return result

            } catch {
                scWindowCache.removeValue(forKey: window.id)
                let count = (captureFailCount[window.id] ?? 0) + 1
                captureFailCount[window.id] = count
                // 只在第1、10、30次打印，避免刷屏
                if count == 1 || count == 10 || count % 30 == 0 {
                    let isTCC = error.localizedDescription.contains("TCC") ||
                                error.localizedDescription.contains("拒绝") ||
                                error.localizedDescription.contains("denied")
                    if isTCC {
                        print("[截图] ⚠️ 屏幕录制权限未授权（第\(count)次）请前往：系统设置→隐私与安全性→屏幕录制→添加App→重启")
                    } else {
                        print("[截图] 错误(\(count)次): \(error.localizedDescription)")
                    }
                }
                return nil
            }
        }
    // 手动清除窗口缓存（窗口关闭/重启游戏后调用）
    static func clearWindowCache() {
        scWindowCache.removeAll()
    }

    // MARK: - 黑边检测
    /// 分析截图像素，找出四边黑色边框，将结果写入 window。
    /// 像素格式 kCVPixelFormatType_32BGRA（SCStreamConfiguration 默认）。
    /// 成功返回 true，并设置 window.insetReady = true。
    /// 之后所有点击用 contentOrigin + relX*fixedContentWidth 换算，不受窗口尺寸和黑边影响。
    @discardableResult
    static func detectAndApplyContentInsets(cgImage: CGImage, window: inout GameWindow) -> Bool {
        let imgW = cgImage.width
        let imgH = cgImage.height
        let bpr  = cgImage.bytesPerRow

        guard imgW > 200, imgH > 150,
              let cfData = cgImage.dataProvider?.data else {
            print("[黑边检测] 无法读取图像数据")
            return false
        }

        let ptr = CFDataGetBytePtr(cfData)!

        // BGRA 格式：offset+0=B, offset+1=G, offset+2=R, offset+3=A
        @inline(__always)
        func isBlack(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < imgW, y >= 0, y < imgH else { return true }
            let off = y * bpr + x * 4
            return ptr[off + 2] < 20 && ptr[off + 1] < 20 && ptr[off] < 20
        }

        // ── 5条采样线取中位数，对抗游戏内深色UI误判 ──────────────
        // 使用中位数（而非max/min），3条或更多采样中只要超半数结果一致就采纳，
        // 单条采样线碰到游戏深色内容无法影响最终结论。
        func median(_ vals: [Int]) -> Int {
            let s = vals.sorted()
            return s[s.count / 2]
        }

        // 上边：沿5列从顶往下扫，找到第一个非黑像素的行号
        let sampleX = [imgW/6, imgW/4, imgW/2, imgW*3/4, imgW*5/6]
        var topCands: [Int] = []
        for x in sampleX {
            var y = 0
            while y < imgH / 2 && isBlack(x, y) { y += 1 }
            topCands.append(y)
        }
        let topPx = median(topCands)

        // 下边：沿5列从底往上扫
        var botCands: [Int] = []
        for x in sampleX {
            var y = imgH - 1
            while y > imgH / 2 && isBlack(x, y) { y -= 1 }
            botCands.append((imgH - 1) - y)
        }
        let botPx = median(botCands)

        // 左边：沿5行从左往右扫
        let sampleY = [imgH/6, imgH/4, imgH/2, imgH*3/4, imgH*5/6]
        var leftCands: [Int] = []
        for y in sampleY {
            var x = 0
            while x < imgW / 2 && isBlack(x, y) { x += 1 }
            leftCands.append(x)
        }
        let leftPx = median(leftCands)

        // 右边：沿5行从右往左扫
        var rightCands: [Int] = []
        for y in sampleY {
            var x = imgW - 1
            while x > imgW / 2 && isBlack(x, y) { x -= 1 }
            rightCands.append((imgW - 1) - x)
        }
        let rightPx = median(rightCands)

        // 像素坐标 → 逻辑点
        // SCStreamConfiguration.width 设置为 scWin.frame.width（逻辑点），
        // 所以 cgImage.width == window.frame.width（均为逻辑点数值），scaleX = 1.0；
        // Retina 2x 时同样如此，无需额外处理。
        let scaleX = CGFloat(imgW) / window.frame.width
        let scaleY = CGFloat(imgH) / window.frame.height

        let inL = CGFloat(leftPx)  / scaleX
        let inT = CGFloat(topPx)   / scaleY
        let inR = CGFloat(rightPx) / scaleX
        let inB = CGFloat(botPx)   / scaleY

        let cW = window.frame.width  - inL - inR
        let cH = window.frame.height - inT - inB

        guard cW > 100, cH > 100 else {
            print("[黑边检测] ⚠️ 结果异常 content=\(Int(cW))×\(Int(cH)) 候选值→顶:\(topCands) 底:\(botCands) 左:\(leftCands) 右:\(rightCands)")
            return false
        }

        window.contentInsetLeft   = inL
        window.contentInsetTop    = inT
        window.contentInsetRight  = inR
        window.contentInsetBottom = inB
        window.fixedContentWidth  = cW
        window.fixedContentHeight = cH
        window.insetReady         = true

        print("[黑边检测] ✅ 上\(Int(inT))pt 下\(Int(inB))pt 左\(Int(inL))pt 右\(Int(inR))pt  内容区 \(Int(cW))×\(Int(cH))pt")
        return true
    }
    
    /// 实时查询窗口当前位置（窗口移动后仍然准确）
    /// 不加 .optionOnScreenOnly，确保跨 Space（虚拟桌面）也能找到窗口
    static func getWindowFrame(windowID: Int) -> CGRect? {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in rawList {
            guard let wid    = info[kCGWindowNumber as String] as? Int, wid == windowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            return CGRect(
                x:      bounds["X"]      ?? 0,
                y:      bounds["Y"]      ?? 0,
                width:  bounds["Width"]  ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
        return nil
    }

    /// 窗口 ID 失效时（关闭重开后），通过 PID 找回最大窗口
    /// 不加 .optionOnScreenOnly，确保跨 Space 也能找到
    static func findWindowByPID(_ pid: Int32) -> (id: Int, frame: CGRect)? {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var bestArea: CGFloat = 0
        var result: (id: Int, frame: CGRect)? = nil
        for info in rawList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid,
                  let wid    = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 200 && h > 150
            else { continue }
            let area = w * h
            if area > bestArea {
                bestArea = area
                result = (id: wid, frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h))
            }
        }
        return result
    }

    // MARK: - 激活 + 等待窗口位置稳定
    // activateApp 让 app.isActive=true，但 Space 切换动画还需要额外时间，
    // 动画期间 CGWindowListCopyWindowInfo 返回的是中途坐标，点击会偏移。
    // 解决方案：激活后每 100ms 轮询一次 frame，连续 2 次 (<1pt) 不变化才认为稳定。
    private static func activateAndStabilize(window: inout GameWindow) {
        let app = NSRunningApplication(processIdentifier: window.pid)

           // ── 优化1：游戏已在前台，跳过激活，只刷新 frame ──────────────
           // 重复激活 Wine 进程会触发层级动画，导致 frame 抖动。
           // Bot 运行期间游戏通常一直在前台，此分支覆盖 90% 的调用。
           if app?.isActive == true {
               if let fresh = getWindowFrame(windowID: window.id) {
                   window.frame = fresh
               }
               return
           }

           // ── 需要激活：等待 Wine 层级动画真正结束 ────────────────────
           activateApp(pid: window.pid)

           var prevX: CGFloat = -.infinity
           var prevY: CGFloat = -.infinity
           var stableCount    = 0

           for _ in 0..<40 { // 最长等待 4 秒（40 × 100ms）
               Thread.sleep(forTimeInterval: 0.1)

               let fresh: CGRect
               if let f = getWindowFrame(windowID: window.id) {
                   fresh = f
               } else if let found = findWindowByPID(window.pid) {
                   window.id = found.id
                   fresh = found.frame
               } else {
                   continue
               }

               // ── 优化2：阈值收紧到 0.5pt，连续 5 次（500ms）才算稳定 ──
               if abs(fresh.minX - prevX) < 0.5 && abs(fresh.minY - prevY) < 0.5 {
                   stableCount += 1
               } else {
                   stableCount = 0  // 任何抖动都重置，必须重新计数
               }
               prevX = fresh.minX
               prevY = fresh.minY
               window.frame = fresh

               if stableCount >= 5 { break } // 连续 500ms 不动，动画已结束
           }

           // ── 优化3：稳定后再取一次最终 frame，防止"动画末尾假稳定" ──
           Thread.sleep(forTimeInterval: 0.1)
           if let finalFrame = getWindowFrame(windowID: window.id) {
               window.frame = finalFrame
           }
//        activateApp(pid: window.pid)
//
//        var prevX: CGFloat = -.infinity
//        var prevY: CGFloat = -.infinity
//        var stableCount    = 0
//
//        for _ in 0..<20 { // 最长等待 2 秒
//            Thread.sleep(forTimeInterval: 0.1)
//
//            let fresh: CGRect
//            if let f = getWindowFrame(windowID: window.id) {
//                fresh = f
//            } else if let found = findWindowByPID(window.pid) {
//                window.id = found.id
//                fresh = found.frame
//            } else {
//                continue
//            }
//
//            if abs(fresh.minX - prevX) < 1 && abs(fresh.minY - prevY) < 1 {
//                stableCount += 1
//            } else {
//                stableCount = 0
//            }
//            prevX = fresh.minX
//            prevY = fresh.minY
//            window.frame = fresh
//
//            if stableCount >= 2 { break } // 连续 200ms 坐标不变，动画已结束
//        }
    }

    // MARK: - 鼠标点击
    // 坐标系：左上角原点 (0,0)，X 向右增大，Y 向下增大
    static func clickAt(window: inout GameWindow, relX: Double, relY: Double,
                         noiseRadius: Int = 0) {
        activateAndStabilize(window: &window)
        let noise: () -> Double = { Double(Int.random(in: -noiseRadius...noiseRadius)) }
        let screenPoint = CGPoint(
            x: window.frame.minX + relX * window.frame.width  + noise(),
            y: window.frame.minY + relY * window.frame.height + noise()
        )
        postMouseClick(at: screenPoint)
    }

    /// 鼠标右键
    static func rightClickAt(window: inout GameWindow, relX: Double, relY: Double,
                              noiseRadius: Int = 0) {
        activateAndStabilize(window: &window)
        let noise: () -> Double = { Double(Int.random(in: -noiseRadius...noiseRadius)) }
        let screenPoint = CGPoint(
            x: window.frame.minX + relX * window.frame.width  + noise(),
            y: window.frame.minY + relY * window.frame.height + noise()
        )
        postMouseClick(at: screenPoint, button: .right)
    }

    /// OCR 点击（归一化坐标）
    /// - srcW/srcH: OCR 来源的 cgImage 实际尺寸（px），用于与 window.frame 对齐
    ///   必须传入，否则 Retina 屏幕下 normY × window.frame.height ≠ 实际像素位置，导致向下偏移
    static func clickAtOCR(window: inout GameWindow, normX: Double, normY: Double,
                            srcW: Int, srcH: Int,
                            noiseRadius: Int = 0) {
        activateAndStabilize(window: &window)
        let noise: () -> Double = { Double(Int.random(in: -noiseRadius...noiseRadius)) }
        // 用源图尺寸换算像素偏移，再转为逻辑点（÷ backingScaleFactor）
        let scale  = NSScreen.main?.backingScaleFactor ?? 2
        let ptOffX = normX * Double(srcW) / scale
        let ptOffY = normY * Double(srcH) / scale
        let screenPoint = CGPoint(
            x: window.frame.minX + ptOffX + noise(),
            y: window.frame.minY + ptOffY + noise()
        )
        postMouseClick(at: screenPoint)
    }

    /// 像素坐标点击（以窗口左上角为原点，单位: pt）
    /// 优点：窗口拖动后仍准确；窗口拉伸缩小时，游戏内容固定分辨率不变，像素坐标不随窗口大小改变
    /// 适用场景：游戏渲染分辨率固定（如 1026×798），窗口可随意拖动
    static func clickAtPx(window: inout GameWindow, px: CGFloat, py: CGFloat,
                           noiseRadius: Int = 0) {
        activateAndStabilize(window: &window)
        let noise: () -> Double = { Double(Int.random(in: -noiseRadius...noiseRadius)) }
        let screenPoint = CGPoint(
            x: window.frame.minX + px + noise(),
            y: window.frame.minY + py + noise()
        )
        postMouseClick(at: screenPoint)
    }

    /// 鼠标右键（像素坐标）
    static func rightClickAtPx(window: inout GameWindow, px: CGFloat, py: CGFloat,
                                noiseRadius: Int = 0) {
        activateAndStabilize(window: &window)
        let noise: () -> Double = { Double(Int.random(in: -noiseRadius...noiseRadius)) }
        let screenPoint = CGPoint(
            x: window.frame.minX + px + noise(),
            y: window.frame.minY + py + noise()
        )
        postMouseClick(at: screenPoint, button: .right)
    }
    
  
    
    static func activateApp(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: .activateIgnoringOtherApps)
        
        // 等待真正激活（最多 500ms，每 20ms 轮询一次）
        let deadline = Date().addingTimeInterval(0.5)
        while !app.isActive && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    
    static func postMouseClick(at point: CGPoint, button: CGMouseButton = .left) {
        let dn: CGEventType = button == .left ? .leftMouseDown  : .rightMouseDown
        let up: CGEventType = button == .left ? .leftMouseUp    : .rightMouseUp
        CGEvent(mouseEventSource: nil, mouseType: dn, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }
    // MARK: - 键盘操作

    /// 按下单个键（通过 CGKeyCode）
    static func pressKey(_ keyCode: CGKeyCode, holdDuration: TimeInterval = 0.05) {
        let dn = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        dn?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: holdDuration)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    /// 按下带修饰键的组合键（如 Cmd+A、Shift+方向键）
    static func pressKeys(_ keyCode: CGKeyCode, modifiers: CGEventFlags,
                          window: GameWindow? = nil) {
        let dn = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        dn?.flags = modifiers
        up?.flags = modifiers
        dn?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.5)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.3)
    }


}

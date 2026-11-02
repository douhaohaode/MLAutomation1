//
//  WindowService.swift
//  MLAutomation
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

// 辅助功能里的窗口对象没有公开接口能转回 CGWindowID。
// 切换时必须靠这个对应关系，才能抬起“这一扇”而不是同进程里的另一扇。
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

class WindowService {

    // 进程名或窗口标题里带这些词，才当成要控制的游戏窗口
    static let gameProcessKeywords = ["mhmain.exe","Simulator","Google Chrome"]

    // MARK: - 发现游戏窗口（正式）
    // 扫描当前屏幕上的窗口，滤出游戏，再按进程合并成“一个进程一扇主窗口”。
    static func discoverGameWindows() -> [GameWindow] {
//        discoverWindows { owner, title in
//            gameProcessKeywords.contains {
//                owner.localizedCaseInsensitiveContains($0) ||
//                title.localizedCaseInsensitiveContains($0)
//            }
//        }
        
        // 先取出所有名字匹配的窗口。一个游戏进程里通常不止一扇（菜单条、边框、内容窗）
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
            // key 是进程号。同一个进程最后只留一扇，所以两个游戏必须是两个进程才会出现两个实例
            var bestByPID: [Int32: GameWindow] = [:]
            for win in allMatched {
                let area = win.frame.width * win.frame.height   // 用面积区分内容窗和细边框
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
    // 向系统要当前屏幕上的窗口列表，再按调用方给的条件过滤。
    // 列表顺序是从最前到最后，但这里先全部收集，稍后才按进程挑选。
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
            guard w > 200 && h > 150 else { continue }          // 丢掉菜单条、小浮窗
            guard filter(ownerName, title) else { continue }    // 丢掉不是游戏的窗口

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            print("[WindowService] ✅ \(ownerName) | \(title) | \(Int(w))×\(Int(h)) | PID:\(pid) | Layer:\(layer)")
            results.append(GameWindow(
                id: windowID, pid: pid,                         // 编号认这一扇，进程号认是哪个客户端
                title: title.isEmpty ? ownerName : title,
                frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h),
                instanceIndex: idx,                             // 第几个匹配到的，后面用来排序
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

    // MARK: - 先把目标窗口切到最前，再发普通点击
    // 游戏（Wine）只处理“这个屏幕点上最上层窗口”的鼠标。
    // 两扇窗叠在一起时，必须先把要操作的那一扇抬上来，点击才会进它。
    // 流程：已在最前就直接点；否则按窗口编号 AXRaise → 确认最上层已经是它 → 再点。

    private static let inputLock = NSLock()          // 两个实例共用。一扇抬起并点完，另一扇才能抬
    private static var didPromptAccessibility = false // 辅助功能弹窗只弹一次
    private static var didLogNeedAX = false           // “没权限”只打印一次，避免刷屏
    private static var didLogRaiseFail = false        // “抬不起来”只打印一次

    /// 点击前刷新这扇窗的位置。窗口被拖动后，旧的 frame 会点偏。
    private static func refreshIdentity(window: inout GameWindow) {
        if let fresh = getWindowFrame(windowID: window.id) {
            window.frame = fresh                         // 编号还在，只更新矩形
        } else if let found = findWindowByPID(window.pid) {
            window.id = found.id                         // 窗口被关掉重开，编号变了，用进程号找回
            window.frame = found.frame
        }
    }

    /// 问系统：这个屏幕点上，最上层的普通窗口是谁。
    /// 窗口列表从前到后，第一个盖住该点的就是当前会吃掉点击的那扇。
    private static func frontmostWindowID(at point: CGPoint) -> Int? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }       // 拿不到列表（通常是没有屏幕录制权限）

        for info in list {                               // 从前到后看
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0,                            // 只要普通窗口，跳过菜单栏、程序坞
                  let wid = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 20, h > 20                         // 忽略极小的装饰窗
            else { continue }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h)
            if frame.contains(point) { return wid }      // 这扇盖住了该点，它就是最上层
        }
        return nil                                       // 这个点上没有任何普通窗口
    }

    /// 有没有辅助功能权限。没有权限就无法把别的进程的窗口抬到最前。
    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }          // 已经允许过，直接通过
        guard prompt else { return false }               // 调用方说这次不要弹系统框
        guard !didPromptAccessibility else { return false } // 已经弹过一次，不再反复弹
        didPromptAccessibility = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary) // 弹出系统授权框
    }

    /// 读辅助功能窗口的位置和大小。编号对不上时，用矩形再对一次。
    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),  // 确认拿到的是坐标，不是别的类型
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// 把传入的这一扇窗口抬到最前。返回值表示“抬起”这个动作有没有发出去，不表示已经在最前。
    @discardableResult
    private static func raiseSpecificWindow(_ window: GameWindow) -> Bool {
        guard accessibilityTrusted(prompt: true) else {  // 没权限就无法切换
            if !didLogNeedAX {
                didLogNeedAX = true
                print("[WindowService] 没有辅助功能权限，无法把被挡住的游戏窗口切到最前。请在系统设置 → 隐私与安全性 → 辅助功能中允许本应用。")
            }
            return false
        }

        let app = AXUIElementCreateApplication(window.pid) // 用进程号找到这个游戏客户端
        AXUIElementSetMessagingTimeout(app, 1.0)            // 游戏不响应时，最多等 1 秒，避免卡死
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) // 先让整个进程到前台

        var value: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) // 取出该进程的全部窗口
        guard copyErr == .success, let windows = value as? [AXUIElement], !windows.isEmpty else {
            print("[WindowService] 读取窗口列表失败 pid=\(window.pid) err=\(copyErr.rawValue)")
            return false
        }

        var target: AXUIElement?                         // 最终要抬的那一个辅助功能窗口
        for element in windows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(element, &wid) == .success, Int(wid) == window.id {
                target = element                         // 编号相同，就是扫描时记下的那一扇
                break
            }
        }
        if target == nil {                               // 编号对不上时，用位置和大小再认一次
            target = windows.first { element in
                guard let frame = axFrame(element) else { return false }
                return abs(frame.minX - window.frame.minX) < 8
                    && abs(frame.minY - window.frame.minY) < 8
                    && abs(frame.width - window.frame.width) < 12
                    && abs(frame.height - window.frame.height) < 12
            }
        }
        guard let target else {
            print("[WindowService] 找不到窗口 id=\(window.id) 对应的可切换窗口")
            return false
        }

        let raiseErr = AXUIElementPerformAction(target, kAXRaiseAction as CFString) // 把这一扇盖到别的窗口上面
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)    // 设为主窗口
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue) // 让它接收键盘
        return raiseErr == .success
    }

    /// 保证这扇窗在自己的中心点上是最上层。已经是就马上返回，不必每次都切换。
    private static func makeFrontmost(_ window: inout GameWindow) -> Bool {
        refreshIdentity(window: &window)                 // 先用最新位置，避免用拖动前的旧坐标判断
        func probe() -> CGPoint {
            CGPoint(x: window.frame.midX, y: window.frame.midY) // 用窗口中心代表“这扇窗所在的位置”
        }
        if frontmostWindowID(at: probe()) == window.id { return true } // 中心点已经是自己，不用抬

        guard raiseSpecificWindow(window) else { return false } // 抬起失败（没权限或找不到窗）就放弃这次操作

        let deadline = Date().addingTimeInterval(0.8)    // 层次变化不是瞬时的，最多等 0.8 秒
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.03)          // 每 30 毫秒看一次
            refreshIdentity(window: &window)
            if frontmostWindowID(at: probe()) == window.id { return true } // 确认系统已经把它放到最前
        }
        if !didLogRaiseFail {
            didLogRaiseFail = true
            print("[WindowService] 窗口 id=\(window.id) 仍不在最前，本次点击已跳过，避免点到另一扇游戏。")
        }
        return false                                     // 超时仍被挡住，调用方不会发出点击
    }

    /// 在已经确认的屏幕坐标上发送一次真实点击。游戏只认这种点击。
    private static func hidClick(at point: CGPoint, button: CGMouseButton) {
        let dn: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown // 按下
        let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp     // 松开
        CGEvent(mouseEventSource: nil, mouseType: dn, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)                   // 发给系统，由最上层窗口接收
        Thread.sleep(forTimeInterval: 0.1)               // 按下和松开之间留一点时间，游戏才当成一次点击
        CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    /// 点击的总入口：加锁 → 切到最前 → 算出屏幕点 → 再确认这个点属于自己 → 点击。
    private static func clickOnFront(window: inout GameWindow, button: CGMouseButton, pointIn: (CGRect) -> CGPoint) {
        inputLock.lock()                                 // 挡住另一个实例，防止它中途把窗口又盖回来
        defer { inputLock.unlock() }
        guard makeFrontmost(&window) else { return }     // 没切到最前就不点
        let point = pointIn(window.frame)                // 用最新矩形把“窗口内坐标”换成屏幕坐标
        guard frontmostWindowID(at: point) == window.id else {
            print("[WindowService] 点击位置仍被挡住，跳过 id=\(window.id)")
            return                                       // 中心是自己，但这个点击点仍被别的窗盖住
        }
        hidClick(at: point, button: button)
    }

    // MARK: - 鼠标点击
    // 下面几个 click 都只负责把“窗口内的点”算成屏幕坐标，真正的切换和点击都在 clickOnFront。
    // 坐标系：窗口左上角是 (0,0)，X 向右，Y 向下。relX/relY 是占窗口宽高的比例，0.5 就是正中。
    static func clickAt(window: inout GameWindow, relX: Double, relY: Double,
                         noiseRadius: Int = 0) {
        clickOnFront(window: &window, button: .left) { frame in
            let nx = Double(Int.random(in: -noiseRadius...noiseRadius)) // 水平随机偏移，避免每次点同一像素
            let ny = Double(Int.random(in: -noiseRadius...noiseRadius))
            return CGPoint(x: frame.minX + relX * frame.width + nx,     // 窗口左边 + 比例 × 宽
                           y: frame.minY + relY * frame.height + ny)     // 窗口上边 + 比例 × 高
        }
    }

    /// 鼠标右键
    static func rightClickAt(window: inout GameWindow, relX: Double, relY: Double,
                              noiseRadius: Int = 0) {
        clickOnFront(window: &window, button: .right) { frame in
            let nx = Double(Int.random(in: -noiseRadius...noiseRadius))
            let ny = Double(Int.random(in: -noiseRadius...noiseRadius))
            return CGPoint(x: frame.minX + relX * frame.width + nx,
                           y: frame.minY + relY * frame.height + ny)
        }
    }

    /// OCR 点击（归一化坐标）
    /// - srcW/srcH: OCR 来源的 cgImage 实际尺寸（px），用于与 window.frame 对齐
    ///   必须传入，否则 Retina 屏幕下 normY × window.frame.height ≠ 实际像素位置，导致向下偏移
    static func clickAtOCR(window: inout GameWindow, normX: Double, normY: Double,
                            srcW: Int, srcH: Int,
                            noiseRadius: Int = 0) {
        clickOnFront(window: &window, button: .left) { frame in
            let nx = Double(Int.random(in: -noiseRadius...noiseRadius))
            let ny = Double(Int.random(in: -noiseRadius...noiseRadius))
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            return CGPoint(x: frame.minX + normX * Double(srcW) / scale + nx,
                           y: frame.minY + normY * Double(srcH) / scale + ny)
        }
    }

    /// 像素坐标点击（以窗口左上角为原点，单位: pt）
    /// 优点：窗口拖动后仍准确；窗口拉伸缩小时，游戏内容固定分辨率不变，像素坐标不随窗口大小改变
    /// 适用场景：游戏渲染分辨率固定（如 1026×798），窗口可随意拖动
    static func clickAtPx(window: inout GameWindow, px: CGFloat, py: CGFloat,
                           noiseRadius: Int = 0) {
        clickOnFront(window: &window, button: .left) { frame in
            let nx = Double(Int.random(in: -noiseRadius...noiseRadius))
            let ny = Double(Int.random(in: -noiseRadius...noiseRadius))
            return CGPoint(x: frame.minX + px + nx, y: frame.minY + py + ny)
        }
    }

    /// 鼠标右键（像素坐标）
    static func rightClickAtPx(window: inout GameWindow, px: CGFloat, py: CGFloat,
                                noiseRadius: Int = 0) {
        clickOnFront(window: &window, button: .right) { frame in
            let nx = Double(Int.random(in: -noiseRadius...noiseRadius))
            let ny = Double(Int.random(in: -noiseRadius...noiseRadius))
            return CGPoint(x: frame.minX + px + nx, y: frame.minY + py + ny)
        }
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
    
    // MARK: - 键盘操作

    /// 按下单个键。键盘没有坐标，谁在最前就进谁，所以按之前也要先切换窗口。
    static func pressKey(_ keyCode: CGKeyCode, window: inout GameWindow, holdDuration: TimeInterval = 0.05) {
        inputLock.lock()                                 // 和点击共用同一把锁
        defer { inputLock.unlock() }
        guard makeFrontmost(&window) else { return }     // 没切到最前，这次按键取消
        let dn = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)  // 按下
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) // 松开
        dn?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: holdDuration)      // 按住这么久
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    /// 按下带修饰键的组合键（如 Cmd+A、Shift+方向键）
    static func pressKeys(_ keyCode: CGKeyCode, modifiers: CGEventFlags,
                          window: inout GameWindow) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard makeFrontmost(&window) else { return }     // 组合键同样先切到这扇窗
        let dn = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        dn?.flags = modifiers                            // 带上 Command / Shift 等修饰键
        up?.flags = modifiers
        dn?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.5)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.3)
    }


}

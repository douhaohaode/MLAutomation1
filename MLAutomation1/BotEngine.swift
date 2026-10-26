//
//  BotEngine.swift
//  MLAutomation
//

import Foundation
import AppKit

/// 坐标点
struct SkillSlots {
  
        //地府 无名鬼蜮 烧双点位
        static let DF1 = CGPoint(x: 0.5942, y: 0.4590)
        static let DF2 = CGPoint(x: 0.4144, y: 0.4580)
        static let DF3 = CGPoint(x: 0.4040, y: 0.6371)
        static let DF4 = CGPoint(x: 0.6158, y: 0.6370)
     
        // 地府4曾
        static let DF41 = CGPoint(x: 0.5590, y: 0.4598)
        static let DF42 = CGPoint(x: 0.3457, y: 0.4708)
        static let DF43 = CGPoint(x: 0.5540, y: 0.6003)
        static let DF44 = CGPoint(x: 0.3234, y: 0.6139)
    
        //龙1 烧双点位
        static let L11 = CGPoint(x: 0.6361, y: 0.4610)
        static let L12 = CGPoint(x: 0.2945, y: 0.6403)
        static let L13 = CGPoint(x: 0.2926, y: 0.4806)
        static let L14 = CGPoint(x: 0.4965, y: 0.6298)
}

/// 键盘
struct GameKeys {
    static let attack    = KeyCode.num1
    static let skill1    = KeyCode.num2
    static let skill2    = KeyCode.num3
    static let skill3    = KeyCode.num4
    static let skill4    = KeyCode.num5
    static let useItem   = KeyCode.num6
    static let pickUp    = KeyCode.space
    static let confirm   = KeyCode.return
    static let cancel    = KeyCode.escape
    static let openBag   = KeyCode.b
    static let openMap   = KeyCode.m
    static let walkUp    = KeyCode.arrowUp
    static let walkDown  = KeyCode.arrowDown
    static let walkLeft  = KeyCode.arrowLeft
    static let walkRight = KeyCode.arrowRight
    static let v = KeyCode.v
    static let tab = KeyCode.tab
    static let f9 = KeyCode.f9
}

enum TaskMode: CaseIterable {
    case test       // 测试
    case shaoshuang // 烧双
    case zhuaGui    // 抓鬼
    case fengyao    // 封妖
    case paoshang   // 跑商

    var displayName: String {
        switch self {
        case .test:       return "测试"
        case .shaoshuang: return "烧双"
        case .zhuaGui:    return "抓鬼"
        case .fengyao:    return "封妖"
        case .paoshang:   return "跑商"
        }
    }

    var icon: String {
        switch self {
        case .test:       return "🧪"
        case .shaoshuang: return "🔥"
        case .zhuaGui:    return "👻"
        case .fengyao:    return "⚡️"
        case .paoshang:   return "🛒"
        }
    }
}

/// 弹屏区域配置（归一化坐标，需根据实际游戏画面校准）
/// 使用坐标录制工具点击弹屏弹窗边界 + 每个角色区域边界来确定精确范围
struct PopupCharRegions {
    /// 弹屏弹窗整体区域（相对全图的归一化坐标）
    /// 先裁剪这个区域，隔离背景人物等干扰
    static let popupROI = CGRect(x: 0.20, y: 0.25, width: 0.60, height: 0.55)

    /// 四个角色在弹屏弹窗内的子区域（⚠️ 相对 popupROI 的归一化坐标，不是全图坐标）
    /// 例如 (0.05, 0.05, 0.40, 0.45) 表示 popupROI 内左上 40%×45% 的区域
    static let char1 = CGRect(x: 0.05, y: 0.05, width: 0.40, height: 0.45)  // 左上角色
    static let char2 = CGRect(x: 0.55, y: 0.05, width: 0.40, height: 0.45)  // 右上角色
    static let char3 = CGRect(x: 0.05, y: 0.52, width: 0.40, height: 0.45)  // 左下角色
    static let char4 = CGRect(x: 0.55, y: 0.52, width: 0.40, height: 0.45)  // 右下角色

    static let all: [CGRect] = [char1, char2, char3, char4]
}


class BotEngine {
    
    private let state:    InstanceState
    private let detector: SceneDetector = SceneDetector()
    private var onLog:    ((LogEntry) -> Void)?

    private var task:      Task<Void, Never>?
    private(set) var isRunning: Bool = false


    private let reactionDelay: ClosedRange<Double> = 0.35...0.85
    private let clickInterval:  ClosedRange<Double> = 0.10...0.30

    // ── 截图共享（核心修复）──────────────────────────────
    // 截图只在一处获取，通过 actor 安全共享给预览和识别两个消费者
    private let frameBuffer = FrameBuffer()
    

    private var eventTap: CFMachPort?
    
    
    //  // 抓鬼 mainLoop() 内部的局部变量，提升到这里
    private var currentStep: QuestStep = .step1_teleportToStation
    private var retryCount: Int = 0
    
    // shouldStop 让 QuestFlow 感知暂停/停止
      // 初始化时注入
      private func setupQuestFlow() {
          questFlow.shouldStop = { [weak self] in
              guard let self else { return true }
              return !self.isRunning
          }
      }
    
    // 抓鬼
    private lazy var questFlow = QuestFlow(
        state:    state,
        detector: detector,
        freshFrame: { [weak self] in await self?.freshFrame() },
        onLog:    { [weak self] msg in self?.log(scene: .unknown, action: msg) }
    )
    
    
    // 云游道人购买任务
    private lazy var wanderingTaoistTask = WanderingTaoistTask(
        state:       state,
        frameBuffer: frameBuffer,
        detector:    detector,
        onLog:       { [weak self] in self?.onLog?($0) }
    )

    // 封妖任务
    private lazy var fengyaoTask = FengyaoTask(
        state:    state,
        detector: detector,
        onLog:    { [weak self] msg in self?.log(scene: .unknown, action: msg) }
    )


    // 🔧 调试：点击坐标监听
    private var clickMonitor: Any?

    /// taskMode 直接读 state.taskMode，UI 通过 InstanceState 的 @Published 驱动刷新
    var taskMode: TaskMode {
        get { state.taskMode }
        set { state.taskMode = newValue }
    }
    
   
    init(state: InstanceState, onLog: @escaping (LogEntry) -> Void) {
        self.state = state
        self.onLog = onLog

        questFlow.shouldStop = { [weak self] in
            guard let self else { return true }
            return !self.isRunning
        }
        fengyaoTask.shouldStop = { [weak self] in
            guard let self else { return true }
            return !self.isRunning
        }
    }

    // MARK: - 控制
    func start() {
        guard !isRunning else { return }

        if task != nil {
            task?.cancel()
            task = nil
            Thread.sleep(forTimeInterval: 0.35)
        }

        isRunning = true
        DispatchQueue.main.async { self.state.status = .running; self.state.startTime = Date() }
        task = Task(priority: .userInitiated) { [weak self] in await self?.mainLoop() }

        startClickMonitor()
    }
    
    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        currentStep = .step1_teleportToStation
        retryCount  = 0
        DispatchQueue.main.async { self.state.status = .stopped }
        stopClickMonitor()
    }

    func pause() {
        isRunning = false; task?.cancel(); task = nil
        DispatchQueue.main.async { self.state.status = .paused }
    }

    func resume() {
        guard state.status == .paused else { return }
        start()
    }
    
    

    // MARK: - 主循环
    // ┌─────────────────────────────────────────────────┐
    // │  截图线程（唯一）→ FrameBuffer                   │
    // │       ↓                ↓                        │
    // │  预览消费者(5fps)  战斗逻辑消费者(原节奏)          │
    // └─────────────────────────────────────────────────┘
    private func mainLoop() async {
        print("111");
        // ── 1. 唯一截图循环 ───────────────────────────────
        // 每 0.2 秒截一次图，写入 frameBuffer
        let captureTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            var errorCount = 0

            while self.isRunning && !Task.isCancelled {
                if let nsImage = await WindowService.captureWindowAsync(self.state.window) {
                    await self.frameBuffer.set(nsImage)
                    errorCount = 0
                } else {
                    errorCount += 1
                    if errorCount >= 5 {
                        DispatchQueue.main.async { self.state.status = .error }
                        return
                    }
                }
                // 截图频率：5fps
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        // ── 2. 预览刷新（消费 frameBuffer，直接更新UI）──────
        let previewTask = Task<Void, Never> { [weak self] in
            guard let self else { return }

            while self.isRunning && !Task.isCancelled {
                if let img = await self.frameBuffer.get() {
                    DispatchQueue.main.async { self.state.screenshot = img }
                }
                // 预览刷新与截图同频即可
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        
        // ── 3. 主任务循环 ────────────────────────────────────
            //  var currentStep: QuestStep = .step1_teleportToStation
              //var retryCount  = 0
              let maxRetry    = 3
              // 保存上一帧坐标，用于判断玩家是否移动
              var prevXPx: String = ""
              var prevYPx: String = ""

              // 黑边自动检测已禁用：自动检测在游戏加载画面等深色场景下会产生错误偏移值，
              // 导致每次点击都带有额外偏差，反而更不准确。
              // 坐标系：直接使用 window.frame（激活后由 activateAndStabilize 保证是最新稳定值）。

              while isRunning && !Task.isCancelled {
       
                  guard let cgImage = await freshFrame() else {
                      try? await Task.sleep(nanoseconds: 500_000_000)
                      continue
                  }
                 // 测试（像素坐标版，以窗口左上角为原点）
                 // 当前坐标是临时占位符，请启动程序开始运行后点击游戏界面录制新坐标
                 if taskMode == .test {
                     // ── 弹屏检测：先裁剪弹屏区域，再在其中找朝向自己的角色并点击 ──
                     if let popupResult = detector.findFrontFacingCharacter(
                         in: cgImage,
                         popupROI: PopupCharRegions.popupROI,
                         charRegions: PopupCharRegions.all
                     ) {
                         detector.debugSavePopupDetection(cgImage,
                                                         popupROI: PopupCharRegions.popupROI,
                                                         charRegions: PopupCharRegions.all,
                                                         result: popupResult)
                         log(scene: .unknown,
                             action: "🎯 弹屏: #\(popupResult.index+1) 对称度=\(String(format:"%.3f", popupResult.score))")
                         await click(popupResult.center)
                         await humanDelay(1...2)
                     } else {
                         log(scene: .unknown, action: "⚠️ 弹屏检测: 未找到正面")
                         await humanDelay(0.5...1)
                     }
                 }
  
                  if taskMode == .fengyao {
                      // ── 封妖任务 ──────────────────────────────────────
                      // 每帧扫描 npcScanROI 区域找含「远古」的 NPC，
                      // 过滤失效坐标后点击并监测弹框「对话」/「战斗」，
                      // 无论结果如何都记入失效坐标，防止重复点击玩家/已完成 NPC
                      await fengyaoTask.runOnce(cgImage: cgImage)
                  }
                  
                  // ── 任务 ──────────────────────────────────────
                    if taskMode == .shaoshuang {
                        async let mapNameTask    = detector.ocrRegion(cgImage, region: UIRegions.locationPx)
                        async let coordinateTask = detector.ocrRegion(cgImage, region: UIRegions.fightPx)
                        async let xPxTask        = detector.ocrRegion(cgImage, region: UIRegions.xPx)
                        async let yPxTask        = detector.ocrRegion(cgImage, region: UIRegions.yPx)

                        let (mapName, coordinate, currentXPx, currentYPx) = await (
                            mapNameTask, coordinateTask, xPxTask, yPxTask
                        )

                        let playerMoved = (currentXPx != prevXPx) || (currentYPx != prevYPx)
                        prevXPx = currentXPx
                        prevYPx = currentYPx

                        if playerMoved {
                            print("玩家移动中 (\(currentXPx), \(currentYPx))")
                            continue  // 移动中不操作，等下一帧
                        }

                        print("玩家停止, 地图: \(mapName)")

                        if coordinate.contains("回合") {
                            print("战斗中，等待回合结束")
                            continue
                        }

                        // 随机选传送点，Tab 打开地图 → 点击 → Tab 关闭
                        let targetPos = getRandomPosition(from: [SkillSlots.DF1, SkillSlots.DF2, SkillSlots.DF3, SkillSlots.DF4])
                        await humanDelay(0.3...0.6)
                        await pressKey(GameKeys.tab)
                        await humanDelay(0.8...1.4)
                        await click(targetPos)
                        await humanDelay(1.8...2.6)
                        await pressKey(GameKeys.tab)

                        // 等待玩家开始移动（最多 4 秒，每 200ms 检测一次）
                        var moved = false
                        for _ in 0..<20 {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            guard let fresh = await freshFrame() else { continue }
                            let newX = await detector.ocrRegion(fresh, region: UIRegions.xPx)
                            let newY = await detector.ocrRegion(fresh, region: UIRegions.yPx)
                            if newX != prevXPx || newY != prevYPx {
                                print("✅ 玩家开始移动")
                                prevXPx = newX
                                prevYPx = newY
                                moved = true
                                break
                            }
                        }

                        if !moved {
                            log(scene: .unknown, action: "⚠️ 移动超时，下一帧重试")
                        }
                    }

                    // ── 抓鬼任务 ──────────────────────────────────────
                    if taskMode == .zhuaGui {
                        let result = await questFlow.run(step: currentStep, cgImage: cgImage)

                        switch result {
                        case .success:
                            retryCount  = 0
                            currentStep = currentStep.next
                            log(scene: .unknown, action: "✅ \(currentStep.description)")

                        case .failure(let reason):
                            retryCount += 1
                              log(scene: .unknown, action: "❌ 步骤失败: \(reason) (\(retryCount)/\(maxRetry))")
                              if reason.contains("未能点击到驿站老板") || retryCount >= maxRetry {
                                  log(scene: .unknown, action: "⚠️ 重置流程从步骤1开始")
                                  retryCount  = 0
                                  currentStep = .step1_teleportToStation
                              }

                        case .retry(let reason):
                            log(scene: .unknown, action: "🔄 等待重试: \(reason)")
                        }
                    }
                  
              }

        // 主循环退出时同时取消子任务
        captureTask.cancel()
        previewTask.cancel()
    }
    
    func freshFrame() async -> CGImage? {
            for _ in 0..<3 {
                if let img = await frameBuffer.get() {
                    // autoreleasepool 包裹 cgImage 转换，避免 async 循环中 autorelease 对象累积
                    let cg: CGImage? = autoreleasepool {
                        img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }
                    if let cg { return cg }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return nil
        }
    
    func getRandomPosition(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        
        let randomIndex = Int.random(in: 0..<points.count)
        let selectedPoint = points[randomIndex]
        
        let randomOffsetX = Double.random(in: 0.0003...0.0008)
        let randomOffsetY = Double.random(in: 0.0003...0.0008)
        
        return CGPoint(
            x: selectedPoint.x + CGFloat(randomOffsetX),
            y: selectedPoint.y + CGFloat(randomOffsetY)
        )
    }
    
    
    
    // ── 🔧 调试：点击游戏内位置获取NPC坐标 ──────────────
    private func startClickMonitor() {
        // 检查辅助功能权限
           let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
           guard AXIsProcessTrustedWithOptions(options) else {
               print("⚠️ 需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 添加本App")
               return
           }
           
           let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
           
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else {
                        // event 本身不是 Optional，直接返回
                        return Unmanaged.passRetained(event)
                    }
                    let engine = Unmanaged<BotEngine>.fromOpaque(refcon).takeUnretainedValue()
                    engine.handleClickEvent(event)
                    return Unmanaged.passRetained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                print("⚠️ CGEvent tap 创建失败")
                return
            }
               
           let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
           CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
           CGEvent.tapEnable(tap: tap, enable: true)
           eventTap = tap
           print("✅ CGEvent tap 启动成功")
    }
    
    
    private func stopClickMonitor() {
        if let tap = eventTap {
               CGEvent.tapEnable(tap: tap, enable: false)
               eventTap = nil
           }
    }

    // 坐标录制：点击游戏窗口时同时输出比例坐标和像素坐标
    // 像素坐标用于 clickPx()，窗口拉伸缩小后不偏移
    private func handleClickEvent(_ event: CGEvent) {
        guard let fresh = WindowService.getWindowFrame(windowID: state.window.id) else { return }
        state.window.frame = fresh

        let loc     = event.location
        let offsetX = loc.x - fresh.minX
        let offsetY = loc.y - fresh.minY

        guard offsetX >= 0, offsetX <= fresh.width,
              offsetY >= 0, offsetY <= fresh.height else { return }

        let relX = offsetX / fresh.width
        let relY = offsetY / fresh.height

        // 像素坐标（推荐使用）：窗口拉伸缩小不影响
        print("📌 像素: CGPoint(x: \(Int(offsetX)), y: \(Int(offsetY)))  → clickPx(CGPoint(x: \(Int(offsetX)), y: \(Int(offsetY))))")
        // 比例坐标（旧接口兼容）：窗口大小改变后会偏移
        print("📌 比例: CGPoint(x: \(String(format: "%.4f", relX)), y: \(String(format: "%.4f", relY)))  → click(CGPoint(...))")
    }
    
    
    // MARK: - 辅助
    private func pressKey(_ keyCode: CGKeyCode) async {
        WindowService.activateApp(pid: state.window.pid)
        Thread.sleep(forTimeInterval: 0.06)
        WindowService.pressKey(keyCode)          // ✅ _ 参数，无标签
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: clickInterval) * 1_000_000_000))
    }


    private func click(_ relPoint: CGPoint, _ noiseRadius: Int = 0) async {
        WindowService.clickAt(window: &state.window, relX: relPoint.x, relY: relPoint.y, noiseRadius: noiseRadius)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: clickInterval) * 1_000_000_000))
    }

    /// 像素坐标点击：point.x/y 是以窗口左上角为原点的固定像素数
    /// 窗口移动后仍准确，窗口拉伸缩小不影响（游戏固定分辨率时）
    private func clickPx(_ point: CGPoint) async {
        WindowService.clickAtPx(window: &state.window, px: point.x, py: point.y)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: clickInterval) * 1_000_000_000))
    }
    

    private func humanDelay(_ range: ClosedRange<Double>? = nil) async {
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: range ?? reactionDelay) * 1_000_000_000))
    }

    private func log(scene: GameScene, action: String, detail: String = "") {
        let entry = LogEntry(timestamp: Date(), instanceIndex: state.id,
                             scene: scene, action: action, detail: detail)
        DispatchQueue.main.async { self.onLog?(entry) }
    }
    
    // ── 第一层：纯扫描，只返回匹配元素，不做任何操作 ──────────────
    /// 扫描画面全部文字，按关键词优先级返回首个命中的 TextElement。
    /// 调用方自行决定是否点击、记录日志或做其他处理。
    private func scanKeywords(_ keywords: [String],
                              in cgImage: CGImage) async -> TextElement? {
        let elements = await detector.scanAllText(cgImage: cgImage)
        for kw in keywords {
            if let hit = elements.first(where: { $0.text.contains(kw) }) {
                return hit
            }
        }
        return nil
    }

    // ── 第二层：纯点击，根据已有元素点击其中心 ───────────────────
    /// 点击指定 TextElement 的中心位置，并写入日志。
    /// OCR 专用点击：传入 TextElement，用 clickAtOCR 精准换算实际窗口尺寸，不走 CoordBase
     private func clickElement(_ element: TextElement, label: String = "OCR") async {
         let cx = element.normX + element.normW / 2.0
         let cy = element.normY + element.normH / 2.0
         log(scene: .unknown,
             action: "🔍 \(label) 命中「\(element.text)」",
             detail: String(format: "位置(%.4f, %.4f)", cx, cy))
         // 传入 TextElement 的源图尺寸（px），确保 Retina 屏幕下坐标换算准确
         WindowService.clickAtOCR(window: &state.window, normX: cx, normY: cy,
                                   srcW: element.srcW, srcH: element.srcH)
         try? await Task.sleep(nanoseconds: UInt64(Double.random(in: clickInterval) * 1_000_000_000))
     }


    // ── 第三层：组合便捷方法（扫描 + 点击二合一）────────────────
    /// 扫描关键词后**立即点击**，适合不需要额外判断的简单场景。
    @discardableResult
    private func scanAndClick(_ keywords: [String],
                              in cgImage: CGImage,
                              label: String = "OCR") async -> TextElement? {
        guard let element = await scanKeywords(keywords, in: cgImage) else { return nil }
        await clickElement(element, label: label)
        return element
    }
    
}

// MARK: - FrameBuffer（线程安全的帧共享）
// actor 保证多个 Task 并发读写时不产生数据竞争
actor FrameBuffer {
    private var latest: NSImage? = nil

    func set(_ image: NSImage) {
        latest = image
    }

    func get() -> NSImage? {
        return latest
    }
}

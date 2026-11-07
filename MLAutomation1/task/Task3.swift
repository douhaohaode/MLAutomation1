//
//  Task3.swift
//  MLAutomation1
//
//  云游道人购买。
//
//  启动后一直扫描，不按整点限次数。模板对上身体就点，认出「购买宝贝」再点选项。
//  购买窗出现后：左上格 → 确定，重复 4 次，然后右键点「确定」右侧窗内空白处关掉窗口，
//  接着继续扫描。
//

import Foundation
import AppKit

class WanderingTaoistTask {

    // MARK: - 区域和已标定的点击点（比例坐标，窗口左上角为原点）
    struct Regions {
        /// 站定后道人身体出现的范围。按 1024×771 全图标定，身体中心约 (0.43, 0.51)。
        static let npc = CGRect(x: 0.22, y: 0.28, width: 0.40, height: 0.40)
        /// 对话框选项「购买宝贝」
        static let dialog = CGRect(x: 0.14, y: 0.46, width: 0.36, height: 0.16)
        /// 购买窗里的「单价 / 银两」，避开右侧任务栏和底部聊天
        static let shop = CGRect(x: 0.32, y: 0.50, width: 0.30, height: 0.20)
    }

    struct Coords {
        /// 对话框「购买宝贝」
        static let dialogBuyItem = CGPoint(x: 0.2307, y: 0.5254)
        /// 「确定」
        static let confirmBtn = CGPoint(x: 0.4809, y: 0.7092)
        /// 「确定」右侧、仍在购买窗里的空白。右键关闭窗口。
        static let closeBlank = CGPoint(x: 0.5800, y: 0.7092)
    }

    private let templateName = "npc_yunyou_daoren"
    /// 全图里第二名大约 0.42，道人本人大约 0.77。
    private let minScore: Double = 0.55
    private let maxNPCClicks = 3
    private let maxDialogClicks = 2
    /// 购买窗打开后，左上格和确定重复的次数。
    private let buyRepeats = 4

    private enum Phase {
        case waitArm
        case seek
    }

    private let state: InstanceState
    private let frameBuffer: FrameBuffer
    private let detector: SceneDetector
    private let onLog: (LogEntry) -> Void

    var shouldStop: (() -> Bool) = { false }

    private let phaseLock = NSLock()
    private var _phase: Phase = .waitArm
    private var phase: Phase {
        get { phaseLock.lock(); defer { phaseLock.unlock() }; return _phase }
        set { phaseLock.lock(); _phase = newValue; phaseLock.unlock() }
    }

    /// 截图循环在搜索和点购买的时候把间隔降到 50ms。
    var needsFastFrames: Bool { phase == .seek }

    private var seenSerial: UInt64 = 0
    private var didLogMissingTemplate = false

    init(state: InstanceState,
         frameBuffer: FrameBuffer,
         detector: SceneDetector,
         onLog: @escaping (LogEntry) -> Void) {
        self.state = state
        self.frameBuffer = frameBuffer
        self.detector = detector
        self.onLog = onLog
    }

    func reset() {
        phase = .waitArm
        seenSerial = 0
        didLogMissingTemplate = false
    }

    // MARK: - 入口（启动后一直扫，直到停止）

    func runOnce() async {
        if shouldStop() { return }
        phase = .seek
        await scan()
        phase = .waitArm
    }

    // MARK: - 持续扫描

    private func scan() async {
        log("开始持续寻找云游道人")
        var npcClicks = 0
        var dialogClicks = 0
        var lastNPCClick = Date.distantPast
        var lastDialogClick = Date.distantPast
        var lastScoreLog = Date.distantPast

        while !shouldStop() {
            guard let cg = await nextFrame() else { continue }

            // 点过「购买宝贝」之后才认购买窗，避免地图上别的界面被当成商店。
            if dialogClicks > 0, await contains(cg, Regions.shop, ["单价", "银两"]) {
                await repeatBuyAndClose()
                npcClicks = 0
                dialogClicks = 0
                lastNPCClick = .distantPast
                lastDialogClick = .distantPast
                log("购买窗已处理，继续扫描")
                continue
            }

            // 还没点到道人之前不做文字识别，把时间留给模板匹配。
            if npcClicks > 0, await contains(cg, Regions.dialog, ["购买宝贝"]) {
                if dialogClicks < maxDialogClicks,
                   Date().timeIntervalSince(lastDialogClick) >= 0.45 {
                    click(Coords.dialogBuyItem)
                    dialogClicks += 1
                    lastDialogClick = Date()
                    log("检测到「购买宝贝」，点击选项")
                }
                continue
            }

            guard let hit = detector.findTemplate(named: templateName, in: cg, roi: Regions.npc) else {
                if !didLogMissingTemplate {
                    didLogMissingTemplate = true
                    log("没有云游道人模板，或搜索区域无效")
                }
                continue
            }

            if hit.score < minScore {
                if npcClicks > 0 && dialogClicks == 0 {
                    npcClicks = 0
                }
                if Date().timeIntervalSince(lastScoreLog) > 2 {
                    lastScoreLog = Date()
                    log(String(format: "未看到道人，最高相似度 %.2f", hit.score))
                }
                continue
            }

            if npcClicks < maxNPCClicks,
               Date().timeIntervalSince(lastNPCClick) >= 0.8 {
                click(hit.center)
                npcClicks += 1
                lastNPCClick = Date()
                log(String(format: "点到道人（%.2f）第 %d 次 (%.3f, %.3f)",
                           hit.score, npcClicks, hit.center.x, hit.center.y))
            }
        }

    }

    /// 先用 ShopFirstSlot 看第一格是空是有，再左上格和确定重复 4 次，然后右键关掉购买窗。
    private func repeatBuyAndClose() async {
        if let cg = await nextFrame(timeout: 0.3) {
            let slot = ShopFirstSlot.inspect(cg)
            log(String(format: "第一格%@，中心 (%.4f, %.4f)，亮度差 %.0f",
                       slot.empty ? "是空的" : "有物品",
                       slot.center.x, slot.center.y, slot.spread))
        }
        for i in 1...buyRepeats {
            if shouldStop() { return }
            click(ShopFirstSlot.center)
            try? await Task.sleep(nanoseconds: 60_000_000)
            if shouldStop() { return }
            click(Coords.confirmBtn)
            log("购买 \(i)/\(buyRepeats)：左上格和确定")
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        var attempts = 0
        while !shouldStop() && attempts < 3 {
            rightClick(Coords.closeBlank)
            attempts += 1
            log(attempts == 1 ? "右键关闭购买窗" : "购买窗还在，再右键一次")
            guard let cg = await nextFrame(timeout: 0.4) else { break }
            if await contains(cg, Regions.shop, ["单价", "银两"]) == false { break }
        }
    }

    // MARK: - 帧和文字

    private func nextFrame(timeout: TimeInterval = 0.25) async -> CGImage? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return nil }
            if let (img, serial) = await frameBuffer.getIfNewer(than: seenSerial) {
                seenSerial = serial
                if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return cg
                }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func contains(_ image: CGImage, _ region: CGRect, _ keywords: [String]) async -> Bool {
        let elements = await detector.scanTextInRegion(cgImage: image, region: region)
        let text = elements.map(\.text).joined()
        return keywords.contains { text.contains($0) }
    }

    private func click(_ relPoint: CGPoint) {
        WindowService.clickAt(window: &state.window,
                              relX: relPoint.x,
                              relY: relPoint.y,
                              noiseRadius: 0)
    }

    private func rightClick(_ relPoint: CGPoint) {
        WindowService.rightClickAt(window: &state.window,
                                   relX: relPoint.x,
                                   relY: relPoint.y,
                                   noiseRadius: 0)
    }

    private func log(_ msg: String) {
        let entry = LogEntry(timestamp: Date(),
                             instanceIndex: state.id,
                             scene: .unknown,
                             action: msg,
                             detail: "")
        onLog(entry)
        print("[云游道人] \(msg)")
    }
}

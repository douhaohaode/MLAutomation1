//
//  Task3.swift
//  MLAutomation1
//
//  云游道人购买流程
//
//  流程：
//  1. 点击 NPC 云游道人
//  2. 等待弹框出现「购买宝物」→ 点击固定坐标
//  3. 进入抢购循环（直到外部停止）：
//     无限重复：点击第一个商品 → 立即点击确定
//     （商店打开后无需重新点 NPC，直接无限抢购）
//

import Foundation
import AppKit

class WanderingTaoistTask {
    private let state: InstanceState
    // MARK: - 依赖
    private let frameBuffer: FrameBuffer
    private let detector:    SceneDetector
    private let onLog:       (LogEntry) -> Void

    // MARK: - ⚠️ 坐标（用鼠标监控工具标定后填入）
    struct Coords {
        ///长安 真人坐标  人点坐标 478 130
        /// 云游道人 NPC 位置
        static let npc           = CGPoint(x: 0.4725, y: 0.4446)
        /// 对话框「购买宝物」选项位置
        static let dialogBuyItem = CGPoint(x: 0.2307, y: 0.5254)
        /// 商店第一个商品位置
        static let shopFirstItem = CGPoint(x: 0.3871, y: 0.2974)
        /// 确认购买按钮位置
        static let confirmBtn    = CGPoint(x: 0.4809, y: 0.7092)
    }
    

    private let dialogKeyword = "购买宝贝"
    private let waitTimeout: Double = 8.0

    // 抢购间隔：尽量快，只加极短延迟防止游戏丢包
    // 调小可以更快，调大更稳定，根据实际情况调整
    //private let rushInterval: TimeInterval = 0.05
    private let rushInterval: TimeInterval = 0.5

    // MARK: - Init
    init(state: InstanceState,
         frameBuffer: FrameBuffer,
         detector:    SceneDetector,
         onLog:       @escaping (LogEntry) -> Void) {
        self.state = state
        self.frameBuffer = frameBuffer
        self.detector    = detector
        self.onLog       = onLog
    }

    // MARK: - 主流程
    // 调用后会一直抢购，直到外部调用 stop() 停止 BotEngine
    func run() async -> Bool {

        // ── Step 1. 点击 NPC ──────────────────────────────────
        log("👆 点击云游道人 NPC")
        await click(Coords.npc)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await click(Coords.npc)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await click(Coords.npc)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // ── Step 2. 等待「购买宝物」弹框 ─────────────────────
        log("⏳ 等待「\(dialogKeyword)」弹框...")
//        guard await waitForKeyword(dialogKeyword, timeout: waitTimeout) else {
//            log("❌ 超时：未检测到「\(dialogKeyword)」，流程结束")
//            return false
//        }
//
//        click(Coords.npc)
//        Thread.sleep(forTimeInterval: 1.0)
        
        await click(Coords.dialogBuyItem)
        // 等商店界面打开
        try? await Task.sleep(nanoseconds: 150_000_000)

        // ── Step 3. 无限抢购循环 ──────────────────────────────
        log("🚀 进入抢购循环：商品→确定→商品→确定...")
        var count = 0
        while count < 5 {
            await clickFast(Coords.shopFirstItem)
            try? await Task.sleep(nanoseconds: 150_000_000)
            await clickFast(Coords.confirmBtn)
            count += 1
            log("⚡ 已抢购 \(count) 次")
            try? await Task.sleep(nanoseconds: UInt64(rushInterval * 1_000_000_000))
        }
        return true
    }

    // MARK: - 等待关键词（轮询 OCR）
    private func waitForKeyword(_ keyword: String, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let img = await frameBuffer.get(),
               let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let elements = await detector.scanAllText(cgImage: cg)
                if elements.map({ $0.text }).joined(separator: " ").contains(keyword) {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - 辅助
    /// 普通点击（带随机噪声，用于非抢购步骤）
    private func click(_ relPoint: CGPoint) async {
        // 每次点击前重新获取窗口最新位置
        WindowService.clickAt(window: &state.window,
                                      relX: relPoint.x,
                                      relY: relPoint.y,
                                      noiseRadius: 0)
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    /// 快速点击（无延迟，用于抢购循环）
    private func clickFast(_ relPoint: CGPoint) async {
        WindowService.clickAt(window: &state.window,
                                      relX: relPoint.x,
                                      relY: relPoint.y,
                                      noiseRadius: 0)
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    private func log(_ msg: String) {
        let entry = LogEntry(timestamp: Date(), instanceIndex: state.window.instanceIndex,
                             scene: .unknown, action: msg, detail: "")
        onLog(entry)
        print("[云游道人] \(msg)")
    }
}


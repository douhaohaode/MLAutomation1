//
//  FengyaoTask.swift
//  MLAutomation1
//
//  封妖任务完整自动化流程
//
//  设计原则：
//  ① 每帧一次性扫描，同时检测「远古」「对话」「战斗」三个关键词，无内部轮询循环
//  ② 优先级处理（游戏画面可能同时出现多种情况）：
//     * 见到「对话」→ 立即点「对话」（NPC 已被我点中，弹出对话框）→ 失效 15 分钟
//     * 见到「战斗」→ 立即点「战斗」（别人抢先，需点按钮退出）→ 失效  3 分钟
//     * 只见NPC     → 点击 NPC，记录 pendingNPCClick，本帧结束
//     * 无有效 NPC  → 静默返回，不点击屏幕
//  ③ 点击 NPC 后通过 pendingNPCClick 跨帧追踪结果：
//     - 下一帧若出现「对话」/「战斗」→ 确认来源，执行点击，设置失效期
//     - 超过 popupTimeout 秒无响应   → 视为玩家，失效  1 分钟
//  ④ 全程使用 clickPx 精确点击，日志输出物理像素与逻辑点坐标，方便比对校准
//
//  ┌─── 如何验证点击位置是否准确 ──────────────────────────────────────────────┐
//  │  日志格式：「文字」ocr物理px(cx,cy) → clickPx(逻辑pt_x, 逻辑pt_y)          │
//  │  · ocr物理px : Vision OCR 在截图中识别到的像素中心点                       │
//  │  · clickPx   : 发出鼠标事件的坐标，以窗口左上角为原点的逻辑点               │
//  │                逻辑点 = 物理像素 ÷ Retina倍率（通常 ÷2）                   │
//  │  · 若点击偏移：游戏内开坐标显示，与 clickPx 对比确认偏差方向               │
//  └────────────────────────────────────────────────────────────────────────────┘

import Foundation
import AppKit

// MARK: - 封妖任务
class FengyaoTask {

    // MARK: - 区域配置（归一化坐标 0~1）
    struct Regions {
        /// 统一扫描区域：NPC名字、对话/战斗按钮均在此范围内
        //static let npcScanROI = CGRect(x: 0.01, y: 0.00, width: 0.90, height: 0.90)
        static let npcScanROI = CGRect(x: 0.27, y: 0.2, width: 0.38, height: 0.48)
    }

    // MARK: - 关键词
    let npcKeyword    = "远古"   // OCR 找到后视为目标 NPC
    let dialogKeyword = "开打"   // 弹框：我点中了 NPC，点此按钮
    let battleKeyword = "请勿打扰"   // 弹框：别人抢先，点此退出
    let errorKeyword = "改天来找你"   // 点错了
    // MARK: - 参数
    /// 点击 NPC 时相对名字文字中心向上偏移的像素数（负值=向上）
    let npcClickYOffset: Int = -60
    /// 对话框选项的固定像素坐标（以窗口左上角为原点）。
    /// 不依赖 OCR 坐标，避免每帧识别坐标微小不同导致点击偏移。
    /// 按钮在对话框中的相对位置固定，可直接使用固定坐标。
    /// 调整方式：运行时开坐标显示，点击应出现对话框时手动记录按钮中心坐标填入这里
    let dialogFixedPx = CGPoint(x: 264, y: 449)   // 「少说废话」按钮固定点击坐标
    let errorFixedPx  = CGPoint(x: 264, y: 501)   // 「我今天没带钱」按钮固定点击坐标
    let battleFixedPx = CGPoint(x: 264, y: 403)   // 「我正在战斗中」按钮固定点击坐标
    /// 点击 NPC 后等待弹框的最长时间（秒）
    /// 抢怪场景不宜过长，3 秒内无弹框则视为玩家/抢不到，立即放弃换下一个
    let popupTimeout:   TimeInterval = 1
    /// 重复点击 NPC 的间隔（秒）— 等满此时间无弹框才重试，避免快速连点
    let retryInterval:  TimeInterval = 0.2
    /// 最多重复点击次数（首次 + retry 次，共最多 1+3=4 次）
    let maxRetries:     Int          = 1
    /// 坐标去重容差（归一化，两点距离小于此值视为同一位置）
    let tolerance:      Double       = 0.03

    // MARK: - 分级过期时长
    let expiryDialog:  TimeInterval = 15 * 60   // 对话成功 → 15 分钟
    let expiryBattle:  TimeInterval =  3 * 60   // 被别人抢 →  3 分钟
    let expiryTimeout: TimeInterval =  1 * 60   // 超时/玩家 →  1 分钟

    // MARK: - 依赖
    private let state:      InstanceState
    private let detector:   SceneDetector
    private let onLog:      (String) -> Void

    /// 由 BotEngine 注入：返回 true 时中止当前操作
    var shouldStop: (() -> Bool) = { false }

    // MARK: - 失效坐标（带过期时间和原因）
    private struct IgnoreEntry {
        let point:  CGPoint
        let expiry: Date
        let reason: String
    }
    private var ignoreList: [IgnoreEntry] = []

    /// 上一帧点击的 NPC 归一化坐标 + 点击时间
    /// 用于跨帧关联弹框结果，不再做内部轮询
    private struct PendingNPC {
        let point:       CGPoint   // NPC 归一化坐标（用于失效列表）
        let clickedAt:   Date      // 首次点击时间（用于整体超时判断）
        var lastClickAt: Date      // 最近一次点击时间（用于重试间隔）
        var clickCount:  Int       // 已点击次数
    }
    private var pendingNPCClick: PendingNPC? = nil

    // MARK: - Init
    init(state:    InstanceState,
         detector: SceneDetector,
         onLog:    @escaping (String) -> Void) {
        self.state    = state
        self.detector = detector
        self.onLog    = onLog
    }
    

    // MARK: - 单帧入口（BotEngine 主循环每帧调用）
    @discardableResult
    func runOnce(cgImage: CGImage) async -> Bool {

        let now = Date()

        // ── 步骤 0a：清理已过期的失效坐标 ─────────────────────────────
        let before = ignoreList.count
        ignoreList.removeAll { now >= $0.expiry }
        let removed = before - ignoreList.count
        if removed > 0 {
            log("🔓 \(removed) 个失效坐标已过期恢复（剩余 \(ignoreList.count) 个）")
        }

        // ── 步骤 0b：检查 pendingNPCClick 整体是否超时 ────────────────
        // 所有重试机会已用尽（首次 + maxRetries 次）且最后一次等待也超时，才视为玩家
        if let pending = pendingNPCClick {
            let totalTimeout = popupTimeout * Double(pending.clickCount + 1)
            if now.timeIntervalSince(pending.clickedAt) > totalTimeout {
                log("⏱ 共点击 \(pending.clickCount) 次均无弹框，视为玩家 → 失效 \(Int(expiryTimeout / 60)) 分钟")
                addIgnore(pending.point, expiry: expiryTimeout, reason: "超时/玩家")
                pendingNPCClick = nil
                log("📝 当前失效列表共 \(ignoreList.count) 个坐标")
            }
        }

        if shouldStop() { return false }

        // ── 步骤 1：一次扫描，同时获取三种关键词 ──────────────────────
        let elements = await detector.scanTextInRegion(cgImage: cgImage,
                                                       region: Regions.npcScanROI)

        let npcElements   = elements.filter { $0.text.contains(npcKeyword) }
        let dialogElement = elements.first  { $0.text.contains(dialogKeyword) }
        let battleElement = elements.first  { $0.text.contains(battleKeyword) }
        let errorElement = elements.first  { $0.text.contains(errorKeyword) }

        
        // 有效 NPC：不在失效列表中
        let validNPCs = npcElements.filter { !isIgnored(centerOf($0)) }

        // 当前帧「关联 NPC」：优先用当帧可见的有效 NPC，
        // 若 NPC 已移出视野但 pending 仍有效，用 pending 记录的坐标
        let associatedNPCPoint: CGPoint? = validNPCs.first.map { centerOf($0) }
                                        ?? pendingNPCClick?.point

        // ── 优先级 ①：检测到对话/错误弹框 → 立即点击固定坐标 ──────────────
        if let _ = dialogElement {
            log("💬 检测到「\(dialogKeyword)」，使用固定坐标 px(\(Int(dialogFixedPx.x)),\(Int(dialogFixedPx.y)))")
            WindowService.clickAtPx(window: &state.window, px: dialogFixedPx.x, py: dialogFixedPx.y)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let npc = associatedNPCPoint {
                addIgnore(npc, expiry: expiryDialog, reason: "对话成功")
                log("✅ 封妖成功，NPC 失效 \(Int(expiryDialog / 60)) 分钟  |  失效列表 \(ignoreList.count) 个")
            }
            pendingNPCClick = nil
            return true
        }
        if let _ = errorElement {
            log("💬 检测到「\(errorKeyword)」，使用固定坐标 px(\(Int(errorFixedPx.x)),\(Int(errorFixedPx.y)))")
            WindowService.clickAtPx(window: &state.window, px: errorFixedPx.x, py: errorFixedPx.y)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let npc = associatedNPCPoint {
                addIgnore(npc, expiry: expiryDialog, reason: "点错了")
                log("✅ 封妖成功，NPC 失效 \(Int(expiryDialog / 60)) 分钟  |  失效列表 \(ignoreList.count) 个")
            }
            pendingNPCClick = nil
            return true
        }
        

        // ── 优先级 ②：检测到「战斗」→ 立即点击 ────────────────────────
        if let _ = battleElement {
            log("⚔️ 检测到「\(battleKeyword)」，使用固定坐标 px(\(Int(battleFixedPx.x)),\(Int(battleFixedPx.y)))")
            WindowService.clickAtPx(window: &state.window, px: battleFixedPx.x, py: battleFixedPx.y)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let npc = associatedNPCPoint {
                addIgnore(npc, expiry: expiryBattle, reason: "被别人抢先")
                log("📝 NPC 失效 \(Int(expiryBattle / 60)) 分钟  |  失效列表 \(ignoreList.count) 个")
            }
            pendingNPCClick = nil
            return true
        }

        // ── 优先级 ③：只发现 NPC → 点击一次，记录 pendingNPCClick ────
        guard let npcTarget = validNPCs.first else {
            // NPC 不可见：若 pending 仍在（人物走路途中 NPC 移出视野），继续等待
            if pendingNPCClick != nil { return true }
            return false
        }

        let npcCenter = centerOf(npcTarget)

        // ── 有 pending 未完成 → 不点新 NPC，只在同位置重试 ────────────
        // ⚠️ 核心规则：只要 pendingNPCClick 存在（未超时），就绝不点击任何新 NPC。
        // 原因：点击 NPC 后人物开始移动，画面滚动导致所有 NPC 的归一化坐标全部改变，
        //       若此时继续匹配 dist < tolerance 会失败，fall-through 会点到别的 NPC 触发乱点。
        if let pending = pendingNPCClick {
            let dist = hypot(pending.point.x - npcCenter.x,
                             pending.point.y - npcCenter.y)
            // 人物走近后画面滚动，用较大容差（0.15）判断是否仍是同一个 NPC
            if dist < 0.15 &&
               pending.clickCount < maxRetries &&
               now.timeIntervalSince(pending.lastClickAt) >= retryInterval {
                log("🔁 重试点击(\(pending.clickCount + 1)/\(maxRetries)): \(pxDesc(npcTarget, keyword: npcKeyword, yOffset: npcClickYOffset))")
                clickPx(npcTarget, keyword: npcKeyword, yOffset: npcClickYOffset, noiseRadius: 0)
                try? await Task.sleep(nanoseconds: 200_000_000)
                pendingNPCClick?.lastClickAt = now
                pendingNPCClick?.clickCount += 1
            }
            // 不论 NPC 是否移动超出容差，都不点新 NPC，等待弹框或超时
            return true
        }

        // 新 NPC（或 pending 已清空）→ 首次点击
        log("🎯 [只有NPC] 首次点击(1/\(maxRetries + 1)): \(pxDesc(npcTarget, keyword: npcKeyword, yOffset: npcClickYOffset))")
        clickPx(npcTarget, keyword: npcKeyword, yOffset: npcClickYOffset, noiseRadius: 0)
        pendingNPCClick = PendingNPC(point:       npcCenter,
                                     clickedAt:   now,
                                     lastClickAt: now,
                                     clickCount:  1)

        return true
    }

    // MARK: - 手动清空失效列表（切换地图时调用）
    func resetIgnoreList() {
        ignoreList.removeAll()
        pendingNPCClick = nil
        log("🔄 失效坐标列表及 pending 状态已手动清空")
    }

    // MARK: - 工具方法

    private func centerOf(_ el: TextElement) -> CGPoint {
        CGPoint(x: el.normX + el.normW / 2, y: el.normY + el.normH / 2)
    }

    private func isIgnored(_ point: CGPoint) -> Bool {
        let now = Date()
        return ignoreList.contains { entry in
            guard now < entry.expiry else { return false }
            let dx = entry.point.x - point.x
            let dy = entry.point.y - point.y
            return sqrt(dx * dx + dy * dy) < tolerance
        }
    }

    private func addIgnore(_ point: CGPoint, expiry: TimeInterval, reason: String) {
        ignoreList.append(IgnoreEntry(
            point:  point,
            expiry: Date().addingTimeInterval(expiry),
            reason: reason
        ))
    }

    /// 像素坐标点击（以窗口左上角为原点的逻辑点）
    /// - keyword:  若传入，则按关键词在文字中的字符位置估算点击 x
    /// - yOffset:  在 OCR 识别到的中心 Y 基础上叠加的物理像素偏移（负值=向上），用于点击名字上方的角色精灵
    private func clickPx(_ element: TextElement, keyword: String? = nil,
                         yOffset: Int = 0, noiseRadius: Int = 0) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let (rawCx, rawCyBase) = keywordPixelCenter(in: element, keyword: keyword)
        let rawCy = rawCyBase + yOffset
        let px = CGFloat(rawCx) / scale
        let py = CGFloat(rawCy) / scale
        print("[FengyaoTask 点击诊断] scale=\(scale)  rawCy=\(rawCyBase)  yOffset=\(yOffset)  finalPy=\(Int(py))  预期屏幕Y=\(Int(state.window.frame.minY + py))")
        WindowService.clickAtPx(window: &state.window,
                                 px: px, py: py,
                                 noiseRadius: noiseRadius)
    }

    /// 生成可读的像素坐标描述，用于日志核查点击位置是否正确
    /// 格式：「文字[关键词]」ocr物理px(cx,cy) yOffset=N → clickPx(逻辑pt_x, 逻辑pt_y)
    private func pxDesc(_ el: TextElement, keyword: String? = nil, yOffset: Int = 0) -> String {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let (rawCx, rawCyBase) = keywordPixelCenter(in: el, keyword: keyword)
        let rawCy = rawCyBase + yOffset
        let px = Int(CGFloat(rawCx) / scale)
        let py = Int(CGFloat(rawCy) / scale)
        let label = keyword.map { "「\(el.text)」→ 关键词[\($0)]" } ?? "「\(el.text)」"
        return "\(label) ocr物理px(\(rawCx),\(rawCyBase)) yOffset=\(yOffset) → clickPx(\(px),\(py))"
    }
    
    

    /// 计算关键词在文字包围盒内的物理像素中心点
    ///
    /// 原理：CJK 字符等宽，每个字符占 `w / totalCount` 像素。
    /// 例：「都好好远古」共 5 字，「远古」从第 3 位开始，宽 2 字
    ///     → center_x = x + (3 + 2/2) / 5 * w = x + 0.8 * w
    ///
    /// 若 keyword 为 nil 或找不到，退回整体中心点。
    private func keywordPixelCenter(in el: TextElement, keyword: String?) -> (cx: Int, cy: Int) {
        let cy = el.y + el.h / 2
        guard let kw = keyword,
              !kw.isEmpty,
              let range = el.text.range(of: kw) else {
            return (el.x + el.w / 2, cy)
        }
        let totalChars = el.text.count
        guard totalChars > 0 else { return (el.x + el.w / 2, cy) }
        let startOffset = el.text.distance(from: el.text.startIndex, to: range.lowerBound)
        let ratio = (Double(startOffset) + Double(kw.count) / 2.0) / Double(totalChars)
        let cx = el.x + Int(Double(el.w) * ratio)
        return (cx, cy)
    }

    private func log(_ msg: String) {
        print("[FengyaoTask] \(msg)")
        onLog(msg)
    }
}

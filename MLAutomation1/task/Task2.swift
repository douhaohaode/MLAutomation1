//
//  QuestFlow.swift
//  MLAutomation
//
//  领取鬼任务完整自动化流程
//

import Foundation
import AppKit


// MARK: - 步骤枚举
enum QuestStep {
    case step1_teleportToStation   // 1. 传送到驿站
    case step2_stationToDaTang     // 2. 驿站传送到大唐国境
    case step3_daTangToDiFu        // 3. 大唐国境到地府
    case step4_acceptQuest         // 4. 地府领取任务
    case step5_goToQuestTarget     // 5. 传送到任务地点并找寻目标
    case step6_completeQuest       // 6. 任务结束

    var description: String {
        switch self {
        case .step1_teleportToStation: return "1. 传送到驿站"
        case .step2_stationToDaTang:   return "2. 驿站→大唐国境"
        case .step3_daTangToDiFu:      return "3. 大唐国境→地府"
        case .step4_acceptQuest:       return "4. 地府领取任务"
        case .step5_goToQuestTarget:   return "5. 前往任务目标"
        case .step6_completeQuest:     return "6. 完成任务"
        }
    }

    var next: QuestStep {
        switch self {
        case .step1_teleportToStation: return .step2_stationToDaTang
        case .step2_stationToDaTang:   return .step3_daTangToDiFu
        case .step3_daTangToDiFu:      return .step4_acceptQuest
        case .step4_acceptQuest:       return .step5_goToQuestTarget
        case .step5_goToQuestTarget:   return .step6_completeQuest
        case .step6_completeQuest:     return .step1_teleportToStation  // 循环
        }
    }
}

// MARK: - 步骤结果
enum StepResult {
    case success
    case failure(reason: String)
    case retry(reason: String)   // 需要重试但不算失败（如等待中）
}



struct TaskaParameter{
    // 传送点位
        //NPC 1 号CGPoint(x: 0.0620, y: 0.9127)
        static let npcOne   = CGPoint(x:  0.0620, y: 0.9127)
        
        // 行囊 长安城旗点
        static let xingNangCN   = CGPoint(x: 0.0628, y: 0.4691)
        
        // 长安城驿站
        static let changAnYZ   = CGPoint(x: 0.4942, y: 0.6363)

        // 长安城大唐国境
        static let changAnDTGJ  = CGPoint(x: 0.2416, y: 0.6717)

        // 行囊 大唐境外城旗点
        static let xingNangDTGJ  = CGPoint(x: 0.1153, y: 0.4826)
        
        // 大唐境外城 中间位置
        static let daTangGuoJingGLZ = CGPoint(x: 0.5680, y: 0.5165)
        
        // 大唐境外城 五庄观位置
        static let daTangGuoJingWZG =  CGPoint(x: 0.8090, y: 0.4888)

        // 行囊 傲来旗点
        static let xingNangAL  = CGPoint(x: 0.1607, y: 0.4584)
        
        // 傲来女儿村
        static let aolaiNE  = CGPoint(x: 0.3185, y: 0.3562)
        
        //飞行符
        static let fXF  = CGPoint(x: 0.0602, y: 0.5089)
        // 眼
        static let yan  =  CGPoint(x: 0.1234, y: 0.5213)
        
         // 驿站 是的，我要去
        static let yizhan1  = CGPoint(x: 0.2333, y: 0.5093)

         // 大唐国境地图 地府点
        static let guojingDiFu  = CGPoint(x: 0.3232, y: 0.3203)
        
        // 进地府点位
        static let guojingjinDiFu  = CGPoint(x: 0.4525, y: 0.1880)

        // 地府小地图钟馗
        static let diFuDiTuzhongkui = CGPoint(x: 0.3756, y: 0.5305)
        
        // 地府钟馗
        static let diFuZhongkui = CGPoint(x: 0.3574, y: 0.4441)
        
        //钟馗，好的 我帮你
        static let zhongkuiDuiHua =  CGPoint(x: 0.2374, y: 0.5512)
    
        // 自动寻路
        static let automatedTask = CGPoint(x: 0.8737, y: 0.3272)
    
        // 开始
        static let taskStart  = CGPoint(x: 0.2003, y: 0.4815)
    

}



// MARK: - QuestFlow
class QuestFlow {

    private let state:    InstanceState
    private let detector: SceneDetector
    private var onLog:    ((String) -> Void)?
    
    private let reactionDelay: ClosedRange<Double> = 0.35...0.85

    private let freshFrame: () async -> CGImage?
    
    
    var shouldStop: (() -> Bool) = { false }
    
    private var step2F9 = false

    // 最大重试次数
    private let maxRetry = 3

    init(state: InstanceState,
         detector: SceneDetector,
         freshFrame: @escaping () async -> CGImage?,
         onLog: ((String) -> Void)? = nil) {
        self.state    = state
        self.detector = detector
        self.freshFrame = freshFrame
        self.onLog    = onLog
    }
    

    // MARK: - 执行单个步骤（供 BotEngine 调用）
    func run(step: QuestStep, cgImage: CGImage) async -> StepResult {
        print("▶️ \(step.description)")
        switch step {
        case .step1_teleportToStation: return await step1_teleportToStation(cgImage)
        case .step2_stationToDaTang:   return await step2_stationToDaTang(cgImage)
        case .step3_daTangToDiFu:      return await step3_daTangToDiFu(cgImage)
        case .step4_acceptQuest:       return await step4_acceptQuest(cgImage)
        case .step5_goToQuestTarget:   return await step5_goToQuestTarget(cgImage)
        case .step6_completeQuest:     return await step6_completeQuest(cgImage)
        }
    }
    
    private func cleanFalg(){
        step2F9 = false;
    }

    // MARK: - ── 步骤1：传送到驿站 ──────────────────────────
    /// 小任务：
    private func step1_teleportToStation(_ cgImage: CGImage) async -> StepResult {
     
     
        // 如果在战斗中，等待
        let coordinate = await detector.ocrRegion(cgImage, region: UIRegions.fightPx)
        if coordinate.contains("回合") {
            return .retry(reason: "战斗中，等待回合结束")
        }

        if  step2F9 == false{
         await pressKey(KeyCode.f9)
         await humanDelay(  0.3...0.8)
            step2F9 = true
        }
         // 1-2. Command+E 打开行囊
        // Cmd + E 打开道具行囊
        WindowService.pressKeys(KeyCode.e, modifiers: .maskCommand, window: state.window)
         // 延迟0.3到0.8秒
        await humanDelay(0.3...0.8)

        await rightClick(TaskaParameter.xingNangCN,noiseRadius: 0)
        // 延迟0.3到0.8秒
        await humanDelay(0.3...0.8)
       // 1-4. 右键点击驿站传送点
        await click(TaskaParameter.changAnYZ,noiseRadius: 0)
        // 延迟0.3到0.8秒
        await humanDelay(0.3...0.8)
     
        // 1-6. 等待地图切换到长安城（最多 6 秒）
           let arrived = await waitForMap("长安城", timeout: 6.0)
           guard arrived else {
               cleanFalg()
               return .retry(reason: "传送超时，未到达长安城")
           }

           WindowService.pressKeys(KeyCode.e, modifiers: .maskCommand, window: state.window)
           await humanDelay(0.1...0.3)
           cleanFalg();
           return .success
    }

    // MARK: - ── 步骤2：驿站传送到大唐国境 ────────────────────
    /// 小任务：
    private func step2_stationToDaTang(_ cgImage: CGImage) async -> StepResult {
        
        // 已在大唐国境直接跳过
            let mapName = await detector.ocrRegion(cgImage, region: UIRegions.locationPx)
            if mapName.contains("大唐国境") {
                log("✅ 已在大唐国境，跳过")
                return .success
            }

        await humanDelay(0.3...0.8)

        // ── 模板匹配找驿站老板 ──
        if let npcPoint = detector.findNPCByTemplate(in: cgImage) {
            log("🎯 模板匹配找到老板: (\(String(format:"%.4f",npcPoint.x)), \(String(format:"%.4f",npcPoint.y)))")
            debugSaveImage(cgImage,
                           dots: [(CGPoint(x: npcPoint.x, y: npcPoint.y),
                                   CGColor(red: 1, green: 0, blue: 0, alpha: 1))],
                           boxes: [],
                           label: "npc_click")
            await click(npcPoint, noiseRadius: 0)
            try? await Task.sleep(nanoseconds: 900_000_000)
            
            var dialogFound = false
            for attempt in 1...3 {
                guard let newFrame = await freshFrame() else { continue }
                
                // 只扫对话框区域
                let dialogElements = await detector.scanTextInRegion(
                    cgImage: newFrame,
                    region: UIRegions.dialogROI
                )
                
                if let dialogLabel = dialogElements.first(where: {
                    $0.text.contains("是的") || $0.text.contains("我要去")
                }) {
                    log("✅ 第\(attempt)次找到对话选项，点击")
                    debugSaveImage(newFrame,
                                   dots: [(CGPoint(x: dialogLabel.normX + dialogLabel.normW/2,
                                                   y: dialogLabel.normY + dialogLabel.normH/2),
                                           CGColor(red: 0, green: 1, blue: 0, alpha: 1))],
                                   boxes: [(dialogLabel.normX, dialogLabel.normY,
                                            dialogLabel.normW, dialogLabel.normH)],
                                   label: "dialog_click")
                    await clickOCR(dialogLabel)
                    dialogFound = true
                    break
                }
                
                log("⚠️ 第\(attempt)次未检测到对话框，重新点击老板")
                await click(npcPoint, noiseRadius: 2)
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            
            if !dialogFound {
                return .retry(reason: "模板匹配到老板但对话框未出现")
            }
            
        } else {
            log("⚠️ 模板匹配未找到老板")
            return .retry(reason: "未能找到驿站老板")
        }

        
        
         await humanDelay(  0.3...0.8)
        
     
        
          await humanDelay(1.2...2.0)
         ///  click(SkillSlots.yiZhanLaoBan)
           // 2-5. 等待地图切换到大唐国境
        let arrived = await waitForMap("大唐国境", timeout: 8.0)
           guard arrived else {
               cleanFalg()
               return .retry(reason: "传送超时，未到达大唐国境")
           }
        return .success
    }
  
  
    private func findNPCClickWithPoint(named npcName: String,
                                    searchRegion: CGRect,
                                    cgImage: CGImage) async -> CGPoint? {
        // 先裁剪到指定区域
        let x = Int(searchRegion.minX * Double(cgImage.width))
        let y = Int(searchRegion.minY * Double(cgImage.height))
        let w = Int(searchRegion.width  * Double(cgImage.width))
        let h = Int(searchRegion.height * Double(cgImage.height))

        guard let roi = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            log("❌ 裁剪区域失败")
            return nil
        }

        // 在裁剪区域内扫描文字
        let elements = await detector.scanAllTextElements(cgImage: roi)

        guard let npc = elements.first(where: { $0.text.contains(npcName) }) else {
            log("❌ 未找到NPC: \(npcName)")
            return nil
        }

        // 坐标从裁剪区域相对坐标 → 转回全图相对坐标
        let absNormX = searchRegion.minX + npc.normX * searchRegion.width
        let absNormY = searchRegion.minY + npc.normY * searchRegion.height

        // 名字水平中心，人物在名字上方
        let clickX = absNormX + (npc.normW * searchRegion.width)  / 2
        let clickY = absNormY - 0.08

        log("✅ 找到 \(npcName) 点击位置: x:\(String(format:"%.4f", clickX)) y:\(String(format:"%.4f", clickY))")
        return CGPoint(x: clickX, y: clickY)
    }
    
    
    
    
    
    // MARK: - ── 步骤3：大唐国境到地府 ───────────────────────
    /// 小任务：
    private func step3_daTangToDiFu(_ cgImage: CGImage) async -> StepResult {
//        let mapName = await detector.ocrRegion(cgImage, region: SceneDetector.UIRegions.locationPx)
//           if mapName.contains("地府") {
//               log("✅ 已在地府，跳过")
//               return .success
//           }
        
           // 3-1. Tab 打开大地图
            await humanDelay(0.6...1.0)
            await pressKey(GameKeys.tab)
            await humanDelay(0.5...0.8)
            
            // 3-2. 点击地图中地府位置
            await click(TaskaParameter.guojingDiFu,noiseRadius: 0)
            await humanDelay(0.5...0.8)

            // 3-3. Tab 关闭地图
            await pressKey(GameKeys.tab)
            await humanDelay(0.5...0.8)

            // 3-4. 等待移动到地府传送点附近，再点击地府入口
            let nearPortal = await waitForCoord(x: 48, y: 326, tolerance: 2, timeout: 30.0)
            guard nearPortal else {
                return .retry(reason: "未到达地府传送点附近")
            }
        
           // 3-5. 点击地府门口
           await click(TaskaParameter.guojingjinDiFu,noiseRadius: 0)
           await humanDelay(0.4...0.8)

           // 3-6. 等待进入地府
           let arrived = await waitForMap("地府", timeout: 15.0)
           guard arrived else {
                return .retry(reason: "传送超时，未到达地府")
           }

           return .success
    }

    // MARK: - ── 步骤4：地府领取任务 ─────────────────────────
    /// 小任务：

    private func step4_acceptQuest(_ cgImage: CGImage) async -> StepResult {
        let mapName = await detector.ocrRegion(cgImage, region: UIRegions.locationPx)
           guard mapName.contains("地府") else {
               return .retry(reason: "不在地府，当前: \(mapName)")
           }
        
        // 4-1. Tab 打开小地图，点击钟馗位置
           await humanDelay(0.6...1.0)
           await pressKey(GameKeys.tab)
           await humanDelay(0.6...1.0)
           await click(TaskaParameter.diFuDiTuzhongkui,noiseRadius: 0)
           await humanDelay(0.6...1.0)
        
          // 4-2. Tab 关闭小地图
          await pressKey(GameKeys.tab)
          await humanDelay(0.3...0.8)
        
        // 4-3. 等待走到钟馗 NPC 附近
          let nearNPC = await waitForCoord(x: 50, y: 55, tolerance: 4, timeout: 30.0)
          guard nearNPC else {
              return .retry(reason: "未走到钟馗附近")
          }
        
         await pressKey(KeyCode.f9)
         await humanDelay(0.4...0.8)
        
        // 4-4. 点击钟馗 NPC
         await click(TaskaParameter.diFuZhongkui,noiseRadius: 0)
         await humanDelay(0.8...1.0)

        
        // 4-5. 截图检测对话框
          guard let freshImg = await WindowService.captureWindowAsync(state.window),
                let freshCG  = freshImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
          else { return .retry(reason: "截图失败") }

          let dialogText = await detector.ocrRegion(freshCG, region: UIRegions.dialogROI)
          guard dialogText.contains("好的") || dialogText.contains("帮你") else {
              return .retry(reason: "对话框未出现: \(dialogText)")
          }
        
        // 4-6. 点击"好的，我帮你"
           await click(TaskaParameter.zhongkuiDuiHua,noiseRadius: 0)
           await humanDelay(0.3...0.8)
        
        // 4-7. 根据任务目标地点决定传送方式
            guard let taskImg = await WindowService.captureWindowAsync(state.window),
                  let taskCG  = taskImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return .retry(reason: "截图失败") }

            let taskMap = await detector.ocrRegion(taskCG, region: UIRegions.locationPx)
            let needsBagTeleport = ["大唐境外", "普陀山", "五庄观", "女儿村"]
                .contains(where: { taskMap.contains($0) })
            if needsBagTeleport {
               // 打开行囊使用传送旗
               WindowService.pressKeys(KeyCode.e, modifiers: .maskCommand, window: state.window)
                if taskMap == "大唐境外"{
                    await humanDelay(0.3...0.8)
                    await rightClick(TaskaParameter.xingNangDTGJ,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                    await click(TaskaParameter.daTangGuoJingGLZ,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                }
                if taskMap == "普陀山"{
                    await humanDelay(0.3...0.8)
                    await rightClick(TaskaParameter.xingNangCN,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                    await click(TaskaParameter.changAnDTGJ,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                }
                if taskMap == "五庄观"{
                    await humanDelay(0.3...0.8)
                    await rightClick(TaskaParameter.xingNangDTGJ,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                    await click(TaskaParameter.daTangGuoJingWZG,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                }
                if taskMap == "女儿村"{
                    await humanDelay(0.3...0.8)
                    await rightClick(TaskaParameter.xingNangAL,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                    await click(TaskaParameter.aolaiNE,noiseRadius: 0)
                    await humanDelay(0.8...1.0)
                }
              
            }
        
        // 点击任务栏开始自动寻路
            await click(TaskaParameter.automatedTask,noiseRadius: 0)
           await humanDelay(0.8...1.0)
        
           // 等待离开地府（说明自动寻路启动）
           let departed = await waitForMapChange(from: "地府", timeout: 20.0)
           guard departed else {
               return .retry(reason: "自动寻路未启动，仍在地府")
           }

           return .success
    }

    // MARK: - ── 步骤5：前往任务地点找目标 ────────────────────
    /// 小任务：
 
    private func step5_goToQuestTarget(_ cgImage: CGImage) async -> StepResult {
        // 战斗中等待结束
            let coordinate = await detector.ocrRegion(cgImage, region: UIRegions.fightPx)
            if coordinate.contains("回合") {
                return .retry(reason: "战斗中，等待结束")
            }

            // 5-1. 截图检测任务对话框，点击"我来了"
            guard let freshImg = await WindowService.captureWindowAsync(state.window),
                  let freshCG  = freshImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return .retry(reason: "截图失败") }

            let dialogText = await detector.ocrRegion(freshCG, region: UIRegions.dialogROI)
            if dialogText.contains("我来了") {
                await click(TaskaParameter.taskStart,noiseRadius: 0)
                await humanDelay(0.8...1.0)
            }

            // 5-2. 等待战斗开始
            let battleStarted = await waitForBattle(timeout: 10.0)
            if !battleStarted {
                return .retry(reason: "未检测到战斗开始")
            }

            // 5-3. 等待战斗结束
            let battleEnded = await waitForBattleEnd(timeout: 60.0)
            if !battleEnded {
                return .retry(reason: "战斗超时未结束")
            }

            // 5-4. 检测是否还有抓鬼任务
            guard let afterImg = await WindowService.captureWindowAsync(state.window),
                  let afterCG  = afterImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return .retry(reason: "截图失败") }

            let taskText = await detector.ocrRegion(afterCG, region: UIRegions.dialogROI)
            if taskText.contains("抓鬼") {
                // 还有任务，继续寻路
                let mapName = await detector.ocrRegion(afterCG, region: UIRegions.locationPx)
                let needsBagTeleport = ["大唐境外", "普陀山", "五庄观", "女儿村"]
                    .contains(where: { mapName.contains($0) })

                if needsBagTeleport {
                    // 打开行囊使用传送旗
                    WindowService.pressKeys(KeyCode.e, modifiers: .maskCommand, window: state.window)
                     if mapName == "大唐境外"{
                         await humanDelay(0.5...0.8)
                         await rightClick(TaskaParameter.xingNangDTGJ,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                         await click(TaskaParameter.daTangGuoJingGLZ,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                     }
                     if mapName == "普陀山"{
                         await humanDelay(0.3...0.8)
                         await rightClick(TaskaParameter.xingNangCN,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                         await click(TaskaParameter.changAnDTGJ,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                     }
                     if mapName == "五庄观"{
                         await humanDelay(0.3...0.8)
                         await rightClick(TaskaParameter.xingNangDTGJ,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                         await click(TaskaParameter.daTangGuoJingWZG,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                     }
                     if mapName == "女儿村"{
                         await humanDelay(0.3...0.8)
                         await rightClick(TaskaParameter.xingNangAL,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                         await click(TaskaParameter.aolaiNE,noiseRadius: 0)
                         await humanDelay(0.8...1.0)
                     }
                   
                }
                await click(TaskaParameter.automatedTask,noiseRadius: 0)
                await humanDelay(0.8...1.0)
                return .retry(reason: "还有抓鬼任务，继续寻路")
            }

            return .success
    }

    // MARK: - ── 步骤6：任务结束 ──────────────────────────────
    /// 小任务：
    ///   6-1. OCR 检测任务完成弹窗
    ///   6-2. 点击确认/完成按钮
    ///   6-3. 等待动画结束
    ///   6-4. 更新统计数据
    private func step6_completeQuest(_ cgImage: CGImage) async -> StepResult {
        // 6-1. 检测任务完成弹窗
            guard let freshImg = await WindowService.captureWindowAsync(state.window),
                  let freshCG  = freshImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return .retry(reason: "截图失败") }

            let resultText = await detector.ocrRegion(freshCG, region: UIRegions.dialogROI)
            guard resultText.contains("完成") || resultText.contains("奖励") else {
                return .retry(reason: "任务完成弹窗未出现")
            }

            // 6-2. 点击确认
//            click(SkillSlots.confirm)
//            await humanDelay(0.8...1.0)

            // 6-3. 更新统计
            DispatchQueue.main.async { [weak self] in
                self?.state.wins += 1
                self?.state.battles += 1
            }

            log("🏆 任务完成，准备下一轮")
            return .success
    }

    // MARK: - 辅助
    private func log(_ msg: String) {
        print("[QuestFlow] \(msg)")
        onLog?(msg)
    }

    private func pressKey(_ keyCode: CGKeyCode) async {
        WindowService.pressKey(keyCode)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.3...0.6) * 1_000_000_000))
    }


    private func click(_ point: CGPoint,noiseRadius: Int = 3) async {
        WindowService.clickAt(window: &state.window, relX: point.x, relY: point.y,noiseRadius:noiseRadius)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.3...0.6) * 1_000_000_000))
    }
    
    private func rightClick(_ point: CGPoint,noiseRadius: Int = 3) async {
        WindowService.rightClickAt(window: &state.window, relX: point.x, relY: point.y,noiseRadius:noiseRadius)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.1...0.3) * 1_000_000_000))
    }

    /// OCR 专用点击：传入 TextElement，用 frame 尺寸换算，不走 CoordBase
    private func clickOCR(_ element: TextElement, noiseRadius: Int = 0) async {
        let cx = element.normX + element.normW / 2.0
        let cy = element.normY + element.normH / 2.0
        WindowService.clickAtOCR(window: &state.window, normX: cx, normY: cy,
                                  srcW: element.srcW, srcH: element.srcH,
                                  noiseRadius: noiseRadius)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.3...0.6) * 1_000_000_000))
    }

    // MARK: - 调试：把点位/文字框画在截图上并保存到桌面
    /// - dots:  [(归一化坐标, 颜色)]  → 画实心圆 + 坐标文字
    /// - boxes: [(normX, normY, normW, normH)]  → 画矩形框（黄色）
    private func debugSaveImage(
        _ cgImage: CGImage,
        dots:  [(CGPoint, CGColor)],
        boxes: [(Double, Double, Double, Double)],
        label: String
    ) {
        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 黄色矩形框（OCR 文字区域）
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        ctx.setLineWidth(2)
        for (nx, ny, nw, nh) in boxes {
            let rect = CGRect(x: nx * Double(w), y: ny * Double(h),
                              width: nw * Double(w), height: nh * Double(h))
            ctx.stroke(rect)
        }

        // 彩色实心圆 + 坐标标注
        for (pt, color) in dots {
            let px = pt.x * Double(w)
            let py = pt.y * Double(h)
            let r: Double = 10
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: px - r, y: py - r, width: r*2, height: r*2))
            // 白色描边
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: px - r, y: py - r, width: r*2, height: r*2))
            // 坐标文字
            let label2 = String(format: "(%.4f,%.4f)", pt.x, pt.y) as CFString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.yellow
            ]
            let attrStr = NSAttributedString(string: label2 as String, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            ctx.textPosition = CGPoint(x: px + r + 2, y: py - 7)
            CTLineDraw(line, ctx)
        }

        guard let result = ctx.makeImage() else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss_SSS"
        let ts = formatter.string(from: Date())
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent("debug_\(label)_\(ts).png")

        if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, result, nil)
            if CGImageDestinationFinalize(dest) {
                print("[DEBUG] 📸 已保存: \(url.lastPathComponent)")
            }
        }
    }
    
   
    private func humanDelay(_ range: ClosedRange<Double> = 0.3...0.8) async {
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: range) * 1_000_000_000))
    }

    /// 等待地图变为目标名称（最多 timeout 秒）
    func waitForMap(_ targetMap: String, timeout: TimeInterval = 15.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return false }
            guard let img = await WindowService.captureWindowAsync(state.window),
                  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { try? await Task.sleep(nanoseconds: 500_000_000); continue }
            let mapName = await detector.ocrRegion(cg, region: UIRegions.locationPx)
            if mapName.contains(targetMap) {
                log("✅ 已到达: \(targetMap)")
                return true
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        log("❌ 等待超时: \(targetMap)")
        return false
    }
    
    
    // MARK: - 等待地图从某个地点离开
    private func waitForMapChange(from currentMap: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return false }
            guard let img = await WindowService.captureWindowAsync(state.window),
                  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { try? await Task.sleep(nanoseconds: 500_000_000); continue }
            let mapName = await detector.ocrRegion(cg, region: UIRegions.locationPx)
            if !mapName.contains(currentMap) {
                return true
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return false
    }


    /// 等待坐标到达目标附近
    func waitForCoord(x targetX: Int, y targetY: Int,
                      tolerance: Int = 8,
                      timeout: TimeInterval = 30.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return false }
            guard let img = await WindowService.captureWindowAsync(state.window),
                  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { try? await Task.sleep(nanoseconds: 500_000_000); continue }
            let xStr = await detector.ocrRegion(cg, region: UIRegions.xPx)
            let yStr = await detector.ocrRegion(cg, region: UIRegions.yPx)
            if let cx = Int(xStr.filter(\.isNumber)),
               let cy = Int(yStr.filter(\.isNumber)),
               abs(cx - targetX) <= tolerance,
               abs(cy - targetY) <= tolerance {
                log("✅ 到达坐标: (\(cx), \(cy))")
                return true
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        log("❌ 坐标等待超时")
        return false
    }
    
    // MARK: - 等待战斗开始
    private func waitForBattle(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return false }
            guard let img = await WindowService.captureWindowAsync(state.window),
                  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { try? await Task.sleep(nanoseconds: 500_000_000); continue }
            let coord = await detector.ocrRegion(cg, region: UIRegions.fightPx)
            if coord.contains("回合") { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - 等待战斗结束
    private func waitForBattleEnd(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shouldStop() { return false }
            guard let img = await WindowService.captureWindowAsync(state.window),
                  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { try? await Task.sleep(nanoseconds: 500_000_000); continue }
            let coord = await detector.ocrRegion(cg, region: UIRegions.fightPx)
            if !coord.contains("回合") { return true }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return false
    }
}

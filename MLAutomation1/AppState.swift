import Foundation
import AppKit
import Combine
 
// MARK: - 全局应用状态 & 多Bot管理器
class AppState: ObservableObject {
 
    @Published var instances:   [InstanceState] = []
    @Published var logs:        [LogEntry]       = []
    @Published var isScanning   = false
 
    // 实例ID → BotEngine
    private var engines: [Int: BotEngine] = [:]
 
    // 最多保留日志条数
    private let maxLogs = 500
 
    // MARK: 自动关闭相关
    /// 本次连续运行的开始时间（所有实例均停止时置 nil）
    private var sessionStartDate: Date?
    /// 每 30 秒轮询一次，检查是否超时
    private var autoStopTimer: AnyCancellable?
    /// 连续运行上限：2 小时
    private let autoStopLimit: TimeInterval = 2 * 60 * 60
    /// F5 开始快捷键
    private var f5Monitor:      Any?   // 全局监听（其他 App 有焦点时）
    private var f5LocalMonitor: Any?   // 本地监听（本 App 有焦点时）

    // 烧双多窗口调度。两个引擎同时点会互相切窗口，所以改由这里轮流操作。
    private let dualWalkLock = NSLock()
    private var dualWalkGeneration = 0
    private var dualWalkTask: Task<Void, Never>?
 
    // MARK: 扫描游戏窗口
    func scanWindows() {
        isScanning = true
 
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = WindowService.discoverGameWindows()
 
            DispatchQueue.main.async {
                self.stopDualWalk()
                // 停止旧引擎
                self.engines.values.forEach { $0.stop() }
                self.engines.removeAll()
 
                // 创建新实例状态
                self.instances = windows.enumerated().map { idx, win in
                    InstanceState(id: idx, window: win)
                }
 
                // 为每个实例创建 BotEngine
                for inst in self.instances {
                    let engine = BotEngine(state: inst) { [weak self] entry in
                        self?.appendLog(entry)
                    }
                    self.engines[inst.id] = engine
                }
 
                self.isScanning = false
                self.appendSystemLog("扫描完成，发现 \(windows.count) 个游戏窗口")
            }
        }
    }
 
    // MARK: 全局控制
    func startAll() {
        let shaoshuang = engines.values.filter { $0.taskMode == .shaoshuang }
        if shaoshuang.count >= 2 {
            shaoshuang.forEach { $0.coordinatedShaoshuang = true }
        }
        engines.values.forEach { $0.start() }
        appendSystemLog("已启动全部 \(engines.count) 个实例")
        beginSessionIfNeeded()   // ← 有实例开始运行，启动计时
        refreshDualWalk()
    }
 
    func stopAll() {
        stopDualWalk()
        engines.values.forEach { $0.stop() }
        appendSystemLog("已停止全部实例")
        endSessionIfAllStopped() // ← 全部停止，重置计时
    }
 
    func pauseAll() {
        stopDualWalk()
        engines.values.forEach { $0.pause() }
        // 暂停不重置计时：暂停期间仍计入连续运行时间
    }
 
    // MARK: 单实例控制
    func start(id: Int) {
        engines[id]?.start()
        beginSessionIfNeeded()
        refreshDualWalk()
    }
 
    func stop(id: Int) {
        engines[id]?.stop()
        endSessionIfAllStopped()
        refreshDualWalk()
    }
 
    func pause(id: Int)  {
        engines[id]?.pause()
        refreshDualWalk()
    }
    func resume(id: Int) {
        engines[id]?.resume()
        refreshDualWalk()
    }


    func setStrategy(_ strategy: BattleStrategy, for id: Int? = nil) {
        if let id = id {
            instances.first { $0.id == id }?.strategy = strategy
        } else {
            instances.forEach { $0.strategy = strategy }
        }
    }
 
    // MARK: 日志管理
    func clearLogs() { logs.removeAll() }
 
    private func appendLog(_ entry: LogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > maxLogs { logs.removeLast() }
    }
 
    private func appendSystemLog(_ msg: String) {
        let entry = LogEntry(
            timestamp: Date(),
            instanceIndex: -1,
            scene: .unknown,
            action: msg,
            detail: ""
        )
        appendLog(entry)
    }
 
    // MARK: - 连续运行监听 & 自动关闭
 
    /// 当前是否有任何引擎处于运行状态（非 stopped）
    private var hasRunningEngine: Bool {
        instances.contains { $0.status == .running || $0.status == .paused }
    }
    
    
    // ── 新增方法 ──
        func registerF5HotKey() {
            guard f5Monitor == nil else { return }
            
            // 同时监听本地（App 有焦点）和全局（其他 App 有焦点）
            f5LocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 96 {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let anyRunning = self.engines.values.contains { $0.isRunning }
                        if anyRunning {
                            self.stopAll()
                            self.appendSystemLog("⏹ F5 停止")
                        } else {
                            self.startAll()
                            self.appendSystemLog("▶️ F5 启动")
                        }
                    }
                    return nil
                }
                return event
            }
            
            // 游戏窗口有焦点时用全局监听
            f5Monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 96 else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let anyRunning = self.engines.values.contains { $0.isRunning }
                    if anyRunning {
                        self.stopAll()
                        self.appendSystemLog("⏹ F5 停止")
                    } else {
                        self.startAll()
                        self.appendSystemLog("▶️ F5 启动")
                    }
                }
            }
            print("✅ F5注册完成")
        }
    
    
 
    /// 启动计时（只在尚未计时时才开始）
    private func beginSessionIfNeeded() {
        guard sessionStartDate == nil else { return }
 
        sessionStartDate = Date()
        appendSystemLog("自动关闭计时开始，将在 2 小时后自动停止所有实例")
 
        // 每 30 秒检查一次剩余时间
        autoStopTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkAutoStop()
            }
    }
 
    /// 若全部实例已停止，则重置本次会话计时
    private func endSessionIfAllStopped() {
        guard !hasRunningEngine else { return }
 
        autoStopTimer?.cancel()
        autoStopTimer = nil
        sessionStartDate = nil
        appendSystemLog("所有实例已停止，自动关闭计时已重置")
    }
 
    /// 每 30 秒由 Timer 触发：检查是否达到 2 小时上限
    private func checkAutoStop() {
        guard let start = sessionStartDate else { return }
 
        let elapsed = Date().timeIntervalSince(start)
        let remaining = autoStopLimit - elapsed
        
        
        if remaining <= 0 {
            // 超时 → 强制停止全部实例
            stopDualWalk()
            engines.values.forEach { $0.stop() }
            appendSystemLog("⚠️ 已连续运行 2 小时，所有实例自动停止")
 
            autoStopTimer?.cancel()
            autoStopTimer = nil
            sessionStartDate = nil
 
        } else if remaining <= 10 * 60 {
            // 不足 10 分钟时每次轮询都提醒
            let mins = Int(remaining / 60)
            appendSystemLog("⏱ 距自动停止还剩约 \(mins) 分钟")
        }else {
            let mins = Int(remaining / 60)
            print("⏱ 距自动停止还剩约 \(mins) 分钟")
        }
    }

    // MARK: - 烧双双窗口调度
    // 一次走路（Tab、点击、Tab）始终留在同一扇窗口。
    // 点完后把下一轮交给另一扇，中间大约隔 2 秒。
    // 若即将操作的窗口已经在战斗，立刻改操作另一扇，不等满 2 秒。

    private func stopDualWalk() {
        dualWalkLock.lock()
        dualWalkGeneration += 1
        dualWalkTask?.cancel()
        dualWalkTask = nil
        dualWalkLock.unlock()
        engines.values.forEach { $0.coordinatedShaoshuang = false }
    }

    /// 正在跑的烧双窗口达到两个时，关掉它们各自的点击，改由调度轮流操作。
    private func refreshDualWalk() {
        dualWalkLock.lock()
        dualWalkGeneration += 1
        let generation = dualWalkGeneration
        dualWalkTask?.cancel()
        dualWalkLock.unlock()

        let active = engines.values
            .filter { $0.isRunning && $0.taskMode == .shaoshuang }
            .sorted { $0.instanceID < $1.instanceID }

        engines.values.forEach { $0.coordinatedShaoshuang = false }
        guard active.count >= 2 else {
            dualWalkLock.lock()
            dualWalkTask = nil
            dualWalkLock.unlock()
            return
        }

        active.forEach { $0.coordinatedShaoshuang = true }
        appendSystemLog("烧双由调度轮流操作 \(active.count) 个窗口，点完一步再换窗，间隔约 2 秒")
        let task = Task { [weak self] in
            guard let self else { return }
            await self.dualWalkLoop(active, generation: generation)
        }
        dualWalkLock.lock()
        if generation == dualWalkGeneration {
            dualWalkTask = task
        } else {
            task.cancel()
        }
        dualWalkLock.unlock()
    }

    private func dualWalkGenerationNow() -> Int {
        dualWalkLock.lock()
        defer { dualWalkLock.unlock() }
        return dualWalkGeneration
    }

    private func dualWalkLoop(_ members: [BotEngine], generation: Int) async {
        defer {
            if generation == dualWalkGenerationNow() {
                members.forEach { $0.coordinatedShaoshuang = false }
            }
        }
        // 先记一次坐标，避免第一眼就把“没走过”认成“正在走”
        for engine in members {
            _ = await engine.readShaoshuangView()
        }

        var nextIndex = 0
        var actNow = true

        while !Task.isCancelled && generation == dualWalkGenerationNow() {
            let running = members.filter { $0.isRunning && $0.taskMode == .shaoshuang }
            if running.count < 2 { break }

            if !actNow {
                guard let picked = await waitNextTurn(members, preferred: nextIndex, generation: generation) else { break }
                nextIndex = picked
            }
            actNow = false
            guard members.indices.contains(nextIndex) else { break }

            if await offerBattlePopups(members) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard generation == dualWalkGenerationNow() else { break }
            }

            guard let view = await members[nextIndex].readShaoshuangView() else {
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }

            if view.inBattle {
                if let free = await firstWalkableIndex(members, after: nextIndex) {
                    logDual("实例 \(members[nextIndex].instanceID) 战斗中，改操作实例 \(members[free].instanceID)")
                    nextIndex = free
                    actNow = true
                } else {
                    logDual("两扇都在战斗，2 秒后再看弹框")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                continue
            }

            if view.moved {
                logDual("实例 \(members[nextIndex].instanceID) 还在走路，2 秒后看下一扇")
                nextIndex = (nextIndex + 1) % members.count
                continue
            }

            logDual("实例 \(members[nextIndex].instanceID) 开始走一步")
            await members[nextIndex].performShaoshuangWalk()
            guard generation == dualWalkGenerationNow() else { break }

            let handed = (nextIndex + 1) % members.count
            if let handedView = await members[handed].readShaoshuangView(), handedView.inBattle {
                logDual("实例 \(members[handed].instanceID) 在战斗，继续留在实例 \(members[nextIndex].instanceID)")
            } else {
                logDual("交给实例 \(members[handed].instanceID)")
                nextIndex = handed
            }
        }
    }

    /// 战斗中的窗口如果弹出四人框，点正面角色。走路仍然留给没在战斗的那一扇。
    private func offerBattlePopups(_ members: [BotEngine]) async -> Bool {
        var clicked = false
        for engine in members where engine.isRunning && engine.taskMode == .shaoshuang {
            if await engine.clickFrontPortraitIfPopup() {
                logDual("实例 \(engine.instanceID) 战斗弹框，已点正面角色")
                clicked = true
            }
        }
        return clicked
    }

    /// 最多等 2 秒。期间如果预定的窗口进入战斗，而另一扇还能走，立刻改去那一扇。
    private func waitNextTurn(_ members: [BotEngine], preferred: Int, generation: Int) async -> Int? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if Task.isCancelled || generation != dualWalkGenerationNow() { return nil }
            if let freeNow = await redirectedIfBattling(members, preferred: preferred) {
                return freeNow
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        if Task.isCancelled || generation != dualWalkGenerationNow() { return nil }
        if await isInBattle(members, index: preferred) {
            return await firstWalkableIndex(members, after: preferred) ?? preferred
        }
        return preferred
    }

    /// 预定窗口已经在战斗、且存在另一扇没在战斗时，返回那一扇。否则返回 nil，表示继续等。
    private func redirectedIfBattling(_ members: [BotEngine], preferred: Int) async -> Int? {
        guard await isInBattle(members, index: preferred) else { return nil }
        return await firstWalkableIndex(members, after: preferred)
    }

    private func isInBattle(_ members: [BotEngine], index: Int) async -> Bool {
        guard members.indices.contains(index) else { return false }
        let view = await members[index].readShaoshuangView()
        return view?.inBattle == true
    }

    /// 从 index 的下一扇开始，找第一扇不在战斗中的窗口。
    private func firstWalkableIndex(_ members: [BotEngine], after index: Int) async -> Int? {
        guard !members.isEmpty else { return nil }
        for offset in 1...members.count {
            let candidate = (index + offset) % members.count
            if candidate == index { continue }
            let view = await members[candidate].readShaoshuangView()
            if view?.inBattle == false { return candidate }
        }
        return nil
    }

    private func logDual(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appendSystemLog(message)
        }
    }
}

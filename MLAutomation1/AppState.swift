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
 
    // MARK: 扫描游戏窗口
    func scanWindows() {
        isScanning = true
 
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = WindowService.discoverGameWindows()
 
            DispatchQueue.main.async {
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
        engines.values.forEach { $0.start() }
        appendSystemLog("已启动全部 \(engines.count) 个实例")
        beginSessionIfNeeded()   // ← 有实例开始运行，启动计时
    }
 
    func stopAll() {
        engines.values.forEach { $0.stop() }
        appendSystemLog("已停止全部实例")
        endSessionIfAllStopped() // ← 全部停止，重置计时
    }
 
    func pauseAll() {
        engines.values.forEach { $0.pause() }
        // 暂停不重置计时：暂停期间仍计入连续运行时间
    }
 
    // MARK: 单实例控制
    func start(id: Int) {
        engines[id]?.start()
        beginSessionIfNeeded()
    }
 
    func stop(id: Int) {
        engines[id]?.stop()
        endSessionIfAllStopped()
    }
 
    func pause(id: Int)  { engines[id]?.pause() }
    func resume(id: Int) { engines[id]?.resume() }


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
}

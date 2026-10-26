//
//  Models.swift
//  MLAutomation
//

import Foundation
import AppKit
import Combine

// MARK: - 坐标基准（记录点位时的窗口尺寸，保持窗口不变则点击永远准确）
struct CoordBase {
    static let width:  CGFloat = 1024
    static let height: CGFloat = 768
}

// MARK: - 游戏场景枚举
enum GameScene: String, CaseIterable {
    case unknown         = "未知"
    case mainMap         = "主地图"
    case battleMyTurn    = "⚔️ 我的回合"
    case battleEnemyTurn = "🛡 敌方回合"
    case battleResult    = "🏆 战斗结算"
    case lowHP           = "❤️ 血量危险"
    case dead            = "💀 死亡"
    case dialog          = "💬 对话框"
    case itemDrop        = "🎁 掉落物品"
    case levelUp         = "⬆️ 升级"
    case changAnCheng = "长安城"
    case jianyecheng = "建邺城"
    case jiangNanYeWai = "江南野外"
    case daTangGuoJing = "大唐国境"
    case daTangJingWai = "大唐境外"
    case changShoucun = "长寿村"
    case xiLiangNvGuo = "西梁女国"
    case baoXiangguo = "宝象国"
    case zhuZi = "朱紫国"
    case aoLaiGuo = "傲来国"
    case nvErCun = "女儿村"
    case diFu = "地府"
    case wuZhuangGuan = "五庄观"
    case puTuoShan = "普陀山"
    
    case beiJuRuzhou = "北俱芦洲"
    case longGuYiCeng = "龙窟一层"
    case longGuLiuCeng = "龙窟六层"
    case longGuQiCeng = "龙窟七层"
    case qiLinShan = "麒麟山"
    
    case huiHe = "回合"

    var color: NSColor {
        switch self {
        case .battleMyTurn:    return .systemGreen
        case .battleEnemyTurn: return .systemOrange
        case .battleResult:    return .systemYellow
        case .lowHP:           return .systemRed
        case .dead:            return .systemGray
        case .levelUp:         return .systemPurple
        default:               return .systemBlue
        }
    }
}

// MARK: - Bot 运行状态
enum BotStatus: String {
    case idle    = "空闲"
    case running = "运行中"
    case paused  = "已暂停"
    case stopped = "已停止"
    case error   = "错误"

    var color: NSColor {
        switch self {
        case .running: return .systemGreen
        case .paused:  return .systemOrange
        case .error:   return .systemRed
        default:       return .systemGray
        }
    }

    var icon: String {
        switch self {
        case .idle:    return "circle"
        case .running: return "play.circle.fill"
        case .paused:  return "pause.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .error:   return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - 战斗策略
enum BattleStrategy: String, CaseIterable, Identifiable {
    case normalAttack  = "普通攻击"
    case skillPriority = "技能优先"
    case safeMode      = "安全模式"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .normalAttack:  return "省蓝，持续战斗"
        case .skillPriority: return "快速清怪"
        case .safeMode:      return "低血自动回血"
        }
    }

    var icon: String {
        switch self {
        case .normalAttack:  return "bolt"
        case .skillPriority: return "flame.fill"
        case .safeMode:      return "heart.fill"
        }
    }
}

// MARK: - 游戏窗口信息
struct GameWindow {
    var id: Int
    var pid: Int32
    var title: String
    var frame: CGRect
    var instanceIndex: Int
    /// kCGWindowLayer：普通应用窗口 = 0，Wine 根窗口/桌面层 < 0，悬浮面板 > 0
    var layer: Int = 0

    // 四边黑边pt（相对窗口左上角，检测一次后固定）
    var contentInsetLeft:   CGFloat = 0
    var contentInsetTop:    CGFloat = 0
    var contentInsetRight:  CGFloat = 0
    var contentInsetBottom: CGFloat = 0

    // 检测时固定的内容区尺寸
    var fixedContentWidth:  CGFloat = 0
    var fixedContentHeight: CGFloat = 0
    var insetReady: Bool = false

    // 内容区屏幕起点（只跟随窗口移动）
    var contentOrigin: CGPoint {
        CGPoint(
            x: frame.minX + contentInsetLeft,
            y: frame.minY + contentInsetTop
        )
    }

    // 调试用
    var contentFrame: CGRect {
        CGRect(
            x:      frame.minX + contentInsetLeft,
            y:      frame.minY + contentInsetTop,
            width:  fixedContentWidth,
            height: fixedContentHeight
        )
    }
}

// MARK: - 游戏场景信息（从截图中识别出的完整状态）
struct GameInfo {
    var mapName: String    = "未知地图"   // 当前地图名称
    var coordinate: String = "-, -"      // 当前坐标 e.g. "(123, 456)"
    var currentTask: String = "无任务"    // 当前任务描述
    var taskProgress: String = ""        // 任务进度 e.g. "3/10"
}

// MARK: - 战斗日志条目
struct LogEntry: Identifiable {
    let id        = UUID()
    let timestamp: Date
    let instanceIndex: Int
    let scene: GameScene
    let action: String
    let detail: String

    var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}

// MARK: - 单实例运行时数据
class InstanceState: ObservableObject, Identifiable {
    let id: Int
    var window: GameWindow

    @Published var status: BotStatus       = .idle
    @Published var taskMode: TaskMode        = .fengyao
    @Published var strategy: BattleStrategy = .normalAttack
    @Published var currentScene: GameScene  = .unknown
    @Published var hpPercent: Double        = 1.0
    @Published var mpPercent: Double        = 1.0
    @Published var screenshot: NSImage?     = nil

    // 新增：地图/坐标/任务信息
    @Published var gameInfo: GameInfo       = GameInfo()

    // 统计
    @Published var battles: Int     = 0
    @Published var wins: Int        = 0
    @Published var deaths: Int      = 0
    @Published var itemsPicked: Int = 0
    @Published var startTime: Date? = nil

    var runtime: String {
        guard let start = startTime else { return "00:00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        return String(format: "%02d:%02d:%02d",
                      elapsed / 3600, (elapsed % 3600) / 60, elapsed % 60)
    }

    init(id: Int, window: GameWindow) {
        self.id     = id
        self.window = window
    }
}

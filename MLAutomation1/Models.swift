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
// 一次扫描得到的一扇窗口。两个游戏客户端 = 两个 GameWindow，各自交给一个 BotEngine。
// id 和 pid 不是一回事：pid 是进程，一个进程里可以有很多扇窗；id 才是这一扇窗。
struct GameWindow {
    var id: Int                 // 系统分配的窗口编号（CGWindowID）。切换、截图、对位置都用它
    var pid: Int32              // 拥有这扇窗的进程号。两个 mhmain.exe 是两个不同的 pid
    var title: String           // 窗口标题，没有标题时用进程名
    var frame: CGRect           // 窗口在屏幕上的矩形。原点是屏幕左上角，单位是点
    var instanceIndex: Int      // 扫描时的顺序，用来让界面上的实例顺序保持稳定
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
    /// 烧双时用哪个地点预设的点位（ShaoshuangPresets 里的 id）。nil 表示用列表里的第一个。
    @Published var shaoshuangPresetID: String? = nil
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

// MARK: - 烧双地点预设
/// 一个烧双地点：名字 + Tab 小地图上要点的几个点（占窗口宽高的比例，和其它点击同一套坐标）。
/// 每张地图的小地图大小、位置都不同，所以点位按地点预设好，界面里直接选。
struct ShaoshuangPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let points: [CGPoint]
}

enum ShaoshuangPresets {
    /// 新增地点：在这里加一项即可，界面下拉框会自动出现。
    /// 点位 = 打开该地图小地图后，要点的位置 / 窗口宽高（窗口 1026×798，含标题栏）。
    static let all: [ShaoshuangPreset] = [
        // 以下三张按小地图截图估算：落在地图图像中部偏散的四个角，别贴边
        ShaoshuangPreset(id: "dtjw", name: "大唐境外", points: [
            CGPoint(x: 0.370, y: 0.482), CGPoint(x: 0.624, y: 0.482),
            CGPoint(x: 0.370, y: 0.570), CGPoint(x: 0.624, y: 0.570),
        ]),
        ShaoshuangPreset(id: "dtgj", name: "大唐国境", points: [
            CGPoint(x: 0.380, y: 0.414), CGPoint(x: 0.546, y: 0.414),
            CGPoint(x: 0.380, y: 0.627), CGPoint(x: 0.546, y: 0.627),
        ]),
        ShaoshuangPreset(id: "csjw", name: "长寿郊外", points: [
            CGPoint(x: 0.390, y: 0.426), CGPoint(x: 0.526, y: 0.426),
            CGPoint(x: 0.390, y: 0.602), CGPoint(x: 0.526, y: 0.602),
        ]),
        // 以下是原来代码里就有的点位
        ShaoshuangPreset(id: "mini", name: "通用（小地图缩小后）", points: [
            SkillSlots.wj1, SkillSlots.wj2, SkillSlots.wj3, SkillSlots.wj4,
        ]),
        ShaoshuangPreset(id: "df", name: "地府 无名鬼蜮", points: [
            SkillSlots.DF1, SkillSlots.DF2, SkillSlots.DF3, SkillSlots.DF4,
        ]),
        ShaoshuangPreset(id: "df4", name: "地府 4 层", points: [
            SkillSlots.DF41, SkillSlots.DF42, SkillSlots.DF43, SkillSlots.DF44,
        ]),
        ShaoshuangPreset(id: "l1", name: "龙 1", points: [
            SkillSlots.L11, SkillSlots.L12, SkillSlots.L13, SkillSlots.L14,
        ]),
    ]

    static func preset(id: String?) -> ShaoshuangPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

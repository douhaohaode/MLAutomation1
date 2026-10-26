import SwiftUI

// MARK: - 主界面（三栏布局）
struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedInstance: Int? = nil

    var body: some View {
        HStack(spacing: 0) {

            // ── 左栏：实例卡片列表 ──────────────────────────
            VStack(spacing: 0) {
                TopBar()
                InstanceListPanel(selectedInstance: $selectedInstance)
            }
            .frame(width: 300)
            .background(Color("BgPanel"))

            Divider()

            // ── 中栏：截图预览 & 详情 ───────────────────────
            if let id = selectedInstance,
               let inst = app.instances.first(where: { $0.id == id }) {
                InstanceDetailPanel(instance: inst)
                    .frame(maxWidth: .infinity)
            } else {
                EmptySelectionView()
                    .frame(maxWidth: .infinity)
            }

            Divider()

            // ── 右栏：战斗日志 ──────────────────────────────
            LogPanel()
                .frame(width: 280)
                .background(Color("BgPanel"))
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color("BgMain"))
    }
}

// MARK: - 顶部工具栏
struct TopBar: View {
    @EnvironmentObject var app: AppState
    @State private var showTemplateTest = false

    var body: some View {
        HStack(spacing: 10) {
            // Logo
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.purple)
            }

            Spacer()

            // 扫描按钮
            Button(action: { app.scanWindows() }) {
                HStack(spacing: 4) {
                    Text(app.isScanning ? "扫描中" : "扫描")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(CompactButtonStyle(color: .purple))

            // 模板调试按钮
            Button("调试") { showTemplateTest = true }
                .buttonStyle(CompactButtonStyle(color: .orange))

            // 全启 / 全停
            Button("全启") { app.startAll() }
                .buttonStyle(CompactButtonStyle(color: .green))
            Button("全停") { app.stopAll() }
                .buttonStyle(CompactButtonStyle(color: .red))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color("BgTopBar"))
        .sheet(isPresented: $showTemplateTest) {
            TemplateTestView(isPresented: $showTemplateTest)
                .frame(minWidth: 720, minHeight: 580)
        }
    }
}

// MARK: - 实例列表面板
struct InstanceListPanel: View {
    @EnvironmentObject var app: AppState
    @Binding var selectedInstance: Int?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if app.instances.isEmpty {
                    EmptyInstanceHint()
                } else {
                    ForEach(app.instances) { inst in
                        InstanceCard(instance: inst,
                                     isSelected: selectedInstance == inst.id)
                            .onTapGesture { selectedInstance = inst.id }
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 单个实例卡片
struct InstanceCard: View {
    @ObservedObject var instance: InstanceState
    @EnvironmentObject var app: AppState
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // 标题行
            HStack {
                Text("实例 #\(instance.id)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                StatusBadge(status: instance.status)
            }

            // 场景
            Text(instance.currentScene.rawValue)
                .font(.system(size: 11))
                .foregroundColor(Color(instance.currentScene.color))

            // 任务模式选择器
            TaskModePicker(instance: instance)

            // 统计行
            HStack {
                StatChip(icon: "⚔️", value: "\(instance.battles)")
                StatChip(icon: "🏆", value: "\(instance.wins)")
                StatChip(icon: "💀", value: "\(instance.deaths)")
                Spacer()
                Text(instance.runtime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }

            // 控制按钮
            HStack(spacing: 6) {
                ControlButton(label: "启动", icon: "play.fill",  color: .green)  { app.start(id: instance.id) }
                ControlButton(label: "暂停", icon: "pause.fill", color: .orange) { app.pause(id: instance.id) }
                ControlButton(label: "停止", icon: "stop.fill",  color: .red)    { app.stop(id: instance.id) }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.purple.opacity(0.2) : Color("BgCard"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.purple : Color.white.opacity(0.06),
                                lineWidth: 1)
                )
        )
    }
}

// MARK: - 任务模式选择器
struct TaskModePicker: View {
    @ObservedObject var instance: InstanceState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("执行任务")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)

            // 两行排列：每行最多3个
            let modes = TaskMode.allCases
            let rows = stride(from: 0, to: modes.count, by: 3).map {
                Array(modes[$0 ..< min($0 + 3, modes.count)])
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { mode in
                        TaskModeButton(
                            mode: mode,
                            isSelected: instance.taskMode == mode
                        ) {
                            instance.taskMode = mode
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 单个任务模式按钮
struct TaskModeButton: View {
    let mode: TaskMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(mode.icon)
                    .font(.system(size: 10))
                Text(mode.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.purple.opacity(0.35) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1)
                    )
            )
            .foregroundColor(isSelected ? .purple : .gray)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 实例详情面板（中栏）
struct InstanceDetailPanel: View {
    @ObservedObject var instance: InstanceState
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 截图预览
            ZStack {
                Color.black
                if let img = instance.screenshot {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("等待截图...")
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .cornerRadius(8)
            .padding(16)

            Divider()

            // 策略选择
            VStack(alignment: .leading, spacing: 12) {
                Text("战斗策略")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)

                HStack(spacing: 8) {
                    ForEach(BattleStrategy.allCases) { strategy in
                        StrategyButton(
                            strategy: strategy,
                            isSelected: instance.strategy == strategy
                        ) {
                            instance.strategy = strategy
                        }
                    }
                }

                // 详细统计
                DetailStatsView(instance: instance)
            }
            .padding(16)

            Spacer()
        }
    }
}

// MARK: - 策略按钮
struct StrategyButton: View {
    let strategy: BattleStrategy
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: strategy.icon)
                    .font(.system(size: 16))
                Text(strategy.rawValue)
                    .font(.system(size: 11, weight: .medium))
                Text(strategy.description)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.purple.opacity(0.3) : Color("BgCard"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .purple : .white)
    }
}

// MARK: - 详细统计
struct DetailStatsView: View {
    @ObservedObject var instance: InstanceState

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            StatCard(label: "总战斗", value: "\(instance.battles)", icon: "⚔️")
            StatCard(label: "胜利",   value: "\(instance.wins)",    icon: "🏆")
            StatCard(label: "死亡",   value: "\(instance.deaths)",  icon: "💀")
            StatCard(label: "拾取",   value: "\(instance.itemsPicked)", icon: "🎁")
        }
    }
}

// MARK: - 日志面板（右栏）
struct LogPanel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.purple)
                Text("战斗日志")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("清空") { app.clearLogs() }
                    .buttonStyle(CompactButtonStyle(color: .gray))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color("BgTopBar"))

            Divider()

            // 日志列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(app.logs) { entry in
                        LogRow(entry: entry)
                        Divider().opacity(0.2)
                    }
                }
            }
        }
    }
}

// MARK: - 日志行
struct LogRow: View {
    let entry: LogEntry

    var instanceLabel: String {
        entry.instanceIndex < 0 ? "系统" : "实例#\(entry.instanceIndex)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(instanceLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.purple)
                    Text(entry.action)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - 空状态
struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.4))
            Text("选择左侧实例查看详情")
                .foregroundColor(.gray)
        }
    }
}

struct EmptyInstanceHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.4))
            Text("点击「扫描」发现游戏窗口")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.top, 60)
    }
}

// MARK: - 小组件
struct StatusBadge: View {
    let status: BotStatus
    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(status.color).opacity(0.25))
            .foregroundColor(Color(status.color))
            .clipShape(Capsule())
    }
}

struct BarView: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 28)
        }
    }
}

struct StatChip: View {
    let icon: String; let value: String
    var body: some View {
        HStack(spacing: 3) {
            Text(icon).font(.system(size: 10))
            Text(value).font(.system(size: 10, weight: .medium)).foregroundColor(.white)
        }
    }
}

struct StatCard: View {
    let label: String; let value: String; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 18))
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color("BgCard")))
    }
}

struct ControlButton: View {
    let label: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct CompactButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.5 : 0.25))
            .foregroundColor(color)
            .cornerRadius(5)
    }
}

// MARK: - 调试面板（模板匹配 + 文字检测）
struct TemplateTestView: View {
    @Binding var isPresented: Bool
    @State private var tabIndex: Int = 0   // 0=模板匹配  1=文字检测  2=区域OCR

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 + 关闭按钮
            HStack {
                Text("调试工具")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Tab 切换栏
            HStack(spacing: 0) {
                tabBtn("NPC模板匹配", idx: 0)
                tabBtn("文字检测",    idx: 1)
                tabBtn("区域OCR",     idx: 2)
                tabBtn("弹屏检测",    idx: 3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Divider().padding(.top, 8)

            if tabIndex == 0 {
                TemplateMatchTab()
            } else if tabIndex == 1 {
                OCRTestTab()
            } else if tabIndex == 2 {
                RegionOCRTab()
            } else {
                PopupDetectionTab()
            }
        }
        .background(Color("BgMain"))
    }

    @ViewBuilder
    private func tabBtn(_ label: String, idx: Int) -> some View {
        Button(label) { tabIndex = idx }
            .buttonStyle(CompactButtonStyle(color: tabIndex == idx ? .purple : .gray))
            .padding(.trailing, 8)
    }
}

// MARK: - Tab 1：NPC 模板匹配
struct TemplateMatchTab: View {
    @State private var testImage:     NSImage? = nil
    @State private var roiImage:      NSImage? = nil
    @State private var templateImage: NSImage? = nil
    @State private var resultPoint:   CGPoint? = nil
    @State private var resultLog:     String   = "请选择一张游戏截图"
    @State private var isRunning:     Bool     = false

    // ROI 可调滑块（初始值来自代码定义）
    @State private var roiX: Double = 0.30
    @State private var roiY: Double = 0.25
    @State private var roiW: Double = 0.50
    @State private var roiH: Double = 0.35

    // 点击 Y 偏移（像素）：负数=往上，正数=往下
    @State private var clickYOffset: Double = 0

    private var currentROI: CGRect { CGRect(x: roiX, y: roiY, width: roiW, height: roiH) }
    private let detector = SceneDetector()

    var body: some View {
        VStack(spacing: 8) {

            // ── 上方：原图（左）+ 右侧（ROI裁剪 + 模板）──
            HStack(spacing: 10) {

                // 左：原图 + 可调绿框
                ZStack {
                    Color.black
                    if let img = testImage {
                        GeometryReader { geo in
                            // 计算图片在 fit 模式下的实际显示区域（含黑边偏移）
                            let imgSize  = img.size
                            let scale    = min(geo.size.width / imgSize.width,
                                               geo.size.height / imgSize.height)
                            let dispW    = imgSize.width  * scale
                            let dispH    = imgSize.height * scale
                            let offX     = (geo.size.width  - dispW) / 2
                            let offY     = (geo.size.height - dispH) / 2

                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)

                            // ROI 绿框（基于实际图片区域）
                            Rectangle()
                                .stroke(Color.green.opacity(0.9), lineWidth: 2)
                                .frame(width: currentROI.width * dispW,
                                       height: currentROI.height * dispH)
                                .position(x: offX + (currentROI.minX + currentROI.width  / 2) * dispW,
                                          y: offY + (currentROI.minY + currentROI.height / 2) * dispH)
                            Text(String(format: "x:%.2f y:%.2f w:%.2f h:%.2f",
                                        roiX, roiY, roiW, roiH))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .background(Color.black.opacity(0.7))
                                .position(x: offX + (currentROI.minX + currentROI.width / 2) * dispW,
                                          y: offY + currentROI.minY * dispH + 8)

                            // 红点（基于实际图片区域）
                            if let pt = resultPoint {
                                let dx = offX + pt.x * dispW
                                let dy = offY + pt.y * dispH
                                Circle().fill(Color.red).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .position(x: dx, y: dy)
                                Text(String(format: "(%.4f,%.4f)", pt.x, pt.y))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow).background(Color.black.opacity(0.7))
                                    .position(x: min(dx + 55, geo.size.width - 45), y: dy - 12)
                            }
                        }
                    } else {
                        Text("点击「选图」加载截图").foregroundColor(.gray).font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 300).cornerRadius(8)

                // 右：ROI裁剪（可框选） + 模板
                VStack(spacing: 6) {
                    VStack(spacing: 3) {
                        Text("ROI 裁剪区  拖拽框选NPC → 存为模板")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.green)
                        ROICropView(roiImage: roiImage, onCrop: { cropped in
                            templateImage = cropped
                            saveTemplateToAssets(cropped)
                        })
                        .frame(width: 190, height: 130)
                        .cornerRadius(6)
                    }
                    Divider().background(Color.white.opacity(0.15))
                    VStack(spacing: 3) {
                        Text("当前模板").font(.system(size: 10, weight: .semibold)).foregroundColor(.orange)
                        ZStack {
                            Color.black
                            if let tmpl = templateImage {
                                Image(nsImage: tmpl).resizable().aspectRatio(contentMode: .fit)
                                if let cg = tmpl.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                                    Text("\(cg.width)×\(cg.height)px")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.yellow)
                                        .background(Color.black.opacity(0.6))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                        .padding(3)
                                }
                            } else {
                                Text("station_boss_tmpl_A\n未加载").foregroundColor(.gray)
                                    .font(.system(size: 10)).multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 190, height: 130).cornerRadius(6)
                    }
                }
            }

            // ── ROI 调整滑块 ──
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("X").frame(width: 14).foregroundColor(.gray).font(.system(size: 10))
                    Slider(value: $roiX, in: 0...0.9, step: 0.01).onChange(of: roiX) { _ in showROI() }
                    Text(String(format: "%.2f", roiX)).frame(width: 32).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)

                    Text("Y").frame(width: 14).foregroundColor(.gray).font(.system(size: 10))
                    Slider(value: $roiY, in: 0...0.9, step: 0.01).onChange(of: roiY) { _ in showROI() }
                    Text(String(format: "%.2f", roiY)).frame(width: 32).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
                }
                HStack(spacing: 6) {
                    Text("W").frame(width: 14).foregroundColor(.gray).font(.system(size: 10))
                    Slider(value: $roiW, in: 0.05...1.0, step: 0.01).onChange(of: roiW) { _ in showROI() }
                    Text(String(format: "%.2f", roiW)).frame(width: 32).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)

                    Text("H").frame(width: 14).foregroundColor(.gray).font(.system(size: 10))
                    Slider(value: $roiH, in: 0.05...1.0, step: 0.01).onChange(of: roiH) { _ in showROI() }
                    Text(String(format: "%.2f", roiH)).frame(width: 32).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
                }
                // 点击 Y 偏移调整
                HStack(spacing: 6) {
                    Text("点击Y偏移").frame(width: 50).foregroundColor(.yellow).font(.system(size: 10))
                    Slider(value: $clickYOffset, in: -100...100, step: 1)
                        .onChange(of: clickYOffset) { _ in
                            if testImage != nil { runTest() }
                        }
                    Text(String(format: "%+.0fpx", clickYOffset))
                        .frame(width: 42).font(.system(size: 10, design: .monospaced)).foregroundColor(.yellow)
                    Button("重置") { clickYOffset = 0 }.buttonStyle(CompactButtonStyle(color: .gray))
                }
                HStack {
                    Text(String(format: "CGRect(x: %.2f, y: %.2f, width: %.2f, height: %.2f)", roiX, roiY, roiW, roiH))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    Button("📋 复制") {
                        let s = String(format: "CGRect(x: %.2f, y: %.2f, width: %.2f, height: %.2f)", roiX, roiY, roiW, roiH)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(s, forType: .string)
                        resultLog = "✅ 已复制：\(s)"
                    }.buttonStyle(CompactButtonStyle(color: .cyan))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .cornerRadius(6)

            logLine(resultLog, ok: resultPoint != nil)

            HStack(spacing: 10) {
                Button("选图") { pickImage() }.buttonStyle(CompactButtonStyle(color: .blue))
                Button("刷新ROI") { showROI() }
                    .buttonStyle(CompactButtonStyle(color: .green))
                    .disabled(testImage == nil)
                Button(action: runTest) {
                    HStack(spacing: 4) {
                        if isRunning { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                        Text(isRunning ? "识别中..." : "开始识别")
                    }
                }
                .buttonStyle(CompactButtonStyle(color: .purple))
                .disabled(testImage == nil || isRunning)
                Button("导出ROI") { exportROI() }
                    .buttonStyle(CompactButtonStyle(color: .orange))
                    .disabled(testImage == nil)
                Button("清除") {
                    testImage = nil; roiImage = nil
                    resultPoint = nil; resultLog = "请选择一张游戏截图"
                }.buttonStyle(CompactButtonStyle(color: .red))
            }
        }
        .padding(16)
        .onAppear { loadTemplate() }
    }

    private func loadTemplate() {
        if let img = NSImage(named: "station_boss_tmpl_A") { templateImage = img }
    }

    private func showROI() {
        guard let nsImg = testImage,
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let sw = Double(cg.width), sh = Double(cg.height)
        let rX = Int(currentROI.minX * sw)
        let rY = Int(currentROI.minY * sh)
        let rW = Int(currentROI.width  * sw)
        let rH = Int(currentROI.height * sh)
        guard let roiCG = cg.cropping(to: CGRect(x: rX, y: rY, width: rW, height: rH)) else {
            resultLog = "❌ ROI 裁剪失败"; return
        }
        roiImage = NSImage(cgImage: roiCG, size: NSSize(width: rW, height: rH))
    }

    private func pickImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .tiff]
        if p.runModal() == .OK, let url = p.url, let img = NSImage(contentsOf: url) {
            testImage = img; resultPoint = nil
            resultLog = "已加载：\(url.lastPathComponent)"
            showROI()
        }
    }

    private func exportROI() {
        guard let nsImg = testImage,
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let sw = Double(cg.width), sh = Double(cg.height)
        let rX = Int(currentROI.minX * sw)
        let rY = Int(currentROI.minY * sh)
        let rW = Int(currentROI.width  * sw)
        let rH = Int(currentROI.height * sh)
        guard let roiCG = cg.cropping(to: CGRect(x: rX, y: rY, width: rW, height: rH)) else {
            resultLog = "❌ ROI 裁剪失败"; return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "roi_export.png"
        panel.allowedContentTypes  = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            resultLog = "❌ 无法创建输出文件"; return
        }
        CGImageDestinationAddImage(dest, roiCG, nil)
        if CGImageDestinationFinalize(dest) {
            resultLog = "✅ ROI已导出：\(url.lastPathComponent)  (\(rW)×\(rH)px)"
        } else {
            resultLog = "❌ PNG写入失败"
        }
    }

    private func runTest() {
        guard let cg = testImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        isRunning = true; resultLog = "识别中..."
        let offset = Int(clickYOffset)
        Task {
            let pt = detector.findNPCByTemplate(in: cg, clickYOffset: offset)
            await MainActor.run {
                isRunning = false; resultPoint = pt
                resultLog = pt.map { String(format: "✅ 找到 NPC (%.4f, %.4f)  Y偏移:%+dpx", $0.x, $0.y, offset) }
                         ?? "❌ 未找到（相似度不足或超出范围）"
            }
        }
    }
}

// MARK: - Tab 2：文字检测
struct OCRTestTab: View {
    @State private var testImage:    NSImage?       = nil
    @State private var allElements:  [TextElement]  = []
    @State private var hitElements:  [TextElement]  = []   // 命中关键词的
    @State private var resultLog:    String         = "请选择一张游戏截图"
    @State private var isRunning:    Bool           = false

    // 可自定义搜索关键词，默认对话选项
    @State private var keywords: String = "是的,我要去,确认,确定,进入,传送"

    private let detector = SceneDetector()

    var body: some View {
        VStack(spacing: 14) {
            // 关键词输入
            HStack(spacing: 8) {
                Text("关键词（逗号分隔）:")
                    .font(.system(size: 11)).foregroundColor(.gray)
                TextField("是的,我要去,确认...", text: $keywords)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 4)

            previewArea
            logLine(resultLog, ok: !hitElements.isEmpty)

            // 文字列表（全量）
            if !allElements.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(allElements.enumerated()), id: \.offset) { _, el in
                            let isHit = hitElements.contains(where: { $0.text == el.text && $0.normX == el.normX })
                            HStack(spacing: 6) {
                                Circle().fill(isHit ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(el.description)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(isHit ? .green : .white.opacity(0.7))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(Color.black.opacity(0.3)).cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("选图") { pickImage() }.buttonStyle(CompactButtonStyle(color: .blue))
                Button(action: runOCR) {
                    HStack(spacing: 4) {
                        if isRunning { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                        Text(isRunning ? "检测中..." : "开始文字检测")
                    }
                }
                .buttonStyle(CompactButtonStyle(color: .green))
                .disabled(testImage == nil || isRunning)
                Button("清除") { testImage = nil; allElements = []; hitElements = []; resultLog = "请选择一张游戏截图" }
                    .buttonStyle(CompactButtonStyle(color: .red))
            }
        }
        .padding(20)
    }

    private var previewArea: some View {
        ZStack {
            Color.black
            if let img = testImage {
                GeometryReader { geo in
                    // 计算 .fit 模式下图片实际渲染尺寸
                    let imgSize  = img.size
                    let scale    = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
                    let displayW = imgSize.width  * scale
                    let displayH = imgSize.height * scale

                    // 以图片实际尺寸为画布，图片填满这个 ZStack
                    // 再用 .position 将整个 ZStack 居中于 GeometryReader
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: displayW, height: displayH)

                        // 所有识别到的文字框（坐标直接相对图片区域，无需 offset）
                        ForEach(Array(allElements.enumerated()), id: \.offset) { _, el in
                            let isHit = hitElements.contains(where: { $0.text == el.text && $0.normX == el.normX })
                            Rectangle()
                                .stroke(isHit ? Color.green : Color.yellow.opacity(0.5), lineWidth: isHit ? 2 : 1)
                                .frame(width: el.normW * displayW, height: el.normH * displayH)
                                .position(x: (el.normX + el.normW / 2) * displayW,
                                          y: (el.normY + el.normH / 2) * displayH)
                            if isHit {
                                Text(el.text)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                    .background(Color.black.opacity(0.7))
                                    .position(x: (el.normX + el.normW / 2) * displayW,
                                              y: el.normY * displayH - 8)
                            }
                        }
                    }
                    .frame(width: displayW, height: displayH)
                    // 将图片区域居中于 GeometryReader（即黑色背景）
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Text("点击「选图」加载截图").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 320).cornerRadius(8)
    }

    private func pickImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .tiff]
        if p.runModal() == .OK, let url = p.url, let img = NSImage(contentsOf: url) {
            testImage = img; allElements = []; hitElements = []
            resultLog = "已加载：\(url.lastPathComponent)"
        }
    }

    private func runOCR() {
        guard let cg = testImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        isRunning = true; resultLog = "OCR 检测中..."
        let kwList = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task {
            let elements = await detector.scanAllText(cgImage: cg)
            let hits = elements.filter { el in kwList.contains(where: { el.text.contains($0) }) }
            await MainActor.run {
                isRunning   = false
                allElements = elements
                hitElements = hits
                if hits.isEmpty {
                    resultLog = "共识别 \(elements.count) 个文字，❌ 未命中任何关键词"
                } else {
                    let names = hits.map { "\"\($0.text)\"" }.joined(separator: "、")
                    resultLog = "共识别 \(elements.count) 个文字，✅ 命中 \(hits.count) 个：\(names)"
                }
            }
        }
    }
}

// MARK: - Tab 3：区域 OCR 测试
/// 只扫指定归一化区域，结果坐标还原到全图，用于精确识别对话框等局部区域
struct RegionOCRTab: View {
    @State private var testImage:    NSImage?      = nil
    @State private var allElements:  [TextElement] = []   // 本次区域扫描结果（全图坐标）
    @State private var hitElements:  [TextElement] = []   // 命中关键词的
    @State private var resultLog:    String        = "请选择截图，填写区域，点击「区域识别」"
    @State private var isRunning:    Bool          = false

    // 区域参数（归一化 0~1），默认对话框区域
    @State private var roiX: String = "0.17"
    @State private var roiY: String = "0.53"
    @State private var roiW: String = "0.38"
    @State private var roiH: String = "0.18"

    // 关键词
    @State private var keywords: String = "是的,我要去,确认,确定,进入,开始"

    private let detector = SceneDetector()

    // 预设区域快捷选择
    private let presets: [(String, CGRect)] = [
        ("对话框",  UIRegions.dialogROI),
        ("地点",    UIRegions.locationPx),
        ("战斗",    UIRegions.fightPx),
        ("NPC区",   UIRegions.npcLabelROI),
    ]

    var body: some View {
        VStack(spacing: 12) {

            // ── 预设快捷按钮 ──
            HStack(spacing: 6) {
                Text("预设:").font(.system(size: 11)).foregroundColor(.gray)
                ForEach(presets, id: \.0) { name, rect in
                    Button(name) { applyPreset(rect) }
                        .buttonStyle(CompactButtonStyle(color: .purple))
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // ── 区域坐标输入 ──
            HStack(spacing: 8) {
                roiField("X", $roiX)
                roiField("Y", $roiY)
                roiField("W", $roiW)
                roiField("H", $roiH)
            }
            .padding(.horizontal, 4)

            // ── 关键词 ──
            HStack(spacing: 8) {
                Text("关键词（逗号分隔）:").font(.system(size: 11)).foregroundColor(.gray)
                TextField("是的,确认...", text: $keywords).textFieldStyle(.roundedBorder).font(.system(size: 11))
            }
            .padding(.horizontal, 4)

            // ── 预览区（图片 + 区域蓝框 + 识别结果框） ──
            previewArea

            logLine(resultLog, ok: !hitElements.isEmpty)

            // ── 识别结果列表 ──
            if !allElements.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(allElements.enumerated()), id: \.offset) { _, el in
                            let isHit = hitElements.contains(where: { $0.text == el.text && $0.normX == el.normX })
                            HStack(spacing: 6) {
                                Circle().fill(isHit ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(el.description)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(isHit ? .green : .white.opacity(0.7))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 90)
                .background(Color.black.opacity(0.3)).cornerRadius(6)
            }

            // ── 操作按钮 ──
            HStack(spacing: 12) {
                Button("选图") { pickImage() }.buttonStyle(CompactButtonStyle(color: .blue))
                Button(action: runRegionOCR) {
                    HStack(spacing: 4) {
                        if isRunning { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                        Text(isRunning ? "识别中..." : "区域识别")
                    }
                }
                .buttonStyle(CompactButtonStyle(color: .green))
                .disabled(testImage == nil || isRunning)

                Button("清除") {
                    testImage = nil; allElements = []; hitElements = []
                    resultLog = "请选择截图，填写区域，点击「区域识别」"
                }
                .buttonStyle(CompactButtonStyle(color: .red))
            }
        }
        .padding(20)
    }

    // MARK: - 预览区
    private var previewArea: some View {
        ZStack {
            Color.black
            if let img = testImage {
                GeometryReader { geo in
                    let imgSize  = img.size
                    let scale    = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
                    let displayW = imgSize.width  * scale
                    let displayH = imgSize.height * scale

                    ZStack(alignment: .topLeading) {
                        // 底图
                        Image(nsImage: img).resizable().frame(width: displayW, height: displayH)

                        // 蓝色 ROI 区域框
                        if let roi = currentROI() {
                            Rectangle()
                                .stroke(Color.blue, lineWidth: 1.5)
                                .background(Color.blue.opacity(0.08))
                                .frame(width: roi.width * displayW, height: roi.height * displayH)
                                .position(x: (roi.minX + roi.width / 2) * displayW,
                                          y: (roi.minY + roi.height / 2) * displayH)
                        }

                        // 识别结果框
                        ForEach(Array(allElements.enumerated()), id: \.offset) { _, el in
                            let isHit = hitElements.contains(where: { $0.text == el.text && $0.normX == el.normX })

                            // 文字包围框
                            Rectangle()
                                .stroke(isHit ? Color.green : Color.yellow.opacity(0.6), lineWidth: isHit ? 2 : 1)
                                .frame(width: el.normW * displayW, height: el.normH * displayH)
                                .position(x: (el.normX + el.normW / 2) * displayW,
                                          y: (el.normY + el.normH / 2) * displayH)

                            // 命中项：画中心点（点击目标）+ 文字标签
                            if isHit {
                                let cx = (el.normX + el.normW / 2) * displayW
                                let cy = (el.normY + el.normH / 2) * displayH
                                // 十字准心
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .position(x: cx, y: cy)
                                Text(el.text)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                    .background(Color.black.opacity(0.75))
                                    .position(x: cx, y: cy - el.normH * displayH / 2 - 8)
                            }
                        }
                    }
                    .frame(width: displayW, height: displayH)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Text("点击「选图」加载截图").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 320).cornerRadius(8)
    }

    // MARK: - 辅助
    @ViewBuilder
    private func roiField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray).frame(width: 12)
            TextField("0.0", text: binding).textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 60)
        }
    }

    private func currentROI() -> CGRect? {
        guard let x = Double(roiX), let y = Double(roiY),
              let w = Double(roiW), let h = Double(roiH),
              w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func applyPreset(_ rect: CGRect) {
        roiX = String(format: "%.4f", rect.minX)
        roiY = String(format: "%.4f", rect.minY)
        roiW = String(format: "%.4f", rect.width)
        roiH = String(format: "%.4f", rect.height)
    }

    private func pickImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .tiff]
        if p.runModal() == .OK, let url = p.url, let img = NSImage(contentsOf: url) {
            testImage = img; allElements = []; hitElements = []
            resultLog = "已加载：\(url.lastPathComponent)"
        }
    }

    private func runRegionOCR() {
        guard let cg  = testImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let roi = currentROI() else { return }
        isRunning = true; resultLog = "区域识别中..."
        let kwList = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task {
            let elements = await detector.scanTextInRegion(cgImage: cg, region: roi)
            let hits = elements.filter { el in kwList.contains(where: { el.text.contains($0) }) }
            await MainActor.run {
                isRunning   = false
                allElements = elements
                hitElements = hits
                if elements.isEmpty {
                    resultLog = "❌ 区域内未识别到任何文字"
                } else if hits.isEmpty {
                    resultLog = "识别 \(elements.count) 个文字，❌ 未命中关键词"
                } else {
                    let info = hits.map { el -> String in
                        let cx = String(format: "%.4f", el.normX + el.normW / 2)
                        let cy = String(format: "%.4f", el.normY + el.normH / 2)
                        return "\"\(el.text)\" 点击中心:(\(cx),\(cy))"
                    }.joined(separator: "  |  ")
                    resultLog = "✅ 命中 \(hits.count)/\(elements.count)：\(info)"
                }
            }
        }
    }
}

// MARK: - Tab 4：弹屏朝向检测
/// 输入一张截图 + 弹屏区域 + 4个角色子区域，检测哪个角色面向屏幕
struct PopupDetectionTab: View {
    @State private var testImage:    NSImage?      = nil
    @State private var resultLog:    String        = "请选择截图，调整区域参数，点击「检测朝向」"
    @State private var isRunning:    Bool          = false
    @State private var popupResult:  PopupResult?  = nil

    // 弹屏弹窗 ROI（相对全图归一化）
    @State private var roiX: String = "0.20"
    @State private var roiY: String = "0.25"
    @State private var roiW: String = "0.60"
    @State private var roiH: String = "0.55"

    // 角色1~4 子区域（相对 ROI 归一化）
    @State private var c1X: String = "0.05"; @State private var c1Y: String = "0.05"
    @State private var c1W: String = "0.40"; @State private var c1H: String = "0.45"

    @State private var c2X: String = "0.55"; @State private var c2Y: String = "0.05"
    @State private var c2W: String = "0.40"; @State private var c2H: String = "0.45"

    @State private var c3X: String = "0.05"; @State private var c3Y: String = "0.52"
    @State private var c3W: String = "0.40"; @State private var c3H: String = "0.45"

    @State private var c4X: String = "0.55"; @State private var c4Y: String = "0.52"
    @State private var c4W: String = "0.40"; @State private var c4H: String = "0.45"

    private let detector = SceneDetector()

    private func parseROI() -> CGRect? {
        guard let x = Double(roiX), let y = Double(roiY),
              let w = Double(roiW), let h = Double(roiH),
              w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func parseCharRegions() -> [CGRect] {
        func rect(_ sx: String, _ sy: String, _ sw: String, _ sh: String) -> CGRect {
            CGRect(x: Double(sx) ?? 0, y: Double(sy) ?? 0,
                   width: Double(sw) ?? 0.1, height: Double(sh) ?? 0.1)
        }
        return [
            rect(c1X, c1Y, c1W, c1H),
            rect(c2X, c2Y, c2W, c2H),
            rect(c3X, c3Y, c3W, c3H),
            rect(c4X, c4Y, c4W, c4H),
        ]
    }

    var body: some View {
        VStack(spacing: 10) {

            // ── 弹屏 ROI 区域 ──
            HStack(spacing: 4) {
                Text("弹屏ROI:").font(.system(size: 11, weight: .bold)).foregroundColor(.white).frame(width: 55, alignment: .leading)
                paramField("X", $roiX); paramField("Y", $roiY)
                paramField("W", $roiW); paramField("H", $roiH)
            }.padding(.horizontal, 4)

            // ── 角色子区域（相对ROI） ──
            Group {
                charRow("角色1", $c1X, $c1Y, $c1W, $c1H, color: .red)
                charRow("角色2", $c2X, $c2Y, $c2W, $c2H, color: .orange)
                charRow("角色3", $c3X, $c3Y, $c3W, $c3H, color: .cyan)
                charRow("角色4", $c4X, $c4Y, $c4W, $c4H, color: .pink)
            }

            // ── 预览区 ──
            popupPreviewArea

            logLine(resultLog, ok: popupResult != nil)

            // ── 结果详情 ──
            if let pr = popupResult {
                HStack(spacing: 12) {
                    ForEach(0..<pr.allScores.count, id: \.self) { i in
                        let sel = (i == pr.index)
                        Text(String(format: "#%d: %.4f%@", i+1, pr.allScores[i], sel ? " ✅" : ""))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(sel ? .green : .white.opacity(0.7))
                    }
                }
            }

            // ── 操作按钮 ──
            HStack(spacing: 12) {
                Button("选图") { pickImage() }.buttonStyle(CompactButtonStyle(color: .blue))
                Button(action: runDetection) {
                    HStack(spacing: 4) {
                        if isRunning { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                        Text(isRunning ? "检测中..." : "检测朝向")
                    }
                }
                .buttonStyle(CompactButtonStyle(color: .green))
                .disabled(testImage == nil || isRunning)

                Button("保存调试图") { saveDebugImage() }
                    .buttonStyle(CompactButtonStyle(color: .orange))
                    .disabled(popupResult == nil)

                Button("清除") {
                    testImage = nil; popupResult = nil
                    resultLog = "请选择截图，调整区域参数，点击「检测朝向」"
                }
                .buttonStyle(CompactButtonStyle(color: .red))
            }
        }
        .padding(20)
    }

    // MARK: - 预览区
    private var popupPreviewArea: some View {
        ZStack {
            Color.black
            if let img = testImage {
                GeometryReader { geo in
                    let imgSize  = img.size
                    let scale    = min(geo.size.width / imgSize.width, geo.size.height / imgSize.height)
                    let displayW = imgSize.width  * scale
                    let displayH = imgSize.height * scale

                    ZStack(alignment: .topLeading) {
                        Image(nsImage: img).resizable().frame(width: displayW, height: displayH)

                        // 弹屏 ROI 蓝色虚线框
                        if let roi = parseROI() {
                            Rectangle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                .foregroundColor(.blue)
                                .background(Color.blue.opacity(0.05))
                                .frame(width: roi.width * displayW, height: roi.height * displayH)
                                .position(x: (roi.minX + roi.width / 2) * displayW,
                                          y: (roi.minY + roi.height / 2) * displayH)

                            // 4个角色子区域框
                            let chars = parseCharRegions()
                            let colors: [Color] = [.red, .orange, .cyan, .pink]
                            ForEach(0..<chars.count, id: \.self) { i in
                                let sub = chars[i]
                                let absX = roi.minX + sub.minX * roi.width
                                let absY = roi.minY + sub.minY * roi.height
                                let absW = sub.width  * roi.width
                                let absH = sub.height * roi.height
                                let isSelected = (popupResult?.index == i)

                                Rectangle()
                                    .stroke(isSelected ? Color.green : colors[i], lineWidth: isSelected ? 3 : 1.5)
                                    .frame(width: absW * displayW, height: absH * displayH)
                                    .position(x: (absX + absW / 2) * displayW,
                                              y: (absY + absH / 2) * displayH)

                                // 标号
                                Text("#\(i+1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(isSelected ? .green : colors[i])
                                    .position(x: absX * displayW + 14,
                                              y: absY * displayH + 10)
                            }
                        }
                    }
                    .frame(width: displayW, height: displayH)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Text("点击「选图」加载弹屏截图").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 320).cornerRadius(8)
    }

    // MARK: - 辅助 UI
    @ViewBuilder
    private func paramField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray).frame(width: 12)
            TextField("0.0", text: binding).textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 50)
        }
    }

    @ViewBuilder
    private func charRow(_ label: String, _ sx: Binding<String>, _ sy: Binding<String>,
                          _ sw: Binding<String>, _ sh: Binding<String>, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundColor(.white).frame(width: 40, alignment: .leading)
            paramField("X", sx); paramField("Y", sy)
            paramField("W", sw); paramField("H", sh)
        }.padding(.horizontal, 4)
    }

    // MARK: - 操作
    private func pickImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .tiff]
        if p.runModal() == .OK, let url = p.url, let img = NSImage(contentsOf: url) {
            testImage = img; popupResult = nil
            resultLog = "已加载：\(url.lastPathComponent)  (\(Int(img.size.width))×\(Int(img.size.height)))"
        }
    }

    private func runDetection() {
        guard let cg = testImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let roi = parseROI() else {
            resultLog = "❌ 图片或ROI参数无效"
            return
        }
        isRunning = true; resultLog = "检测中..."
        let chars = parseCharRegions()
        Task {
            let result = detector.findFrontFacingCharacter(in: cg, popupROI: roi, charRegions: chars)
            await MainActor.run {
                isRunning = false
                popupResult = result
                if let r = result {
                    resultLog = String(format: "✅ 正面角色: #%d  对称度=%.4f  点击=(%.4f, %.4f)",
                                       r.index + 1, r.score, r.center.x, r.center.y)
                } else {
                    resultLog = "❌ 未检测到正面角色（所有区域裁剪失败）"
                }
            }
        }
    }

    private func saveDebugImage() {
        guard let cg = testImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let roi = parseROI(),
              let pr = popupResult else { return }
        detector.debugSavePopupDetection(cg, popupROI: roi, charRegions: parseCharRegions(), result: pr)
        resultLog = "📸 调试图已保存到桌面"
    }
}

// MARK: - ROI 框选裁剪视图
struct ROICropView: NSViewRepresentable {
    let roiImage: NSImage?
    let onCrop: (NSImage) -> Void

    func makeNSView(context: Context) -> ROICropNSView {
        let v = ROICropNSView()
        v.onCrop = onCrop
        return v
    }
    func updateNSView(_ nsView: ROICropNSView, context: Context) {
        nsView.roiImage = roiImage
        nsView.onCrop   = onCrop
        nsView.needsDisplay = true
    }
}

class ROICropNSView: NSView {
    var roiImage: NSImage?
    var onCrop: ((NSImage) -> Void)?

    private var startPt: CGPoint = .zero
    private var endPt:   CGPoint = .zero
    private var isDragging = false

    // 图片在 view 内的实际显示 rect（fit 模式）
    private var imageRect: CGRect {
        guard let img = roiImage else { return bounds }
        let s = min(bounds.width / img.size.width, bounds.height / img.size.height)
        let w = img.size.width  * s
        let h = img.size.height * s
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let img = roiImage else {
            NSColor.gray.setFill()
            let s = "点击「刷新ROI」" as NSString
            s.draw(at: CGPoint(x: 10, y: bounds.midY), withAttributes: [
                .foregroundColor: NSColor.gray, .font: NSFont.systemFont(ofSize: 10)])
            return
        }
        img.draw(in: imageRect)

        if isDragging {
            let sel = selectionRect
            NSColor.yellow.withAlphaComponent(0.3).setFill()
            sel.fill()
            NSColor.yellow.setStroke()
            let path = NSBezierPath(rect: sel)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private var selectionRect: CGRect {
        CGRect(x: min(startPt.x, endPt.x),
               y: min(startPt.y, endPt.y),
               width:  abs(endPt.x - startPt.x),
               height: abs(endPt.y - startPt.y))
    }

    override func mouseDown(with e: NSEvent) {
        startPt = convert(e.locationInWindow, from: nil)
        endPt = startPt; isDragging = true; needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        endPt = convert(e.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        endPt = convert(e.locationInWindow, from: nil)
        isDragging = false; needsDisplay = true
        cropAndSave()
    }

    private func cropAndSave() {
        guard let img = roiImage,
              let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let sel  = selectionRect
        guard sel.width > 4, sel.height > 4 else { return }

        let ir = imageRect
        // view 坐标 → 图片归一化（NSView Y 轴向上）
        let nx = (sel.minX - ir.minX) / ir.width
        let ny = (sel.minY - ir.minY) / ir.height   // NSView bottom=0
        let nw = sel.width  / ir.width
        let nh = sel.height / ir.height

        // CGImage crop（原点左上角，Y向下）→ 翻转 y
        let pw = Double(cg.width),  ph = Double(cg.height)
        let cx = Int(nx * pw)
        let cy = Int((1.0 - ny - nh) * ph)   // 翻转
        let cw = max(1, Int(nw * pw))
        let ch = max(1, Int(nh * ph))

        guard let cropped = cg.cropping(to: CGRect(x: cx, y: cy, width: cw, height: ch)) else { return }
        let result = NSImage(cgImage: cropped, size: NSSize(width: cw, height: ch))
        onCrop?(result)
    }
}

// 将框选的模板用 NSSavePanel 保存
private func saveTemplateToAssets(_ img: NSImage) {
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "station_boss_tmpl_NEW.png"
    panel.allowedContentTypes  = [.png]
    // 默认打开桌面
    panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, cg, nil)
    if CGImageDestinationFinalize(dest) {
        print("✅ 新模板已保存: \(url.lastPathComponent)  (\(cg.width)×\(cg.height)px)  请拖入 Xcode Assets 替换")
    }
}

// 通用日志行
private func logLine(_ text: String, ok: Bool) -> some View {
    Text(text)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(ok ? .green : .orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .lineLimit(2)
}

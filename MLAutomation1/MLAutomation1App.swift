//
//  MLAutomationApp.swift
//  MLAutomation
//
//  Created by wangjian on 2026/3/11.
//

import SwiftUI

@main
struct MLAutomation1App: App {
    // 使用@StateObject创建并持有appState对象
    // @StateObject确保当视图更新时，这个对象不会被重新创建
    // appState是共享的应用状态数据模型
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            // 创建一个窗口组，可以管理一个或多个窗口
            ContentView()
                .environmentObject(appState)
                 // 将appState作为环境对象传递给ContentView
                 // 使得ContentView及其子视图都可以访问这个共享数据
                .frame(minWidth: 1100, minHeight: 700)
                // 设置窗口的最小宽度为1100点，最小高度为700点
                .onAppear {
                         appState.registerF5HotKey()
                       }
            
        }
        .windowStyle(.hiddenTitleBar)
        // 设置窗口样式为隐藏标题栏，使界面更简洁
        .commands {
            // 配置应用的菜单命令
            CommandGroup(replacing: .newItem) {}
            // 替换默认的"新建"菜单项为一个空操作
            // 这通常用于禁用或自定义文件菜单中的新建选项
        }
    }
}

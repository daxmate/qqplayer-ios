//  QQPlayerMacApp.swift
//  QQPlayer
//
//  macOS app entry point (QQPlayerMac target only). The iOS app uses
//  QQPlayerApp.swift as its @main; this file must stay out of the iOS
//  QQPlayer target to avoid duplicate @main declarations.
//
import SwiftUI

@main
struct QQPlayerMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacLibraryView()
                // macOS 26 (Tahoe) 上 unified 工具栏默认透明，sidebar 内容会延伸到
                // 标题栏区域、第一行与交通灯重叠。强制工具栏背景不透明后内容从标题栏下方开始。
                .toolbarBackground(.visible, for: .windowToolbar)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

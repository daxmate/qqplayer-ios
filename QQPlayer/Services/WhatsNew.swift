//
//  WhatsNew.swift
//  QQPlayer
//
//  新功能通告（What's New）：
//  - WhatsNewItem：一个版本号的通告内容（id 用版本号）
//  - WhatsNewContent.all：按版本维护的通告列表（当前版本由 maintainer 维护）
//  - WhatsNewStore：UserDefaults 记录上次已读版本；首次启动（无记录）不弹，
//    避免与首次引导 Tutorial 撞车
//

import Foundation

/// 单个版本的通告条目
struct WhatsNewItem: Codable, Identifiable {
    /// 版本号（如 "1.2.4 (59)"）
    let id: String
    let title: String
    let items: [String]
}

enum WhatsNewContent {
    /// 当前版本通告（id 与 build 号对齐：MARKETING_VERSION + CURRENT_PROJECT_VERSION）
    static let currentVersion = "1.0.0 (60)"

    /// 全部版本通告，从新到旧。后续版本由 maintainer 在发版时追加。
    static let all: [WhatsNewItem] = [
        WhatsNewItem(
            id: currentVersion,
            title: Localized.whatsNewTitle,
            items: [
                Localized.whatsNewItemHints,
                Localized.whatsNewItemGuide,
                Localized.whatsNewItemAnnouncement,
            ]
        ),
    ]
}

/// 已读版本记录。UserDefaults 线程安全，单例可跨并发访问。
final class WhatsNewStore: @unchecked Sendable {
    static let shared = WhatsNewStore()

    private static let lastSeenKey = "whatsnew.lastSeenVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastSeenVersion() -> String? {
        defaults.string(forKey: Self.lastSeenKey)
    }

    func markSeen(_ version: String) {
        defaults.set(version, forKey: Self.lastSeenKey)
    }

    /// 是否应展示当前版本通告：当前版本 != 已读版本即弹（无记录视为未看过也弹）。
    /// 「全新安装用户不弹」由挂载层保证：Tutorial 显示期间不检查 WhatsNew，
    /// Tutorial 完成时 markSeen(当前版本)，之后本版不再弹、下次升级才弹。
    /// 版本注入参数仅供测试（模拟"升级到新版本"）。
    func shouldShowCurrent(version: String? = nil) -> Bool {
        let current = version ?? WhatsNewContent.currentVersion
        return lastSeenVersion() != current
    }

    func resetForTesting() {
        defaults.removeObject(forKey: Self.lastSeenKey)
    }
}

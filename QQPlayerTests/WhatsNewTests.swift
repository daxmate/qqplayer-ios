//
//  WhatsNewTests.swift
//  QQPlayerTests
//
//  新功能弹窗（WhatsNew）纯逻辑测试：
//  - 首次启动（无 lastSeen 记录）不弹（避免与 Tutorial 撞车）
//  - 看过后同版本不弹
//  - 模拟升级到新版本（注入不同版本号）→ 弹
//  - markSeen 持久化（跨 store 实例仍可见）
//  使用独立 UserDefaults suite，不污染全局 standard defaults。
//

import Foundation
import Testing

@testable import QQPlayer

@Suite("WhatsNew 新功能弹窗", .serialized)
struct WhatsNewTests {
    private let suiteName = "WhatsNewTests"

    private func makeStore() -> WhatsNewStore {
        WhatsNewStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    @Test("无已读记录（含老用户首次升级）→ 弹")
    func firstLaunchShowsForUpgrade() {
        let store = makeStore()
        store.resetForTesting()

        // 老用户升级场景：从旧版升到本版、从未看过通告 → 应弹
        // （全新安装不弹由挂载层保证：Tutorial 显示期间不检查，完成时 markSeen）
        #expect(store.lastSeenVersion() == nil)
        #expect(store.shouldShowCurrent() == true)
    }

    @Test("看过后同版本不再弹")
    func seenSameVersionDoesNotShow() {
        let store = makeStore()
        store.resetForTesting()

        store.markSeen(WhatsNewContent.currentVersion)
        #expect(store.shouldShowCurrent() == false)
        #expect(store.shouldShowCurrent(version: WhatsNewContent.currentVersion) == false)
    }

    @Test("模拟升级到新版本 → 弹")
    func upgradedVersionShows() {
        let store = makeStore()
        store.resetForTesting()

        // 上个版本已读（如 1.2.3），当前版本 1.2.4 (59) → 应弹
        store.markSeen("1.2.3 (58)")
        #expect(store.shouldShowCurrent() == true)

        // 注入任意"新版本号"同样触发
        #expect(store.shouldShowCurrent(version: "9.9.9 (999)") == true)

        // 已读当前版本后不再弹
        store.markSeen(WhatsNewContent.currentVersion)
        #expect(store.shouldShowCurrent() == false)
    }

    @Test("markSeen 持久化（跨 store 实例）")
    func markSeenPersists() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeObject(forKey: "whatsnew.lastSeenVersion")

        WhatsNewStore(defaults: defaults).markSeen("1.2.4 (59)")

        let freshStore = WhatsNewStore(defaults: defaults)
        #expect(freshStore.lastSeenVersion() == "1.2.4 (59)")
        #expect(freshStore.shouldShowCurrent() == false)
    }
}

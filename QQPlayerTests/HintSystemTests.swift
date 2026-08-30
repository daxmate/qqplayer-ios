//
//  HintSystemTests.swift
//  QQPlayerTests
//
//  首次提示气泡（HintSystem）纯逻辑测试：
//  - 未读 → showIfNeeded 返回 true 并标记已读；再调用返回 false
//  - resetAll 恢复所有提示点
//  - 不同提示点互不影响
//  注意：HintCoordinator 使用 HintStore.shared（UserDefaults.standard），
//  测试串行执行并在前后清空 hint.seen.* 键，避免相互污染。
//

import Foundation
import Testing

@testable import QQPlayer

@Suite("HintSystem 首次提示气泡", .serialized)
struct HintSystemTests {
    private func resetAll() {
        HintStore.shared.resetAll()
    }

    @Test("未读 → showIfNeeded 返回 true 并标记；再调用返回 false")
    func unreadThenSeen() {
        resetAll()
        defer { resetAll() }

        #expect(HintStore.shared.hasSeen(.playbackPage) == false)
        #expect(HintCoordinator.showIfNeeded(.playbackPage) == true)
        #expect(HintStore.shared.hasSeen(.playbackPage) == true)
        #expect(HintCoordinator.showIfNeeded(.playbackPage) == false)
    }

    @Test("resetAll 恢复所有提示点为未读")
    func resetAllRestores() {
        resetAll()
        defer { resetAll() }

        for key in HintKey.allCases {
            #expect(HintCoordinator.showIfNeeded(key) == true)
            #expect(HintStore.shared.hasSeen(key) == true)
        }

        HintStore.shared.resetAll()

        for key in HintKey.allCases {
            #expect(HintStore.shared.hasSeen(key) == false)
        }
    }

    @Test("不同提示点互不影响")
    func keysAreIndependent() {
        resetAll()
        defer { resetAll() }

        // 三个提示点首次调用都返回 true（彼此不串扰）
        #expect(HintCoordinator.showIfNeeded(.playbackPage) == true)
        #expect(HintCoordinator.showIfNeeded(.fullLyricsPage) == true)
        #expect(HintCoordinator.showIfNeeded(.lyricsSearchPage) == true)

        // 只看过 playbackPage 时，其他 key 仍为未读
        HintStore.shared.resetAll()
        HintStore.shared.markSeen(.playbackPage)
        #expect(HintStore.shared.hasSeen(.playbackPage) == true)
        #expect(HintStore.shared.hasSeen(.fullLyricsPage) == false)
        #expect(HintStore.shared.hasSeen(.lyricsSearchPage) == false)
        #expect(HintCoordinator.showIfNeeded(.fullLyricsPage) == true)
        #expect(HintCoordinator.showIfNeeded(.playbackPage) == false)
    }
}

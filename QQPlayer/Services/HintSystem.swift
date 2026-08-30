//
//  HintSystem.swift
//  QQPlayer
//
//  首次上下文提示气泡（contextual hint）：
//  - HintKey：需要提示的界面（每个界面只提示一次）
//  - HintStore：UserDefaults 标记"已看过"，提供测试用 resetAll
//  - HintCoordinator：统一入口——未看过则标记并返回 true，看过返回 false。
//    调用即标记已读（onAppear 时机即算看过），保证"永不再现"。
//

import Foundation

/// 提示点：每个 case 对应一个界面，每个界面首次进入时提示一次。
enum HintKey: String, CaseIterable {
    case playbackPage
    case fullLyricsPage
    case lyricsSearchPage
}

/// 已读标记存储（UserDefaults）。UserDefaults 线程安全，单例可跨并发访问。
final class HintStore: @unchecked Sendable {
    static let shared = HintStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for hint: HintKey) -> String {
        "hint.seen.\(hint.rawValue)"
    }

    func hasSeen(_ hint: HintKey) -> Bool {
        defaults.bool(forKey: Self.key(for: hint))
    }

    func markSeen(_ hint: HintKey) {
        defaults.set(true, forKey: Self.key(for: hint))
    }

    func resetAll() {
        for hint in HintKey.allCases {
            defaults.removeObject(forKey: Self.key(for: hint))
        }
    }
}

/// 提示决策：调用即标记已读，返回是否需要显示气泡。
enum HintCoordinator {
    @discardableResult
    static func showIfNeeded(_ key: HintKey) -> Bool {
        guard !HintStore.shared.hasSeen(key) else { return false }
        HintStore.shared.markSeen(key)
        return true
    }
}

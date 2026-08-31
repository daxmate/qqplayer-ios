//  MacIndexingGate.swift
//  QQPlayer
//
//  macOS 音乐库扫描的状态决策纯逻辑（平台无关，可单测）。
//
//  背景（2026-08-31 首测 bug）：LibraryIndexer.start() 的 macOS 分支直接调
//  startMacScan() 就 return，从未把 isIndexing 置 true；而 scanMusicFolder 首行
//  guard isIndexing 直接拦截——扫描从未真正执行，音乐库永远为空。
//  决策上收为纯函数后，这类"状态前置缺失"的回归由单测锁定。
//

import Foundation

enum MacIndexingGate {
    /// 扫描开始决策。start() 的 macOS 分支（startMacScan）调用此函数决定是否启动：
    /// - currentlyIndexing 为 true → 已在扫描中，不重复启动（返回 false）
    /// - 否则 → 应启动扫描，且调用方必须把 isIndexing 置 true（历史 bug 根因）
    /// 返回 true 表示"应该开始扫描"。
    static func shouldBeginScan(currentlyIndexing: Bool) -> Bool {
        !currentlyIndexing
    }

    /// scanMusicFolder 首行 guard：扫描是否被允许继续执行。
    /// - generationMatches：任务代次是否仍有效（stop()/switchToOfflineMode() 会 bump）
    /// - isIndexing：start() 必须已置 true（否则扫描被拦截，历史 bug 根因）
    static func canProceedScan(generationMatches: Bool, isIndexing: Bool) -> Bool {
        generationMatches && isIndexing
    }
}

//  MacIndexingGateTests.swift
//  QQPlayerTests
//
//  macOS 音乐库扫描状态决策防回归测试（MacIndexingGate）。
//
//  背景（2026-08-31 首测 bug）：startMacScan() 未置 isIndexing=true → scanMusicFolder
//  首行 guard 直接拦截 → 扫描从未执行、音乐库永远为空（用户放歌不进库的根因）。
//  这些测试锁定"扫描状态前置"语义：任何人删掉 start 处的 isIndexing=true，
//  或破坏 guard 的 generation/isIndexing 校验，CI 立即变红。
//

import Foundation
import Testing

@testable import QQPlayer

struct MacIndexingGateTests {
    // MARK: - shouldBeginScan

    @Test("未在扫描：应该开始扫描")
    func notIndexingShouldBegin() {
        #expect(MacIndexingGate.shouldBeginScan(currentlyIndexing: false))
    }

    @Test("已在扫描：不应重复启动")
    func alreadyIndexingShouldNotBegin() {
        #expect(!MacIndexingGate.shouldBeginScan(currentlyIndexing: true))
    }

    // MARK: - canProceedScan

    @Test("代次匹配 + isIndexing=true：扫描可继续")
    func generationMatchAndIndexingProceeds() {
        #expect(MacIndexingGate.canProceedScan(generationMatches: true, isIndexing: true))
    }

    @Test("isIndexing=false（start 未置 true，历史 bug 场景）：扫描被拦截")
    func missingIsIndexingBlocksScan() {
        #expect(!MacIndexingGate.canProceedScan(generationMatches: true, isIndexing: false))
    }

    @Test("代次不匹配（stop()/offline 切换后）：扫描被拦截")
    func staleGenerationBlocksScan() {
        #expect(!MacIndexingGate.canProceedScan(generationMatches: false, isIndexing: true))
    }

    @Test("代次不匹配 + isIndexing=false：扫描被拦截")
    func staleGenerationAndNoIndexingBlocksScan() {
        #expect(!MacIndexingGate.canProceedScan(generationMatches: false, isIndexing: false))
    }
}

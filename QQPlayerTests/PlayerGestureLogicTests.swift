//
//  PlayerGestureLogicTests.swift
//  QQPlayerTests
//
//  播放页/歌词页手势判定与歌词时间轴纯逻辑测试：
//  - LyricTiming.activeLineIndex：当前播放时间 → 当前歌词行
//  - PlayerDismissGesture：歌词页右滑关闭 / 播放页下拉关闭阈值
//

import Foundation
import Testing

@testable import QQPlayer

struct LyricTimingTests {
    private func lines(_ texts: [(TimeInterval?, String)]) -> [LyricsLine] {
        texts.map { LyricsLine(timestamp: $0.0, text: $0.1) }
    }

    @Test("时间在句间：返回最后一句已到时间戳的行")
    func activeLineBetweenLines() {
        let l = lines([(0, "A"), (5, "B"), (10, "C")])
        #expect(LyricTiming.activeLineIndex(time: 0, in: l) == 0)
        #expect(LyricTiming.activeLineIndex(time: 4.9, in: l) == 0)
        #expect(LyricTiming.activeLineIndex(time: 5, in: l) == 1)
        #expect(LyricTiming.activeLineIndex(time: 9.9, in: l) == 1)
        #expect(LyricTiming.activeLineIndex(time: 10, in: l) == 2)
    }

    @Test("时间超过最后一句：返回最后一句")
    func activeLinePastEnd() {
        let l = lines([(0, "A"), (5, "B")])
        #expect(LyricTiming.activeLineIndex(time: 100, in: l) == 1)
        #expect(LyricTiming.activeLineIndex(time: 5, in: l) == 1)
    }

    @Test("时间早于第一句：返回 nil")
    func activeLineBeforeFirst() {
        let l = lines([(5, "A"), (10, "B")])
        #expect(LyricTiming.activeLineIndex(time: 0, in: l) == nil)
        #expect(LyricTiming.activeLineIndex(time: 4.9, in: l) == nil)
    }

    @Test("空歌词：返回 nil")
    func activeLineEmpty() {
        #expect(LyricTiming.activeLineIndex(time: 0, in: []) == nil)
    }

    @Test("无时间戳的行被跳过，不影响 index")
    func activeLineSkipsUntimed() {
        let l = lines([(0, "A"), (nil, "旁白"), (5, "B")])
        #expect(LyricTiming.activeLineIndex(time: 2, in: l) == 0)
        #expect(LyricTiming.activeLineIndex(time: 5, in: l) == 2)
        #expect(LyricTiming.activeLineIndex(time: 6, in: l) == 2)
    }

    @Test("全部无时间戳：返回 nil")
    func activeLineAllUntimed() {
        let l = lines([(nil, "A"), (nil, "B")])
        #expect(LyricTiming.activeLineIndex(time: 0, in: l) == nil)
    }
}

struct PlayerDismissGestureTests {
    // ---- 歌词页右滑关闭 ----

    @Test("位移超 120pt：关闭")
    func dismissLyricsLargeTranslation() {
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 121, predictedTranslation: 0) == true)
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 300, predictedTranslation: 50) == true)
    }

    @Test("位移未达 120pt 且非快速回甩：不关闭")
    func dismissLyricsSmallTranslation() {
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 119, predictedTranslation: 0) == false)
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 30, predictedTranslation: 250) == false)
    }

    @Test("位移过半（>40pt）且快速回甩（预测 >260pt）：关闭")
    func dismissLyricsFlick() {
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 41, predictedTranslation: 261) == true)
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 80, predictedTranslation: 265) == true)
        // 边界：刚好 40/260 不关闭
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 40, predictedTranslation: 260) == false)
        #expect(PlayerDismissGesture.shouldDismissLyrics(translation: 40, predictedTranslation: 300) == false)
    }

    // ---- 播放页封面下拉关闭 ----

    @Test("下拉位移达 100pt：关闭")
    func dismissPlayerLargePull() {
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 100, predictedHeight: 0) == true)
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 160, predictedHeight: 10) == true)
    }

    @Test("下拉未达阈值且非快速：不关闭（回弹）")
    func dismissPlayerSmallPull() {
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 99, predictedHeight: 0) == false)
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 50, predictedHeight: 200) == false)
    }

    @Test("下拉过半（≥40pt）且快速下拉（预测 >300pt）：关闭")
    func dismissPlayerFlick() {
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 40, predictedHeight: 301) == true)
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 60, predictedHeight: 350) == true)
        // 边界：预测 300 不关闭
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 40, predictedHeight: 300) == false)
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 39, predictedHeight: 500) == false)
    }

    @Test("上滑（位移为负）不参与关闭判定")
    func dismissPlayerIgnoresUpward() {
        // 上滑时 predictedHeight 为负/小，不应触发
        #expect(PlayerDismissGesture.shouldDismissPlayer(pullOffset: 0, predictedHeight: -100) == false)
    }
}

struct MiniLyricSwipeGestureTests {
    // ---- 左滑打开全屏歌词页（阈值与历史硬编码 -60/-120 一致） ----

    @Test("左滑位移超 60pt：打开歌词页")
    func openLyricsSheetLargeSwipe() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -61, predictedTranslation: 0) == true)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -300, predictedTranslation: -50) == true)
    }

    @Test("左滑快速回甩（预测 < -120pt）：打开歌词页")
    func openLyricsSheetFlick() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -20, predictedTranslation: -121) == true)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -59, predictedTranslation: -200) == true)
    }

    @Test("左滑未达阈值且非快速回甩：不打开")
    func openLyricsSheetSmallSwipe() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -59, predictedTranslation: -100) == false)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: -30, predictedTranslation: -119) == false)
        // 右滑（正位移）不触发
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSheet(translation: 100, predictedTranslation: 200) == false)
    }

    // ---- 右滑打开歌词搜索页（与左滑阈值对称） ----

    @Test("右滑位移超 60pt：打开搜索页")
    func openLyricsSearchLargeSwipe() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 61, predictedTranslation: 0) == true)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 300, predictedTranslation: 50) == true)
    }

    @Test("右滑快速回甩（预测 > 120pt）：打开搜索页")
    func openLyricsSearchFlick() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 20, predictedTranslation: 121) == true)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 59, predictedTranslation: 200) == true)
    }

    @Test("右滑未达阈值且非快速回甩：不打开")
    func openLyricsSearchSmallSwipe() {
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 59, predictedTranslation: 100) == false)
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: 30, predictedTranslation: 119) == false)
        // 左滑（负位移）不触发
        #expect(MiniLyricSwipeGesture.shouldOpenLyricsSearch(translation: -100, predictedTranslation: -200) == false)
    }
}

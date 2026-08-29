//
//  PlaybackOrderModeTests.swift
//  QQPlayerTests
//
//  播放顺序四态（顺序/随机/循环列表/单曲循环）纯逻辑测试：
//  - playbackOrderMode 由 isShuffled/isRepeating/isLoopingSong 三布尔推导
//  - cyclePlaybackOrderMode / applyPlaybackOrderMode 的状态轮换
//  注：PlayerEngine.init 是 private，无法在测试里直接实例化；测试复用
//  PlayerEngine.shared（空播放队列下 toggleShuffle 的队列副作用全部有
//  guard 保护，不触数据库）。串行执行避免共享单例被并发改写。
//

import Foundation
import Testing

@testable import QQPlayer

@MainActor
@Suite(.serialized)
struct PlaybackOrderModeTests {
    private let engine = PlayerEngine.shared

    // 快照三布尔状态，测试结束后还原（共享单例，防泄漏到其他测试）
    private func withRestoredState(_ body: () throws -> Void) rethrows {
        let saved = (engine.isShuffled, engine.isRepeating, engine.isLoopingSong)
        defer {
            engine.isShuffled = saved.0
            engine.isRepeating = saved.1
            engine.isLoopingSong = saved.2
        }
        try body()
    }

    // MARK: - 状态推导

    @Test("三布尔全 false → .sequential")
    func deriveSequential() {
        withRestoredState {
            engine.isShuffled = false
            engine.isRepeating = false
            engine.isLoopingSong = false
            #expect(engine.playbackOrderMode == .sequential)
        }
    }

    @Test("isShuffled=true → .shuffle（优先级最高，即使循环同时开着）")
    func deriveShuffle() {
        withRestoredState {
            engine.isShuffled = true
            engine.isRepeating = false
            engine.isLoopingSong = false
            #expect(engine.playbackOrderMode == .shuffle)

            engine.isShuffled = true
            engine.isRepeating = true
            engine.isLoopingSong = true
            #expect(engine.playbackOrderMode == .shuffle)
        }
    }

    @Test("仅 isRepeating=true → .repeatAll")
    func deriveRepeatAll() {
        withRestoredState {
            engine.isShuffled = false
            engine.isRepeating = true
            engine.isLoopingSong = false
            #expect(engine.playbackOrderMode == .repeatAll)
        }
    }

    @Test("isLoopingSong=true → .repeatOne（优先级高于 isRepeating）")
    func deriveRepeatOne() {
        withRestoredState {
            engine.isShuffled = false
            engine.isRepeating = false
            engine.isLoopingSong = true
            #expect(engine.playbackOrderMode == .repeatOne)

            engine.isShuffled = false
            engine.isRepeating = true
            engine.isLoopingSong = true
            #expect(engine.playbackOrderMode == .repeatOne)
        }
    }

    // MARK: - 轮换序列

    @Test("顺序 → 随机 → 循环列表 → 单曲循环 → 顺序（四态完整轮换）")
    func cycleFullSequence() {
        withRestoredState {
            // 初始：顺序播放
            engine.isShuffled = false
            engine.isRepeating = false
            engine.isLoopingSong = false

            // 顺序 → 随机
            engine.cyclePlaybackOrderMode()
            #expect(engine.playbackOrderMode == .shuffle)
            #expect(engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(!engine.isLoopingSong)

            // 随机 → 循环列表
            engine.cyclePlaybackOrderMode()
            #expect(engine.playbackOrderMode == .repeatAll)
            #expect(!engine.isShuffled)
            #expect(engine.isRepeating)
            #expect(!engine.isLoopingSong)

            // 循环列表 → 单曲循环
            engine.cyclePlaybackOrderMode()
            #expect(engine.playbackOrderMode == .repeatOne)
            #expect(!engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(engine.isLoopingSong)

            // 单曲循环 → 顺序
            engine.cyclePlaybackOrderMode()
            #expect(engine.playbackOrderMode == .sequential)
            #expect(!engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(!engine.isLoopingSong)
        }
    }

    // MARK: - applyPlaybackOrderMode 目标态

    @Test("随机中切到 .repeatAll：先关随机再开循环列表")
    func applyRepeatAllFromShuffle() {
        withRestoredState {
            engine.isShuffled = true
            engine.isRepeating = false
            engine.isLoopingSong = false

            engine.applyPlaybackOrderMode(.repeatAll)
            #expect(!engine.isShuffled)
            #expect(engine.isRepeating)
            #expect(!engine.isLoopingSong)
        }
    }

    @Test("随机中切到 .repeatOne：先关随机再开单曲循环")
    func applyRepeatOneFromShuffle() {
        withRestoredState {
            engine.isShuffled = true
            engine.isRepeating = false
            engine.isLoopingSong = false

            engine.applyPlaybackOrderMode(.repeatOne)
            #expect(!engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(engine.isLoopingSong)
        }
    }

    @Test("随机中切到 .sequential：关随机恢复原队列")
    func applySequentialFromShuffle() {
        withRestoredState {
            engine.isShuffled = true
            engine.isRepeating = false
            engine.isLoopingSong = false

            engine.applyPlaybackOrderMode(.sequential)
            #expect(!engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(!engine.isLoopingSong)
        }
    }

    @Test("顺序中切到 .shuffle：开随机保存原队列")
    func applyShuffleFromSequential() {
        withRestoredState {
            engine.isShuffled = false
            engine.isRepeating = false
            engine.isLoopingSong = false

            engine.applyPlaybackOrderMode(.shuffle)
            #expect(engine.isShuffled)
            #expect(!engine.isRepeating)
            #expect(!engine.isLoopingSong)
        }
    }

    // MARK: - 枚举 rawValue 轮换

    @Test("PlaybackOrderMode rawValue 连续 0-3 且 allCases 顺序一致")
    func enumRawValueContinuity() {
        let all = PlaybackOrderMode.allCases
        #expect(all.map(\.rawValue) == [0, 1, 2, 3])
        #expect(all == [.sequential, .shuffle, .repeatAll, .repeatOne])
        // rawValue 可逆
        for mode in all {
            #expect(PlaybackOrderMode(rawValue: mode.rawValue) == mode)
        }
        // 越界 rawValue 返回 nil
        #expect(PlaybackOrderMode(rawValue: 4) == nil)
    }
}

//  MacPlaybackGateTests.swift
//  QQPlayerTests
//
//  macOS 播放链路决策纯逻辑防回归测试（MacPlaybackGate）：
//  - canStartPlayback：play() 前置条件（audioFile 已加载 / 非 loading / 非 loading 态）
//  - segmentPlan：scheduleSegment 帧计划校验（engine running / startFrame 范围 / remaining）
//
//  背景（2026-08-31）：macOS 版首测暴露"能编译但行为错"类 bug（扫描不执行/库为空），
//  决策逻辑必须上收为纯函数并锁定语义，防止播放链路被后续改动悄悄破坏。
//

import Foundation
import Testing

@testable import QQPlayer

struct MacPlaybackGateCanStartTests {
    @Test("audioFile 已加载 + 非 loading：可播放")
    func readyCanPlay() {
        #expect(MacPlaybackGate.canStartPlayback(
            audioFileLoaded: true, isLoadingTrack: false, playbackStateIsLoading: false))
    }

    @Test("audioFile 未加载：不可播放")
    func noAudioFileCannotPlay() {
        #expect(!MacPlaybackGate.canStartPlayback(
            audioFileLoaded: false, isLoadingTrack: false, playbackStateIsLoading: false))
    }

    @Test("加载任务进行中：不可播放（避免与加载竞争）")
    func loadingTrackCannotPlay() {
        #expect(!MacPlaybackGate.canStartPlayback(
            audioFileLoaded: true, isLoadingTrack: true, playbackStateIsLoading: false))
    }

    @Test("播放状态为 loading：不可播放")
    func loadingStateCannotPlay() {
        #expect(!MacPlaybackGate.canStartPlayback(
            audioFileLoaded: true, isLoadingTrack: false, playbackStateIsLoading: true))
    }

    @Test("全部前置不满足：不可播放")
    func nothingReadyCannotPlay() {
        #expect(!MacPlaybackGate.canStartPlayback(
            audioFileLoaded: false, isLoadingTrack: true, playbackStateIsLoading: true))
    }
}

struct MacPlaybackGateSegmentPlanTests {
    @Test("正常帧计划：返回剩余帧数")
    func normalSegment() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 0, fileLength: 1000, maxFrameCount: 1_000_000)
            == .success(frameCount: 1000))
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 400, fileLength: 1000, maxFrameCount: 1_000_000)
            == .success(frameCount: 600))
    }

    @Test("引擎未运行：拒绝")
    func engineNotRunning() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: false, startFrame: 0, fileLength: 1000, maxFrameCount: 1_000_000)
            == .failure(.engineNotRunning))
    }

    @Test("startFrame 为负：拒绝")
    func negativeStartFrame() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: -1, fileLength: 1000, maxFrameCount: 1_000_000)
            == .failure(.invalidStartFrame))
    }

    @Test("startFrame 超出文件长度：拒绝")
    func startFrameBeyondFile() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 1000, fileLength: 1000, maxFrameCount: 1_000_000)
            == .failure(.invalidStartFrame))
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 5000, fileLength: 1000, maxFrameCount: 1_000_000)
            == .failure(.invalidStartFrame))
    }

    @Test("startFrame == 文件末尾（remaining 为 0）：拒绝")
    func zeroRemaining() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 1000, fileLength: 1000, maxFrameCount: 1_000_000)
            == .failure(.invalidStartFrame))
    }

    @Test("remaining 超 AVAudioFrameCount.max：拒绝")
    func remainingExceedsMax() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 0, fileLength: 2_000_000_000, maxFrameCount: 1_000_000_000)
            == .failure(.exceedsMaxFrameCount))
    }

    @Test("remaining 恰好等于 max：接受")
    func remainingEqualsMax() {
        #expect(MacPlaybackGate.segmentPlan(
            engineIsRunning: true, startFrame: 0, fileLength: 1_000_000_000, maxFrameCount: 1_000_000_000)
            == .success(frameCount: 1_000_000_000))
    }
}

//  MacPlaybackGate.swift
//  QQPlayer
//
//  macOS 播放链路的纯决策逻辑（平台无关，可单测）：
//  - canStartPlayback：play() 的前置条件（audioFile 已加载、非 loading 中、非 loading 态）
//  - segmentPlan：scheduleSegment 的帧范围校验与剩余帧计算
//  - canResumeFromSavedPosition：恢复播放时的位置有效性
//
//  设计遵循 InterruptionResumePolicy 模式：决策抽纯函数，引擎只执行不决策。
//  2026-08-31 立：macOS 首测暴露"能编译但行为错"类 bug，决策逻辑必须有防回归测试。
//

import Foundation

enum MacPlaybackGate {
    /// play() 前置条件：native 路径能否真正开始播放。
    /// - audioFileLoaded：当前已加载音频文件
    /// - isLoadingTrack：加载任务进行中
    /// - playbackState：当前播放状态（.loading 时跳过，避免与加载竞争）
    static func canStartPlayback(audioFileLoaded: Bool, isLoadingTrack: Bool, playbackStateIsLoading: Bool) -> Bool {
        audioFileLoaded && !isLoadingTrack && !playbackStateIsLoading
    }

    /// scheduleSegment 的帧计划。与 PlayerEngine.scheduleSegment 的 guard 链一一对应：
    ///   engine running / startFrame 有效 / remaining > 0 / remaining 不超 AVAudioFrameCount.max
    static func segmentPlan(
        engineIsRunning: Bool,
        startFrame: Int64,
        fileLength: Int64,
        maxFrameCount: Int64
    ) -> SegmentPlanResult {
        guard engineIsRunning else { return .failure(.engineNotRunning) }
        guard startFrame >= 0 && startFrame < fileLength else { return .failure(.invalidStartFrame) }
        let remaining = fileLength - startFrame
        guard remaining > 0 else { return .failure(.noRemainingFrames) }
        guard remaining <= maxFrameCount else { return .failure(.exceedsMaxFrameCount) }
        return .success(frameCount: remaining)
    }

    enum SegmentPlanResult: Equatable {
        case success(frameCount: Int64)
        case failure(SegmentPlanFailure)

        enum SegmentPlanFailure: Equatable {
            case engineNotRunning
            case invalidStartFrame
            case noRemainingFrames
            case exceedsMaxFrameCount
        }
    }
}

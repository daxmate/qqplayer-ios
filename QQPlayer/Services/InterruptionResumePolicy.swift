//
//  InterruptionResumePolicy.swift
//  QQPlayer
//
//  音频中断「保存位置 / 恢复起点」决策的纯逻辑（不依赖 AVAudioEngine，可单元测试）。
//  背景（2026-08-30 中断后从头播诊断）：后台/锁屏时 0.25s UI timer 故意不跑，
//  playbackTime 冻结（可能 0 或 0.26s）；系统音频抢占时 interruption .began 通知
//  延迟到达，引擎已停，currentNodeSampleTime() 失效（lastRenderTime 为 nil），
//  保存位置只能读到冻结值 → 恢复 play() 命中 PLAY FROM BEGINNING 分支。
//  兜底方案：引擎存活时由 currentTimeForCurrentNativeFile() 持续刷新的
//  lastKnownPlaybackPosition 缓存；本类型负责「何时信任 lastKnown」的纯决策。
//

import Foundation

/// 音频中断保存/恢复位置决策
enum InterruptionResumePolicy {
    /// lastKnown 缓存视为「新鲜」的最大年龄（秒）
    static let lastKnownMaxAge: TimeInterval = 5.0
    /// lastKnown 缓存视为「有效」的最小位置（秒；低于此值可能是初始 0 或刚起步）
    static let lastKnownMinValidPosition: TimeInterval = 1.0
    /// playbackTime 视为「冻结」的最小年龄（秒）
    static let playbackTimeFrozenAge: TimeInterval = 5.0
    /// 修正时 lastKnown 必须比 playbackTime 大出的最小差值（秒）
    static let correctionMinDelta: TimeInterval = 1.0

    /// 中断 .began 保存位置决策。返回 nil = 使用调用方默认值（livePosition / playbackTime）。
    /// - 引擎存活（sampleTime 有效）→ nil（livePosition 本身是实时值）
    /// - wasPlaying 且引擎已停（sampleTime 无效）但 lastKnown 新鲜且有效 → lastKnown
    /// - 其余（非播放 / lastKnown 陈旧 / lastKnown 过小）→ nil（默认冻结值，保持现状）
    static func savedPosition(wasPlaying: Bool, livePosition: TimeInterval, sampleTimeValid: Bool,
                              lastKnown: TimeInterval, lastKnownAge: TimeInterval) -> TimeInterval? {
        guard wasPlaying, !sampleTimeValid else { return nil }
        guard lastKnownAge < lastKnownMaxAge, lastKnown > lastKnownMinValidPosition else { return nil }
        return lastKnown
    }

    /// 中断 .ended 恢复前修正决策（双保险，幂等）。返回 nil = 用当前 playbackTime 原样恢复。
    /// - playbackTime 冻结（年龄 > 5s）且 lastKnown 新鲜且明显更大 → lastKnown
    /// - 其余 → nil
    static func correctedResumePosition(playbackTime: TimeInterval, playbackTimeAge: TimeInterval,
                                        lastKnown: TimeInterval, lastKnownAge: TimeInterval) -> TimeInterval? {
        guard playbackTimeAge > playbackTimeFrozenAge else { return nil }
        guard lastKnownAge < lastKnownMaxAge else { return nil }
        guard lastKnown > playbackTime + correctionMinDelta else { return nil }
        return lastKnown
    }
}

//  PlaybackModels.swift
//  QQPlayer
//
//  Playback models used by PlayerEngine: playback order modes, the fast
//  playback-position observable, and playback errors.
//
import Combine
import Foundation

/// 播放顺序四态：顺序播放 → 随机播放 → 循环列表 → 单曲循环 → 顺序播放
enum PlaybackOrderMode: Int, CaseIterable {
    case sequential = 0
    case shuffle = 1
    case repeatAll = 2
    case repeatOne = 3
}

/// Holds the fast-changing playback position so that only views showing the
/// progress bar/time labels re-render at the 10Hz timer rate. Observing
/// PlayerEngine itself must not subscribe views to these updates.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var playbackTime: TimeInterval = 0
}

enum PlayerError: Error {
    case fileNotFound
    case invalidAudioFile
    case audioEngineError
    case configurationError
}

//
//  PlayerGestureLogic.swift
//  QQPlayer
//
//  播放页/歌词页手势与歌词时间轴的纯逻辑（不依赖 SwiftUI，可单元测试）
//

import CoreGraphics
import Foundation

/// 歌词时间轴计算：当前播放时间 → 当前歌词行
enum LyricTiming {
    /// 当前播放时间对应的歌词行 index；早于第一句返回 nil；无时间戳的行跳过。
    /// 语义：最后一个 timestamp <= time 的行；time 在两句之间时返回前一句。
    static func activeLineIndex(time: TimeInterval, in lines: [LyricsLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        var idx: Int?
        for (i, line) in lines.enumerated() {
            guard let ts = line.timestamp else { continue }
            if time >= ts {
                idx = i
            } else {
                break
            }
        }
        return idx
    }
}

/// 播放页/歌词页的滑动手势关闭判定（阈值 + 快速回甩）
enum PlayerDismissGesture {
    /// 歌词页右滑关闭：位移超过 120pt，或位移过半（>40pt）且快速回甩（预测 >260pt）
    static func shouldDismissLyrics(translation: CGFloat, predictedTranslation: CGFloat) -> Bool {
        translation > 120 || (translation > 40 && predictedTranslation > 260)
    }

    /// 播放页封面下拉关闭：位移达 100pt，或位移过半（>40pt）且快速下拉（预测 >300pt）
    static func shouldDismissPlayer(pullOffset: CGFloat, predictedHeight: CGFloat) -> Bool {
        pullOffset >= 100 || (pullOffset >= 40 && predictedHeight > 300)
    }
}

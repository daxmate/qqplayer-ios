//
//  LyricsModels.swift
//  QQPlayer
//
//  歌词数据模型（LyricsLine / Lyrics / 来源枚举）。
//

import Foundation

struct LyricsLine: Equatable, Codable {
    let timestamp: TimeInterval?
    let text: String
    /// 中文翻译（网易云 tlyric 按时间戳合并，桌面版 text = [原文, 罗马音, 翻译] 的 iOS 等价物）
    var translation: String?
}

struct Lyrics: Codable {
    let plainLyrics: String
    let syncedLyrics: [LyricsLine]
    let isInstrumental: Bool
    let source: LyricsSource

    enum LyricsSource: String, Codable {
        case embedded
        case netease
        case lrclib
        case none
    }
}

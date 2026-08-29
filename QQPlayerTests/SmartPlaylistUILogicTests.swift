//
//  SmartPlaylistUILogicTests.swift
//  QQPlayerTests
//
//  自动歌单 UI 层纯逻辑测试：置顶卡片的图标映射 + 副标题格式选择。
//  SmartPlaylistCardView 的视觉决策抽成 SmartPlaylistUILogic，可脱离
//  本地化/数据库单独验证（视图本身是 SwiftUI 声明，不做单元测试）。
//

import Testing

@testable import QQPlayer

struct SmartPlaylistUILogicTests {
    @Test func iconMappingCoversAllKinds() {
        #expect(SmartPlaylistUILogic.iconName(for: .recentAdded) == "clock")
        #expect(SmartPlaylistUILogic.iconName(for: .recentPlayed) == "history")
        #expect(SmartPlaylistUILogic.iconName(for: .topPlayed) == "flame")
        #expect(SmartPlaylistUILogic.iconName(for: .decades) == "calendar")
    }

    @Test func cardSubtitleUsesSongsFormatForTrackKinds() {
        for kind in [SmartPlaylistKind.recentAdded, .recentPlayed, .topPlayed] {
            let subtitle = SmartPlaylistUILogic.cardSubtitle(
                kind: kind,
                count: 7,
                songsFormat: { "\($0) songs" },
                decadesFormat: { "\($0) decades" }
            )
            #expect(subtitle == "7 songs")
        }
    }

    @Test func cardSubtitleUsesDecadesFormatForDecades() {
        let subtitle = SmartPlaylistUILogic.cardSubtitle(
            kind: .decades,
            count: 9,
            songsFormat: { "\($0) songs" },
            decadesFormat: { "\($0) decades" }
        )
        #expect(subtitle == "9 decades")
    }
}

//
//  LyricsSearchTests.swift
//  QQPlayerTests
//
//  歌词搜索/手动指定歌词测试：
//  - 应用搜索候选（netease：原文+翻译合并；lrclib：无翻译）
//  - 手动指定持久化（磁盘文件写入/删除，重启后可恢复）
//  - 清除手动指定恢复自动
//  网络路径不测（手动指定命中时 getLyrics 直接返回，不触发网络）。
//
//  注意：LyricsManager.shared 是全局单例（actor），测试并行会互相污染
//  manualOverrides → suite 串行 + 每个测试独立 stableId。
//

import Foundation
import Testing

@testable import QQPlayer

@Suite(.serialized)
struct LyricsSearchTests {
    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-search-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // 注入临时存储目录，避免污染 App 沙盒 Documents
        LyricsManager.manualLyricsDirectoryOverride = tempDir
    }

    private func makeTrack(_ stableId: String) -> Track {
        Track(stableId: stableId, title: "花海", path: "/tmp/\(stableId).flac")
    }

    private func neteaseCandidate() -> LyricsSearchCandidate {
        LyricsSearchCandidate(
            source: .netease,
            title: "花海",
            artist: "周杰伦",
            duration: 270,
            text: "[00:01.00]花海\n[00:05.00]爱存在",
            tlyric: "[00:01.00]花海\n[00:05.00]爱存在（翻译）"
        )
    }

    private func lrclibCandidate() -> LyricsSearchCandidate {
        LyricsSearchCandidate(
            source: .lrclib,
            title: "Flower Sea",
            artist: "Jay Chou",
            duration: 270,
            text: "[00:01.00]Flower Sea\n[00:05.00]Love exists",
            tlyric: nil
        )
    }

    private func manualFileURL(for stableId: String) -> URL {
        tempDir.appendingPathComponent("\(stableId).json")
    }

    // MARK: - 应用候选

    @Test("netease 候选应用：手动指定 + 翻译按时间戳合并 + getLyrics 优先返回")
    func applyNeteaseCandidate() async {
        let track = makeTrack("test-track-netease")

        let lyrics = await LyricsManager.shared.apply(candidate: neteaseCandidate(), for: track)
        #expect(lyrics != nil)
        #expect(lyrics?.source == .netease)

        let fetched = await LyricsManager.shared.getLyrics(for: track)
        #expect(fetched?.source == .netease)
        #expect(fetched?.syncedLyrics.count == 2)
        #expect(fetched?.syncedLyrics[0].text == "花海")
        #expect(fetched?.syncedLyrics[0].translation == "花海")
        #expect(fetched?.syncedLyrics[1].text == "爱存在")
        #expect(fetched?.syncedLyrics[1].translation == "爱存在（翻译）")

        #expect(await LyricsManager.shared.hasManualLyrics(for: track) == true)
    }

    @Test("lrclib 候选应用：source 标记 lrclib，无翻译")
    func applyLRCLibCandidate() async {
        let track = makeTrack("test-track-lrclib")

        let lyrics = await LyricsManager.shared.apply(candidate: lrclibCandidate(), for: track)
        #expect(lyrics?.source == .lrclib)

        let fetched = await LyricsManager.shared.getLyrics(for: track)
        #expect(fetched?.source == .lrclib)
        #expect(fetched?.syncedLyrics.count == 2)
        #expect(fetched?.syncedLyrics[0].translation == nil)
    }

    @Test("替换手动指定：后选覆盖先选")
    func applyOverwritesPrevious() async {
        let track = makeTrack("test-track-overwrite")

        await LyricsManager.shared.apply(candidate: neteaseCandidate(), for: track)
        await LyricsManager.shared.apply(candidate: lrclibCandidate(), for: track)

        let fetched = await LyricsManager.shared.getLyrics(for: track)
        #expect(fetched?.source == .lrclib)
        #expect(fetched?.syncedLyrics[0].text == "Flower Sea")
    }

    // MARK: - 持久化

    @Test("手动指定持久化：磁盘文件可解码（模拟重启恢复）")
    func manualLyricsPersisted() async throws {
        let track = makeTrack("test-track-persist")

        await LyricsManager.shared.apply(candidate: neteaseCandidate(), for: track)
        // 排空 actor 内的磁盘写 Task（await 一次 actor 调用保证写完成）
        _ = await LyricsManager.shared.hasManualLyrics(for: track)

        let data = try Data(contentsOf: manualFileURL(for: track.stableId))
        let decoded = try JSONDecoder().decode(Lyrics.self, from: data)
        #expect(decoded.source == .netease)
        #expect(decoded.syncedLyrics.count == 2)
        #expect(decoded.syncedLyrics[1].translation == "爱存在（翻译）")
    }

    // MARK: - 清除

    @Test("清除手动指定：标记移除 + 磁盘文件删除")
    func clearManualLyrics() async {
        let track = makeTrack("test-track-clear")

        await LyricsManager.shared.apply(candidate: neteaseCandidate(), for: track)
        _ = await LyricsManager.shared.hasManualLyrics(for: track) // 排空磁盘写
        #expect(FileManager.default.fileExists(atPath: manualFileURL(for: track.stableId).path) == true)

        await LyricsManager.shared.clearManualLyrics(for: track)
        #expect(await LyricsManager.shared.hasManualLyrics(for: track) == false)
        #expect(FileManager.default.fileExists(atPath: manualFileURL(for: track.stableId).path) == false)
    }

    @Test("未设置手动指定：hasManualLyrics 为 false")
    func noManualLyricsByDefault() async {
        let other = makeTrack("test-track-none")
        #expect(await LyricsManager.shared.hasManualLyrics(for: other) == false)
    }

    // MARK: - 简繁转换（lrclib 繁体标题补搜）

    @Test("简体转繁体：电台情歌 → 電台情歌")
    func traditionalChineseConversion() {
        #expect(traditionalChinese("电台情歌") == "電台情歌")
        #expect(traditionalChinese("莫文蔚") == "莫文蔚")
        #expect(traditionalChinese("半島鐵盒") == "半島鐵盒") // 已是繁体，原样
        #expect(traditionalChinese("").isEmpty)
    }
}

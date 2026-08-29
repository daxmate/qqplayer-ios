//
//  PlayHistoryCleanupTests.swift
//  QQPlayerTests
//
//  P0-3 回归测试：play_history 表的清理配套。
//  - deleteTrack(byStableId:) 删除曲目时同步删除其播放历史
//  - stable-id 合并/迁移路径（mergeTrackReferences / upsertTrack 去重）
//    把历史 UPDATE 到新 stable_id——历史跟随歌曲，而不是被删除
//
//  与 SmartPlaylistDataTests 的"最小 schema 复刻"不同，这里通过
//  DatabaseManager.init(dbWriter:) 测试缝 + createTables() 在内存 GRDB 上
//  跑真实生产代码路径，能抓住"某个清理点漏了 play_history"的回归。
//

import Foundation
import GRDB
import Testing

@testable import QQPlayer

struct PlayHistoryCleanupTests {
    // MARK: - Fixture

    private static func makeManager() throws -> (DatabaseManager, DatabaseQueue) {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbWriter: dbQueue)
        try manager.createTables()
        return (manager, dbQueue)
    }

    private static func historyStableIds(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT track_stable_id FROM play_history ORDER BY id")
    }

    private static func insertHistory(db: Database, stableId: String, playedAt: Int64) throws {
        try db.execute(
            sql: "INSERT INTO play_history (track_stable_id, played_at, play_duration_ms) VALUES (?, ?, 0)",
            arguments: [stableId, playedAt]
        )
    }

    // MARK: - deleteTrack

    @Test("deleteTrack：删除曲目同时删除其 play_history，其他曲目历史保留")
    func deleteTrackRemovesPlayHistory() throws {
        let (manager, dbQueue) = try Self.makeManager()
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO track (stable_id, title, path) VALUES
                ('del-me', 'Del Me', '/m/del-me.flac'),
                ('keep-me', 'Keep Me', '/m/keep-me.flac')
            """)
            try Self.insertHistory(db: db, stableId: "del-me", playedAt: 100)
            try Self.insertHistory(db: db, stableId: "del-me", playedAt: 200)
            try Self.insertHistory(db: db, stableId: "keep-me", playedAt: 300)
        }

        try manager.deleteTrack(byStableId: "del-me")

        try dbQueue.read { db in
            let ids = try Self.historyStableIds(db)
            #expect(ids == ["keep-me"])
        }
    }

    // MARK: - 迁移/合并路径

    @Test("migrateTrackStableIdAndPath：历史 UPDATE 到新 id（跟随歌曲），不丢不删")
    func migrationUpdatesHistoryToNewStableId() throws {
        let (manager, dbQueue) = try Self.makeManager()
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO track (stable_id, title, path) VALUES ('old-id', 'Song', '/m/old.flac')
            """)
            try Self.insertHistory(db: db, stableId: "old-id", playedAt: 100)
            try Self.insertHistory(db: db, stableId: "old-id", playedAt: 200)
        }

        try manager.migrateTrackStableIdAndPath(oldStableId: "old-id", newStableId: "new-id", newPath: "/m/new.flac")

        try dbQueue.read { db in
            let ids = try Self.historyStableIds(db)
            #expect(ids == ["new-id", "new-id"])
            #expect(!ids.contains("old-id"))
        }
    }

    @Test("upsertTrack 去重：同路径不同 stable_id 的重复项历史迁移到保留项")
    func upsertDedupMigratesHistory() throws {
        let (manager, dbQueue) = try Self.makeManager()
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO track (id, stable_id, duration_ms, file_size, title, path) VALUES
                (1, 'keep-id', 1000, 100, 'X', '/m/x.flac'),
                (2, 'dup-id', 1000, 100, 'X', '/m/x.flac')
            """)
            try Self.insertHistory(db: db, stableId: "dup-id", playedAt: 100)
            try Self.insertHistory(db: db, stableId: "dup-id", playedAt: 150)
        }

        let track = Track(stableId: "keep-id", title: "X", path: "/m/x.flac")
        try manager.upsertTrack(track)

        try dbQueue.read { db in
            let ids = try Self.historyStableIds(db)
            #expect(ids == ["keep-id", "keep-id"])
            #expect(!ids.contains("dup-id"))
        }
    }
}

// MARK: - PlayHistoryRecorder（会话结算校验 + 墙钟计时）

@MainActor
struct PlayHistoryRecorderTests {
    private static func makeRecorder() throws -> (PlayHistoryRecorder, DatabaseQueue) {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbWriter: dbQueue)
        try manager.createTables()
        return (PlayHistoryRecorder(database: manager), dbQueue)
    }

    private func makeTrack(_ stableId: String) -> Track {
        Track(stableId: stableId, title: stableId, path: "/m/\(stableId).flac")
    }

    @Test("playbackEnded 校验 track：不匹配/已结算的 ended 丢弃，不结算错会话")
    func endedWithMismatchedTrackIsDropped() throws {
        let (recorder, _) = try Self.makeRecorder()
        let trackA = makeTrack("a")
        recorder.playbackBegan(track: trackA, at: 0)

        // 别的曲目的 ended：丢弃，会话保持（此前会直接结算）
        recorder.playbackEnded(track: makeTrack("other"), at: 5)
        #expect(recorder.activeSessionTrackStableId == "a")

        // 正确曲目的 ended：结算
        recorder.playbackEnded(track: trackA, at: 5)
        #expect(recorder.activeSessionTrackStableId == nil)

        // 已结算后再 ended：幂等丢弃
        recorder.playbackEnded(track: trackA, at: 6)
        #expect(recorder.activeSessionTrackStableId == nil)
    }

    @Test("墙钟计时：前向 seek 不虚增时长（位置差 999s 只记真实墙钟）")
    func wallClockDoesNotCountForwardSeek() throws {
        let (recorder, dbQueue) = try Self.makeRecorder()
        let track = makeTrack("t1")
        recorder.playbackBegan(track: track, at: 0)
        Thread.sleep(forTimeInterval: 0.15)
        // 旧位置差逻辑：pause at 999 会记 ~999s；墙钟只记真实收听 ~0.15s
        recorder.playbackPaused(track: track, at: 999)
        recorder.playbackEnded(track: track, at: 999)

        try dbQueue.read { db in
            let dur = try Int64.fetchOne(db, sql: "SELECT play_duration_ms FROM play_history WHERE track_stable_id = 't1'") ?? 0
            #expect(dur > 0)
            #expect(dur < 5_000) // 远小于 999_000ms
        }
    }

    @Test("暂停/恢复：墙钟分段累计，暂停间隔不计入")
    func pauseResumeSegments() throws {
        let (recorder, dbQueue) = try Self.makeRecorder()
        let track = makeTrack("t2")
        recorder.playbackBegan(track: track, at: 0)
        Thread.sleep(forTimeInterval: 0.1)
        recorder.playbackPaused(track: track, at: 10) // 累计 ~0.1s，检查点推进
        Thread.sleep(forTimeInterval: 0.25) // 暂停 0.25s（不应计入）
        recorder.playbackBegan(track: track, at: 10) // 恢复：重置墙钟检查点
        Thread.sleep(forTimeInterval: 0.1)
        recorder.playbackEnded(track: track, at: 20) // 再累计 ~0.1s

        try dbQueue.read { db in
            let dur = try Int64.fetchOne(db, sql: "SELECT play_duration_ms FROM play_history WHERE track_stable_id = 't2'") ?? 0
            #expect(dur > 100)
            #expect(dur < 2_000) // ~0.2s 总量，暂停的 0.25s 不计入
        }
    }
}

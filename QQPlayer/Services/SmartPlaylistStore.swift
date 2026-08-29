//
//  SmartPlaylistStore.swift
//  QQPlayer
//
//  Data layer for automatic playlists (最近添加 / 最近播放 / 常听排行 / 年代).
//  Contract mirrors the desktop implementation (useSmartViews.ts):
//  - SMART_VIEW_LIMIT = 50
//  - recentPlayed dedupes by track, keeping each track's latest play
//  - topPlayed ranks by play count, ties broken by total listened duration
//  - decades buckets: 1950s (≤1959) ... 2020s (≥2020) + unknown, 9 buckets
//
//  UI-facing methods read through DatabaseManager.shared; the `from db`
//  variants are the testable cores used with an in-memory database.
//

import Foundation
@preconcurrency import GRDB

/// Automatic playlist kinds shown on the playlist page.
enum SmartPlaylistKind: String, CaseIterable, Identifiable {
    case recentAdded, recentPlayed, topPlayed, decades
    var id: String { rawValue }
}

/// Metadata for one pinned card on the playlist page. The UI derives its
/// localized title from `kind` (and `key` for decade buckets) and uses `count`
/// for the badge; `title` is a plain placeholder here.
struct SmartPlaylistCardInfo {
    let kind: SmartPlaylistKind
    let title: String
    let count: Int
}

/// One decade bucket with its track count (0-count buckets are included).
struct DecadeBucketInfo {
    let key: String
    let label: String
    let count: Int
}

enum SmartPlaylistStore {
    /// Same cap as the desktop SMART_VIEW_LIMIT.
    static let limit = 50

    // MARK: - Decade buckets (single source of truth, mirrors desktop DECADE_BUCKETS)

    /// Ordered bucket definitions. minYear/maxYear are inclusive; nil means
    /// unbounded in that direction (1950s has no lower bound within valid
    /// years, 2020s has no upper bound, unknown matches everything invalid).
    static let decadeBucketDefinitions: [(key: String, label: String, minYear: Int?, maxYear: Int?)] = [
        ("1950s", "1950s", 1000, 1959),
        ("1960s", "1960s", 1960, 1969),
        ("1970s", "1970s", 1970, 1979),
        ("1980s", "1980s", 1980, 1989),
        ("1990s", "1990s", 1990, 1999),
        ("2000s", "2000s", 2000, 2009),
        ("2010s", "2010s", 2010, 2019),
        ("2020s", "2020s", 2020, 9999),
        ("unknown", "unknown", nil, nil),
    ]

    /// Pure function: album year → decade bucket key.
    /// Follows the desktop `decadeOfYear`: non-4-digit years (<1000 or >9999)
    /// and nil map to "unknown"; 1959 → "1950s", 1960 → "1960s", 2020 → "2020s".
    static func decadeKey(ofYear year: Int?) -> String {
        guard let year else { return "unknown" }
        return decadeBucketDefinitions.first { bucket in
            guard let minYear = bucket.minYear, let maxYear = bucket.maxYear else { return false }
            return (minYear ... maxYear).contains(year)
        }?.key ?? "unknown"
    }

    // MARK: - UI-facing queries (via DatabaseManager.shared)

    /// 最近添加：modification_date 降序，nil 最后，截断 limit。
    static func recentAddedTracks() throws -> [Track] {
        try DatabaseManager.shared.read { db in
            try recentAddedTracks(from: db, limit: limit)
        }
    }

    /// 最近播放：按最新播放时间倒序，同一曲目只保留最新一条，截断 limit。
    static func recentPlayedTracks() throws -> [Track] {
        try DatabaseManager.shared.read { db in
            try recentPlayedTracks(from: db, limit: limit)
        }
    }

    /// 常听排行：按播放次数降序，并列按累计播放时长降序；只返回仍存在的曲目。
    static func topPlayedTracks() throws -> [(track: Track, playCount: Int)] {
        try DatabaseManager.shared.read { db in
            try topPlayedTracks(from: db, limit: limit)
        }
    }

    /// 年代聚合：9 个 bucket（含 0 数量）按固定顺序返回。
    static func decadeBuckets() throws -> [DecadeBucketInfo] {
        try DatabaseManager.shared.read { db in
            try decadeBuckets(from: db)
        }
    }

    /// 某 bucket 的歌曲：同年内按 year 降序，截断 limit。
    static func tracks(inDecade key: String) throws -> [Track] {
        try DatabaseManager.shared.read { db in
            try tracks(inDecade: key, from: db, limit: limit)
        }
    }

    /// 播放列表页置顶卡片的元数据（计数：recent* 为曲目数，decades 为 bucket 数）。
    static func cardInfos() throws -> [SmartPlaylistCardInfo] {
        [
            SmartPlaylistCardInfo(kind: .recentAdded, title: SmartPlaylistKind.recentAdded.rawValue, count: try recentAddedTracks().count),
            SmartPlaylistCardInfo(kind: .recentPlayed, title: SmartPlaylistKind.recentPlayed.rawValue, count: try recentPlayedTracks().count),
            SmartPlaylistCardInfo(kind: .topPlayed, title: SmartPlaylistKind.topPlayed.rawValue, count: try topPlayedTracks().count),
            SmartPlaylistCardInfo(kind: .decades, title: SmartPlaylistKind.decades.rawValue, count: try decadeBuckets().count),
        ]
    }

    /// 置顶卡片封面拼贴用的曲目：track 类歌单取前 limit 首；
    /// decades 取前 limit 个非空年代桶各 1 首（尽量覆盖不同年代封面）。
    static func coverTracks(for kind: SmartPlaylistKind, limit: Int = 4) throws -> [Track] {
        try DatabaseManager.shared.read { db in
            try coverTracks(for: kind, from: db, limit: limit)
        }
    }

    static func coverTracks(for kind: SmartPlaylistKind, from db: Database, limit: Int) throws -> [Track] {
        switch kind {
        case .recentAdded:
            return Array(try recentAddedTracks(from: db, limit: limit))
        case .recentPlayed:
            return Array(try recentPlayedTracks(from: db, limit: limit))
        case .topPlayed:
            return try topPlayedTracks(from: db, limit: limit).map(\.track)
        case .decades:
            var result: [Track] = []
            // DecadeBucketInfo.count 是 Int（非 Collection），empty_count 误报
            // swiftlint:disable:next empty_count
            let buckets = try decadeBuckets(from: db).filter { $0.count > 0 }
            for bucket in buckets.prefix(limit) {
                if let first = try tracks(inDecade: bucket.key, from: db, limit: 1).first {
                    result.append(first)
                }
            }
            return result
        }
    }

    // MARK: - Testable query cores (in-memory Database)

    static func recentAddedTracks(from db: Database, limit: Int) throws -> [Track] {
        try Track.fetchAll(db, sql: """
        SELECT * FROM track
        ORDER BY modification_date IS NULL ASC, modification_date DESC, title COLLATE NOCASE ASC
        LIMIT ?
        """, arguments: [limit])
    }

    static func recentPlayedTracks(from db: Database, limit: Int) throws -> [Track] {
        try Track.fetchAll(db, sql: """
        SELECT t.*
        FROM track t
        JOIN (
            SELECT track_stable_id, MAX(played_at) AS latest_played_at
            FROM play_history
            GROUP BY track_stable_id
        ) h ON h.track_stable_id = t.stable_id
        ORDER BY h.latest_played_at DESC, t.title COLLATE NOCASE ASC
        LIMIT ?
        """, arguments: [limit])
    }

    static func topPlayedTracks(from db: Database, limit: Int) throws -> [(track: Track, playCount: Int)] {
        let rows = try Row.fetchAll(db, sql: """
        SELECT t.*, COUNT(h.track_stable_id) AS play_count, COALESCE(SUM(h.play_duration_ms), 0) AS total_played
        FROM track t
        JOIN play_history h ON h.track_stable_id = t.stable_id
        GROUP BY t.stable_id
        ORDER BY play_count DESC, total_played DESC, t.title COLLATE NOCASE ASC
        LIMIT ?
        """, arguments: [limit])
        return try rows.map { row in
            let track = try Track(row: row)
            let playCount: Int = row["play_count"]
            return (track, playCount)
        }
    }

    static func decadeBuckets(from db: Database) throws -> [DecadeBucketInfo] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.year AS year
            FROM track t
            LEFT JOIN album a ON a.id = t.album_id
        """)
        var counts: [String: Int] = [:]
        for row in rows {
            let year: Int? = row["year"]
            counts[decadeKey(ofYear: year), default: 0] += 1
        }
        return decadeBucketDefinitions.map {
            DecadeBucketInfo(key: $0.key, label: $0.label, count: counts[$0.key, default: 0])
        }
    }

    static func tracks(inDecade key: String, from db: Database, limit: Int) throws -> [Track] {
        let clause = yearClause(for: key) ?? yearClause(for: "unknown")!
        return try Track.fetchAll(db, sql: """
        SELECT t.*
        FROM track t
        LEFT JOIN album a ON a.id = t.album_id
        WHERE \(clause)
        ORDER BY a.year DESC, t.title COLLATE NOCASE ASC
        LIMIT ?
        """, arguments: [limit])
    }

    /// SQL year predicate for a bucket key, mirroring `decadeKey` exactly so
    /// bucket membership never drifts from the pure function.
    private static func yearClause(for key: String) -> String? {
        guard let bucket = decadeBucketDefinitions.first(where: { $0.key == key }) else { return nil }
        if let minYear = bucket.minYear, let maxYear = bucket.maxYear {
            return "a.year BETWEEN \(minYear) AND \(maxYear)"
        }
        return "a.year IS NULL OR a.year < 1000 OR a.year > 9999"
    }
}

//
//  PlayHistoryRecorder.swift
//  QQPlayer
//
//  Play history instrumentation: one play session = a song that started
//  playing and was later switched away, stopped, or finished naturally.
//
//  - Pausing does NOT close the session; resuming keeps accumulating into the
//    same `play_history` record.
//  - Only settling (track switch / stop / natural end) closes the session and
//    stores the actually-listened duration via an UPDATE.
//  - Every DB write goes through DatabaseManager.shared.write; records are
//    tiny and written synchronously on the main actor, matching the existing
//    codebase style.
//

import Foundation
@preconcurrency import GRDB

@MainActor
final class PlayHistoryRecorder {
    static let shared = PlayHistoryRecorder()

    /// Stable id of the track with an open session (nil = no active session).
    private(set) var activeSessionTrackStableId: String?
    /// Playback position (seconds) at the last duration checkpoint. Advances on
    /// every accumulate so repeated pause/resume cycles never double-count.
    private(set) var sessionStartPlaybackTime: Double = 0
    /// `play_history` row id of the open session; the settling UPDATE targets it.
    private(set) var activeRecordId: Int64?

    /// Upper bound for a single accumulated segment (seconds). Pure backstop
    /// against corrupt timestamps; a real segment is bounded by track length.
    private static let maxSegmentDurationSeconds: Double = 24 * 60 * 60

    private init() {}

    // MARK: - Instrumentation entry points (called by PlayerEngine)

    /// Playback started (including resume from pause).
    ///
    /// Ignored when a session for the same track is already open (resume keeps
    /// the original record). Otherwise the previous session (if any) is settled
    /// first, then a fresh record is inserted with played_at = now.
    func playbackBegan(track: Track?, at playbackTime: Double) {
        guard let track, !track.stableId.isEmpty else { return }
        guard activeSessionTrackStableId != track.stableId else { return }

        // Defensive: a different track started while a session is still open
        // (should not happen - PlayerEngine settles before switching).
        if activeSessionTrackStableId != nil {
            settleSession(endingAt: playbackTime)
        }

        var insertedId: Int64?
        do {
            try DatabaseManager.shared.write { db in
                var entry = PlayHistoryEntry(
                    trackStableId: track.stableId,
                    playedAt: Int64(Date().timeIntervalSince1970),
                    playDurationMs: 0
                )
                try entry.insert(db)
                insertedId = entry.id
            }
        } catch {
            print("⚠️ PlayHistoryRecorder: 写入播放记录失败: \(error)")
        }

        activeRecordId = insertedId
        activeSessionTrackStableId = track.stableId
        sessionStartPlaybackTime = playbackTime
    }

    /// Playback paused. Accumulates the elapsed segment into the open record
    /// but keeps the session (track unchanged) so a later resume continues it.
    func playbackPaused(track: Track?, at playbackTime: Double) {
        guard let track else { return }
        guard activeSessionTrackStableId == track.stableId else { return }
        accumulateDuration(until: playbackTime)
    }

    /// Playback ended (track switched / stopped / finished). Accumulates the
    /// final segment and closes the session.
    func playbackEnded(track: Track?, at playbackTime: Double) {
        settleSession(endingAt: playbackTime)
    }

    // MARK: - Session accounting

    private func accumulateDuration(until playbackTime: Double) {
        guard activeSessionTrackStableId != nil,
              let recordId = activeRecordId,
              playbackTime.isFinite else {
            return
        }
        let sessionStart = sessionStartPlaybackTime
        let elapsed = playbackTime - sessionStart
        // Only positive, finite segments: seeks backwards or corrupt values
        // (NaN/inf, huge jumps) must not pollute the duration.
        guard elapsed > 0, elapsed <= Self.maxSegmentDurationSeconds else { return }
        let milliseconds = Int64(elapsed * 1000)
        guard milliseconds > 0 else { return }

        do {
            try DatabaseManager.shared.write { db in
                try db.execute(
                    sql: "UPDATE play_history SET play_duration_ms = play_duration_ms + ? WHERE id = ?",
                    arguments: [milliseconds, recordId]
                )
            }
        } catch {
            print("⚠️ PlayHistoryRecorder: 更新播放时长失败: \(error)")
        }

        // Advance the checkpoint so the next accumulate covers only the new
        // segment (pause at 30s, resume, pause at 60s -> 60s total, not 90s).
        sessionStartPlaybackTime = playbackTime
    }

    private func settleSession(endingAt playbackTime: Double) {
        guard activeSessionTrackStableId != nil else { return }
        accumulateDuration(until: playbackTime)
        activeSessionTrackStableId = nil
        sessionStartPlaybackTime = 0
        activeRecordId = nil
    }
}

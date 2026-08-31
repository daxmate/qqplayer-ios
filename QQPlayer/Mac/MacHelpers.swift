//
//  MacHelpers.swift
//  QQPlayer
//
//  Shared helpers for the macOS UI (QQPlayerMac target only).
//

import Foundation

enum MacTimeFormat {
    /// "m:ss" — matches the iOS player label format.
    static func format(_ time: TimeInterval) -> String {
        let safeTime = time.isFinite ? max(0, time) : 0
        let minutes = Int(safeTime) / 60
        let seconds = Int(safeTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Track is shared Core (Equatable only). The macOS table/list views need
// Identifiable + Hashable; the conformance lives here so the iOS target is
// untouched. Track already exposes `id: Int64?`, which satisfies Identifiable.
extension Track: Identifiable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(stableId)
    }
}

/// Table row wrapper with a non-optional identity.
///
/// `Track.id` is an optional database primary key (`Int64?`); using it as the
/// `Table` element identity breaks SwiftUI's selection mechanism on macOS
/// (rows never highlight on click and the double-click primary action never
/// fires). Every other list in the codebase uses the non-optional `stableId`
/// (`ForEach(..., id: \.stableId)` / `List(..., id: \.stableId)`) — this
/// wrapper does the same for `Table`.
struct MacTrackRow: Identifiable, Hashable {
    let id: String
    let track: Track

    static func == (lhs: MacTrackRow, rhs: MacTrackRow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

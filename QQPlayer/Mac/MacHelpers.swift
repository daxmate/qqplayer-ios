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

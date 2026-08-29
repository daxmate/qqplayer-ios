//
//  SmartPlaylistCardView.swift
//  QQPlayer
//
//  Pinned card for one automatic playlist (自动歌单) on the playlist page.
//  Visually mirrors PlaylistCardView (square artwork area plus two text
//  lines) so the grid rows stay aligned, but carries no edit/delete
//  affordances — the smart cards are fixed and not user-editable.
//
//  SmartPlaylistUILogic holds the pure card decisions (icon / subtitle
//  mapping) so they can be unit-tested without localization or the database.
//

import SwiftUI

/// Pure UI decisions for the smart playlist cards.
enum SmartPlaylistUILogic {
    /// SF Symbol shown on the pinned card for each kind.
    static func iconName(for kind: SmartPlaylistKind) -> String {
        switch kind {
        case .recentAdded: return "clock"
        case .recentPlayed: return "history"
        case .topPlayed: return "flame"
        case .decades: return "calendar"
        }
    }

    /// Card badge: song count for track-based kinds, decade count for decades.
    /// Formatting is injected so the decision is testable without localization.
    static func cardSubtitle(
        kind: SmartPlaylistKind,
        count: Int,
        songsFormat: (Int) -> String,
        decadesFormat: (Int) -> String
    ) -> String {
        switch kind {
        case .decades:
            return decadesFormat(count)
        default:
            return songsFormat(count)
        }
    }
}

/// Pinned automatic-playlist card. `info.count` comes from
/// `SmartPlaylistStore.cardInfos()`; on failure the caller falls back to a
/// placeholder info with count 0 and the card still renders.
struct SmartPlaylistCardView: View {
    let info: SmartPlaylistCardInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon area, matching PlaylistCardView's square artwork geometry.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)

                Image(systemName: SmartPlaylistUILogic.iconName(for: info.kind))
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))

            // Text info
            VStack(alignment: .leading, spacing: 2) {
                Text(Localized.smartPlaylistTitle(info.kind))
                    .font(.headline)
                    .lineLimit(1)

                Text(SmartPlaylistUILogic.cardSubtitle(
                    kind: info.kind,
                    count: info.count,
                    songsFormat: Localized.smartSongsCount,
                    decadesFormat: Localized.smartDecadeCount
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localized.smartPlaylistTitle(info.kind))
        .accessibilityAddTraits(.isButton)
    }
}

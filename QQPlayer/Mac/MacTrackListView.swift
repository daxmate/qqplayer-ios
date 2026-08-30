//
//  MacTrackListView.swift
//  QQPlayer
//
//  macOS track list (content column for the 歌曲 section). QQPlayerMac target only.
//

import SwiftUI

struct MacTrackListView: View {
    let tracks: [Track]
    let activeTrackId: String?
    let isPlaying: Bool
    let artistNameResolver: (Track) -> String?
    let onPlay: (Track) -> Void
    let onSelect: (Track) -> Void

    var body: some View {
        if tracks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("音乐库为空")
                    .font(.title3)
                Text("点击左下角「刷新音乐库」扫描 ~/Music/QQPlayer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(tracks) {
                TableColumn("#") { track in
                    if track.stableId == activeTrackId {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .foregroundColor(.accentColor)
                    } else {
                        Text("\(track.trackNo.map(String.init) ?? "")")
                            .foregroundColor(.secondary)
                    }
                }
                .width(32)

                TableColumn("标题") { track in
                    Text(track.title)
                        .fontWeight(track.stableId == activeTrackId ? .semibold : .regular)
                        .lineLimit(1)
                }

                TableColumn("艺术家") { track in
                    Text(artistNameResolver(track) ?? "")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                TableColumn("专辑") { track in
                    Text(albumTitle(for: track))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                TableColumn("时长") { track in
                    Text(MacTimeFormat.format(duration(for: track)))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .width(56)
            }
            .contextMenu(forSelectionType: Track.self) { _ in
            } primaryAction: { selection in
                if let track = selection.first {
                    onPlay(track)
                    onSelect(track)
                }
            }
        }
    }

    private func albumTitle(for track: Track) -> String {
        guard let albumId = track.albumId,
              let album = try? DatabaseManager.shared.read({ db in
                  try Album.fetchOne(db, key: albumId)
              }) else {
            return ""
        }
        return album.title
    }

    private func duration(for track: Track) -> TimeInterval {
        guard let ms = track.durationMs else { return 0 }
        return Double(ms) / 1000.0
    }
}
